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
        if let front = ItemPhotoSlot.photosMatching(photos, slot: "front").first(where: {
            ItemPhotoSlot.normalizedType($0) == "front"
        }) {
            return front
        }
        if let legacy = ItemPhotoSlot.photosMatching(photos, slot: "front").first {
            return legacy
        }
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

// MARK: - Photo slot replace / delete

/// Shared front/worn replace rules. Prevents leftover primaries / empty-type fronts
/// from surviving a replace (the stale-primary Profile image bug).
enum ItemPhotoSlot {
    static func normalizedType(_ photo: Photo) -> String {
        (photo.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Photos to remove when replacing/deleting a slot. Front also clears legacy primary /
    /// empty-type slots so Profile/read-only detail cannot keep serving a deleted image.
    static func photosMatching(_ photos: Set<Photo>, slot type: String) -> [Photo] {
        let target = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return photos.filter { photo in
            let t = normalizedType(photo)
            if t == target { return true }
            if target == "front", photo.isPrimary, t.isEmpty { return true }
            return false
        }
    }

    static func deleteMatching(in item: Item, slot type: String, context: NSManagedObjectContext) {
        let photos = (item.photos as? Set<Photo>) ?? []
        for photo in photosMatching(photos, slot: type) {
            context.delete(photo)
        }
        if type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "front" {
            demoteOtherPrimaries(in: item, keeping: nil)
        }
    }

    /// Item back photos were retired (front + worn only). Removes local rows so sync can drop R2.
    @discardableResult
    static func purgeRetiredBackPhotos(in item: Item, context: NSManagedObjectContext) -> Bool {
        let before = photosMatching((item.photos as? Set<Photo>) ?? [], slot: "back")
        guard !before.isEmpty else { return false }
        deleteMatching(in: item, slot: "back", context: context)
        return true
    }

    static func demoteOtherPrimaries(in item: Item, keeping kept: Photo?) {
        let photos = (item.photos as? Set<Photo>) ?? []
        for photo in photos where photo.isPrimary && photo.objectID != kept?.objectID {
            photo.isPrimary = false
        }
    }

    /// Configures a newly inserted photo for a slot after prior matches were deleted.
    static func configureReplacedPhoto(
        _ newPhoto: Photo,
        on item: Item,
        image: UIImage,
        processedData: Data?,
        type: String,
        asPrimary: Bool
    ) {
        let now = Date()
        if newPhoto.id == nil {
            newPhoto.id = UUID()
        }
        PhotoContentBounds.assignProcessedData(processedData, sourceImage: image, to: newPhoto)
        newPhoto.thumbnailData = image.generateThumbnail()
        newPhoto.type = type
        newPhoto.isPrimary = asPrimary
        newPhoto.createdAt = now
        newPhoto.timestamp = now
        // Drop stale remote URLs until upload finishes.
        newPhoto.imageUrl = nil
        newPhoto.thumbnailUrl = nil
        newPhoto.item = item
        if asPrimary {
            demoteOtherPrimaries(in: item, keeping: newPhoto)
        }
    }
}
