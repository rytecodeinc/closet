//
//  SyncEngine+Outfits
//  closet
//

import CoreData
import Foundation
import Supabase
import UIKit


extension SyncEngine {
    func syncAllOutfits(userId: UUID) async throws {
        let request: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        // Include soft-deleted outfits (same as items) so deletes reach Supabase.
        // Excluding them left friend-visible rows alive after local delete.
        request.predicate = NSPredicate(
            format: "userId == %@ AND isDraft != YES AND (syncedAt == nil OR updatedAt > syncedAt)",
            userId.uuidString
        )

        let outfitObjectIDs: [NSManagedObjectID]
        do {
            outfitObjectIDs = try await performOnSyncContext { ctx in
                try ctx.fetch(request).map { $0.objectID }
            }
        } catch {
            print("⚠️ Failed to fetch outfits for sync: \(error.localizedDescription)")
            try await cleanupOrphanedOutfits(userId: userId)
            return
        }

        if outfitObjectIDs.isEmpty {
            print("ℹ️ No outfits need syncing")
        } else {
            print("🔍 Found \(outfitObjectIDs.count) outfit(s) that need syncing")

            for outfitObjectID in outfitObjectIDs {
                try await performOnSyncContext { ctx in
                    guard let outfit = try ctx.existingObject(with: outfitObjectID) as? Outfit else { return }
                    if outfit.userId == nil || outfit.userId?.isEmpty == true {
                        outfit.userId = userId.uuidString
                    }
                    if ctx.hasChanges { try ctx.save() }
                }
                do {
                    try await syncOutfit(objectID: outfitObjectID, userId: userId)
                    let name = try await performOnSyncContext { ctx in
                        (try ctx.existingObject(with: outfitObjectID) as? Outfit)?.name ?? "unnamed"
                    }
                    print("✅ Synced outfit: \(name)")
                } catch {
                    let name = (try? await performOnSyncContext { ctx in
                        (try ctx.existingObject(with: outfitObjectID) as? Outfit)?.name ?? "unnamed"
                    }) ?? "unnamed"
                    print("⚠️ Failed to sync outfit '\(name)': \(error.localizedDescription)")
                }
            }
        }

        // Heal zombie cloud rows left when tombstones were purged before server delete ran.
        try await cleanupOrphanedOutfits(userId: userId)
    }

    /// Remote outfit IDs for this user, normalized as `UUID` (avoids string case mismatches).
    private func fetchRemoteOutfitIds(userId: UUID) async throws -> Set<UUID> {
        let supabase = await getSupabase()
        let response = try await supabase.supabaseClient.from("outfits")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .execute()

        struct OutfitIdRow: Decodable {
            let id: String
        }
        let rows = try JSONDecoder().decode([OutfitIdRow].self, from: response.data)
        return Set(rows.compactMap { UUID(uuidString: $0.id) })
    }

    /// Deletes Supabase outfits that no longer exist locally (including soft-deleted tombstones).
    /// Friend-visible grids read cloud state; without this, incorrectly purged tombstones left live rows.
    func cleanupOrphanedOutfits(userId: UUID) async throws {
        let outfitRequest: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        outfitRequest.predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        outfitRequest.propertiesToFetch = ["id"]
        let localOutfitIds: Set<UUID> = Set(
            try await performOnSyncContext { ctx in
                try ctx.fetch(outfitRequest).compactMap { $0.id }
            }
        )

        let remoteIds = try await fetchRemoteOutfitIds(userId: userId)
        let orphanedIds = remoteIds.subtracting(localOutfitIds)
        guard !orphanedIds.isEmpty else {
            print("ℹ️ No orphaned outfits to clean up")
            return
        }

        print("🗑️ Found \(orphanedIds.count) orphaned outfit(s) in Supabase")
        for orphanedId in orphanedIds {
            do {
                try await deleteRemoteOutfit(outfitId: orphanedId, userId: userId)
                print("✅ Cleaned up orphaned outfit: \(orphanedId.uuidString)")
            } catch {
                print("⚠️ Failed to clean orphaned outfit \(orphanedId.uuidString): \(error.localizedDescription)")
            }
        }

        await (await getSupabase()).invalidateWardrobeGridOutfitsCache(forUserId: userId)
    }

