//
//  PhotoContentBounds.swift
//  closet
//
//  Normalized cutout bounds (0…1) stored on Photo at save time for layout without alpha scans.
//

import UIKit
import CoreData

struct NormalizedContentBounds: Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    var aspectRatio: CGFloat {
        guard height > 0 else { return 1 }
        return width / height
    }

    var midX: CGFloat { x + width / 2 }
    var midY: CGFloat { y + height / 2 }

    var area: CGFloat { max(width, 0.001) * max(height, 0.001) }

    static let fullFrame = NormalizedContentBounds(x: 0, y: 0, width: 1, height: 1)
}

enum PhotoContentBounds {

    /// Computes opaque-pixel bounds in normalized image coordinates (relative to `cgImage` pixels).
    static func normalizedBounds(for image: UIImage) -> NormalizedContentBounds {
        guard let cgImage = image.cgImage else { return .fullFrame }
        let pixelW = CGFloat(cgImage.width)
        let pixelH = CGFloat(cgImage.height)
        guard pixelW > 0, pixelH > 0 else { return .fullFrame }

        let pixelBounds = image.nonTransparentContentBoundsInPixelSpace()
            ?? CGRect(x: 0, y: 0, width: pixelW, height: pixelH)

        guard pixelBounds.width > 0, pixelBounds.height > 0 else { return .fullFrame }

        return NormalizedContentBounds(
            x: pixelBounds.origin.x / pixelW,
            y: pixelBounds.origin.y / pixelH,
            width: pixelBounds.width / pixelW,
            height: pixelBounds.height / pixelH
        )
    }

    static func writeNormalizedContentBounds(from image: UIImage, to photo: Photo) {
        let b = normalizedBounds(for: image)
        photo.contentBoundsX = Double(b.x)
        photo.contentBoundsY = Double(b.y)
        photo.contentBoundsW = Double(b.width)
        photo.contentBoundsH = Double(b.height)
    }

    static func clear(on photo: Photo) {
        photo.contentBoundsX = 0
        photo.contentBoundsY = 0
        photo.contentBoundsW = 0
        photo.contentBoundsH = 0
    }

    static func read(from photo: Photo) -> NormalizedContentBounds? {
        let w = photo.contentBoundsW
        let h = photo.contentBoundsH
        guard w > 0, h > 0 else { return nil }
        return NormalizedContentBounds(
            x: CGFloat(photo.contentBoundsX),
            y: CGFloat(photo.contentBoundsY),
            width: CGFloat(w),
            height: CGFloat(h)
        )
    }

    static func contentAspectRatio(for photo: Photo) -> CGFloat {
        read(from: photo)?.aspectRatio ?? 1
    }

    static func primaryPhoto(for item: Item) -> Photo? {
        let photos = item.photos as? Set<Photo> ?? []
        if let front = photos.first(where: { $0.type == "front" }) { return front }
        if let primary = photos.first(where: { $0.isPrimary && ($0.type == nil || $0.type == "") }) { return primary }
        return photos.first
    }

    static func contentAspectRatio(for item: Item) -> CGFloat {
        contentBounds(for: item).aspectRatio
    }

    static func contentBounds(for item: Item) -> NormalizedContentBounds {
        guard let photo = primaryPhoto(for: item), let bounds = read(from: photo) else {
            return .fullFrame
        }
        return bounds
    }

    /// Assigns image bytes and persists normalized cutout bounds from the same `UIImage`.
    static func assignImage(_ image: UIImage, to photo: Photo, data: Data) {
        photo.data = data
        writeNormalizedContentBounds(from: image, to: photo)
    }

    /// Assigns encoded bytes; bounds are taken from decoded stored pixels when possible.
    static func assignProcessedData(_ data: Data?, sourceImage: UIImage, to photo: Photo) {
        guard let data, !data.isEmpty else {
            photo.data = nil
            clear(on: photo)
            return
        }
        let imageForBounds = UIImage(data: data) ?? sourceImage
        assignImage(imageForBounds, to: photo, data: data)
    }
}
