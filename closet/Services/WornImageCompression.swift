//
//  WornImageCompression.swift
//  closet
//
//  Shared worn-photo pipeline: opaque flatten, long edge ≤ 2048, JPEG ~0.8, soft ~1 MB cap.
//  Used by ItemAddView and Developer Settings bulk recompress. Does not touch front/back cutouts.
//

import CoreData
import Foundation
import UIKit

enum WornImageCompression {
    static let maxLongEdge: CGFloat = 2048
    static let targetMaxBytes = 1 * 1024 * 1024
    static let preferredQuality: CGFloat = 0.8
    static let minimumQuality: CGFloat = 0.55
    /// Bulk repair skips blobs already this small or smaller.
    static let skipUnderBytes = 400 * 1024

    struct RecompressResult: Sendable {
        var itemWornRecompressed = 0
        var outfitWornRecompressed = 0
        var itemWornSkipped = 0
        var outfitWornSkipped = 0
        var failures = 0
        var bytesBefore: Int64 = 0
        var bytesAfter: Int64 = 0

        var summaryMessage: String {
            let saved = max(0, bytesBefore - bytesAfter)
            return [
                "Item worn recompressed: \(itemWornRecompressed) (skipped \(itemWornSkipped))",
                "Outfit worn recompressed: \(outfitWornRecompressed) (skipped \(outfitWornSkipped))",
                "Failures: \(failures)",
                "Before: \(formatByteCount(Int(bytesBefore)))",
                "After: \(formatByteCount(Int(bytesAfter)))",
                "Saved: \(formatByteCount(Int(saved)))",
            ].joined(separator: "\n")
        }
    }

    /// Encodes a worn UIImage to JPEG. Same pipeline as ItemAddView worn upload.
    static func encode(_ image: UIImage, logLabel: String = "Worn") -> Data? {
        let pixelW: Int
        let pixelH: Int
        if let cgImage = image.cgImage {
            pixelW = cgImage.width
            pixelH = cgImage.height
        } else {
            let s = max(image.scale, 1)
            pixelW = Int(image.size.width * s)
            pixelH = Int(image.size.height * s)
        }

        let sourceJPEGBytes = image.jpegData(compressionQuality: 1.0)?.count
        let sourcePNGBytes = image.pngData()?.count
        var beforeParts = ["\(pixelW)×\(pixelH) px"]
        if let sourceJPEGBytes {
            beforeParts.append("source JPEG q1.0 \(formatByteCount(sourceJPEGBytes))")
        } else {
            beforeParts.append("source JPEG unavailable (unsupported pixel format)")
        }
        if let sourcePNGBytes {
            beforeParts.append("source PNG \(formatByteCount(sourcePNGBytes))")
        }
        print("📸 \(logLabel) upload (before compression): \(beforeParts.joined(separator: ", "))")

        guard let working = jpegCompatibleImage(image, maxLongEdge: maxLongEdge) else {
            print("⚠️ \(logLabel) compression failed: could not build JPEG-compatible bitmap")
            return nil
        }

        let outW = Int(working.size.width * working.scale)
        let outH = Int(working.size.height * working.scale)

        guard var best = working.jpegData(compressionQuality: preferredQuality) else {
            print("⚠️ \(logLabel) compression failed: could not encode JPEG after flatten")
            return nil
        }
        var quality = preferredQuality

        while best.count > targetMaxBytes, quality > minimumQuality {
            quality = max(minimumQuality, quality - 0.05)
            guard let next = working.jpegData(compressionQuality: quality) else { break }
            best = next
            if quality <= minimumQuality { break }
        }

        print("📸 \(logLabel) after compression: \(outW)×\(outH) px, \(formatByteCount(best.count)) JPEG @ q=\(String(format: "%.2f", quality))")
        return best
    }

