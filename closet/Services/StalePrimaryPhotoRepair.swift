//
//  StalePrimaryPhotoRepair.swift
//  closet
//
//  Repair for leftovers from the old replaceFrontImage bug: multiple primaries and/or
//  legacy empty-type primary photos that should have been deleted when a typed front was set.
//  Deletes stale front/legacy-primary photos from Core Data, then pushes orphan deletes to
//  Supabase + R2 via photo sync. Safe to run repeatedly.
//

import CoreData
import Foundation

enum StalePrimaryPhotoRepair {
    struct Result: Sendable {
        var itemsTouched: Int = 0
        var photosDeletedLocally: Int = 0
        var photosDemoted: Int = 0
        var itemsSynced: Int = 0
        var syncFailures: Int = 0

        var summaryMessage: String {
            if itemsTouched == 0 && photosDeletedLocally == 0 && photosDemoted == 0 {
                return "No stale primary photos found."
            }
            var lines = [
                "Items updated: \(itemsTouched)",
                "Photos deleted (local): \(photosDeletedLocally)",
                "Extra primaries demoted: \(photosDemoted)",
                "Items synced to cloud: \(itemsSynced)",
            ]
            if syncFailures > 0 {
                lines.append("Sync failures: \(syncFailures) (local deletes were kept; retry later)")
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Purges duplicate / legacy primary front photos for the signed-in user.
    static func purgeStalePrimaryPhotos(
        for userId: UUID,
        in context: NSManagedObjectContext
    ) async throws -> Result {
        let uid = userId.uuidString
        var result = Result()

        let itemReq: NSFetchRequest<Item> = Item.fetchRequest()
        itemReq.predicate = NSPredicate(
            format: "userId == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
            uid
        )

        let items = try context.fetch(itemReq)
        var touchedItems: [Item] = []

        for item in items {
            let photos = Array((item.photos as? Set<Photo>) ?? [])
            guard !photos.isEmpty else { continue }

            let change = applyLocalRepair(to: item, photos: photos, in: context)
            guard change.deleted > 0 || change.demoted > 0 || change.normalizedKeeper else { continue }

            result.photosDeletedLocally += change.deleted
            result.photosDemoted += change.demoted
            setUpdatedAt(item)
            touchedItems.append(item)
        }

        result.itemsTouched = touchedItems.count

        if context.hasChanges {
            try context.save()
        }

        for item in touchedItems {
            guard let itemId = item.id else { continue }
            do {
                try await SyncEngine.shared.syncItemPhotos(item, itemId: itemId, userId: userId)
                result.itemsSynced += 1
            } catch {
                result.syncFailures += 1
                print("⚠️ Stale primary repair sync failed for item \(itemId): \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            SupabaseService.shared.invalidateWardrobeGridItemsCache(forUserId: userId)
        }

        print("🧹 Stale primary photo repair: \(result.summaryMessage)")
        return result
    }

    // MARK: - Local rules

    private struct LocalChange {
        var deleted: Int = 0
        var demoted: Int = 0
        var normalizedKeeper: Bool = false
    }

    private static func normalizedType(_ photo: Photo) -> String {
        (photo.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func photoDate(_ photo: Photo) -> Date {
        photo.createdAt ?? photo.timestamp ?? .distantPast
    }

    /// Chooses the canonical front, deletes duplicate fronts / leftover legacy primaries,
    /// demotes non-front extras still marked primary.
    private static func applyLocalRepair(
        to item: Item,
        photos: [Photo],
        in context: NSManagedObjectContext
    ) -> LocalChange {
        var change = LocalChange()

        let fronts = photos.filter { normalizedType($0) == "front" }
        let legacyPrimaries = photos.filter { $0.isPrimary && normalizedType($0).isEmpty }

        let keeper: Photo?
        if !fronts.isEmpty {
            keeper = fronts.sorted { a, b in
                if a.isPrimary != b.isPrimary { return a.isPrimary && !b.isPrimary }
                return photoDate(a) > photoDate(b)
            }.first
        } else if !legacyPrimaries.isEmpty {
            keeper = legacyPrimaries.sorted { photoDate($0) > photoDate($1) }.first
        } else {
            keeper = nil
        }

        guard let keeper else {
            // No front/legacy slot — only demote stray primaries on back/worn.
            for photo in photos where photo.isPrimary {
                let t = normalizedType(photo)
                if t != "front" && !t.isEmpty {
                    photo.isPrimary = false
                    change.demoted += 1
                }
            }
            return change
        }

        var deleteIDs = Set<NSManagedObjectID>()

        // Extra typed fronts (replace bug often left the old front alongside the new one).
        for photo in fronts where photo.objectID != keeper.objectID {
            deleteIDs.insert(photo.objectID)
        }

        // Legacy empty-type primaries once a typed front exists (or extras among legacy-only).
        if normalizedType(keeper) == "front" || !legacyPrimaries.isEmpty {
            for photo in legacyPrimaries where photo.objectID != keeper.objectID {
                deleteIDs.insert(photo.objectID)
            }
        }

        for objectID in deleteIDs {
            guard let photo = photos.first(where: { $0.objectID == objectID }) else { continue }
            context.delete(photo)
            change.deleted += 1
        }

        let remaining = ((item.photos as? Set<Photo>) ?? []).filter { !deleteIDs.contains($0.objectID) }
        for photo in remaining where photo.isPrimary && photo.objectID != keeper.objectID {
            photo.isPrimary = false
            change.demoted += 1
        }

        if !keeper.isPrimary {
            keeper.isPrimary = true
            change.normalizedKeeper = true
        }
        if normalizedType(keeper).isEmpty {
            keeper.type = "front"
            change.normalizedKeeper = true
        }

        return change
    }
}
