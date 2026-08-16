//
//  SyncEngine+Incremental.swift
//  closet
//

import CoreData
import Foundation

extension SyncEngine {

    /// Incremental item sync after MainActor preflight (viewContext save, userId assignment).
    func syncItemAfterPreflight(objectID: NSManagedObjectID, userId: UUID) async throws {
        try await ensureReferencedEntitiesSynced(forItemObjectID: objectID, userId: userId)
        try await syncAllReferenceData(userId: userId)
        try await syncItem(objectID: objectID, userId: userId)
    }

    /// Outfit worn removal only — R2 delete + null `worn_image_url` (no collage re-upload).
    func syncOutfitWornRemovalAfterPreflight(objectID: NSManagedObjectID, userId: UUID) async throws {
        let snapshot = try await performOnSyncContext { ctx -> (outfitId: UUID, name: String, hasWorn: Bool, isDraft: Bool)? in
            guard let outfit = try ctx.existingObject(with: objectID) as? Outfit,
                  let outfitId = outfit.id else { return nil }
            return (outfitId, outfit.name ?? "unnamed", outfit.wornImage != nil, outfit.isDraft)
        }
        guard let snapshot else { return }
        guard !snapshot.isDraft else {
            print("⏭️ Skipping worn removal sync for draft outfit: \(snapshot.name)")
            return
        }
        guard !snapshot.hasWorn else {
            print("⚠️ Local outfit still has worn data; skipping worn-only removal sync")
            return
        }

        try await (await getSupabase()).clearOutfitWornImage(outfitId: snapshot.outfitId, userId: userId)
        print("✅ Synced outfit worn removal only: \(snapshot.name)")
    }

    /// Outfit worn add/replace only — R2 upload + `worn_image_url` patch (no full metadata upsert).
    func syncOutfitWornUploadAfterPreflight(objectID: NSManagedObjectID, userId: UUID) async throws {
        let snapshot = try await performOnSyncContext { ctx -> (outfitId: UUID, name: String, wornData: Data, isDraft: Bool)? in
            guard let outfit = try ctx.existingObject(with: objectID) as? Outfit,
                  let outfitId = outfit.id,
                  let wornData = outfit.wornImage, !wornData.isEmpty else { return nil }
            return (outfitId, outfit.name ?? "unnamed", wornData, outfit.isDraft)
        }
        guard let snapshot else {
            print("⚠️ Outfit missing worn data; skipping worn-only upload sync")
            return
        }
        guard !snapshot.isDraft else {
            print("⏭️ Skipping worn upload sync for draft outfit: \(snapshot.name)")
            return
        }

        _ = try await (await getSupabase()).setOutfitWornImage(
            imageData: snapshot.wornData,
            outfitId: snapshot.outfitId,
            userId: userId
        )
        print("✅ Synced outfit worn upload only: \(snapshot.name)")
    }

    /// Photo-only push (delete/replace front or worn). Skips item metadata, refs, and junctions.
    func syncItemPhotosAfterPreflight(objectID: NSManagedObjectID, userId: UUID) async throws {
        let softDeleted = try await withSyncItem(objectID) { $0.isSoftDeleted }
        if softDeleted {
            try await syncItemAfterPreflight(objectID: objectID, userId: userId)
            return
        }

        guard let itemId = try await withSyncItem(objectID, { $0.id }) else {
            print("⚠️ Item missing ID, skipping photo sync")
            return
        }

        try await syncItemPhotos(itemObjectID: objectID, itemId: itemId, userId: userId)
        // Do not set item.syncedAt — photo push must not clear pending attribute dirty state.
        let name = try await withSyncItem(objectID) { $0.name ?? "unnamed" }
        print("✅ Synced item photos only: \(name)")
    }

