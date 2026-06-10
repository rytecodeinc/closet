//
//  SyncEngine+Items
//  closet
//

import CoreData
import Foundation
import Supabase
import UIKit


extension SyncEngine {
    func syncItem(objectID: NSManagedObjectID, userId: UUID) async throws {
        func loadItem<T>(_ work: @escaping (Item) throws -> T) async throws -> T {
            try await withSyncItem(objectID, work)
        }
        func mutateItem(_ work: @escaping (Item) throws -> Void) async throws {
            try await performOnSyncContext { ctx in
                guard let item = try ctx.existingObject(with: objectID) as? Item else { return }
                try work(item)
                if ctx.hasChanges { try ctx.save() }
            }
        }

        guard let itemId = try await loadItem({ $0.id }) else {
            print("⚠️ Item missing ID, skipping sync")
            return
        }
        
        // If soft-deleted, actually delete from Supabase and R2
        if try await loadItem({ $0.isSoftDeleted }) {
            print("🗑️ Deleting item from Supabase and R2: \(try await loadItem({ $0.name ?? "unnamed" }))")
            
            // STEP 1: Delete all photos from R2
            let deletePhotoIds = try await loadItem { item in
                (item.photos as? Set<Photo>)?.compactMap { $0.id } ?? []
            }
            for photoId in deletePhotoIds {
                    // Delete full image from R2
                    do {
                        try await (await getSupabase()).deletePhoto(
                            itemId: itemId,
                            photoId: photoId,
                            userId: userId
                        )
                        print("✅ Deleted photo from R2: \(photoId.uuidString)")
                    } catch {
                        print("⚠️ Failed to delete photo \(photoId.uuidString) from R2: \(error.localizedDescription)")
                    }

                    do {
                        let thumbnailFileName = "\(userId.uuidString)/\(itemId.uuidString)/\(photoId.uuidString)_thumb.jpg"
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
                            print("✅ Deleted thumbnail from R2: \(photoId.uuidString)")
                        }
                    } catch {
                        print("⚠️ Failed to delete thumbnail \(photoId.uuidString) from R2: \(error.localizedDescription)")
                    }
                }

            // STEP 2: Delete item relationships from Supabase (junction tables)
            // Delete item_colors
            do {
                try await (await getSupabase()).supabaseClient.from("item_colors")
                    .delete()
                    .eq("item_id", value: itemId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete item_colors: \(error.localizedDescription)")
            }
            
            // Delete item_seasons
            do {
                try await (await getSupabase()).supabaseClient.from("item_seasons")
                    .delete()
                    .eq("item_id", value: itemId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete item_seasons: \(error.localizedDescription)")
            }
            
            // Delete item_tags
            do {
                try await (await getSupabase()).supabaseClient.from("item_tags")
                    .delete()
                    .eq("item_id", value: itemId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete item_tags: \(error.localizedDescription)")
            }
            
            // Delete item_wardrobes
            do {
                try await (await getSupabase()).supabaseClient.from("item_wardrobes")
                    .delete()
                    .eq("item_id", value: itemId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete item_wardrobes: \(error.localizedDescription)")
            }
            
            // Delete item_pairs (both directions)
            do {
                try await (await getSupabase()).supabaseClient.from("item_pairs")
                    .delete()
                    .eq("item_id", value: itemId.uuidString)
                    .execute()
                
                try await (await getSupabase()).supabaseClient.from("item_pairs")
                    .delete()
                    .eq("paired_item_id", value: itemId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete item_pairs: \(error.localizedDescription)")
            }
            
            // Delete item_links
            do {
                try await (await getSupabase()).supabaseClient.from("item_links")
                    .delete()
                    .eq("item_id", value: itemId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete item_links: \(error.localizedDescription)")
            }
            
            // Delete item_prices
            do {
                try await (await getSupabase()).supabaseClient.from("item_prices")
                    .delete()
                    .eq("item_id", value: itemId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete item_prices: \(error.localizedDescription)")
            }
            
            // Delete item_photos
            do {
                try await (await getSupabase()).supabaseClient.from("item_photos")
                    .delete()
                    .eq("item_id", value: itemId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete item_photos: \(error.localizedDescription)")
            }
            
            // STEP 3: Delete the item itself from Supabase
            do {
                try await (await getSupabase()).supabaseClient.from("items")
                    .delete()
                    .eq("id", value: itemId.uuidString)
                    .execute()
                print("✅ Successfully deleted item from Supabase: \(try await loadItem({ $0.name ?? "unnamed" }))")
            } catch {
                print("❌ Failed to delete item from Supabase: \(error.localizedDescription)")
                throw error
            }
            
            // Mark as synced after successful deletion
            try await mutateItem { $0.syncedAt = Date() }
            print("✅ Successfully deleted item from Supabase and R2")

            // Now that backend deletion succeeded, purge the local tombstone later (safe timing).
            schedulePurgeCallback()
            return
        }
        
        // Otherwise, upsert as normal
        // Prepare item data using Codable struct
        // Sizes are now independent of categories, so we can always include size_id
        let itemData = try await loadItem { item in
            SyncItemData(
            id: itemId.uuidString,
            userId: userId.uuidString,
            name: item.name ?? "",
            notes: item.notes,
            isFavorite: item.isFavorite,
            isDraft: item.isDraft,
            minTemperature: item.minTemperature > 0 ? item.minTemperature : nil,
            maxTemperature: item.maxTemperature > 0 ? item.maxTemperature : nil,
            temperatureUnit: item.temperatureUnit,
            weight: item.weight > 0 ? item.weight : nil,
            weightUnit: item.weightUnit,
            isSoftDeleted: item.isSoftDeleted,
            createdAt: item.createdAt?.ISO8601String,
            wishedAt: item.wishedAt?.ISO8601String,
            purchasedAt: item.purchasedAt?.ISO8601String,
            updatedAt: item.updatedAt?.ISO8601String ?? item.createdAt?.ISO8601String,
            brandId: item.brand?.id?.uuidString,
            categoryId: item.category?.id?.uuidString,
            subcategoryId: item.subcategory?.id?.uuidString,
            sizeId: item.itemSize?.id?.uuidString,
            locationId: item.location?.id?.uuidString
            )
        }
        
        // Upload item metadata
        do {
            try await (await getSupabase()).supabaseClient.from("items")
                .upsert(itemData, onConflict: "id")
                .execute()
            print("✅ Uploaded item metadata to Supabase: \(try await loadItem({ $0.name ?? "unnamed" }))")
        } catch {
            print("❌ Failed to upload item '\(try await loadItem({ $0.name ?? "unnamed" }))' to Supabase")
            print("❌ Error: \(error)")
            let nsError = error as NSError
            print("❌ Error domain: \(nsError.domain), code: \(nsError.code)")
            print("❌ User info: \(nsError.userInfo)")
            throw error
        }
        
        // Sync photos with proper deletion handling
        try await syncItemPhotos(itemObjectID: objectID, itemId: itemId, userId: userId)
        
        // Sync relationships (colors, seasons, tags, etc.)
        try await syncItemRelationships(itemObjectID: objectID, userId: userId)
        
        // Sync price if exists
        if let priceObjectID = try await loadItem({ $0.price?.objectID }) {
            try await syncPrice(objectID: priceObjectID, itemId: itemId, userId: userId)
        }
        
        // Sync links with proper deletion handling
        try await syncItemLinks(itemObjectID: objectID, itemId: itemId, userId: userId)
        
        try await mutateItem { $0.syncedAt = Date() }
        
        print("✅ Synced item: \(try await loadItem({ $0.name ?? "unnamed" }))")
    }
    

    func syncItem(_ item: Item, userId: UUID) async throws {
        try await syncItem(objectID: item.objectID, userId: userId)
    }
}