    /// Hard-deletes an outfit from R2 + Supabase (junction rows + outfits row).
    func deleteRemoteOutfit(outfitId: UUID, userId: UUID) async throws {
        let supabase = await getSupabase()
        do { try await supabase.deleteOutfitImage(outfitId: outfitId, userId: userId) } catch {
            print("⚠️ Failed to delete outfit image from R2: \(error.localizedDescription)")
        }
        do { try await supabase.deleteOutfitWornImage(outfitId: outfitId, userId: userId) } catch {
            print("⚠️ Failed to delete outfit worn image from R2: \(error.localizedDescription)")
        }
        do {
            try await supabase.supabaseClient.from("outfit_items")
                .delete().eq("outfit_id", value: outfitId.uuidString).execute()
        } catch {
            print("⚠️ Failed to delete outfit_items: \(error.localizedDescription)")
        }
        do {
            try await supabase.supabaseClient.from("outfit_tags")
                .delete().eq("outfit_id", value: outfitId.uuidString).execute()
        } catch {
            print("⚠️ Failed to delete outfit_tags: \(error.localizedDescription)")
        }
        try await supabase.supabaseClient.from("outfits")
            .delete().eq("id", value: outfitId.uuidString).execute()
    }
    func syncOutfit(objectID: NSManagedObjectID, userId: UUID) async throws {
        struct OutfitSyncSnapshot {
            let outfitId: UUID
            let isSoftDeleted: Bool
            let name: String
            let image: Data?
            let wornImage: Data?
            let transformationData: Data?
            let notes: String?
            let isFavorite: Bool
            let isDraft: Bool
            let categoryId: String?
            let categoryObjectID: NSManagedObjectID?
            let createdAt: Date?
            let updatedAt: Date?
            let unsyncedItemObjectIDs: [NSManagedObjectID]
            let itemIds: Set<String>
            let tagIds: Set<String>
        }

        let snapshot = try await performOnSyncContext { ctx -> OutfitSyncSnapshot? in
            guard let outfit = try ctx.existingObject(with: objectID) as? Outfit,
                  let outfitId = outfit.id else { return nil }

            var unsyncedItemObjectIDs: [NSManagedObjectID] = []
            if let items = outfit.items as? Set<Item> {
                for item in items {
                    guard item.id != nil, item.syncedAt == nil else { continue }
                    if item.userId == nil || item.userId?.isEmpty == true {
                        item.userId = userId.uuidString
                    }
                    unsyncedItemObjectIDs.append(item.objectID)
                }
            }
            if ctx.hasChanges {
                try ctx.save()
            }

            let itemIds: Set<String>
            if let items = outfit.items as? Set<Item> {
                itemIds = Self.normalizedUUIDStringSet(items.compactMap { $0.id?.uuidString })
            } else {
                itemIds = Set()
            }

            let tagIds: Set<String>
            if let tags = outfit.tags as? Set<Tag> {
                tagIds = Self.normalizedUUIDStringSet(tags.compactMap { $0.id?.uuidString })
            } else {
                tagIds = Set()
            }

            return OutfitSyncSnapshot(
                outfitId: outfitId,
                isSoftDeleted: outfit.isSoftDeleted,
                name: outfit.name ?? "unnamed",
                image: outfit.image,
                wornImage: outfit.wornImage,
                transformationData: outfit.transformationData,
                notes: outfit.notes,
                isFavorite: outfit.isFavorite,
                isDraft: outfit.isDraft,
                categoryId: outfit.category?.id?.uuidString,
                categoryObjectID: outfit.category?.objectID,
                createdAt: outfit.createdAt,
                updatedAt: outfit.updatedAt,
                unsyncedItemObjectIDs: unsyncedItemObjectIDs,
                itemIds: itemIds,
                tagIds: tagIds
            )
        }

        guard let snapshot else { return }
        let outfitId = snapshot.outfitId

        if snapshot.isSoftDeleted {
            print("🗑️ Deleting outfit from Supabase and R2: \(snapshot.name)")
            try await deleteRemoteOutfit(outfitId: outfitId, userId: userId)
            try await performOnSyncContext { ctx in
                guard let outfit = try ctx.existingObject(with: objectID) as? Outfit else { return }
                outfit.syncedAt = Date()
                try ctx.save()
            }
            await (await getSupabase()).invalidateWardrobeGridOutfitsCache(forUserId: userId)
            print("✅ Deleted outfit from Supabase and R2")
            schedulePurgeCallback()
            return
        }

        var imageUrl: String? = nil
        if let imageData = snapshot.image {
            do {
                imageUrl = try await (await getSupabase()).uploadOutfitImage(
                    imageData: imageData,
                    outfitId: outfitId,
                    userId: userId
                )
                print("✅ Uploaded outfit image to R2: \(imageUrl ?? "")")
            } catch {
                print("⚠️ Failed to upload outfit image to R2: \(error.localizedDescription)")
            }
        }

        var wornImageUrl: String? = nil
        var clearedLocalWorn = false
        if let wornData = snapshot.wornImage {
            do {
                wornImageUrl = try await (await getSupabase()).uploadOutfitWornImage(
                    imageData: wornData,
                    outfitId: outfitId,
                    userId: userId
                )
                print("✅ Uploaded outfit worn image to R2: \(wornImageUrl ?? "")")
            } catch {
                print("⚠️ Failed to upload outfit worn image to R2: \(error.localizedDescription)")
            }
        } else {
            clearedLocalWorn = true
            // Mirror item worn delete: remove R2 object(s) and null Supabase URL.
            do {
                try await (await getSupabase()).clearOutfitWornImage(outfitId: outfitId, userId: userId)
                print("🗑️ Cleared outfit worn image from R2 + Supabase")
            } catch {
                print("⚠️ Failed to clear outfit worn image: \(error.localizedDescription)")
            }
        }

        let transformationJson = snapshot.transformationData.flatMap { String(data: $0, encoding: .utf8) }

        if let categoryObjectID = snapshot.categoryObjectID {
            try await syncOutfitCategory(objectID: categoryObjectID, userId: userId)
        }

        let outfitData = SyncOutfitData(
            id: outfitId.uuidString,
            userId: userId.uuidString,
            name: snapshot.name,
            notes: snapshot.notes,
            isFavorite: snapshot.isFavorite,
            isDraft: snapshot.isDraft,
            isSoftDeleted: snapshot.isSoftDeleted,
            categoryId: snapshot.categoryId,
            createdAt: snapshot.createdAt?.ISO8601String,
            updatedAt: snapshot.updatedAt?.ISO8601String ?? snapshot.createdAt?.ISO8601String,
            imageUrl: imageUrl,
            wornImageUrl: wornImageUrl,
            transformationJson: transformationJson
        )

        try await (await getSupabase()).supabaseClient.from("outfits")
            .upsert(outfitData, onConflict: "id")
            .execute()
        print("✅ Upserted outfit metadata: \(snapshot.name)")

        // Upsert omits nil optionals — re-assert null so worn_image_url cannot stick around.
        if clearedLocalWorn {
            do {
                try await (await getSupabase()).supabaseClient.from("outfits")
                    .update(["worn_image_url": AnyJSON.null])
                    .eq("id", value: outfitId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to re-null outfit worn_image_url after upsert: \(error.localizedDescription)")
            }
        }

        for itemObjectID in snapshot.unsyncedItemObjectIDs {
            do {
                try await ensureReferencedEntitiesSynced(forItemObjectID: itemObjectID, userId: userId)
                try await syncItem(objectID: itemObjectID, userId: userId)
            } catch {
                let itemName = await itemName(for: itemObjectID)
                print("⚠️ Failed to pre-sync outfit item '\(itemName)': \(error.localizedDescription)")
            }
        }

        try await syncOutfitRelationships(itemIds: snapshot.itemIds, tagIds: snapshot.tagIds, outfitId: outfitId)

        try await performOnSyncContext { ctx in
            guard let outfit = try ctx.existingObject(with: objectID) as? Outfit else { return }
            outfit.syncedAt = Date()
            try ctx.save()
        }
    }

    func syncOutfit(_ outfit: Outfit, userId: UUID) async throws {
        try await syncOutfit(objectID: outfit.objectID, userId: userId)
    }

    func syncOutfitRelationships(itemIds: Set<String>, tagIds: Set<String>, outfitId: UUID) async throws {
        let existingItemsResponse = try await (await getSupabase()).supabaseClient.from("outfit_items")
            .select("item_id")
            .eq("outfit_id", value: outfitId.uuidString)
            .execute()

        let existingItemIds: Set<String>
        if let decoded = try? JSONDecoder().decode([OutfitItemResponse].self, from: existingItemsResponse.data) {
            existingItemIds = Self.normalizedUUIDStringSet(decoded.compactMap { $0.itemId })
        } else {
            existingItemIds = Set()
        }

        for idToDelete in existingItemIds.subtracting(itemIds) {
            try? await getSupabase().supabaseClient.from("outfit_items")
                .delete()
                .eq("outfit_id", value: outfitId.uuidString)
                .eq("item_id", value: idToDelete)
                .execute()
        }

        for itemId in itemIds {
            let junction = OutfitItemJunction(outfitId: outfitId.uuidString, itemId: itemId)
            do {
                try await (await getSupabase()).supabaseClient.from("outfit_items")
                    .upsert(junction, onConflict: "outfit_id,item_id")
                    .execute()
            } catch {
                print("⚠️ Skipping outfit_items insert for item \(itemId): \(error.localizedDescription)")
            }
        }

        let existingTagsResponse = try await (await getSupabase()).supabaseClient.from("outfit_tags")
            .select("tag_id")
            .eq("outfit_id", value: outfitId.uuidString)
            .execute()

        let existingTagIds: Set<String>
        if let decoded = try? JSONDecoder().decode([OutfitTagResponse].self, from: existingTagsResponse.data) {
            existingTagIds = Self.normalizedUUIDStringSet(decoded.compactMap { $0.tagId })
        } else {
            existingTagIds = Set()
        }

        for idToDelete in existingTagIds.subtracting(tagIds) {
            try? await getSupabase().supabaseClient.from("outfit_tags")
                .delete()
                .eq("outfit_id", value: outfitId.uuidString)
                .eq("tag_id", value: idToDelete)
                .execute()
        }

        for tagId in tagIds {
            let junction = OutfitTagJunction(outfitId: outfitId.uuidString, tagId: tagId)
            try await (await getSupabase()).supabaseClient.from("outfit_tags")
                .upsert(junction, onConflict: "outfit_id,tag_id")
                .execute()
        }
    }
}
