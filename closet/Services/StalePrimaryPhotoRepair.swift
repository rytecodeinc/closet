//
//  StalePrimaryPhotoRepair.swift
//  closet
//
//  Repair for leftovers from the old replaceFrontImage bug: multiple primaries and/or
//  legacy empty-type primary photos that should have been deleted when a typed front was set.
//  Scans Core Data + Supabase first; deletes only after the user confirms. Safe to run repeatedly.
//

import CoreData
import Foundation

enum StalePrimaryPhotoRepair {
    /// Dry-run findings shown before any delete.
    struct Plan: Sendable {
        var localPhotosToDelete: Int = 0
        var localPrimariesToDemote: Int = 0
        var localItemsAffected: Int = 0
        var cloudPhotosToDelete: Int = 0
        /// Local Photo.id values scheduled for deletion.
        var localPhotoIdsToDelete: Set<String> = []
        /// Cloud item_photos.id → item_id scheduled for deletion.
        var cloudPhotosToDeleteById: [String: String] = [:]
        var localFrontKeeperIds: [String: String] = [:]
        var localItemIds: Set<String> = []
        /// Local photo ids that remain after planned local deletes.
        var localPhotoIdsAfterRepair: Set<String> = []

        var totalPhotosToDelete: Int {
            localPhotosToDelete + cloudPhotosToDelete
        }

        var isEmpty: Bool {
            totalPhotosToDelete == 0 && localPrimariesToDemote == 0
        }

        var confirmationMessage: String {
            if isEmpty {
                return "No stale primary photos found (local or cloud)."
            }
            var lines = [
                "This will permanently delete:",
                "• \(localPhotosToDelete) local photo(s)",
                "• \(cloudPhotosToDelete) cloud photo(s) (Supabase + R2)",
            ]
            if localPrimariesToDemote > 0 {
                lines.append("• \(localPrimariesToDemote) extra primary flag(s) will be cleared")
            }
            if localItemsAffected > 0 {
                lines.append("Affects \(localItemsAffected) local item(s).")
            }
            lines.append("This cannot be undone.")
            return lines.joined(separator: "\n")
        }
    }

    struct Result: Sendable {
        var itemsTouched: Int = 0
        var photosDeletedLocally: Int = 0
        var photosDemoted: Int = 0
        var itemsSynced: Int = 0
        var syncFailures: Int = 0
        var cloudPhotosDeleted: Int = 0
        var cloudDeleteFailures: Int = 0

        var summaryMessage: String {
            let nothingLocal = itemsTouched == 0 && photosDeletedLocally == 0 && photosDemoted == 0
            let nothingCloud = cloudPhotosDeleted == 0 && cloudDeleteFailures == 0
            if nothingLocal && nothingCloud {
                return "No stale primary photos found (local or cloud)."
            }
            var lines: [String] = []
            if !nothingLocal {
                lines += [
                    "Items updated (local): \(itemsTouched)",
                    "Photos deleted (local): \(photosDeletedLocally)",
                    "Extra primaries demoted: \(photosDemoted)",
                    "Items synced after local repair: \(itemsSynced)",
                ]
                if syncFailures > 0 {
                    lines.append("Local sync failures: \(syncFailures)")
                }
            } else {
                lines.append("Local Core Data: clean")
            }
            lines.append("Cloud-only leftovers deleted: \(cloudPhotosDeleted)")
            if cloudDeleteFailures > 0 {
                lines.append("Cloud delete failures: \(cloudDeleteFailures)")
            }
            return lines.joined(separator: "\n")
        }
    }

    private struct CloudPhotoRow: Decodable {
        let id: String
        let itemId: String
        let type: String?
        let isPrimary: Bool
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case itemId = "item_id"
            case type
            case isPrimary = "is_primary"
            case createdAt = "created_at"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            itemId = try c.decode(String.self, forKey: .itemId)
            type = try c.decodeIfPresent(String.self, forKey: .type)
            isPrimary = try c.decodeIfPresent(Bool.self, forKey: .isPrimary) ?? false
            createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        }

