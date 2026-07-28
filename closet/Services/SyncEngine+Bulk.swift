//
//  SyncEngine+Bulk.swift
//  closet
//

import CoreData
import Foundation

extension SyncEngine {

    /// Purges local soft-deleted records whose soft-delete has already been pushed
    /// (`syncedAt >= updatedAt`). Using only `syncedAt != nil` was wrong: live upserts
    /// leave a prior `syncedAt`, so purge removed tombstones before the cloud delete ran
    /// and friends kept seeing zombie outfits.
    func purgeLocalTombstones(userId: UUID) async {
        let userIdString = userId.uuidString
        // Soft-delete bumped updatedAt; successful cloud delete sets syncedAt afterward.
        let syncedSoftDeletePredicate = NSPredicate(
            format: "userId == %@ AND isSoftDeleted == YES AND syncedAt != nil AND updatedAt != nil AND syncedAt >= updatedAt",
            userIdString
        )
        do {
            try await performOnSyncContext { ctx in
                    func purge<T: NSManagedObject>(_ request: NSFetchRequest<T>) throws -> Int {
                        let objects = try ctx.fetch(request)
                        guard !objects.isEmpty else { return 0 }
                        for obj in objects { ctx.delete(obj) }
                        return objects.count
                    }

                    var totalPurged = 0

                    let itemRequest: NSFetchRequest<Item> = Item.fetchRequest()
                    itemRequest.predicate = syncedSoftDeletePredicate
                    totalPurged += try purge(itemRequest)

                    let outfitRequest: NSFetchRequest<Outfit> = Outfit.fetchRequest()
                    outfitRequest.predicate = syncedSoftDeletePredicate
                    totalPurged += try purge(outfitRequest)

                    let wardrobeRequest: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
                    wardrobeRequest.predicate = syncedSoftDeletePredicate
                    totalPurged += try purge(wardrobeRequest)

                    if totalPurged > 0 {
                        try ctx.save()
                        print("🧹 Purged \(totalPurged) synced tombstone record(s) from local Core Data")
                    }
            }
        } catch {
            print("⚠️ Failed to purge local tombstones: \(error.localizedDescription)")
        }
    }

    /// Full sync session: claim orphan local rows → reference data → items → outfits.
    func syncAllItems(userId: UUID, progress: SyncProgressHandler?) async throws {
        print("🔍 Starting sync for user: \(userId.uuidString)")

        progress?("Preparing local data...", 0)
        try await claimUnownedLocalRows(for: userId)

        progress?("Syncing reference data...", 0)

        try await syncAllReferenceData(userId: userId)

        let unsyncedItemIDs = try await fetchUnsyncedItemObjectIDs(userId: userId)
        let totalItems = unsyncedItemIDs.count

        print("🔍 Found \(totalItems) items that need syncing")
        if totalItems > 0, let firstID = unsyncedItemIDs.first {
            print("🔍 First item: \(await itemName(for: firstID)), ID: \(await itemIdString(for: firstID)), userId: \(userId.uuidString)")
        }

        guard totalItems > 0 else {
            progress?("All items are synced", 1)
            print("ℹ️ No items need syncing - all are up to date")
            try await syncAllOutfits(userId: userId)
            schedulePurgeCallback()
            return
        }

        progress?("Syncing \(totalItems) items...", 0)

        for (index, itemObjectID) in unsyncedItemIDs.enumerated() {
            let fraction = Double(index) / Double(totalItems)
            progress?("Syncing item \(index + 1) of \(totalItems)...", fraction)

            do {
                try await syncItem(objectID: itemObjectID, userId: userId)
            } catch {
                print("❌ Failed to sync item '\(await itemName(for: itemObjectID))' (ID: \(await itemIdString(for: itemObjectID))): \(error)")
                print("❌ Error details: \(error.localizedDescription)")
                let nsError = error as NSError
                print("❌ Error domain: \(nsError.domain), code: \(nsError.code)")
                print("❌ User info: \(nsError.userInfo)")
                continue
            }
        }

        progress?("Sync complete!", 1)
        print("✅ Successfully synced \(totalItems) items")

        try await syncAllOutfits(userId: userId)
        schedulePurgeCallback()
    }

    /// Assigns legacy TestFlight / pre–per-user rows (`userId` nil/empty) to the signed-in account
    /// so they are included in `fetchUnsyncedItemObjectIDs` and wardrobe membership sync.
    func claimUnownedLocalRows(for userId: UUID) async throws {
        let uid = userId.uuidString
        try await performOnSyncContext { ctx in
            var claimed = 0

            let itemReq: NSFetchRequest<Item> = Item.fetchRequest()
            itemReq.predicate = NSPredicate(format: "userId == nil OR userId == ''")
            for item in try ctx.fetch(itemReq) {
                item.userId = uid
                if item.syncedAt != nil {
                    // Force re-upload; these never landed under this account in Supabase.
                    item.syncedAt = nil
                }
                setUpdatedAt(item)
                claimed += 1
            }

            let outfitReq: NSFetchRequest<Outfit> = Outfit.fetchRequest()
            outfitReq.predicate = NSPredicate(format: "userId == nil OR userId == ''")
            for outfit in try ctx.fetch(outfitReq) {
                outfit.userId = uid
                if outfit.syncedAt != nil {
                    outfit.syncedAt = nil
                }
                setUpdatedAt(outfit)
                claimed += 1
            }

            let wardrobeReq: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
            wardrobeReq.predicate = NSPredicate(format: "userId == nil OR userId == ''")
            for wardrobe in try ctx.fetch(wardrobeReq) {
                wardrobe.userId = uid
                if wardrobe.syncedAt != nil {
                    wardrobe.syncedAt = nil
                }
                setUpdatedAt(wardrobe)
                claimed += 1
            }

            if ctx.hasChanges {
                try ctx.save()
            }
            if claimed > 0 {
                print("🔁 Claimed \(claimed) local row(s) with missing userId for \(uid)")
            }
        }
    }
}