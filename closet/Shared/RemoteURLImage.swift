//
//  RemoteURLImage.swift
//  closet
//
//  URLSession + in-memory cache image view for remote profile grids.
//  Avoids AsyncImage’s permanent failure state when cell tasks are cancelled.
//

import SwiftUI
import UIKit

enum RemoteImageMemoryCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 200
        return c
    }()

    static func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    static func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

/// Loads a remote image with cache + retries. Cancellation does not stick as a failure.
struct RemoteURLImage: View {
    let url: URL?
    var failureSystemImage: String = "photo"
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var didFail = false

    private static let maxAttempts = 3

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                ProgressView()
            } else if didFail || url == nil {
                Image(systemName: failureSystemImage)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task(id: url?.absoluteString ?? "") {
            await load()
        }
    }

    @MainActor
    private func load() async {
        guard let url else {
            image = nil
            didFail = true
            isLoading = false
            return
        }

        let key = url.absoluteString
        if let cached = RemoteImageMemoryCache.image(for: key) {
            image = cached
            didFail = false
            isLoading = false
            return
        }

        isLoading = true
        didFail = false
        defer { isLoading = false }

        for attempt in 0..<Self.maxAttempts {
            if Task.isCancelled { return }

            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .returnCacheDataElseLoad
                let (data, response) = try await URLSession.shared.data(for: request)
                if Task.isCancelled { return }

                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      let loaded = UIImage(data: data) else {
                    if attempt == Self.maxAttempts - 1 {
                        didFail = image == nil
                    } else {
                        try await Task.sleep(nanoseconds: UInt64(150_000_000 * (attempt + 1)))
                    }
                    continue
                }

                RemoteImageMemoryCache.store(loaded, for: key)
                image = loaded
                didFail = false
                return
            } catch is CancellationError {
                return
            } catch {
                if Self.isCancellation(error) { return }
                if attempt == Self.maxAttempts - 1 {
                    didFail = image == nil
                } else {
                    try? await Task.sleep(nanoseconds: UInt64(150_000_000 * (attempt + 1)))
                }
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }
}