        var normalizedType: String {
            (type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        var isFrontSlot: Bool {
            normalizedType == "front" || (isPrimary && normalizedType.isEmpty)
        }
    }

    // MARK: - Scan (no deletes)

    /// Inspects local + cloud state without mutating anything.
    static func scanStalePrimaryPhotos(
        for userId: UUID,
        in context: NSManagedObjectContext
    ) async throws -> Plan {
        let uid = userId.uuidString
        var plan = Plan()

        let itemReq: NSFetchRequest<Item> = Item.fetchRequest()
        itemReq.predicate = NSPredicate(
            format: "userId == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
            uid
        )
        let items = try context.fetch(itemReq)

        var remainingLocalPhotoIds = Set<String>()
        var localItemIds = Set<String>()
        var localFrontKeeperIds: [String: String] = [:]
        var localDeleteIds = Set<String>()
        var itemsAffected = 0
        var demoteCount = 0

        for item in items {
            guard let itemId = item.id?.uuidString else { continue }
            localItemIds.insert(itemId)

            let photos = Array((item.photos as? Set<Photo>) ?? [])
            guard !photos.isEmpty else { continue }

            let planned = planLocalRepair(photos: photos)
            if !planned.photoIdsToDelete.isEmpty
                || planned.demoteCount > 0
                || planned.normalizedKeeper {
                itemsAffected += 1
            }
            demoteCount += planned.demoteCount
            localDeleteIds.formUnion(planned.photoIdsToDelete)

            for photo in photos {
                guard let id = photo.id?.uuidString else { continue }
                if !planned.photoIdsToDelete.contains(id) {
                    remainingLocalPhotoIds.insert(id)
                }
            }
            if let keeperId = planned.keeperPhotoId {
                localFrontKeeperIds[itemId] = keeperId
            }
        }

        plan.localPhotosToDelete = localDeleteIds.count
        plan.localPrimariesToDemote = demoteCount
        plan.localItemsAffected = itemsAffected
        plan.localPhotoIdsToDelete = localDeleteIds
        plan.localItemIds = localItemIds
        plan.localFrontKeeperIds = localFrontKeeperIds
        plan.localPhotoIdsAfterRepair = remainingLocalPhotoIds

        let cloudIds = try await findCloudLeftoverIds(
            userId: userId,
            localItemIds: localItemIds,
            localPhotoIds: remainingLocalPhotoIds,
            localFrontKeeperIds: localFrontKeeperIds
        )
        plan.cloudPhotosToDeleteById = cloudIds
        plan.cloudPhotosToDelete = cloudIds.count

        print("🧹 Stale primary scan: \(plan.confirmationMessage)")
        return plan
    }

    // MARK: - Apply (after confirm)

    /// Executes a previously scanned plan (re-validates local rules, then deletes).
    static func applyStalePrimaryPhotoPlan(
        _ plan: Plan,
        for userId: UUID,
        in context: NSManagedObjectContext
    ) async throws -> Result {
        var result = Result()

        let itemReq: NSFetchRequest<Item> = Item.fetchRequest()
        itemReq.predicate = NSPredicate(
            format: "userId == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
            userId.uuidString
        )
        let items = try context.fetch(itemReq)
        var touchedItems: [Item] = []

        for item in items {
            let photos = Array((item.photos as? Set<Photo>) ?? [])
            guard !photos.isEmpty else { continue }

            let change = applyLocalRepair(to: item, photos: photos, in: context)
            if change.deleted > 0 || change.demoted > 0 || change.normalizedKeeper {
                result.photosDeletedLocally += change.deleted
                result.photosDemoted += change.demoted
                setUpdatedAt(item)
                touchedItems.append(item)
            }
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

        let cloud = try await deleteCloudPhotos(
            plan.cloudPhotosToDeleteById,
            userId: userId
        )
        result.cloudPhotosDeleted = cloud.deleted
        result.cloudDeleteFailures = cloud.failures

        for itemIdString in cloud.itemIdsNeedingResync {
            guard let itemId = UUID(uuidString: itemIdString),
                  let item = items.first(where: { $0.id == itemId }) else { continue }
            if touchedItems.contains(where: { $0.objectID == item.objectID }) { continue }
            do {
                try await SyncEngine.shared.syncItemPhotos(item, itemId: itemId, userId: userId)
                result.itemsSynced += 1
            } catch {
                result.syncFailures += 1
                print("⚠️ Cloud leftover resync failed for item \(itemId): \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            SupabaseService.shared.invalidateWardrobeGridItemsCache(forUserId: userId)
        }

        print("🧹 Stale primary photo repair: \(result.summaryMessage)")
        return result
    }

    // MARK: - Cloud scan / delete

    private struct CloudPurgeOutcome {
        var deleted: Int = 0
        var failures: Int = 0
        var itemIdsNeedingResync: Set<String> = []
    }

    private static func findCloudLeftoverIds(
        userId: UUID,
        localItemIds: Set<String>,
        localPhotoIds: Set<String>,
        localFrontKeeperIds: [String: String]
    ) async throws -> [String: String] {
        let supabase = await MainActor.run { SupabaseService.shared }

        let response = try await supabase.supabaseClient.from("item_photos")
            .select("id, item_id, type, is_primary, created_at")
            .eq("user_id", value: userId.uuidString)
            .execute()

        let cloudPhotos: [CloudPhotoRow]
        do {
            cloudPhotos = try JSONDecoder().decode([CloudPhotoRow].self, from: response.data)
        } catch {
            print("⚠️ Failed to decode cloud item_photos for stale repair: \(error)")
            throw error
        }

        print("☁️ Cloud scan: \(cloudPhotos.count) item_photos for user; \(localPhotoIds.count) local photo ids")

        var idsToDelete: [String: String] = [:]

        for row in cloudPhotos {
            guard localItemIds.contains(row.itemId) else { continue }
            if !localPhotoIds.contains(row.id) {
                idsToDelete[row.id] = row.itemId
            }
        }

        let byItem = Dictionary(grouping: cloudPhotos.filter { localItemIds.contains($0.itemId) }, by: \.itemId)
        for (itemId, rows) in byItem {
            let frontSlot = rows.filter(\.isFrontSlot)
            guard frontSlot.count > 1 else { continue }

            let keeperId: String? = {
                if let localKeeper = localFrontKeeperIds[itemId],
                   frontSlot.contains(where: { $0.id == localKeeper }) {
                    return localKeeper
                }
                let localMatches = frontSlot.filter { localPhotoIds.contains($0.id) }
                let pool = localMatches.isEmpty ? frontSlot : localMatches
                return pool.sorted { a, b in
                    if a.isPrimary != b.isPrimary { return a.isPrimary && !b.isPrimary }
                    return (a.createdAt ?? "") > (b.createdAt ?? "")
                }.first?.id
            }()

            guard let keeperId else { continue }
            for row in frontSlot where row.id != keeperId && !localPhotoIds.contains(row.id) {
                idsToDelete[row.id] = row.itemId
            }
        }

        print("☁️ Cloud leftovers identified: \(idsToDelete.count)")
        return idsToDelete
    }

    private static func deleteCloudPhotos(
        _ idsToDelete: [String: String],
        userId: UUID
    ) async throws -> CloudPurgeOutcome {
        var outcome = CloudPurgeOutcome()
        let supabase = await MainActor.run { SupabaseService.shared }

        for (photoId, itemIdString) in idsToDelete {
            guard let itemUUID = UUID(uuidString: itemIdString),
                  let photoUUID = UUID(uuidString: photoId) else {
                outcome.failures += 1
                continue
            }

            var deletedSomething = false

            do {
                try await supabase.deletePhoto(
                    itemId: itemUUID,
                    photoId: photoUUID,
                    userId: userId
                )
                deletedSomething = true
            } catch {
                print("⚠️ Failed to delete cloud photo \(photoId) from R2: \(error.localizedDescription)")
            }

            do {
                let thumbnailFileName = "\(userId.uuidString)/\(itemIdString)/\(photoId)_thumb.jpg"
                guard let thumbnailUrl = URL(string: "\(CloudflareR2Config.workerURL)/\(thumbnailFileName)"),
                      let session = await MainActor.run(body: { supabase.currentSession }) else {
                    throw NSError(domain: "StalePrimaryPhotoRepair", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Missing session for thumbnail delete"
                    ])
                }
                var thumbnailRequest = URLRequest(url: thumbnailUrl)
                thumbnailRequest.httpMethod = "DELETE"
                thumbnailRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
                let (_, response) = try await URLSession.shared.data(for: thumbnailRequest)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    deletedSomething = true
                }
            } catch {
                print("⚠️ Failed to delete cloud thumbnail \(photoId): \(error.localizedDescription)")
            }

            do {
                try await supabase.supabaseClient.from("item_photos")
                    .delete()
                    .eq("id", value: photoId)
                    .execute()
                deletedSomething = true
                print("✅ Deleted cloud leftover photo: \(photoId)")
            } catch {
                outcome.failures += 1
                print("⚠️ Failed to delete cloud photo metadata \(photoId): \(error.localizedDescription)")
                continue
            }

            if deletedSomething {
                outcome.deleted += 1
                outcome.itemIdsNeedingResync.insert(itemIdString)
            }
        }

        return outcome
    }

    // MARK: - Local rules

    private struct LocalChange {
        var deleted: Int = 0
        var demoted: Int = 0
        var normalizedKeeper: Bool = false
    }

    private struct PlannedLocalChange {
        var photoIdsToDelete: Set<String> = []
        var demoteCount: Int = 0
        var keeperPhotoId: String?
        var normalizedKeeper: Bool = false
    }

    private static func normalizedType(_ photo: Photo) -> String {
        (photo.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func photoDate(_ photo: Photo) -> Date {
        photo.createdAt ?? photo.timestamp ?? .distantPast
    }

    private static func frontKeeper(in photos: [Photo]) -> Photo? {
        let fronts = photos.filter { normalizedType($0) == "front" }
        let legacyPrimaries = photos.filter { $0.isPrimary && normalizedType($0).isEmpty }
        if !fronts.isEmpty {
            return fronts.sorted { a, b in
                if a.isPrimary != b.isPrimary { return a.isPrimary && !b.isPrimary }
                return photoDate(a) > photoDate(b)
            }.first
        }
        return legacyPrimaries.sorted { photoDate($0) > photoDate($1) }.first
    }

    /// Dry-run of local repair for one item's photos.
    private static func planLocalRepair(photos: [Photo]) -> PlannedLocalChange {
        var planned = PlannedLocalChange()
        let fronts = photos.filter { normalizedType($0) == "front" }
        let legacyPrimaries = photos.filter { $0.isPrimary && normalizedType($0).isEmpty }
        let keeper = frontKeeper(in: photos)

        guard let keeper else {
            for photo in photos where photo.isPrimary {
                let t = normalizedType(photo)
                if t != "front" && !t.isEmpty {
                    planned.demoteCount += 1
                }
            }
            return planned
        }

        planned.keeperPhotoId = keeper.id?.uuidString

        for photo in fronts where photo.objectID != keeper.objectID {
            if let id = photo.id?.uuidString {
                planned.photoIdsToDelete.insert(id)
            }
        }

        if normalizedType(keeper) == "front" || !legacyPrimaries.isEmpty {
            for photo in legacyPrimaries where photo.objectID != keeper.objectID {
                if let id = photo.id?.uuidString {
                    planned.photoIdsToDelete.insert(id)
                }
            }
        }

        let remaining = photos.filter { photo in
            guard let id = photo.id?.uuidString else { return photo.objectID != keeper.objectID }
            return !planned.photoIdsToDelete.contains(id)
        }
        for photo in remaining where photo.isPrimary && photo.objectID != keeper.objectID {
            planned.demoteCount += 1
        }

        if !keeper.isPrimary {
            planned.normalizedKeeper = true
        }
        if normalizedType(keeper).isEmpty {
            planned.normalizedKeeper = true
        }

        return planned
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
        let keeper = frontKeeper(in: photos)

        guard let keeper else {
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

        for photo in fronts where photo.objectID != keeper.objectID {
            deleteIDs.insert(photo.objectID)
        }

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
