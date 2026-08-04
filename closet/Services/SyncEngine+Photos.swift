//
//  SyncEngine+Photos
//  closet
//

import CoreData
import Foundation
import Supabase
import UIKit


extension SyncEngine {
    func syncItemPhotos(itemObjectID: NSManagedObjectID, itemId: UUID, userId: UUID) async throws {
        let itemName = try await withSyncItem(itemObjectID) { $0.name ?? "unnamed" }
        print("📸 Starting photo sync for item: \(itemName) (ID: \(itemId.uuidString))")
        
        // STEP 1: Get what photos SHOULD exist (from Core Data)
        let currentPhotoIds = try await withSyncItem(itemObjectID) { item -> Set<String> in
            if let photos = item.photos as? Set<Photo> {
                print("📸 Core Data shows \(photos.count) photos for this item")
                return Set(photos.compactMap { $0.id?.uuidString })
            }
            print("📸 Core Data shows 0 photos for this item")
            return Set()
        }
        
        // STEP 2: Get what photos currently exist in Supabase (BEFORE making any changes)
        let existingPhotosResponse = try await (await getSupabase()).supabaseClient.from("item_photos")
            .select("id")
            .eq("item_id", value: itemId.uuidString)
            .execute()
        
        let data: Data = existingPhotosResponse.data
        let existingPhotoIds: Set<String>
        if let existingPhotos = try? JSONDecoder().decode([ItemPhotoResponse].self, from: data) {
            existingPhotoIds = Set(existingPhotos.compactMap { $0.id })
            print("📸 Supabase shows \(existingPhotoIds.count) existing photos")
        } else {
            existingPhotoIds = Set()
            print("📸 Supabase shows 0 existing photos (or failed to decode)")
        }
        
        // STEP 3: Delete photos that no longer exist in Core Data
        let photosToDelete = existingPhotoIds.subtracting(currentPhotoIds)
        if !photosToDelete.isEmpty {
            print("🗑️ Deleting \(photosToDelete.count) orphaned photos from R2 and Supabase")
            for photoIdToDelete in photosToDelete {
                guard let photoUUID = UUID(uuidString: photoIdToDelete) else {
                    print("⚠️ Invalid photo ID format: \(photoIdToDelete)")
                    continue
                }
                
                // Delete from R2 (full image)
                do {
                    try await (await getSupabase()).deletePhoto(
                        itemId: itemId,
                        photoId: photoUUID,
                        userId: userId
                    )
                    print("✅ Deleted photo from R2: \(photoIdToDelete)")
                } catch {
                    print("⚠️ Failed to delete photo \(photoIdToDelete) from R2: \(error.localizedDescription)")
                    // Continue with other deletions even if one fails
                }
                
                // Delete thumbnail from R2 (thumbnails use _thumb suffix)
                do {
                    let thumbnailFileName = "\(userId.uuidString)/\(itemId.uuidString)/\(photoIdToDelete)_thumb.jpg"
                    let thumbnailUrl = URL(string: "\(CloudflareR2Config.workerURL)/\(thumbnailFileName)")!
                    
                    guard let session = await getSupabase().currentSession else {
                        print("⚠️ No session available for thumbnail deletion")
                        continue
                    }
                    
                    var thumbnailRequest = URLRequest(url: thumbnailUrl)
                    thumbnailRequest.httpMethod = "DELETE"
                    thumbnailRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
                    
                    let (_, response) = try await URLSession.shared.data(for: thumbnailRequest)
                    if let httpResponse = response as? HTTPURLResponse,
                       (200...299).contains(httpResponse.statusCode) {
                        print("✅ Deleted thumbnail from R2: \(photoIdToDelete)")
                    }
                } catch {
                    print("⚠️ Failed to delete thumbnail \(photoIdToDelete) from R2: \(error.localizedDescription)")
                    // Continue with other deletions even if one fails
                }
                
                // Delete from Supabase item_photos table
                do {
                    try await (await getSupabase()).supabaseClient.from("item_photos")
                        .delete()
                        .eq("id", value: photoIdToDelete)
                        .execute()
                    print("✅ Deleted photo metadata from Supabase: \(photoIdToDelete)")
                } catch {
                    print("⚠️ Failed to delete photo \(photoIdToDelete) from Supabase: \(error)")
                }
            }
        } else {
            print("📸 No orphaned photos to delete")
        }
        
        // STEP 4: Now sync current photos (upsert new/existing)
        let photoObjectIDs = try await withSyncItem(itemObjectID) { item in
            (item.photos as? Set<Photo>)?.map { $0.objectID } ?? []
        }
        if !photoObjectIDs.isEmpty {
            print("📸 Upserting \(photoObjectIDs.count) current photos to Supabase")
            for photoObjectID in photoObjectIDs {
                try await syncPhoto(objectID: photoObjectID, itemId: itemId, userId: userId)
            }
            print("✅ Finished syncing \(photoObjectIDs.count) photos")
        } else {
            print("📸 No photos in Core Data")
        }

        await (await getSupabase()).invalidateWardrobeGridItemsCache(forUserId: userId)
    }

