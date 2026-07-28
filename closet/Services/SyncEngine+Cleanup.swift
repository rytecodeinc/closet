//
//  SyncEngine+Cleanup.swift
//  closet
//

import CoreData
import Foundation

extension SyncEngine {

    /// Removes orphaned data from Supabase and R2 (items/photos in cloud but not in local Core Data).
    func cleanupOrphanedData(userId: UUID, progress: SyncProgressHandler?) async throws {
        print("🧹 Starting orphaned data cleanup for user: \(userId.uuidString)")

        let itemRequest: NSFetchRequest<Item> = Item.fetchRequest()
        itemRequest.predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        itemRequest.propertiesToFetch = ["id"]
        let localItems = try await performOnSyncContext { ctx in try ctx.fetch(itemRequest) }
        let localItemIds = Set(localItems.compactMap { $0.id?.uuidString })
        print("📦 Found \(localItemIds.count) items in Core Data")

        let supabase = await getSupabase()
        let supabaseItemsResponse = try await supabase.supabaseClient.from("items")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .execute()

        struct ItemIdResponse: Codable {
            let id: String
        }
        let supabaseItems = try JSONDecoder().decode([ItemIdResponse].self, from: supabaseItemsResponse.data)
        let supabaseItemIds = Set(supabaseItems.map { $0.id })
        print("📦 Found \(supabaseItemIds.count) items in Supabase")

        let orphanedItemIds = supabaseItemIds.subtracting(localItemIds)
        print("🗑️ Found \(orphanedItemIds.count) orphaned items")

        var deletedPhotos = 0
        var deletedThumbnails = 0
        var deletedJunctionEntries = 0

        for (index, orphanedItemId) in orphanedItemIds.enumerated() {
            let fraction = orphanedItemIds.isEmpty ? 1.0 : Double(index) / Double(orphanedItemIds.count)
            progress?("Cleaning up item \(index + 1) of \(orphanedItemIds.count)...", fraction)

            guard let itemUUID = UUID(uuidString: orphanedItemId) else {
                print("⚠️ Invalid item ID format: \(orphanedItemId)")
                continue
            }

            print("🗑️ Cleaning up orphaned item: \(orphanedItemId)")

            let photosResponse = try await supabase.supabaseClient.from("item_photos")
                .select("id")
                .eq("item_id", value: orphanedItemId)
                .execute()

            if let photos = try? JSONDecoder().decode([ItemPhotoResponse].self, from: photosResponse.data) {
                for photo in photos {
                    guard let photoUUID = UUID(uuidString: photo.id) else { continue }

                    do {
                        try await supabase.deletePhoto(
                            itemId: itemUUID,
                            photoId: photoUUID,
                            userId: userId
                        )
                        deletedPhotos += 1
                        print("✅ Deleted photo from R2: \(photo.id)")
                    } catch {
                        print("⚠️ Failed to delete photo \(photo.id) from R2: \(error.localizedDescription)")
                    }

                    do {
                        let thumbnailFileName = "\(userId.uuidString)/\(orphanedItemId)/\(photo.id)_thumb.jpg"
                        let thumbnailUrl = URL(string: "\(CloudflareR2Config.workerURL)/\(thumbnailFileName)")!

                        guard let session = await MainActor.run(body: { supabase.currentSession }) else { continue }

                        var thumbnailRequest = URLRequest(url: thumbnailUrl)
                        thumbnailRequest.httpMethod = "DELETE"
                        thumbnailRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

                        let (_, response) = try await URLSession.shared.data(for: thumbnailRequest)
                        if let httpResponse = response as? HTTPURLResponse,
                           (200...299).contains(httpResponse.statusCode) {
                            deletedThumbnails += 1
                            print("✅ Deleted thumbnail from R2: \(photo.id)")
                        }
                    } catch {
                        print("⚠️ Failed to delete thumbnail \(photo.id) from R2: \(error.localizedDescription)")
                    }
                }

                do {
                    try await supabase.supabaseClient.from("item_photos")
                        .delete()
                        .eq("item_id", value: orphanedItemId)
                        .execute()
                } catch {
                    print("⚠️ Failed to delete photo metadata for item \(orphanedItemId): \(error.localizedDescription)")
                }
            }

            let junctionTables = [
                "item_colors",
                "item_seasons",
                "item_tags",
                "item_wardrobes",
                "item_links",
                "item_prices",
                "item_pairs"
            ]

            for table in junctionTables {
                do {
                    _ = try await supabase.supabaseClient.from(table)
                        .delete()
                        .eq("item_id", value: orphanedItemId)
                        .execute()
                    deletedJunctionEntries += 1
                    print("✅ Deleted entries from \(table) for item: \(orphanedItemId)")
                } catch {
                    print("⚠️ Failed to delete from \(table) for item \(orphanedItemId): \(error.localizedDescription)")
                }

                if table == "item_pairs" {
                    do {
                        try await supabase.supabaseClient.from(table)
                            .delete()
                            .eq("paired_item_id", value: orphanedItemId)
                            .execute()
                        print("✅ Deleted reverse pairs for item: \(orphanedItemId)")
                    } catch {
                        print("⚠️ Failed to delete reverse pairs for item \(orphanedItemId): \(error.localizedDescription)")
                    }
                }
            }

            try await supabase.supabaseClient.from("items")
                .delete()
                .eq("id", value: orphanedItemId)
                .execute()

            print("✅ Cleaned up orphaned item: \(orphanedItemId)")
        }

        let photoRequest: NSFetchRequest<Photo> = Photo.fetchRequest()
        let allLocalPhotos = try await performOnSyncContext { ctx in try ctx.fetch(photoRequest) }
        let localPhotoIds = Set(allLocalPhotos.compactMap { $0.id?.uuidString })
        print("📸 Found \(localPhotoIds.count) photos in Core Data")

        if !localItemIds.isEmpty {
            let itemIdsArray = Array(localItemIds)
            let allPhotosResponse = try await supabase.supabaseClient.from("item_photos")
                .select("id, item_id")
                .in("item_id", values: itemIdsArray)
                .execute()

            struct PhotoWithItemResponse: Codable {
                let id: String
                let itemId: String

                enum CodingKeys: String, CodingKey {
                    case id
                    case itemId = "item_id"
                }
            }

            if let allPhotos = try? JSONDecoder().decode([PhotoWithItemResponse].self, from: allPhotosResponse.data) {
                let orphanedPhotos = allPhotos.filter { !localPhotoIds.contains($0.id) }
                print("📸 Found \(orphanedPhotos.count) orphaned photos for existing items")

                for photo in orphanedPhotos {
                    guard let itemUUID = UUID(uuidString: photo.itemId),
                          let photoUUID = UUID(uuidString: photo.id) else { continue }

                    do {
                        try await supabase.deletePhoto(
                            itemId: itemUUID,
                            photoId: photoUUID,
                            userId: userId
                        )
                        deletedPhotos += 1
                        print("✅ Deleted orphaned photo from R2: \(photo.id)")
                    } catch {
                        print("⚠️ Failed to delete orphaned photo \(photo.id) from R2: \(error.localizedDescription)")
                    }

                    do {
                        let thumbnailFileName = "\(userId.uuidString)/\(photo.itemId)/\(photo.id)_thumb.jpg"
                        let thumbnailUrl = URL(string: "\(CloudflareR2Config.workerURL)/\(thumbnailFileName)")!

                        guard let session = await MainActor.run(body: { supabase.currentSession }) else { continue }

                        var thumbnailRequest = URLRequest(url: thumbnailUrl)
                        thumbnailRequest.httpMethod = "DELETE"
                        thumbnailRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

                        let (_, response) = try await URLSession.shared.data(for: thumbnailRequest)
                        if let httpResponse = response as? HTTPURLResponse,
                           (200...299).contains(httpResponse.statusCode) {
                            deletedThumbnails += 1
                            print("✅ Deleted orphaned thumbnail from R2: \(photo.id)")
                        }
                    } catch {
                        print("⚠️ Failed to delete orphaned thumbnail \(photo.id) from R2: \(error.localizedDescription)")
                    }

                    do {
                        try await supabase.supabaseClient.from("item_photos")
                            .delete()
                            .eq("id", value: photo.id)
                            .execute()
                        print("✅ Deleted orphaned photo metadata from Supabase: \(photo.id)")
                    } catch {
                        print("⚠️ Failed to delete orphaned photo \(photo.id) from Supabase: \(error.localizedDescription)")
                    }
                }
            }
        }

        progress?("Cleanup complete!", 1)

        print("✅ Cleanup complete!")
        print("   - Deleted \(orphanedItemIds.count) orphaned items")
        print("   - Deleted \(deletedPhotos) orphaned photos from R2")
        print("   - Deleted \(deletedThumbnails) orphaned thumbnails from R2")
        print("   - Deleted \(deletedJunctionEntries) junction table entries")

        try await cleanupOrphanedOutfits(userId: userId)
    }
}
