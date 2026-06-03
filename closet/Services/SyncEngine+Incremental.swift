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
}