    /// Background needsSync check + wardrobe push.
    func syncWardrobeIfNeeded(objectID: NSManagedObjectID, wardrobeId: UUID, userId: UUID) async throws {
        let syncState = try await performOnSyncContext { ctx -> (needsSync: Bool, name: String)? in
            let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", wardrobeId as CVarArg)
            request.fetchLimit = 1
            guard let refreshedWardrobe = try ctx.fetch(request).first else { return nil }

            if refreshedWardrobe.userId == nil || refreshedWardrobe.userId?.isEmpty == true {
                refreshedWardrobe.userId = userId.uuidString
                try ctx.save()
                print("✅ Set userId on new wardrobe: \(refreshedWardrobe.name ?? "unnamed")")
            }

            let needsSync: Bool
            if refreshedWardrobe.syncedAt == nil {
                needsSync = true
            } else if let updatedAt = refreshedWardrobe.updatedAt, let syncedAt = refreshedWardrobe.syncedAt {
                needsSync = updatedAt >= syncedAt
            } else {
                needsSync = false
            }
            return (needsSync, refreshedWardrobe.name ?? "unnamed")
        }

        guard let syncState else {
            print("⚠️ Could not find wardrobe with ID \(wardrobeId) for sync")
            return
        }
        guard syncState.needsSync else { return }

        try await syncWardrobe(objectID: objectID, userId: userId)
        print("✅ Auto-synced wardrobe: \(syncState.name)")
    }

    /// Background needsSync check + outfit push.
    func syncOutfitIfNeeded(objectID: NSManagedObjectID, outfitId: UUID, userId: UUID) async throws {
        let syncState = try await performOnSyncContext { ctx -> (needsSync: Bool, name: String, isDraft: Bool)? in
            let request: NSFetchRequest<Outfit> = Outfit.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", outfitId as CVarArg)
            request.fetchLimit = 1
            guard let refreshedOutfit = try ctx.fetch(request).first else { return nil }

            if refreshedOutfit.userId == nil || refreshedOutfit.userId?.isEmpty == true {
                refreshedOutfit.userId = userId.uuidString
                try ctx.save()
            }

            let needsSync: Bool
            if refreshedOutfit.syncedAt == nil {
                needsSync = true
            } else if let updatedAt = refreshedOutfit.updatedAt, let syncedAt = refreshedOutfit.syncedAt {
                needsSync = updatedAt >= syncedAt
            } else {
                needsSync = true
            }
            return (needsSync, refreshedOutfit.name ?? "unnamed", refreshedOutfit.isDraft)
        }

        guard let syncState else {
            print("⚠️ Could not find outfit with ID \(outfitId) for sync")
            return
        }

        guard !syncState.isDraft else {
            print("⏭️ Skipping sync for draft outfit: \(syncState.name)")
            return
        }
        guard syncState.needsSync else { return }

        try await syncOutfit(objectID: objectID, userId: userId)
        print("✅ Auto-synced outfit: \(syncState.name)")
    }

    /// Background needsSync check + event push.
    func syncEventIfNeeded(objectID: NSManagedObjectID, eventId: UUID, userId: UUID) async throws {
        let syncState = try await performOnSyncContext { ctx -> (needsSync: Bool, name: String)? in
            let request: NSFetchRequest<Event> = Event.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", eventId as CVarArg)
            request.fetchLimit = 1
            guard let refreshed = try ctx.fetch(request).first else { return nil }

            if refreshed.userId == nil || refreshed.userId?.isEmpty == true {
                refreshed.userId = userId.uuidString
                try ctx.save()
            }
            if (refreshed.visibility ?? "").isEmpty {
                refreshed.visibility = WardrobeVisibility.private.rawValue
                try ctx.save()
            }

            let needsSync: Bool
            if refreshed.syncedAt == nil {
                needsSync = true
            } else if let updatedAt = refreshed.updatedAt, let syncedAt = refreshed.syncedAt {
                needsSync = updatedAt >= syncedAt
            } else {
                needsSync = true
            }
            return (needsSync, refreshed.name ?? "unnamed")
        }

        guard let syncState else {
            print("⚠️ Could not find event with ID \(eventId) for sync")
            return
        }
        guard syncState.needsSync else { return }

        try await syncEvent(objectID: objectID, userId: userId)
        print("✅ Auto-synced event: \(syncState.name)")
    }
}