    func syncItemPhotos(_ item: Item, itemId: UUID, userId: UUID) async throws {
        try await syncItemPhotos(itemObjectID: item.objectID, itemId: itemId, userId: userId)
    }
    
    /// Target max payload size for R2 worker (5 MB); stay slightly under for safety.
    static let r2WorkerSafeMaxBytes = 4_800_000

    /// Hard ceiling (5 MiB); reject encoded output that still exceeds worker limits.
    static let r2WorkerHardMaxBytes = 5 * 1024 * 1024

    /// Ensures image bytes respect the worker cap. When re-encoding, updates `photo.data` so Core Data matches the CDN.
    static func imageDataPreparedForR2Upload(original: Data, photo: Photo) throws -> Data {
        if original.count <= Self.r2WorkerSafeMaxBytes {
            return original
        }
        guard let image = UIImage(data: original) else {
            print("❌ Photo \(photo.id?.uuidString ?? "?"): cannot decode; \(original.count) bytes > R2 safe limit")
            throw SyncError.photoExceedsWorkerLimit
        }
        let encoded =
            image.encodeForR2Upload(maxBytes: Self.r2WorkerSafeMaxBytes)
            ?? image.processForStorage(maxDimension: 1200, maxFileSizeKB: 450)
        guard let data = encoded, !data.isEmpty else {
            print("❌ Photo \(photo.id?.uuidString ?? "?"): R2 encode failed")
            throw SyncError.photoEncodingFailed
        }
        guard data.count <= Self.r2WorkerHardMaxBytes else {
            print("❌ Photo \(photo.id?.uuidString ?? "?"): encoded size \(data.count) still exceeds worker max")
            throw SyncError.photoExceedsWorkerLimit
        }
        if let storedImage = UIImage(data: data) {
            PhotoContentBounds.assignImage(storedImage, to: photo, data: data)
        } else {
            photo.data = data
        }
        print("📦 R2-safe full image: \(original.count) → \(data.count) bytes")
        return data
    }

    /// Syncs a photo to Cloudflare R2 via Worker and stores URL
    /// Each photo (front, back, worn) has a unique photoId, ensuring they don't conflict
    /// Uploads both full image and thumbnail to R2 for storage efficiency
    /// Handles migration from base64 thumbnails to R2 URLs
    func syncPhoto(objectID: NSManagedObjectID, itemId: UUID, userId: UUID) async throws {
        try await syncPhotoResolved(objectID: objectID, itemId: itemId, userId: userId)
    }

    func syncPhoto(_ photo: Photo, itemId: UUID, userId: UUID) async throws {
        try await syncPhoto(objectID: photo.objectID, itemId: itemId, userId: userId)
    }

