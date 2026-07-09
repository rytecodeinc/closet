//
//  SyncService.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import Foundation
import CoreData
import Supabase

/// MainActor façade for sync preflight and orchestration; Core Data + network work runs in `SyncEngine`.
@MainActor
class SyncService: ObservableObject {
    static let shared = SyncService()

    private let supabaseService: SupabaseService
    private var viewContext: NSManagedObjectContext?

    private init() {
        self.supabaseService = SupabaseService.shared
    }

    nonisolated private static func logBulkSyncProgress(_ status: String, _ progress: Double) {
        let percent = Int((progress * 100).rounded())
        print("🔄 Sync [\(percent)%]: \(status)")
    }

    func configure(container: NSPersistentContainer) {
        viewContext = container.viewContext
        Task {
            await SyncEngine.shared.configure(container: container) { [weak self] in
                Task { @MainActor in
                    self?.schedulePurgeLocalTombstones()
                }
            }
        }
    }

    // MARK: - Product tier (TestFlight vs Production)

    private var isCloudSyncEnabled: Bool {
        AppEnvironment.capabilities.enablesCloudSync
    }

    private var isTombstonePurgeEnabled: Bool {
        AppEnvironment.capabilities.enablesTombstonePurge
    }

    // MARK: - Local tombstone purge

