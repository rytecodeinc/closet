//
//  LocationSnapshotView.swift
//  closet
//
//  Created by Dan Warner on 10/11/25.
//

import SwiftUI
import MapKit
import UIKit

struct LocationSnapshotView: View {
    var address: String?
    var latitude: Double?
    var longitude: Double?

    @State private var snapshotImage: UIImage? = nil
    @State private var loadedIdentity: String?

    private var snapshotIdentity: String {
        let hasCoordinate = latitude.map { lat in
            longitude.map { lon in lat != 0 || lon != 0 } ?? false
        } ?? false
        if hasCoordinate, let latitude, let longitude {
            return String(format: "coord:%.5f,%.5f", latitude, longitude)
        }
        let trimmed = address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "address:\(trimmed)"
    }

    var body: some View {
        Group {
            if let image = snapshotImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(ProgressView())
                    .aspectRatio(16 / 9, contentMode: .fill)
            }
        }
        .task(id: snapshotIdentity) {
            await loadSnapshotIfNeeded()
        }
    }

    @MainActor
    private func loadSnapshotIfNeeded() async {
        let identity = snapshotIdentity
        if loadedIdentity == identity, snapshotImage != nil { return }

        guard let coordinate = await resolveCoordinate() else { return }
        guard !Task.isCancelled, identity == snapshotIdentity else { return }

        let size = CGSize(
            width: UIScreen.main.bounds.width,
            height: UIScreen.main.bounds.width * 9 / 16
        )
        let scale = UIScreen.main.scale

        let image = await Self.renderSnapshot(
            coordinate: coordinate,
            size: size,
            scale: scale
        )
        guard !Task.isCancelled, identity == snapshotIdentity else { return }
        guard let image else { return }

        snapshotImage = image
        loadedIdentity = identity
    }

    private func resolveCoordinate() async -> CLLocationCoordinate2D? {
        if let latitude, let longitude, latitude != 0 || longitude != 0 {
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        let trimmed = address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(trimmed)
            return placemarks.first?.location?.coordinate
        } catch {
            print("Error geocoding map snapshot address: \(error)")
            return nil
        }
    }

    nonisolated private static func renderSnapshot(
        coordinate: CLLocationCoordinate2D,
        size: CGSize,
        scale: CGFloat
    ) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        options.size = size
        options.scale = scale

        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            return imageByDrawingPin(on: snapshot, at: coordinate)
        } catch {
            print("Error generating map snapshot: \(error)")
            return nil
        }
    }

    /// Composites a map pin so the tip sits on `coordinate`.
    nonisolated private static func imageByDrawingPin(
        on snapshot: MKMapSnapshotter.Snapshot,
        at coordinate: CLLocationCoordinate2D
    ) -> UIImage {
        let base = snapshot.image
        let point = snapshot.point(for: coordinate)
        let format = UIGraphicsImageRendererFormat()
        format.scale = base.scale
        let renderer = UIGraphicsImageRenderer(size: base.size, format: format)
        return renderer.image { _ in
            base.draw(at: .zero)

            let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
            guard let pin = UIImage(systemName: "mappin.circle.fill", withConfiguration: config)?
                .withTintColor(.systemRed, renderingMode: .alwaysOriginal) else {
                return
            }
            let pinSize = pin.size
            let origin = CGPoint(
                x: point.x - pinSize.width / 2,
                y: point.y - pinSize.height
            )
            pin.draw(at: origin)
        }
    }
}