    /// Recompresses existing item `worn` photos and outfit `wornImage` blobs for `userId`.
    /// Skips data ≤ 400 KB. Marks parents dirty and triggers sync. Front/back untouched.
    @MainActor
    static func recompressExisting(
        for userId: UUID,
        in context: NSManagedObjectContext
    ) async throws -> RecompressResult {
        let uid = userId.uuidString
        var result = RecompressResult()
        var itemsToSync: [Item] = []
        var outfitsToSync: [Outfit] = []

        // --- Item worn photos ---
        let photoRequest: NSFetchRequest<Photo> = Photo.fetchRequest()
        photoRequest.predicate = NSPredicate(
            format: "type ==[c] %@ AND item.userId == %@ AND (item.isSoftDeleted != YES OR item.isSoftDeleted == nil)",
            "worn",
            uid
        )

        let wornPhotos = try context.fetch(photoRequest)
        print("📦 Worn recompress: scanning \(wornPhotos.count) item worn photo(s)")

        for photo in wornPhotos {
            guard let data = photo.data, !data.isEmpty else {
                result.itemWornSkipped += 1
                continue
            }
            if data.count < skipUnderBytes {
                result.itemWornSkipped += 1
                continue
            }
            guard let image = UIImage(data: data) else {
                result.failures += 1
                print("⚠️ Item worn decode failed id=\(photo.id?.uuidString.prefix(8) ?? "?")")
                continue
            }

            let before = data.count
            let label = "Item worn \(photo.id?.uuidString.prefix(8) ?? "?")"
            let encoded = await Task.detached(priority: .userInitiated) {
                encode(image, logLabel: label)
            }.value

            guard let encoded, !encoded.isEmpty else {
                result.failures += 1
                continue
            }
            // Only write if we actually shrink (or match) — avoid growing already-efficient files.
            if encoded.count >= before {
                result.itemWornSkipped += 1
                print("ℹ️ Skipped item worn \(photo.id?.uuidString.prefix(8) ?? "?"): recompress did not shrink (\(formatByteCount(before)) → \(formatByteCount(encoded.count)))")
                continue
            }

            if let preview = UIImage(data: encoded) {
                PhotoContentBounds.assignImage(preview, to: photo, data: encoded)
                photo.thumbnailData = preview.generateThumbnail()
            } else {
                photo.data = encoded
            }

            result.itemWornRecompressed += 1
            result.bytesBefore += Int64(before)
            result.bytesAfter += Int64(encoded.count)

            if let item = photo.item {
                setUpdatedAt(item)
                if !itemsToSync.contains(where: { $0.objectID == item.objectID }) {
                    itemsToSync.append(item)
                }
            }
        }

        // --- Outfit worn images ---
        let outfitRequest: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        outfitRequest.predicate = NSPredicate(
            format: "userId == %@ AND wornImage != nil AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
            uid
        )

        let outfits = try context.fetch(outfitRequest)
        print("📦 Worn recompress: scanning \(outfits.count) outfit(s) with wornImage")

        for outfit in outfits {
            guard let data = outfit.wornImage, !data.isEmpty else {
                result.outfitWornSkipped += 1
                continue
            }
            if data.count < skipUnderBytes {
                result.outfitWornSkipped += 1
                continue
            }
            guard let image = UIImage(data: data) else {
                result.failures += 1
                print("⚠️ Outfit worn decode failed id=\(outfit.id?.uuidString.prefix(8) ?? "?")")
                continue
            }

            let before = data.count
            let label = "Outfit worn \(outfit.id?.uuidString.prefix(8) ?? "?")"
            let encoded = await Task.detached(priority: .userInitiated) {
                encode(image, logLabel: label)
            }.value

            guard let encoded, !encoded.isEmpty else {
                result.failures += 1
                continue
            }
            if encoded.count >= before {
                result.outfitWornSkipped += 1
                print("ℹ️ Skipped outfit worn \(outfit.id?.uuidString.prefix(8) ?? "?"): recompress did not shrink (\(formatByteCount(before)) → \(formatByteCount(encoded.count)))")
                continue
            }

            outfit.wornImage = encoded
            setUpdatedAt(outfit)

            result.outfitWornRecompressed += 1
            result.bytesBefore += Int64(before)
            result.bytesAfter += Int64(encoded.count)
            outfitsToSync.append(outfit)
        }

        if context.hasChanges {
            try context.save()
        }

        for item in itemsToSync {
            SyncService.shared.syncItemIfNeeded(item)
        }
        for outfit in outfitsToSync {
            SyncService.shared.syncOutfitIfNeeded(outfit)
        }

        print("📊 Worn recompress totals\n\(result.summaryMessage)")
        return result
    }

    // MARK: - Internals

    private static func jpegCompatibleImage(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage? {
        let pixelW: CGFloat
        let pixelH: CGFloat
        if let cgImage = image.cgImage {
            pixelW = CGFloat(cgImage.width)
            pixelH = CGFloat(cgImage.height)
        } else {
            let s = max(image.scale, 1)
            pixelW = max(image.size.width * s, 1)
            pixelH = max(image.size.height * s, 1)
        }

        let longest = max(pixelW, pixelH)
        let downscale = longest > maxLongEdge ? (maxLongEdge / longest) : 1
        let outW = max((pixelW * downscale).rounded(.toNearestOrAwayFromZero), 1)
        let outH = max((pixelH * downscale).rounded(.toNearestOrAwayFromZero), 1)
        let outSize = CGSize(width: outW, height: outH)

        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1.0
        format.preferredRange = .standard

        let renderer = UIGraphicsImageRenderer(size: outSize, format: format)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: outSize)).fill()
            image.draw(in: CGRect(origin: .zero, size: outSize))
        }
    }

    static func formatByteCount(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.2f MB", kb / 1024)
    }
}