    func syncPhotoResolved(objectID: NSManagedObjectID, itemId: UUID, userId: UUID) async throws {
        func photo<T>(_ work: @escaping (Photo) throws -> T) async throws -> T {
            try await performOnSyncContext { ctx in
                guard let p = try ctx.existingObject(with: objectID) as? Photo else { throw SyncError.noContext }
                return try work(p)
            }
        }
        func mutatePhoto(_ work: @escaping (Photo) throws -> Void) async throws {
            try await performOnSyncContext { ctx in
                guard let p = try ctx.existingObject(with: objectID) as? Photo else { return }
                try work(p)
                if ctx.hasChanges { try ctx.save() }
            }
        }

        guard let photoId = try await photo({ $0.id }) else {
            print("⚠️ Photo missing ID, skipping sync")
            return
        }

        var imageUrl: String? = nil
        var thumbnailUrl: String? = nil
        
        // Check if we have existing R2 URLs (not base64)
        let existingImageUrl = try await photo({ $0.imageUrl })
        let hasValidImageUrl = existingImageUrl != nil && !existingImageUrl!.isEmpty && !existingImageUrl!.starts(with: "data:")
        
        let existingThumbnailUrl = try await photo({ $0.thumbnailUrl })
        let hasValidThumbnailUrl = existingThumbnailUrl != nil && !existingThumbnailUrl!.isEmpty && !existingThumbnailUrl!.starts(with: "data:")
        
        // STEP 1: Upload full image if needed
        if let imageData = try await photo({ $0.data }), !imageData.isEmpty {
            let payload = try await performOnSyncContext { ctx -> Data in
                guard let p = try ctx.existingObject(with: objectID) as? Photo else { throw SyncError.noContext }
                return try Self.imageDataPreparedForR2Upload(original: imageData, photo: p)
            }
            imageUrl = try await (await getSupabase()).uploadPhoto(
                imageData: payload,
                itemId: itemId,
                photoId: photoId,
                userId: userId
            )
            try await mutatePhoto { $0.imageUrl = imageUrl }
            print("✅ Uploaded new image to R2: \(imageUrl ?? "nil")")
        } else if hasValidImageUrl {
            imageUrl = existingImageUrl
            print("✅ Using existing image URL: \(imageUrl ?? "nil")")
        } else {
            print("⚠️ No image data and no valid R2 URL for photo \(photoId)")
        }
        
        // STEP 2: Upload thumbnail
        if let thumbnailData = try await photo({ $0.thumbnailData }), !thumbnailData.isEmpty {
            thumbnailUrl = try await (await getSupabase()).uploadThumbnail(
                imageData: thumbnailData,
                itemId: itemId,
                photoId: photoId,
                userId: userId
            )
            try await mutatePhoto { $0.thumbnailUrl = thumbnailUrl }
            print("✅ Uploaded new thumbnail to R2: \(thumbnailUrl ?? "nil")")
        } else if hasValidThumbnailUrl {
            thumbnailUrl = existingThumbnailUrl
            print("✅ Using existing thumbnail URL: \(thumbnailUrl ?? "nil")")
        } else {
            // MIGRATION: If we have base64 thumbnail, re-generate from image
            if let existingThumb = try await photo({ $0.thumbnailUrl }), existingThumb.starts(with: "data:") {
                print("🔄 Migrating base64 thumbnail to R2 for photo \(photoId)")
                
                // Try to get thumbnail data from the base64 string or re-generate from full image
                if let imageData = try await photo({ $0.data }), !imageData.isEmpty {
                    // Generate thumbnail from full image
                    if let thumbnailData = generateThumbnail(from: imageData) {
                        thumbnailUrl = try await (await getSupabase()).uploadThumbnail(
                            imageData: thumbnailData,
                            itemId: itemId,
                            photoId: photoId,
                            userId: userId
                        )
                        try await mutatePhoto { $0.thumbnailUrl = thumbnailUrl }
                        try await mutatePhoto { $0.thumbnailData = thumbnailData }
                        print("✅ Migrated thumbnail to R2: \(thumbnailUrl ?? "nil")")
                    }
                } else {
                    print("⚠️ Cannot migrate thumbnail - no image data available")
                }
            }
        }
        
        // STEP 3: Update metadata in Supabase
        try await updatePhotoMetadata(objectID: objectID, itemId: itemId, userId: userId, imageUrl: imageUrl, thumbnailUrl: thumbnailUrl)
    }
    
    /// Updates photo metadata in Supabase
    /// Uses thumbnail URL from R2 instead of base64 for storage efficiency
    func updatePhotoMetadata(objectID: NSManagedObjectID, itemId: UUID, userId: UUID, imageUrl: String? = nil, thumbnailUrl: String? = nil) async throws {
        let photoData = try await performOnSyncContext { ctx -> SyncPhotoData? in
            guard let photo = try ctx.existingObject(with: objectID) as? Photo, let photoId = photo.id else { return nil }
            let url = imageUrl ?? photo.imageUrl
            let thumbUrl = thumbnailUrl ?? photo.thumbnailUrl
            return SyncPhotoData(
                id: photoId.uuidString,
                itemId: itemId.uuidString,
                userId: userId.uuidString,
                imageUrl: url,
                isPrimary: photo.isPrimary,
                type: photo.type,
                createdAt: photo.createdAt?.ISO8601String ?? photo.timestamp?.ISO8601String,
                thumbnailUrl: thumbUrl,
                timestamp: photo.timestamp?.ISO8601String,
                updatedAt: Date().ISO8601String
            )
        }
        guard let photoData else { return }
        try await (await getSupabase()).supabaseClient.from("item_photos")
            .upsert(photoData, onConflict: "id")
            .execute()
        print("✅ Updated photo metadata in Supabase: \(photoData.id)")
        if let thumbUrl = photoData.thumbnailUrl {
            print("   Thumbnail URL: \(thumbUrl)")
        }
    }

    func updatePhotoMetadata(_ photo: Photo, itemId: UUID, userId: UUID, imageUrl: String? = nil, thumbnailUrl: String? = nil) async throws {
        try await updatePhotoMetadata(objectID: photo.objectID, itemId: itemId, userId: userId, imageUrl: imageUrl, thumbnailUrl: thumbnailUrl)
    }
    
    /// Generates a thumbnail from full image data
    func generateThumbnail(from imageData: Data, maxSize: CGFloat = 200) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        
        let size = image.size
        let aspectRatio = size.width / size.height
        
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            newSize = CGSize(width: maxSize * aspectRatio, height: maxSize)
        }
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return thumbnail?.jpegData(compressionQuality: 0.7)
    }
    
    /// Downloads image data from URL
    func downloadImage(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "SyncService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}