    func schedulePurgeLocalTombstones(delayNanoseconds: UInt64 = 800_000_000) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            await self.purgeLocalTombstonesIfPossible()
        }
    }

    func purgeLocalTombstonesIfPossible() async {
        guard isTombstonePurgeEnabled else { return }
        guard supabaseService.isAuthenticated, let userId = supabaseService.currentUser?.id else { return }
        await SyncEngine.shared.purgeLocalTombstones(userId: userId)
    }

    // MARK: - Incremental sync (*IfNeeded)

    nonisolated func syncItemIfNeeded(_ item: Item) {
        let objectID = item.objectID
        Task { @MainActor in
            guard self.supabaseService.isAuthenticated,
                  let userId = self.supabaseService.currentUser?.id,
                  let viewContext = self.viewContext else {
                return
            }

            guard !item.isDraft else {
                print("⏭️ Skipping sync for draft item: \(item.name ?? "unnamed")")
                return
            }

            if viewContext.hasChanges {
                do {
                    try viewContext.save()
                    print("💾 Saved pending changes before sync")
                } catch {
                    print("⚠️ Failed to save pending changes: \(error.localizedDescription)")
                }
            }

            if item.userId == nil || item.userId?.isEmpty == true {
                item.userId = userId.uuidString
                do {
                    try viewContext.save()
                    print("✅ Set userId on new item: \(item.name ?? "unnamed")")
                } catch {
                    print("⚠️ Failed to set userId on item: \(error.localizedDescription)")
                }
            }

            guard self.isCloudSyncEnabled else { return }

            viewContext.refresh(item, mergeChanges: true)

            let needsSync: Bool
            if item.syncedAt == nil {
                needsSync = true
            } else if let updatedAt = item.updatedAt, let syncedAt = item.syncedAt {
                needsSync = updatedAt >= syncedAt
            } else {
                needsSync = false
            }

            guard needsSync else { return }

            let itemName = item.name ?? "unnamed"
            Task {
                do {
                    try await SyncEngine.shared.syncItemAfterPreflight(objectID: objectID, userId: userId)
                    print("✅ Auto-synced item: \(itemName)")
                } catch {
                    print("⚠️ Auto-sync failed for item '\(itemName)': \(error.localizedDescription)")
                }
            }
        }
    }

    nonisolated func syncWardrobeIfNeeded(_ wardrobe: Wardrobe) {
        let objectID = wardrobe.objectID
        Task { @MainActor in
            guard self.isCloudSyncEnabled else { return }
            guard self.supabaseService.isAuthenticated,
                  let userId = self.supabaseService.currentUser?.id,
                  let wardrobeId = wardrobe.id else {
                return
            }

            do {
                try await SyncEngine.shared.syncWardrobeIfNeeded(
                    objectID: objectID,
                    wardrobeId: wardrobeId,
                    userId: userId
                )
            } catch {
                print("⚠️ Auto-sync failed for wardrobe: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func syncOutfitIfNeeded(_ outfit: Outfit) {
        let objectID = outfit.objectID
        Task { @MainActor in
            guard self.isCloudSyncEnabled else { return }
            guard self.supabaseService.isAuthenticated,
                  let userId = self.supabaseService.currentUser?.id,
                  let outfitId = outfit.id else {
                return
            }

            do {
                try await SyncEngine.shared.syncOutfitIfNeeded(
                    objectID: objectID,
                    outfitId: outfitId,
                    userId: userId
                )
            } catch {
                print("⚠️ Auto-sync failed for outfit: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func syncPackingChecklistItemIfNeeded(_ row: PackingChecklistItem) {
        let objectID = row.objectID
        Task { @MainActor in
            guard self.isCloudSyncEnabled else { return }
            guard self.supabaseService.isAuthenticated,
                  let userId = self.supabaseService.currentUser?.id,
                  let rowId = row.id else {
                return
            }

            do {
                try await SyncEngine.shared.syncPackingChecklistItemIfNeeded(
                    objectID: objectID,
                    rowId: rowId,
                    userId: userId
                )
            } catch {
                print("⚠️ Failed to sync packing checklist item \(rowId.uuidString): \(error.localizedDescription)")
            }
        }
    }

    nonisolated func syncPackingChecklistSectionIfNeeded(_ section: PackingChecklistSection) {
        let objectID = section.objectID
        Task { @MainActor in
            guard self.isCloudSyncEnabled else { return }
            guard self.supabaseService.isAuthenticated,
                  let userId = self.supabaseService.currentUser?.id,
                  let sectionId = section.id else {
                return
            }

            do {
                try await SyncEngine.shared.syncPackingChecklistSectionIfNeeded(
                    objectID: objectID,
                    sectionId: sectionId,
                    userId: userId
                )
            } catch {
                print("⚠️ Failed to sync packing checklist section \(sectionId.uuidString): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Deletes

    nonisolated func deleteTagFromSupabase(tagId: UUID) {
        Task { @MainActor in
            guard self.isCloudSyncEnabled else { return }
            await SyncEngine.shared.deleteTagFromSupabase(tagId: tagId)
        }
    }

    nonisolated func deleteOutfitCategoryFromSupabase(categoryId: UUID) {
        Task { @MainActor in
            guard self.isCloudSyncEnabled else { return }
            await SyncEngine.shared.deleteOutfitCategoryFromSupabase(categoryId: categoryId)
        }
    }

    nonisolated func deletePackingChecklistItemFromSupabase(checklistRowId: UUID) {
        Task { @MainActor in
            guard self.isCloudSyncEnabled else { return }
            await SyncEngine.shared.deletePackingChecklistItemFromSupabase(checklistRowId: checklistRowId)
        }
    }

    // MARK: - Bulk sync

    func syncAllItems() async throws {
        guard isCloudSyncEnabled else {
            print("⏭️ syncAllItems skipped (cloud sync disabled)")
            return
        }
        guard supabaseService.isAuthenticated,
              let userId = supabaseService.currentUser?.id else {
            throw SyncError.notAuthenticated
        }

        print("🔍 Starting sync for user: \(userId.uuidString)")

        let progress: SyncProgressHandler = { status, progressValue in
            Self.logBulkSyncProgress(status, progressValue)
        }

        try await SyncEngine.shared.syncAllItems(userId: userId, progress: progress)
    }

    func cleanupOrphanedData() async throws {
        guard isCloudSyncEnabled else {
            print("⏭️ cleanupOrphanedData skipped (cloud sync disabled)")
            return
        }
        guard supabaseService.isAuthenticated,
              let userId = supabaseService.currentUser?.id else {
            throw SyncError.notAuthenticated
        }

        let progress: SyncProgressHandler = { status, progressValue in
            Self.logBulkSyncProgress(status, progressValue)
        }

        try await SyncEngine.shared.cleanupOrphanedData(userId: userId, progress: progress)
    }

    // MARK: - Profile download (Supabase → viewContext)

    func syncUsernameToCoreData(_ username: String) async {
        let userId = supabaseService.currentUser?.id.uuidString
        await SyncEngine.shared.syncUsernameToCoreData(username, userId: userId)
    }

    func syncDisplayNameToCoreData(_ displayName: String) async {
        let userId = supabaseService.currentUser?.id.uuidString
        await SyncEngine.shared.syncDisplayNameToCoreData(displayName, userId: userId)
    }

    func syncAvatarUrlToCoreData(_ avatarUrl: String?) async {
        let userId = supabaseService.currentUser?.id.uuidString
        await SyncEngine.shared.syncAvatarUrlToCoreData(avatarUrl, userId: userId)
    }

    func syncStyleTagsToCoreData(_ styleTags: [String], userId: String?) async {
        await SyncEngine.shared.syncStyleTagsToCoreData(styleTags, userId: userId)
    }

    // MARK: - Profile upload

    nonisolated func syncUserProfileIfNeeded(_ profile: UserProfile) {
        let objectID = profile.objectID
        Task { @MainActor in
            guard self.isCloudSyncEnabled else { return }
            guard self.supabaseService.isAuthenticated,
                  let userId = self.supabaseService.currentUser?.id,
                  let viewContext = self.viewContext else {
                return
            }

            guard let profile = try? viewContext.existingObject(with: objectID) as? UserProfile else { return }
            viewContext.refresh(profile, mergeChanges: false)

            let needsSync: Bool
            if profile.syncedAt == nil {
                needsSync = true
            } else if let updatedAt = profile.updatedAt, let syncedAt = profile.syncedAt {
                needsSync = updatedAt > syncedAt
            } else {
                needsSync = false
            }

            guard needsSync else { return }

            do {
                try await SyncEngine.shared.syncUserProfileIfNeeded(objectID: objectID, userId: userId)
            } catch {
                print("⚠️ Auto-sync failed for user profile: \(error.localizedDescription)")
            }
        }
    }
}
