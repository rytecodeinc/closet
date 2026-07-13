//
//  PublicUserProfileAvatarView.swift
//  closet
//
//  Circular avatar for public profiles: remote image when `avatarUrl` is set, otherwise initials.
//

import SwiftUI
import UIKit

struct PublicUserProfileAvatarView: View {
    let profile: PublicUserProfile
    var size: CGFloat = 44

    @State private var remoteImage: UIImage?
    @State private var loadedRemoteURLString: String?
    @State private var isLoadingRemote = false

    var body: some View {
        Group {
            if let image = displayedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if resolvedRemoteURL != nil, isLoadingRemote {
                initialsPlaceholder
                    .overlay { ProgressView() }
            } else {
                initialsPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: remoteLoadToken) {
            await loadRemoteImageIfNeeded()
        }
    }

    /// Prefer local file, then loaded state, then in-memory cache (avoids initials flash on remount).
    private var displayedImage: UIImage? {
        if let resolvedLocalImage { return resolvedLocalImage }
        if let remoteImage { return remoteImage }
        if let urlKey = resolvedRemoteURL?.absoluteString {
            return ProfileAvatarImageCache.image(for: urlKey)
        }
        return nil
    }

    private var remoteLoadToken: String {
        resolvedRemoteURL?.absoluteString ?? ""
    }

    private var resolvedLocalImage: UIImage? {
        // Cloud HTTPS URLs must win over any leftover on-disk TestFlight/local file.
        if let url = resolvedStoredURL, !url.isFileURL {
            return nil
        }
        if let url = resolvedStoredURL, url.isFileURL,
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        // No stored URL: allow local-only avatar (TestFlight / offline).
        if resolvedStoredURL == nil,
           ProfileAvatarLocalStorage.hasSavedAvatar(userId: profile.userId) {
            let path = ProfileAvatarLocalStorage.fileURL(for: profile.userId).path
            return UIImage(contentsOfFile: path)
        }
        return nil
    }

    /// HTTPS (or other remote) URL — never a missing `file://` path (AsyncImage logs cache errors).
    private var resolvedRemoteURL: URL? {
        guard let url = resolvedStoredURL, !url.isFileURL else { return nil }
        return url
    }

    private var resolvedStoredURL: URL? {
        guard let raw = profile.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    @MainActor
    private func loadRemoteImageIfNeeded() async {
        guard resolvedLocalImage == nil, let url = resolvedRemoteURL else {
            isLoadingRemote = false
            return
        }

        let urlKey = url.absoluteString
        if loadedRemoteURLString == urlKey, remoteImage != nil {
            return
        }
        if let cached = ProfileAvatarImageCache.image(for: urlKey) {
            remoteImage = cached
            loadedRemoteURLString = urlKey
            isLoadingRemote = false
            return
        }

        // Keep any existing image visible while fetching a *new* URL.
        if loadedRemoteURLString != urlKey {
            // Only blank when switching to a different avatar URL.
            if remoteImage != nil, loadedRemoteURLString != nil {
                remoteImage = nil
            }
        }

        isLoadingRemote = true
        defer { isLoadingRemote = false }

        do {
            var request = URLRequest(url: url)
            // Prefer cache for steady UI; uploads use unique `?v=` so new photos still refresh.
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                return
            }
            ProfileAvatarImageCache.store(image, for: urlKey)
            remoteImage = image
            loadedRemoteURLString = urlKey
        } catch {
            // Keep initials / previous image on failure.
        }
    }

    private var initialsPlaceholder: some View {
        ZStack {
            Circle()
                .fill(initialsBackgroundColor)
            Text(profileInitials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.85))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }

    private var profileInitials: String {
        let name = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty {
            let parts = name.split(separator: " ").filter { !$0.isEmpty }
            if parts.count >= 2 {
                let a = parts[0].prefix(1)
                let b = parts[parts.count - 1].prefix(1)
                return "\(a)\(b)".uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }
        return String(profile.username.prefix(2)).uppercased()
    }

    private var initialsBackgroundColor: Color {
        var hasher = Hasher()
        hasher.combine(profile.userId)
        let h = abs(hasher.finalize()) % 360
        return Color(hue: Double(h) / 360.0, saturation: 0.38, brightness: 0.88)
    }
}

enum ProfileAvatarImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    static func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    static func remove(for key: String) {
        cache.removeObject(forKey: key as NSString)
    }
}
