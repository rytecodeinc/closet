//
//  SyncService.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import Foundation
import CoreData
import Supabase
import UIKit

/// Service for syncing local items to Supabase
@MainActor
class SyncService: ObservableObject {
    static let shared = SyncService()
    
    @Published var isSyncing = false
    @Published var syncProgress: Double = 0.0
    @Published var syncStatus: String = ""
    
    private let supabaseService: SupabaseService
    private var context: NSManagedObjectContext?
    
    private init() {
        self.supabaseService = SupabaseService.shared
    }
    
    /// Sets the Core Data context for syncing
    func setContext(_ context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Product tier (TestFlight vs Production)

    private var isCloudSyncEnabled: Bool {
        AppEnvironment.capabilities.enablesCloudSync
    }

    private var isTombstonePurgeEnabled: Bool {
        AppEnvironment.capabilities.enablesTombstonePurge
    }

    // MARK: - Local tombstone purge (post-delete cleanup)
    /// Schedules a background purge of locally soft-deleted records that have already been deleted in Supabase.
    /// We delay slightly to avoid hard-deleting objects while SwiftUI may still be rendering them.
    func schedulePurgeLocalTombstones(delayNanoseconds: UInt64 = 800_000_000) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            await self.purgeLocalTombstonesIfPossible()
        }
    }

    /// Purges local soft-deleted records that have `syncedAt != nil` (i.e. backend delete succeeded).
    /// Safe to call repeatedly; does nothing if not authenticated or no context.
    func purgeLocalTombstonesIfPossible() async {
        guard isTombstonePurgeEnabled else { return }
        guard let context = context else { return }
        guard supabaseService.isAuthenticated, let userId = supabaseService.currentUser?.id else { return }

        // Items / outfits / wardrobes are user-scoped in this app.
        let userIdString = userId.uuidString

        // Helper to fetch + delete in a single pass.
        func purge<T: NSManagedObject>(_ request: NSFetchRequest<T>) throws -> Int {
            let objects = try context.fetch(request)
            guard !objects.isEmpty else { return 0 }
            for obj in objects { context.delete(obj) }
            return objects.count
        }

        do {
            var totalPurged = 0

            let itemRequest: NSFetchRequest<Item> = Item.fetchRequest()
            itemRequest.predicate = NSPredicate(format: "userId == %@ AND isSoftDeleted == YES AND syncedAt != nil", userIdString)
            totalPurged += try purge(itemRequest)

            let outfitRequest: NSFetchRequest<Outfit> = Outfit.fetchRequest()
            outfitRequest.predicate = NSPredicate(format: "userId == %@ AND isSoftDeleted == YES AND syncedAt != nil", userIdString)
            totalPurged += try purge(outfitRequest)

            let wardrobeRequest: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
            wardrobeRequest.predicate = NSPredicate(format: "userId == %@ AND isSoftDeleted == YES AND syncedAt != nil", userIdString)
            totalPurged += try purge(wardrobeRequest)

            if totalPurged > 0 {
                try context.save()
                print("🧹 Purged \(totalPurged) synced tombstone record(s) from local Core Data")
            }
        } catch {
            print("⚠️ Failed to purge local tombstones: \(error.localizedDescription)")
        }
    }
    
    /// Migrates existing local items and reference data to the authenticated user
    // Disabled — syncAllItems call commented out.
    /*
    func migrateLocalItemsToUser(userId: UUID) async throws {
        guard let context = context else {
            throw SyncError.noContext
        }
        
        // Migrate items
        let itemRequest: NSFetchRequest<Item> = Item.fetchRequest()
        itemRequest.predicate = NSPredicate(format: "userId == nil OR userId == ''")
        let items = try context.fetch(itemRequest)
        
        for item in items {
            if item.id == nil {
                item.id = UUID()
            }
            item.userId = userId.uuidString
        }
        
        // Migrate reference data
        let brandRequest: NSFetchRequest<Brand> = Brand.fetchRequest()
        brandRequest.predicate = NSPredicate(format: "userId == nil OR userId == ''")
        let brands = try context.fetch(brandRequest)
        for brand in brands {
            if brand.id == nil {
                brand.id = UUID()
            }
            brand.userId = userId.uuidString
        }
        
        let categoryRequest: NSFetchRequest<Category> = Category.fetchRequest()
        categoryRequest.predicate = NSPredicate(format: "userId == nil OR userId == ''")
        let categories = try context.fetch(categoryRequest)
        for category in categories {
            if category.id == nil {
                category.id = UUID()
            }
            category.userId = userId.uuidString
        }
        
        let subcategoryRequest: NSFetchRequest<Subcategory> = Subcategory.fetchRequest()
        subcategoryRequest.predicate = NSPredicate(format: "userId == nil OR userId == ''")
        let subcategories = try context.fetch(subcategoryRequest)
        for subcategory in subcategories {
            if subcategory.id == nil {
                subcategory.id = UUID()
            }
            subcategory.userId = userId.uuidString
        }
        
        let colorRequest: NSFetchRequest<AppColor> = AppColor.fetchRequest()
        colorRequest.predicate = NSPredicate(format: "userId == nil OR userId == ''")
        let colors = try context.fetch(colorRequest)
        for color in colors {
            if color.id == nil {
                color.id = UUID()
            }
            color.userId = userId.uuidString
        }
        
        let seasonRequest: NSFetchRequest<Season> = Season.fetchRequest()
        seasonRequest.predicate = NSPredicate(format: "userId == nil OR userId == ''")
        let seasons = try context.fetch(seasonRequest)
        for season in seasons {
            if season.id == nil {
                season.id = UUID()
            }
            season.userId = userId.uuidString
        }
        
        let sizeRequest: NSFetchRequest<Size> = Size.fetchRequest()
        sizeRequest.predicate = NSPredicate(format: "userId == nil OR userId == ''")
        let sizes = try context.fetch(sizeRequest)
        for size in sizes {
            if size.id == nil {
                size.id = UUID()
            }
            size.userId = userId.uuidString
        }
        
        let tagRequest: NSFetchRequest<Tag> = Tag.fetchRequest()
        tagRequest.predicate = NSPredicate(format: "userId == nil OR userId == ''")
        let tags = try context.fetch(tagRequest)
        for tag in tags {
            if tag.id == nil {
                tag.id = UUID()
            }
            tag.userId = userId.uuidString
        }
        
        let locationRequest: NSFetchRequest<Location> = Location.fetchRequest()
        locationRequest.predicate = NSPredicate(format: "userId == nil OR userId == ''")
        let locations = try context.fetch(locationRequest)
        for location in locations {
            if location.id == nil {
                location.id = UUID()
            }
            location.userId = userId.uuidString
        }
        
        let wardrobeRequest: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        wardrobeRequest.predicate = NSPredicate(format: "userId == nil OR userId == ''")
        let wardrobes = try context.fetch(wardrobeRequest)
        for wardrobe in wardrobes {
            if wardrobe.id == nil {
                wardrobe.id = UUID()
            }
            wardrobe.userId = userId.uuidString
        }
        
        try context.save()
        print("✅ Migrated \(items.count) items and reference data to user: \(userId.uuidString)")
    }
    */
    
    /// Syncs a single item to Supabase (for automatic sync after save)
    /// This is called automatically when items are created or modified
    /// Marked as nonisolated so it can be called from any context
    nonisolated func syncItemIfNeeded(_ item: Item) {
        // Only sync if authenticated - check on main actor
        Task { @MainActor in
            guard self.supabaseService.isAuthenticated,
                  let userId = self.supabaseService.currentUser?.id,
                  let context = self.context else {
                return
            }

            // Drafts are local-only — never push to Supabase
            guard !item.isDraft else {
                print("⏭️ Skipping sync for draft item: \(item.name ?? "unnamed")")
                return
            }
            
            // Process pending changes to ensure newly added photos are included
            if context.hasChanges {
                do {
                    try context.save()
                    print("💾 Saved pending changes before sync")
                } catch {
                    print("⚠️ Failed to save pending changes: \(error.localizedDescription)")
                }
            }
            
            // CRITICAL: Set userId on item if it's not set (for new items)
            if item.userId == nil || item.userId?.isEmpty == true {
                item.userId = userId.uuidString
                do {
                    try context.save()
                    print("✅ Set userId on new item: \(item.name ?? "unnamed")")
                } catch {
                    print("⚠️ Failed to set userId on item: \(error.localizedDescription)")
                }
            }

            guard self.isCloudSyncEnabled else {
                return
            }
            
            // Refresh item from context to ensure we have latest values
            // Use mergeChanges: true to preserve newly added relationships (like photos)
            context.refresh(item, mergeChanges: true)
            
            // Ensure photos relationship is loaded (not a fault) - CRITICAL for new photos
            _ = item.photos
            
            if let pairedItems = item.pairedItems as? Set<Item> {
                print("🔍 Item '\(item.name ?? "unnamed")' has \(pairedItems.count) paired items in Core Data")
                for (idx, paired) in Array(pairedItems).enumerated() {
                    print("   Pair #\(idx + 1): \(paired.name ?? "unnamed") (ID: \(paired.id?.uuidString ?? "no ID"))")
                }
            } else {
                print("🔍 Item '\(item.name ?? "unnamed")' has no paired items")
            }
            
            if let photos = item.photos as? Set<Photo> {
                print("📸 Item '\(item.name ?? "unnamed")' has \(photos.count) photos in Core Data")
                for (idx, photo) in Array(photos).enumerated() {
                    print("   Photo #\(idx + 1): type=\(photo.type ?? "nil"), id=\(photo.id?.uuidString ?? "no ID")")
                }
            } else {
                print("📸 Item '\(item.name ?? "unnamed")' has no photos")
            }
            
            // Check if item needs syncing (syncedAt == nil OR updatedAt >= syncedAt)
            let needsSync: Bool
            if item.syncedAt == nil {
                needsSync = true // Never synced
            } else if let updatedAt = item.updatedAt, let syncedAt = item.syncedAt {
                // Use >= instead of > to handle edge case where they're set at same time
                needsSync = updatedAt >= syncedAt // Changed since last sync
            } else {
                needsSync = false
            }
            
            guard needsSync else {
                return // Item is already synced and up to date
            }
            
            // Sync in background (don't block UI)
            do {
                // CRITICAL: Ensure all referenced entities are synced first
                // This prevents foreign key constraint violations
                try await self.ensureReferencedEntitiesSynced(for: item, userId: userId)
                
                // Ensure reference data is synced (for any other entities that might be needed)
                try await self.syncAllReferenceData(userId: userId)
                
                // Sync the item
                try await self.syncItem(item, userId: userId)
                print("✅ Auto-synced item: \(item.name ?? "unnamed")")
            } catch {
                print("⚠️ Auto-sync failed for item '\(item.name ?? "unnamed")': \(error.localizedDescription)")
                // Don't show error to user - sync happens in background
            }
        }
    }
    
    /// Syncs all local items to Supabase
    func syncAllItems() async throws {
        guard isCloudSyncEnabled else {
            print("⏭️ syncAllItems skipped (cloud sync disabled)")
            return
        }
        guard let context = context else {
            throw SyncError.noContext
        }
        
        guard supabaseService.isAuthenticated,
              let userId = supabaseService.currentUser?.id else {
            throw SyncError.notAuthenticated
        }
        
        print("🔍 Starting sync for user: \(userId.uuidString)")
        print("🔍 Authenticated user ID: \(supabaseService.currentUser?.id.uuidString ?? "none")")
        
        isSyncing = true
        syncStatus = "Starting sync..."
        
        defer {
            isSyncing = false
            syncStatus = ""
        }
        
        // 1. Migrate items to user if needed
        // try await migrateLocalItemsToUser(userId: userId)
        
        // 2. Sync reference data first (brands, categories, etc.) to avoid foreign key violations
        syncStatus = "Syncing reference data..."
        try await syncAllReferenceData(userId: userId)
        
        // 3. Get all items that need syncing
        let unsyncedItems = try fetchUnsyncedItems()
        let totalItems = unsyncedItems.count
        
        print("🔍 Found \(totalItems) items that need syncing")
        if totalItems > 0 {
            print("🔍 First item: \(unsyncedItems.first?.name ?? "unnamed"), ID: \(unsyncedItems.first?.id?.uuidString ?? "no ID"), userId: \(unsyncedItems.first?.userId ?? "no userId")")
        }
        
        guard totalItems > 0 else {
            syncStatus = "All items are synced"
            print("ℹ️ No items need syncing - all are up to date")
            // Even if nothing needs syncing, we may have synced tombstones to purge.
            schedulePurgeLocalTombstones()
            return
        }
        
        syncStatus = "Syncing \(totalItems) items..."
        
        // 4. Sync each item
        for (index, item) in unsyncedItems.enumerated() {
            syncProgress = Double(index) / Double(totalItems)
            syncStatus = "Syncing item \(index + 1) of \(totalItems)..."
            
            do {
                try await syncItem(item, userId: userId)
            } catch {
                print("❌ Failed to sync item '\(item.name ?? "unnamed")' (ID: \(item.id?.uuidString ?? "no ID")): \(error)")
                print("❌ Error details: \(error.localizedDescription)")
                let nsError = error as NSError
                print("❌ Error domain: \(nsError.domain), code: \(nsError.code)")
                print("❌ User info: \(nsError.userInfo)")
                // Continue with next item instead of failing entire sync
                continue
            }
        }
        
        syncProgress = 1.0
        syncStatus = "Sync complete!"
        
        print("✅ Successfully synced \(totalItems) items")
        
        // Sync any outfits that haven't been pushed to Supabase yet
        try await syncAllOutfits(userId: userId)

        // After a sync session completes, purge any soft-deleted records that were successfully deleted in Supabase.
        schedulePurgeLocalTombstones()
    }
    
    /// Syncs all outfits that have never been synced or have changed since last sync.
    /// Called at the end of syncAllItems() so that pre-existing outfits created before
    /// sync was implemented are pushed to Supabase automatically.
    private func syncAllOutfits(userId: UUID) async throws {
        guard let context = context else { return }
        
        let request: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        request.predicate = NSPredicate(
            format: "userId == %@ AND isDraft != YES AND isSoftDeleted != YES AND (syncedAt == nil OR updatedAt > syncedAt)",
            userId.uuidString
        )
        
        let outfitsToSync: [Outfit]
        do {
            outfitsToSync = try context.fetch(request)
        } catch {
            print("⚠️ Failed to fetch outfits for sync: \(error.localizedDescription)")
            return
        }
        
        guard !outfitsToSync.isEmpty else {
            print("ℹ️ No outfits need syncing")
            return
        }
        
        print("🔍 Found \(outfitsToSync.count) outfit(s) that need syncing")
        
        for outfit in outfitsToSync {
            // Ensure userId is set (safety net for outfits created before userId was required)
            if outfit.userId == nil || outfit.userId?.isEmpty == true {
                outfit.userId = userId.uuidString
                try? context.save()
            }
            do {
                try await syncOutfit(outfit, userId: userId)
                print("✅ Synced outfit: \(outfit.name ?? "unnamed")")
            } catch {
                print("⚠️ Failed to sync outfit '\(outfit.name ?? "unnamed")': \(error.localizedDescription)")
            }
        }
    }

    /// One-time cleanup: Removes orphaned data from Supabase and R2
    /// Orphaned data = data in Supabase that references items that don't exist in Core Data
    func cleanupOrphanedData() async throws {
        guard isCloudSyncEnabled else {
            print("⏭️ cleanupOrphanedData skipped (cloud sync disabled)")
            return
        }
        guard let context = context else {
            throw SyncError.noContext
        }
        
        guard supabaseService.isAuthenticated,
              let userId = supabaseService.currentUser?.id else {
            throw SyncError.notAuthenticated
        }
        
        print("🧹 Starting orphaned data cleanup for user: \(userId.uuidString)")
        
        isSyncing = true
        syncStatus = "Cleaning up orphaned data..."
        
        defer {
            isSyncing = false
            syncStatus = ""
        }
        
        // STEP 1: Get all item IDs from Core Data (what should exist)
        let itemRequest: NSFetchRequest<Item> = Item.fetchRequest()
        itemRequest.predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        itemRequest.propertiesToFetch = ["id"]
        let localItems = try context.fetch(itemRequest)
        let localItemIds = Set(localItems.compactMap { $0.id?.uuidString })
        print("📦 Found \(localItemIds.count) items in Core Data")
        
        // STEP 2: Get all items from Supabase
        let supabaseItemsResponse = try await supabaseService.supabaseClient.from("items")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        let itemsData: Data = supabaseItemsResponse.data
        struct ItemIdResponse: Codable {
            let id: String
        }
        let supabaseItems = try JSONDecoder().decode([ItemIdResponse].self, from: itemsData)
        let supabaseItemIds = Set(supabaseItems.map { $0.id })
        print("📦 Found \(supabaseItemIds.count) items in Supabase")
        
        // STEP 3: Find orphaned items (in Supabase but not in Core Data)
        let orphanedItemIds = supabaseItemIds.subtracting(localItemIds)
        print("🗑️ Found \(orphanedItemIds.count) orphaned items")
        
        var deletedPhotos = 0
        var deletedThumbnails = 0
        var deletedJunctionEntries = 0
        
        // STEP 4: For each orphaned item, delete all related data
        for (index, orphanedItemId) in orphanedItemIds.enumerated() {
            syncProgress = Double(index) / Double(orphanedItemIds.count)
            syncStatus = "Cleaning up item \(index + 1) of \(orphanedItemIds.count)..."
            
            guard let itemUUID = UUID(uuidString: orphanedItemId) else {
                print("⚠️ Invalid item ID format: \(orphanedItemId)")
                continue
            }
            
            print("🗑️ Cleaning up orphaned item: \(orphanedItemId)")
            
            // Delete photos from R2 and Supabase
            let photosResponse = try await supabaseService.supabaseClient.from("item_photos")
                .select("id")
                .eq("item_id", value: orphanedItemId)
                .execute()
            
            let photosData: Data = photosResponse.data
            if let photos = try? JSONDecoder().decode([ItemPhotoResponse].self, from: photosData) {
                for photo in photos {
                    guard let photoUUID = UUID(uuidString: photo.id) else { continue }
                    
                    // Delete from R2 (full image)
                    do {
                        try await supabaseService.deletePhoto(
                            itemId: itemUUID,
                            photoId: photoUUID,
                            userId: userId
                        )
                        deletedPhotos += 1
                        print("✅ Deleted photo from R2: \(photo.id)")
                    } catch {
                        print("⚠️ Failed to delete photo \(photo.id) from R2: \(error.localizedDescription)")
                    }
                    
                    // Delete thumbnail from R2
                    do {
                        let thumbnailFileName = "\(userId.uuidString)/\(orphanedItemId)/\(photo.id)_thumb.jpg"
                        let thumbnailUrl = URL(string: "\(CloudflareR2Config.workerURL)/\(thumbnailFileName)")!
                        
                        guard let session = supabaseService.currentSession else {
                            continue
                        }
                        
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
                
                // Delete photo metadata from Supabase
                do {
                    try await supabaseService.supabaseClient.from("item_photos")
                        .delete()
                        .eq("item_id", value: orphanedItemId)
                        .execute()
                } catch {
                    print("⚠️ Failed to delete photo metadata for item \(orphanedItemId): \(error.localizedDescription)")
                }
            }
            
            // Delete junction table entries
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
                    _ = try await supabaseService.supabaseClient.from(table)
                        .delete()
                        .eq("item_id", value: orphanedItemId)
                        .execute()
                    deletedJunctionEntries += 1
                    print("✅ Deleted entries from \(table) for item: \(orphanedItemId)")
                } catch {
                    print("⚠️ Failed to delete from \(table) for item \(orphanedItemId): \(error.localizedDescription)")
                }
                
                // Also delete reverse pairs
                if table == "item_pairs" {
                    do {
                        try await supabaseService.supabaseClient.from(table)
                            .delete()
                            .eq("paired_item_id", value: orphanedItemId)
                            .execute()
                        print("✅ Deleted reverse pairs for item: \(orphanedItemId)")
                    } catch {
                        print("⚠️ Failed to delete reverse pairs for item \(orphanedItemId): \(error.localizedDescription)")
                    }
                }
            }
            
            // Delete the item itself
            try await supabaseService.supabaseClient.from("items")
                .delete()
                .eq("id", value: orphanedItemId)
                .execute()
            
            print("✅ Cleaned up orphaned item: \(orphanedItemId)")
        }
        
        // STEP 5: Clean up orphaned photos for existing items (photos that exist in Supabase but not in Core Data)
        // Get all photos from Core Data
        let photoRequest: NSFetchRequest<Photo> = Photo.fetchRequest()
        let allLocalPhotos = try context.fetch(photoRequest)
        let localPhotoIds = Set(allLocalPhotos.compactMap { $0.id?.uuidString })
        print("📸 Found \(localPhotoIds.count) photos in Core Data")
        
        // Get all photos from Supabase for existing items
        if !localItemIds.isEmpty {
            // Get photos for items that exist in Core Data
            let itemIdsArray = Array(localItemIds)
            let allPhotosResponse = try await supabaseService.supabaseClient.from("item_photos")
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
            
            let allPhotosData: Data = allPhotosResponse.data
            if let allPhotos = try? JSONDecoder().decode([PhotoWithItemResponse].self, from: allPhotosData) {
                let orphanedPhotos = allPhotos.filter { !localPhotoIds.contains($0.id) }
                print("📸 Found \(orphanedPhotos.count) orphaned photos for existing items")
                
                for photo in orphanedPhotos {
                    guard let itemUUID = UUID(uuidString: photo.itemId),
                          let photoUUID = UUID(uuidString: photo.id) else { continue }
                    
                    // Delete from R2
                    do {
                        try await supabaseService.deletePhoto(
                            itemId: itemUUID,
                            photoId: photoUUID,
                            userId: userId
                        )
                        deletedPhotos += 1
                        print("✅ Deleted orphaned photo from R2: \(photo.id)")
                    } catch {
                        print("⚠️ Failed to delete orphaned photo \(photo.id) from R2: \(error.localizedDescription)")
                    }
                    
                    // Delete thumbnail
                    do {
                        let thumbnailFileName = "\(userId.uuidString)/\(photo.itemId)/\(photo.id)_thumb.jpg"
                        let thumbnailUrl = URL(string: "\(CloudflareR2Config.workerURL)/\(thumbnailFileName)")!
                        
                        guard let session = supabaseService.currentSession else { continue }
                        
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
                    
                    // Delete from Supabase
                    do {
                        try await supabaseService.supabaseClient.from("item_photos")
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
        
        syncProgress = 1.0
        syncStatus = "Cleanup complete!"
        
        print("✅ Cleanup complete!")
        print("   - Deleted \(orphanedItemIds.count) orphaned items")
        print("   - Deleted \(deletedPhotos) orphaned photos from R2")
        print("   - Deleted \(deletedThumbnails) orphaned thumbnails from R2")
        print("   - Deleted \(deletedJunctionEntries) junction table entries")
    }
    
    /// Syncs all reference data (brands, categories, colors, etc.) before syncing items
    /// Only syncs entities that have changed since last sync (syncedAt == nil OR updatedAt > syncedAt)
    private func syncAllReferenceData(userId: UUID) async throws {
        guard let context = context else {
            throw SyncError.noContext
        }
        
        // Sync brands - only if changed
        let brandRequest: NSFetchRequest<Brand> = Brand.fetchRequest()
        brandRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let brands = try context.fetch(brandRequest)
        for brand in brands {
            try await syncBrand(brand, userId: userId)
        }
        
        // Sync categories - only if changed
        let categoryRequest: NSFetchRequest<Category> = Category.fetchRequest()
        categoryRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let categories = try context.fetch(categoryRequest)
        for category in categories {
            try await syncCategory(category, userId: userId)
        }
        
        // Sync subcategories - only if changed
        let subcategoryRequest: NSFetchRequest<Subcategory> = Subcategory.fetchRequest()
        subcategoryRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let subcategories = try context.fetch(subcategoryRequest)
        for subcategory in subcategories {
            try await syncSubcategory(subcategory, userId: userId)
        }
        
        // Sync colors - only if changed
        let colorRequest: NSFetchRequest<AppColor> = AppColor.fetchRequest()
        colorRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let colors = try context.fetch(colorRequest)
        for color in colors {
            try await syncColor(color, userId: userId)
        }
        
        // Sync seasons - only if changed
        let seasonRequest: NSFetchRequest<Season> = Season.fetchRequest()
        seasonRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let seasons = try context.fetch(seasonRequest)
        for season in seasons {
            try await syncSeason(season, userId: userId)
        }
        
        // Sync sizes - include all sizes referenced by items, but only sync if changed
        // First, initialize updatedAt for any sizes that don't have it (one-time migration)
        let allSizesRequest: NSFetchRequest<Size> = Size.fetchRequest()
        allSizesRequest.predicate = NSPredicate(format: "userId == %@ OR userId == nil OR userId == ''", userId.uuidString)
        let allSizes = try context.fetch(allSizesRequest)
        var hasChanges = false
        for size in allSizes {
            if size.updatedAt == nil {
                // Initialize updatedAt to syncedAt if available, otherwise use a date in the past
                size.updatedAt = size.syncedAt ?? Date.distantPast
                hasChanges = true
            }
        }
        if hasChanges {
            try context.save()
        }
        
        // Now fetch only sizes that need syncing (syncedAt == nil OR updatedAt > syncedAt)
        let sizeRequest: NSFetchRequest<Size> = Size.fetchRequest()
        sizeRequest.predicate = NSPredicate(format: "(userId == %@ OR userId == nil OR userId == '') AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let sizes = try context.fetch(sizeRequest)
        
        // Also get all sizes referenced by items to ensure we sync them if changed
        let itemRequest: NSFetchRequest<Item> = Item.fetchRequest()
        itemRequest.predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        let items = try context.fetch(itemRequest)
        var referencedSizeIds = Set<UUID>()
        for item in items {
            if let size = item.size, let sizeId = size.id {
                referencedSizeIds.insert(sizeId)
            }
        }
        
        // Sync all sizes (with userId and referenced by items) - only if changed
        var syncedSizeIds = Set<UUID>()
        for size in sizes {
            if let sizeId = size.id {
                // Migrate size to user if needed
                if size.userId == nil || size.userId?.isEmpty == true {
                    size.userId = userId.uuidString
                    // Set updatedAt when migrating
                    size.updatedAt = Date()
                }
                try await syncSize(size, userId: userId)
                syncedSizeIds.insert(sizeId)
            }
        }
        
        // Sync any referenced sizes that weren't already synced and have changed
        for sizeId in referencedSizeIds {
            if !syncedSizeIds.contains(sizeId) {
                let sizeRequest: NSFetchRequest<Size> = Size.fetchRequest()
                sizeRequest.predicate = NSPredicate(format: "id == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", sizeId as CVarArg)
                if let size = try context.fetch(sizeRequest).first {
                    if size.userId == nil || size.userId?.isEmpty == true {
                        size.userId = userId.uuidString
                        size.updatedAt = Date()
                    }
                    try await syncSize(size, userId: userId)
                }
            }
        }
        
        // Sync tags - only if changed
        let tagRequest: NSFetchRequest<Tag> = Tag.fetchRequest()
        tagRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let tags = try context.fetch(tagRequest)
        for tag in tags {
            try await syncTag(tag, userId: userId)
        }
        
        // Sync locations - only if changed
        let locationRequest: NSFetchRequest<Location> = Location.fetchRequest()
        locationRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let locations = try context.fetch(locationRequest)
        for location in locations {
            try await syncLocation(location, userId: userId)
        }
        
        // Sync wardrobes - only if changed (wardrobes already have syncedAt and updatedAt)
        let wardrobeRequest: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        wardrobeRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let wardrobes = try context.fetch(wardrobeRequest)
        for wardrobe in wardrobes {
            try await syncWardrobe(wardrobe, userId: userId)
        }
        
        print("✅ Synced all reference data (only changed entities)")
    }
    
    /// Fetches items that need syncing
    private func fetchUnsyncedItems() throws -> [Item] {
        guard let context = context else {
            throw SyncError.noContext
        }
        
        guard let userId = supabaseService.currentUser?.id else {
            throw SyncError.notAuthenticated
        }
        
        let request: NSFetchRequest<Item> = Item.fetchRequest()
        request.predicate = NSPredicate(
            format: "userId == %@ AND isDraft != YES AND (syncedAt == nil OR updatedAt > syncedAt)",
            userId.uuidString
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.createdAt, ascending: true)]
        
        return try context.fetch(request)
    }
    
    // MARK: - Reference Data Sync Methods
    
    /// Ensures all referenced entities for an item are synced before syncing the item
    /// This prevents foreign key constraint violations
    private func ensureReferencedEntitiesSynced(for item: Item, userId: UUID) async throws {
        guard let context = context else { throw SyncError.noContext }
        
        // Ensure brand is synced if item has a brand
        if let brand = item.brand {
            // Set userId on brand if not set
            if brand.userId == nil || brand.userId?.isEmpty == true {
                brand.userId = userId.uuidString
                try context.save()
            }
            // Sync brand regardless of syncedAt status to ensure it exists in Supabase
            try await syncBrand(brand, userId: userId)
        }
        
        // Ensure category is synced if item has a category
        if let category = item.category {
            // Set userId on category if not set
            if category.userId == nil || category.userId?.isEmpty == true {
                category.userId = userId.uuidString
                try context.save()
            }
            // Sync category regardless of syncedAt status
            try await syncCategory(category, userId: userId)
        }
        
        // Ensure subcategory is synced if item has a subcategory
        if let subcategory = item.subcategory {
            // Ensure parent category is synced first
            if let category = subcategory.category {
                if category.userId == nil || category.userId?.isEmpty == true {
                    category.userId = userId.uuidString
                    try context.save()
                }
                try await syncCategory(category, userId: userId)
            }
            // Set userId on subcategory if not set
            if subcategory.userId == nil || subcategory.userId?.isEmpty == true {
                subcategory.userId = userId.uuidString
                try context.save()
            }
            // Sync subcategory regardless of syncedAt status
            try await syncSubcategory(subcategory, userId: userId)
        }
        
        // Ensure size is synced if item has a size
        if let size = item.size {
            // Set userId on size if not set
            if size.userId == nil || size.userId?.isEmpty == true {
                size.userId = userId.uuidString
                // Initialize updatedAt if nil
                if size.updatedAt == nil {
                    size.updatedAt = Date.distantPast
                }
                try context.save()
            }
            // Sync size regardless of syncedAt status
            try await syncSize(size, userId: userId)
        }
        
        // Ensure location is synced if item has a location
        if let location = item.location {
            // Set userId on location if not set
            if location.userId == nil || location.userId?.isEmpty == true {
                location.userId = userId.uuidString
                try context.save()
            }
            // Sync location regardless of syncedAt status
            try await syncLocation(location, userId: userId)
        }
    }
    
    /// Syncs a brand to Supabase
    private func syncBrand(_ brand: Brand, userId: UUID) async throws {
        guard let context = context else { throw SyncError.noContext }
        guard let brandId = brand.id else { return }
        
        let brandData = SyncBrandData(
            id: brandId.uuidString,
            userId: userId.uuidString,
            name: brand.name ?? "",
            isVisible: brand.isVisible
        )
        
        try await supabaseService.supabaseClient.from("brands")
            .upsert(brandData, onConflict: "id")
            .execute()
        
        // Mark as synced
        brand.syncedAt = Date()
        try context.save()
    }
    
    /// Syncs a category to Supabase
    private func syncCategory(_ category: Category, userId: UUID) async throws {
        guard let context = context else { throw SyncError.noContext }
        guard let categoryId = category.id else { return }
        
        let categoryData = SyncCategoryData(
            id: categoryId.uuidString,
            userId: userId.uuidString,
            name: category.name ?? ""
        )
        
        try await supabaseService.supabaseClient.from("categories")
            .upsert(categoryData, onConflict: "id")
            .execute()
        
        // Mark as synced
        category.syncedAt = Date()
        try context.save()
    }
    
    /// Syncs a subcategory to Supabase
    private func syncSubcategory(_ subcategory: Subcategory, userId: UUID) async throws {
        guard let context = context else { throw SyncError.noContext }
        guard let subcategoryId = subcategory.id else { return }
        guard let categoryId = subcategory.category?.id else { return }
        
        let subcategoryData = SyncSubcategoryData(
            id: subcategoryId.uuidString,
            categoryId: categoryId.uuidString,
            userId: userId.uuidString,
            name: subcategory.name ?? "",
            sortOrder: Int(subcategory.sortOrder)
        )
        
        try await supabaseService.supabaseClient.from("subcategories")
            .upsert(subcategoryData, onConflict: "id")
            .execute()
        
        // Mark as synced
        subcategory.syncedAt = Date()
        try context.save()
    }
    
    /// Syncs a color to Supabase
    private func syncColor(_ color: AppColor, userId: UUID) async throws {
        guard let context = context else { throw SyncError.noContext }
        guard let colorId = color.id else { return }
        
        let colorData = SyncColorData(
            id: colorId.uuidString,
            userId: userId.uuidString,
            name: color.name ?? "",
            hexCode: color.hexCode,
            isVisible: color.isVisible
        )
        
        try await supabaseService.supabaseClient.from("colors")
            .upsert(colorData, onConflict: "id")
            .execute()
        
        // Mark as synced
        color.syncedAt = Date()
        try context.save()
    }
    
    /// Syncs a season to Supabase
    private func syncSeason(_ season: Season, userId: UUID) async throws {
        guard let context = context else { throw SyncError.noContext }
        guard let seasonId = season.id else { return }
        
        let seasonData = SyncSeasonData(
            id: seasonId.uuidString,
            userId: userId.uuidString,
            name: season.name ?? "",
            isVisible: season.isVisible
        )
        
        try await supabaseService.supabaseClient.from("seasons")
            .upsert(seasonData, onConflict: "id")
            .execute()
        
        // Mark as synced
        season.syncedAt = Date()
        try context.save()
    }
    
    /// Syncs a size to Supabase
    private func syncSize(_ size: Size, userId: UUID) async throws {
        guard let context = context else { throw SyncError.noContext }
        guard let sizeId = size.id else {
            print("⚠️ Size missing ID, skipping sync")
            return
        }
        
        // Check if this size actually needs syncing (for logging purposes)
        let needsSync: Bool
        if size.syncedAt == nil {
            needsSync = true // Never synced
        } else if let updatedAt = size.updatedAt, let syncedAt = size.syncedAt {
            needsSync = updatedAt > syncedAt // Changed since last sync
        } else {
            needsSync = false
        }
        
        // Sizes are now independent of categories - category_id is optional
        let sizeData = SyncSizeData(
            id: sizeId.uuidString,
            categoryId: size.category?.id?.uuidString, // Optional
            userId: userId.uuidString,
            value: size.value ?? "",
            scale: size.scale,
            sortOrder: Int(size.sortOrder)
        )
        
        try await supabaseService.supabaseClient.from("sizes")
            .upsert(sizeData, onConflict: "id")
            .execute()
        
        // Mark as synced
        let now = Date()
        size.syncedAt = now
        // Ensure updatedAt is set to syncedAt so it won't sync again unless changed
        if size.updatedAt == nil || (size.updatedAt ?? Date.distantPast) <= (size.syncedAt ?? Date.distantPast) {
            size.updatedAt = now
        }
        try context.save()
        
        // Only print if this was an actual sync (not just initialization)
        if needsSync {
            let categoryInfo = size.category?.name ?? "no category"
            print("✅ Synced size: \(size.value ?? "unknown") (category: \(categoryInfo))")
        }
    }
    
    /// Syncs a tag to Supabase
    private func syncTag(_ tag: Tag, userId: UUID) async throws {
        guard let context = context else { throw SyncError.noContext }
        guard let tagId = tag.id else { return }
        
        let tagData = SyncTagData(
            id: tagId.uuidString,
            userId: userId.uuidString,
            name: tag.name ?? ""
        )
        
        try await supabaseService.supabaseClient.from("tags")
            .upsert(tagData, onConflict: "id")
            .execute()
        
        // Mark as synced
        tag.syncedAt = Date()
        try context.save()
    }
    
    /// Deletes a tag from Supabase (item_tags, outfit_tags, tags). Call after removing the tag from Core Data.
    nonisolated func deleteTagFromSupabase(tagId: UUID) {
        Task { @MainActor in
            guard self.isCloudSyncEnabled else { return }
            guard self.supabaseService.isAuthenticated else { return }
            let idString = tagId.uuidString
            do {
                try await self.supabaseService.supabaseClient.from("item_tags")
                    .delete()
                    .eq("tag_id", value: idString)
                    .execute()
                try await self.supabaseService.supabaseClient.from("outfit_tags")
                    .delete()
                    .eq("tag_id", value: idString)
                    .execute()
                try await self.supabaseService.supabaseClient.from("tags")
                    .delete()
                    .eq("id", value: idString)
                    .execute()
                print("✅ Deleted tag \(idString) from Supabase")
            } catch {
                print("⚠️ Failed to delete tag from Supabase: \(error.localizedDescription)")
            }
        }
    }
    
    /// Syncs a location to Supabase
    private func syncLocation(_ location: Location, userId: UUID) async throws {
        guard let context = context else { throw SyncError.noContext }
        guard let locationId = location.id else { return }
        
        let locationData = SyncLocationData(
            id: locationId.uuidString,
            userId: userId.uuidString,
            name: location.name ?? ""
        )
        
        try await supabaseService.supabaseClient.from("locations")
            .upsert(locationData, onConflict: "id")
            .execute()
        
        // Mark as synced
        location.syncedAt = Date()
        try context.save()
    }
    
    /// Syncs a single wardrobe to Supabase (for automatic sync after save)
    nonisolated func syncWardrobeIfNeeded(_ wardrobe: Wardrobe) {
        Task { @MainActor in
            guard self.supabaseService.isAuthenticated,
                  let userId = self.supabaseService.currentUser?.id,
                  let wardrobeId = wardrobe.id,
                  let context = self.context else {
                return
            }
            
            // Fetch the wardrobe by ID to ensure we have the latest state
            // This is important after soft delete since the wardrobe might be filtered out of fetch requests
            let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", wardrobeId as CVarArg)
            request.fetchLimit = 1
            
            guard let refreshedWardrobe = try? context.fetch(request).first else {
                print("⚠️ Could not find wardrobe with ID \(wardrobeId) for sync")
                return
            }
            
            // Set userId if not set (for new wardrobes)
            if refreshedWardrobe.userId == nil || refreshedWardrobe.userId?.isEmpty == true {
                refreshedWardrobe.userId = userId.uuidString
                do {
                    try context.save()
                    print("✅ Set userId on new wardrobe: \(refreshedWardrobe.name ?? "unnamed")")
                } catch {
                    print("⚠️ Failed to set userId on wardrobe: \(error.localizedDescription)")
                }
            }

            guard self.isCloudSyncEnabled else { return }
            
            // Check if wardrobe needs syncing
            let needsSync: Bool
            if refreshedWardrobe.syncedAt == nil {
                needsSync = true
            } else if let updatedAt = refreshedWardrobe.updatedAt, let syncedAt = refreshedWardrobe.syncedAt {
                needsSync = updatedAt >= syncedAt
            } else {
                needsSync = false
            }
            
            guard needsSync else {
                return
            }
            
            // Sync in background
            do {
                try await self.syncWardrobe(refreshedWardrobe, userId: userId)
                print("✅ Auto-synced wardrobe: \(refreshedWardrobe.name ?? "unnamed") (isSoftDeleted: \(refreshedWardrobe.isSoftDeleted))")
            } catch {
                print("⚠️ Auto-sync failed for wardrobe '\(refreshedWardrobe.name ?? "unnamed")': \(error.localizedDescription)")
            }
        }
    }
    
    /// Syncs a wardrobe to Supabase
    private func syncWardrobe(_ wardrobe: Wardrobe, userId: UUID) async throws {
        guard let wardrobeId = wardrobe.id,
              let context = context else { return }
        
        // If soft-deleted, actually delete from Supabase
        if wardrobe.isSoftDeleted {
            print("🗑️ Deleting wardrobe from Supabase: \(wardrobe.name ?? "unnamed")")
            try await supabaseService.supabaseClient.from("wardrobes")
                .delete()
                .eq("id", value: wardrobeId.uuidString)
                .execute()
            
            // Mark as synced after successful deletion
            wardrobe.syncedAt = Date()
            try context.save()
            print("✅ Successfully deleted wardrobe from Supabase")
            return
        }
        
        // Otherwise, upsert as normal
        let sectionTitleSynced = (wardrobe.packingChecklistSectionTitle ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let wardrobeData = SyncWardrobeData(
            id: wardrobeId.uuidString,
            userId: userId.uuidString,
            name: wardrobe.name ?? "",
            type: wardrobe.type,
            isSoftDeleted: wardrobe.isSoftDeleted,
            isDefault: wardrobe.isDefault,
            packingChecklistSectionTitle: sectionTitleSynced.isEmpty ? "" : sectionTitleSynced,
            createdAt: wardrobe.createdAt?.ISO8601String ?? wardrobe.timestamp?.ISO8601String,
            updatedAt: wardrobe.updatedAt?.ISO8601String
        )
        
        print("📤 Syncing wardrobe to Supabase: \(wardrobe.name ?? "unnamed") (isSoftDeleted: \(wardrobe.isSoftDeleted))")
        
        try await supabaseService.supabaseClient.from("wardrobes")
            .upsert(wardrobeData, onConflict: "id")
            .execute()
        
        print("✅ Successfully synced wardrobe to Supabase: \(wardrobe.name ?? "unnamed")")
        
        // Mark as synced after successful upload
        wardrobe.syncedAt = Date()
        try context.save()
    }
    
    // MARK: - Packing checklist sync
    
    /// Push a checklist row after local edits (travel wardrobe scope).
    nonisolated func syncPackingChecklistItemIfNeeded(_ row: PackingChecklistItem) {
        Task { @MainActor in
            guard self.isCloudSyncEnabled else { return }
            guard self.supabaseService.isAuthenticated,
                  let userId = self.supabaseService.currentUser?.id,
                  let rowId = row.id,
                  let context = self.context else {
                return
            }
            
            let request: NSFetchRequest<PackingChecklistItem> = PackingChecklistItem.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", rowId as CVarArg)
            request.fetchLimit = 1
            
            guard let refreshed = try? context.fetch(request).first else {
                return
            }
            guard refreshed.wardrobe != nil, refreshed.wardrobe?.id != nil else {
                print("⚠️ Packing checklist row missing wardrobe; skip sync \(rowId.uuidString)")
                return
            }
            
            if refreshed.userId == nil || refreshed.userId?.isEmpty == true {
                refreshed.userId = userId.uuidString
                try? context.save()
            }
            
            let needsSync: Bool
            if refreshed.syncedAt == nil {
                needsSync = true
            } else if let updatedAt = refreshed.updatedAt, let syncedAt = refreshed.syncedAt {
                needsSync = updatedAt >= syncedAt
            } else {
                needsSync = false
            }
            
            guard needsSync else { return }

            let trimmedText = (refreshed.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            do {
                // Supabase only stores non-empty lines; placeholders and cleared rows have no remote row.
                if trimmedText.isEmpty {
                    if refreshed.syncedAt != nil {
                        try await self.supabaseService.supabaseClient.from("packing_checklist_items")
                            .delete()
                            .eq("id", value: rowId.uuidString)
                            .execute()
                        print("✅ Removed empty packing_checklist_items row \(rowId.uuidString) from Supabase")
                    }
                    refreshed.syncedAt = Date()
                    try context.save()
                    return
                }

                guard let wardrobe = refreshed.wardrobe else { return }
                var wardrobeNeedsPush = wardrobe.syncedAt == nil
                if !wardrobeNeedsPush,
                   let wu = wardrobe.updatedAt,
                   let ws = wardrobe.syncedAt {
                    wardrobeNeedsPush = wu >= ws
                }
                if wardrobeNeedsPush {
                    try await self.syncWardrobe(wardrobe, userId: userId)
                }
                if let section = refreshed.section {
                    try await self.syncPackingChecklistSection(section, userId: userId)
                }
                try await self.syncPackingChecklistRow(refreshed, userId: userId, checklistText: trimmedText)
            } catch {
                print("⚠️ Failed to sync packing checklist item \(rowId.uuidString): \(error.localizedDescription)")
            }
        }
    }
    
    /// Deletes a checklist row server-side after local removal.
    nonisolated func deletePackingChecklistItemFromSupabase(checklistRowId: UUID) {
        Task { @MainActor in
            guard self.isCloudSyncEnabled else { return }
            guard self.supabaseService.isAuthenticated else { return }
            let idString = checklistRowId.uuidString
            do {
                try await self.supabaseService.supabaseClient.from("packing_checklist_items")
                    .delete()
                    .eq("id", value: idString)
                    .execute()
                print("✅ Deleted packing_checklist_items row \(idString) from Supabase")
            } catch {
                print("⚠️ Failed to delete packing_checklist_items \(idString): \(error.localizedDescription)")
            }
        }
    }
    
    /// Push a checklist section header after local edits.
    nonisolated func syncPackingChecklistSectionIfNeeded(_ section: PackingChecklistSection) {
        Task { @MainActor in
            guard self.isCloudSyncEnabled else { return }
            guard self.supabaseService.isAuthenticated,
                  let userId = self.supabaseService.currentUser?.id,
                  let sectionId = section.id,
                  let context = self.context else {
                return
            }

            let request: NSFetchRequest<PackingChecklistSection> = PackingChecklistSection.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", sectionId as CVarArg)
            request.fetchLimit = 1

            guard let refreshed = try? context.fetch(request).first else { return }
            guard refreshed.wardrobe?.id != nil else { return }

            if refreshed.userId == nil || refreshed.userId?.isEmpty == true {
                refreshed.userId = userId.uuidString
                try? context.save()
            }

            let needsSync: Bool
            if refreshed.syncedAt == nil {
                needsSync = true
            } else if let updatedAt = refreshed.updatedAt, let syncedAt = refreshed.syncedAt {
                needsSync = updatedAt >= syncedAt
            } else {
                needsSync = false
            }

            guard needsSync else { return }

            do {
                try await self.syncPackingChecklistSection(refreshed, userId: userId)
            } catch {
                print("⚠️ Failed to sync packing checklist section \(sectionId.uuidString): \(error.localizedDescription)")
            }
        }
    }

    private func syncPackingChecklistSection(_ section: PackingChecklistSection, userId: UUID) async throws {
        guard let context = context else { throw SyncError.noContext }
        guard let id = section.id, let wardrobeId = section.wardrobe?.id else { return }

        let title = (section.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = SyncPackingChecklistSectionData(
            id: id.uuidString,
            userId: userId.uuidString,
            wardrobeId: wardrobeId.uuidString,
            kind: Int(section.kind),
            title: title,
            sortIndex: Int(section.sortIndex),
            createdAt: section.createdAt?.ISO8601String,
            updatedAt: section.updatedAt?.ISO8601String ?? section.createdAt?.ISO8601String
        )

        try await supabaseService.supabaseClient.from("packing_checklist_sections")
            .upsert(payload, onConflict: "id")
            .execute()

        section.syncedAt = Date()
        try context.save()
    }

    private func syncPackingChecklistRow(_ row: PackingChecklistItem, userId: UUID, checklistText: String) async throws {
        guard let context = context else { throw SyncError.noContext }
        guard let id = row.id, let wardrobeId = row.wardrobe?.id else { return }
        
        let payload = SyncPackingChecklistItemData(
            id: id.uuidString,
            userId: userId.uuidString,
            wardrobeId: wardrobeId.uuidString,
            sectionId: row.section?.id?.uuidString,
            kind: Int(row.kind),
            checklistText: checklistText,
            isCompleted: row.isCompleted,
            sortIndex: Int(row.sortIndex),
            createdAt: row.createdAt?.ISO8601String,
            updatedAt: row.updatedAt?.ISO8601String ?? row.createdAt?.ISO8601String
        )
        
        try await supabaseService.supabaseClient.from("packing_checklist_items")
            .upsert(payload, onConflict: "id")
            .execute()
        
        row.syncedAt = Date()
        try context.save()
    }
    
    // MARK: - Outfit Sync

    nonisolated func syncOutfitIfNeeded(_ outfit: Outfit) {
        Task { @MainActor in
            guard self.supabaseService.isAuthenticated,
                  let userId = self.supabaseService.currentUser?.id,
                  let outfitId = outfit.id,
                  let context = self.context else {
                return
            }

            // Fetch by ID to ensure latest state
            let request: NSFetchRequest<Outfit> = Outfit.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", outfitId as CVarArg)
            request.fetchLimit = 1

            guard let refreshedOutfit = try? context.fetch(request).first else {
                print("⚠️ Could not find outfit with ID \(outfitId) for sync")
                return
            }

            // Drafts are local-only — never push to Supabase
            guard !refreshedOutfit.isDraft else {
                print("⏭️ Skipping sync for draft outfit: \(refreshedOutfit.name ?? "unnamed")")
                return
            }

            // Set userId if missing (safety net)
            if refreshedOutfit.userId == nil || refreshedOutfit.userId?.isEmpty == true {
                refreshedOutfit.userId = userId.uuidString
                try? context.save()
            }

            guard self.isCloudSyncEnabled else { return }

            // Check if sync is needed
            let needsSync: Bool
            if refreshedOutfit.syncedAt == nil {
                needsSync = true
            } else if let updatedAt = refreshedOutfit.updatedAt, let syncedAt = refreshedOutfit.syncedAt {
                needsSync = updatedAt >= syncedAt
            } else {
                needsSync = true // always sync if timestamps are missing
            }

            guard needsSync else { return }

            do {
                try await self.syncOutfit(refreshedOutfit, userId: userId)
                print("✅ Auto-synced outfit: \(refreshedOutfit.name ?? "unnamed")")
            } catch {
                print("⚠️ Auto-sync failed for outfit '\(refreshedOutfit.name ?? "unnamed")': \(error.localizedDescription)")
            }
        }
    }

    private func syncOutfit(_ outfit: Outfit, userId: UUID) async throws {
        guard let outfitId = outfit.id,
              let context = context else { return }

        // Soft-deleted: remove from R2 and Supabase
        if outfit.isSoftDeleted {
            print("🗑️ Deleting outfit from Supabase and R2: \(outfit.name ?? "unnamed")")

            // Delete collage image from R2
            do {
                try await supabaseService.deleteOutfitImage(outfitId: outfitId, userId: userId)
            } catch {
                print("⚠️ Failed to delete outfit image from R2: \(error.localizedDescription)")
            }

            do {
                try await supabaseService.deleteOutfitWornImage(outfitId: outfitId, userId: userId)
            } catch {
                print("⚠️ Failed to delete outfit worn image from R2: \(error.localizedDescription)")
            }

            do {
                try await supabaseService.supabaseClient.from("outfit_items")
                    .delete()
                    .eq("outfit_id", value: outfitId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete outfit_items: \(error.localizedDescription)")
            }

            do {
                try await supabaseService.supabaseClient.from("outfit_tags")
                    .delete()
                    .eq("outfit_id", value: outfitId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete outfit_tags: \(error.localizedDescription)")
            }

            try await supabaseService.supabaseClient.from("outfits")
                .delete()
                .eq("id", value: outfitId.uuidString)
                .execute()

            outfit.syncedAt = Date()
            try context.save()
            print("✅ Deleted outfit from Supabase and R2")

            // Now that backend deletion succeeded, purge the local tombstone later (safe timing).
            schedulePurgeLocalTombstones()
            return
        }

        // Upload collage image to R2 if available
        var imageUrl: String? = nil
        if let imageData = outfit.image {
            do {
                imageUrl = try await supabaseService.uploadOutfitImage(
                    imageData: imageData,
                    outfitId: outfitId,
                    userId: userId
                )
                print("✅ Uploaded outfit image to R2: \(imageUrl ?? "")")
            } catch {
                print("⚠️ Failed to upload outfit image to R2: \(error.localizedDescription)")
                // Continue syncing metadata even if image upload fails
            }
        }

        var wornImageUrl: String? = nil
        if let wornData = outfit.wornImage {
            do {
                wornImageUrl = try await supabaseService.uploadOutfitWornImage(
                    imageData: wornData,
                    outfitId: outfitId,
                    userId: userId
                )
                print("✅ Uploaded outfit worn image to R2: \(wornImageUrl ?? "")")
            } catch {
                print("⚠️ Failed to upload outfit worn image to R2: \(error.localizedDescription)")
            }
        }

        // Serialize transformationData (portable UUID format) as JSON string for Supabase
        var transformationJson: String? = nil
        if let transformationData = outfit.transformationData {
            transformationJson = String(data: transformationData, encoding: .utf8)
        }

        // Upsert outfit metadata
        let outfitData = SyncOutfitData(
            id: outfitId.uuidString,
            userId: userId.uuidString,
            name: outfit.name,
            notes: outfit.notes,
            isFavorite: outfit.isFavorite,
            isDraft: outfit.isDraft,
            isSoftDeleted: outfit.isSoftDeleted,
            category: outfit.category,
            createdAt: outfit.createdAt?.ISO8601String,
            updatedAt: outfit.updatedAt?.ISO8601String ?? outfit.createdAt?.ISO8601String,
            imageUrl: imageUrl,
            wornImageUrl: wornImageUrl,
            transformationJson: transformationJson
        )

        try await supabaseService.supabaseClient.from("outfits")
            .upsert(outfitData, onConflict: "id")
            .execute()
        print("✅ Upserted outfit metadata: \(outfit.name ?? "unnamed")")

        // Ensure every item in the outfit exists in Supabase before inserting outfit_items
        // (outfit_items has a FK constraint: item_id → items.id).
        // Only sync items that have never been synced (syncedAt == nil). Items that already
        // have a syncedAt timestamp are guaranteed to exist in Supabase and must NOT be
        // re-synced here — doing so risks running pair/relationship cleanup against an
        // incompletely-loaded Core Data context, which would delete valid Supabase rows.
        if let items = outfit.items as? Set<Item> {
            for item in items {
                guard item.id != nil else { continue }
                guard item.syncedAt == nil else { continue }
                if item.userId == nil || item.userId?.isEmpty == true {
                    item.userId = userId.uuidString
                    try? context.save()
                }
                do {
                    try await ensureReferencedEntitiesSynced(for: item, userId: userId)
                    try await syncItem(item, userId: userId)
                } catch {
                    print("⚠️ Failed to pre-sync outfit item '\(item.name ?? "unnamed")': \(error.localizedDescription)")
                }
            }
        }

        // Sync relationships
        try await syncOutfitRelationships(outfit, outfitId: outfitId)

        outfit.syncedAt = Date()
        try context.save()
    }

    private func syncOutfitRelationships(_ outfit: Outfit, outfitId: UUID) async throws {
        // --- outfit_items ---
        let currentItemIds: Set<String>
        if let items = outfit.items as? Set<Item> {
            currentItemIds = Set(items.compactMap { $0.id?.uuidString })
        } else {
            currentItemIds = Set()
        }

        let existingItemsResponse = try await supabaseService.supabaseClient.from("outfit_items")
            .select("item_id")
            .eq("outfit_id", value: outfitId.uuidString)
            .execute()

        let existingItemIds: Set<String>
        if let decoded = try? JSONDecoder().decode([OutfitItemResponse].self, from: existingItemsResponse.data) {
            existingItemIds = Set(decoded.compactMap { $0.itemId })
        } else {
            existingItemIds = Set()
        }

        for idToDelete in existingItemIds.subtracting(currentItemIds) {
            try? await supabaseService.supabaseClient.from("outfit_items")
                .delete()
                .eq("outfit_id", value: outfitId.uuidString)
                .eq("item_id", value: idToDelete)
                .execute()
        }

        for itemId in currentItemIds {
            let junction = OutfitItemJunction(outfitId: outfitId.uuidString, itemId: itemId)
            do {
                try await supabaseService.supabaseClient.from("outfit_items")
                    .upsert(junction, onConflict: "outfit_id,item_id")
                    .execute()
            } catch {
                print("⚠️ Skipping outfit_items insert for item \(itemId): \(error.localizedDescription)")
            }
        }

        // --- outfit_tags ---
        let currentTagIds: Set<String>
        if let tags = outfit.tags as? Set<Tag> {
            currentTagIds = Set(tags.compactMap { $0.id?.uuidString })
        } else {
            currentTagIds = Set()
        }

        let existingTagsResponse = try await supabaseService.supabaseClient.from("outfit_tags")
            .select("tag_id")
            .eq("outfit_id", value: outfitId.uuidString)
            .execute()

        let existingTagIds: Set<String>
        if let decoded = try? JSONDecoder().decode([OutfitTagResponse].self, from: existingTagsResponse.data) {
            existingTagIds = Set(decoded.compactMap { $0.tagId })
        } else {
            existingTagIds = Set()
        }

        for idToDelete in existingTagIds.subtracting(currentTagIds) {
            try? await supabaseService.supabaseClient.from("outfit_tags")
                .delete()
                .eq("outfit_id", value: outfitId.uuidString)
                .eq("tag_id", value: idToDelete)
                .execute()
        }

        for tagId in currentTagIds {
            let junction = OutfitTagJunction(outfitId: outfitId.uuidString, tagId: tagId)
            try await supabaseService.supabaseClient.from("outfit_tags")
                .upsert(junction, onConflict: "outfit_id,tag_id")
                .execute()
        }
    }

    /// Syncs username to Core Data (called from SupabaseService when username is loaded)
    @MainActor
    func syncUsernameToCoreData(_ username: String) {
        guard let context = context else {
            print("⚠️ No context available for username sync")
            return
        }
        
        // Get userId from SupabaseService
        let userId = supabaseService.currentUser?.id.uuidString
        
        let repository = UserProfileRepository(context: context)
        do {
            try repository.updateUsername(username, userId: userId)
        } catch {
            print("⚠️ Failed to sync username to Core Data: \(error.localizedDescription)")
        }
    }
    
    /// Syncs display name to Core Data (called from SupabaseService when display_name is loaded)
    @MainActor
    func syncDisplayNameToCoreData(_ displayName: String) {
        guard let context = context else {
            print("⚠️ No context available for display name sync")
            return
        }
        
        // Get userId from SupabaseService
        let userId = supabaseService.currentUser?.id.uuidString
        
        let repository = UserProfileRepository(context: context)
        do {
            try repository.updateDisplayName(displayName, userId: userId)
        } catch {
            print("⚠️ Failed to sync display name to Core Data: \(error.localizedDescription)")
        }
    }

    /// Syncs profile avatar URL from Supabase into Core Data.
    @MainActor
    func syncAvatarUrlToCoreData(_ avatarUrl: String?) {
        guard let context = context else {
            print("⚠️ No context available for avatar URL sync")
            return
        }
        let userId = supabaseService.currentUser?.id.uuidString
        let repository = UserProfileRepository(context: context)
        do {
            try repository.updateAvatarUrl(avatarUrl, userId: userId)
        } catch {
            print("⚠️ Failed to sync avatar URL to Core Data: \(error.localizedDescription)")
        }
    }
    
    /// Syncs user profile (weight data) to Supabase
    nonisolated func syncUserProfileIfNeeded(_ profile: UserProfile) {
        // Only sync if authenticated - check on main actor
        Task { @MainActor in
            guard self.isCloudSyncEnabled else { return }
            guard self.supabaseService.isAuthenticated,
                  let userId = self.supabaseService.currentUser?.id,
                  let context = self.context else {
                return
            }
            
            // Refresh profile from context to ensure we have latest values
            context.refresh(profile, mergeChanges: false)
            
            // Check if profile needs syncing (syncedAt == nil OR updatedAt >= syncedAt)
            let needsSync: Bool
            if profile.syncedAt == nil {
                needsSync = true // Never synced
            } else if let updatedAt = profile.updatedAt, let syncedAt = profile.syncedAt {
                // Strict ordering: equal timestamps mean "already uploaded this revision"; avoid duplicate pushes.
                needsSync = updatedAt > syncedAt
            } else {
                needsSync = false
            }
            
            guard needsSync else {
                return // Profile is already synced and up to date
            }
            
            // Sync in background (don't block UI)
            do {
                try await self.syncUserProfile(profile, userId: userId)
            } catch {
                print("⚠️ Auto-sync failed for user profile: \(error.localizedDescription)")
                // Don't show error to user - sync happens in background
            }
        }
    }
    
    /// Syncs user profile (weight, username, displayName) to Supabase
    private func syncUserProfile(_ profile: UserProfile, userId: UUID) async throws {
        guard let context = context else {
            throw SyncError.noContext
        }
        
        // Build profile data struct with all available fields
        let weightKg = profile.weightKg
        let hasWeight = weightKg > 0 && weightKg.isFinite && !weightKg.isNaN
        let hasWeightUnit = profile.weightUnit != nil && !profile.weightUnit!.isEmpty
        
        let profileData = SyncUserProfileData(
            userId: userId.uuidString,
            weightKg: hasWeight && hasWeightUnit ? weightKg : nil,
            weightUnit: hasWeightUnit ? profile.weightUnit : nil,
            username: (profile.username?.isEmpty == false) ? profile.username : nil,
            displayName: (profile.displayName?.isEmpty == false) ? profile.displayName : nil,
            updatedAt: profile.updatedAt?.ISO8601String
        )
        
        // Only sync if there's data to sync (more than just user_id)
        let hasData = profileData.weightKg != nil || 
                     profileData.weightUnit != nil ||
                     profileData.username != nil ||
                     profileData.displayName != nil
        
        guard hasData else {
            return
        }

        // Upsert profile data to user_profiles table (using user_id as conflict key)
        try await supabaseService.supabaseClient.from("user_profiles")
            .upsert(profileData, onConflict: "user_id")
            .execute()
        
        // Mark as synced after successful upload
        profile.syncedAt = Date()
        try context.save()
    }
    
    /// Syncs a single item to Supabase
    private func syncItem(_ item: Item, userId: UUID) async throws {
        guard let context = context else {
            throw SyncError.noContext
        }
        
        guard let itemId = item.id else {
            print("⚠️ Item missing ID, skipping sync")
            return
        }
        
        // If soft-deleted, actually delete from Supabase and R2
        if item.isSoftDeleted {
            print("🗑️ Deleting item from Supabase and R2: \(item.name ?? "unnamed")")
            
            // STEP 1: Delete all photos from R2
            if let photos = item.photos as? Set<Photo> {
                for photo in photos {
                    guard let photoId = photo.id else { continue }
                    
                    // Delete full image from R2
                    do {
                        try await supabaseService.deletePhoto(
                            itemId: itemId,
                            photoId: photoId,
                            userId: userId
                        )
                        print("✅ Deleted photo from R2: \(photoId.uuidString)")
                    } catch {
                        print("⚠️ Failed to delete photo \(photoId.uuidString) from R2: \(error.localizedDescription)")
                        // Continue with other deletions even if one fails
                    }
                    
                    // Delete thumbnail from R2 (thumbnails use _thumb suffix)
                    do {
                        let thumbnailFileName = "\(userId.uuidString)/\(itemId.uuidString)/\(photoId.uuidString)_thumb.jpg"
                        let thumbnailUrl = URL(string: "\(CloudflareR2Config.workerURL)/\(thumbnailFileName)")!
                        
                        guard let session = supabaseService.currentSession else {
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
                        // Continue with other deletions even if one fails
                    }
                }
            }
            
            // STEP 2: Delete item relationships from Supabase (junction tables)
            // Delete item_colors
            do {
                try await supabaseService.supabaseClient.from("item_colors")
                    .delete()
                    .eq("item_id", value: itemId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete item_colors: \(error.localizedDescription)")
            }
            
            // Delete item_seasons
            do {
                try await supabaseService.supabaseClient.from("item_seasons")
                    .delete()
                    .eq("item_id", value: itemId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete item_seasons: \(error.localizedDescription)")
            }
            
            // Delete item_tags
            do {
                try await supabaseService.supabaseClient.from("item_tags")
                    .delete()
                    .eq("item_id", value: itemId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete item_tags: \(error.localizedDescription)")
            }
            
            // Delete item_wardrobes
            do {
                try await supabaseService.supabaseClient.from("item_wardrobes")
                    .delete()
                    .eq("item_id", value: itemId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete item_wardrobes: \(error.localizedDescription)")
            }
            
            // Delete item_pairs (both directions)
            do {
                try await supabaseService.supabaseClient.from("item_pairs")
                    .delete()
                    .eq("item_id", value: itemId.uuidString)
                    .execute()
                
                try await supabaseService.supabaseClient.from("item_pairs")
                    .delete()
                    .eq("paired_item_id", value: itemId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete item_pairs: \(error.localizedDescription)")
            }
            
            // Delete item_links
            do {
                try await supabaseService.supabaseClient.from("item_links")
                    .delete()
                    .eq("item_id", value: itemId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete item_links: \(error.localizedDescription)")
            }
            
            // Delete item_prices
            do {
                try await supabaseService.supabaseClient.from("item_prices")
                    .delete()
                    .eq("item_id", value: itemId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete item_prices: \(error.localizedDescription)")
            }
            
            // Delete item_photos
            do {
                try await supabaseService.supabaseClient.from("item_photos")
                    .delete()
                    .eq("item_id", value: itemId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Failed to delete item_photos: \(error.localizedDescription)")
            }
            
            // STEP 3: Delete the item itself from Supabase
            do {
                try await supabaseService.supabaseClient.from("items")
                    .delete()
                    .eq("id", value: itemId.uuidString)
                    .execute()
                print("✅ Successfully deleted item from Supabase: \(item.name ?? "unnamed")")
            } catch {
                print("❌ Failed to delete item from Supabase: \(error.localizedDescription)")
                throw error
            }
            
            // Mark as synced after successful deletion
            item.syncedAt = Date()
            try context.save()
            print("✅ Successfully deleted item from Supabase and R2")

            // Now that backend deletion succeeded, purge the local tombstone later (safe timing).
            schedulePurgeLocalTombstones()
            return
        }
        
        // Otherwise, upsert as normal
        // Prepare item data using Codable struct
        // Sizes are now independent of categories, so we can always include size_id
        let itemData = SyncItemData(
            id: itemId.uuidString,
            userId: userId.uuidString,
            name: item.name ?? "",
            notes: item.notes,
            isFavorite: item.isFavorite,
            // isWishlist removed - replaced by item_wardrobes junction table
            isDraft: item.isDraft,
            minTemperature: item.minTemperature > 0 ? item.minTemperature : nil,
            maxTemperature: item.maxTemperature > 0 ? item.maxTemperature : nil,
            temperatureUnit: item.temperatureUnit,
            weight: item.weight > 0 ? item.weight : nil,
            weightUnit: item.weightUnit,
            isSoftDeleted: item.isSoftDeleted,
            createdAt: item.createdAt?.ISO8601String,
            updatedAt: item.updatedAt?.ISO8601String ?? item.createdAt?.ISO8601String,
            brandId: item.brand?.id?.uuidString,
            categoryId: item.category?.id?.uuidString,
            subcategoryId: item.subcategory?.id?.uuidString,
            sizeId: item.size?.id?.uuidString,
            locationId: item.location?.id?.uuidString
        )
        
        // Upload item metadata
        do {
            try await supabaseService.supabaseClient.from("items")
                .upsert(itemData, onConflict: "id")
                .execute()
            print("✅ Uploaded item metadata to Supabase: \(item.name ?? "unnamed")")
        } catch {
            print("❌ Failed to upload item '\(item.name ?? "unnamed")' to Supabase")
            print("❌ Error: \(error)")
            let nsError = error as NSError
            print("❌ Error domain: \(nsError.domain), code: \(nsError.code)")
            print("❌ User info: \(nsError.userInfo)")
            throw error
        }
        
        // Sync photos with proper deletion handling
        try await syncItemPhotos(item, itemId: itemId, userId: userId)
        
        // Sync relationships (colors, seasons, tags, etc.)
        try await syncItemRelationships(item, userId: userId)
        
        // Sync price if exists
        if let price = item.price {
            try await syncPrice(price, itemId: itemId, userId: userId)
        }
        
        // Sync links with proper deletion handling
        try await syncItemLinks(item, itemId: itemId, userId: userId)
        
        // Mark as synced
        item.syncedAt = Date()
        try context.save()
        
        print("✅ Synced item: \(item.name ?? "unnamed")")
    }
    
    /// Syncs item photos with proper deletion handling
    /// Compares Core Data photos vs Supabase photos and deletes orphaned photos from R2 and Supabase
    private func syncItemPhotos(_ item: Item, itemId: UUID, userId: UUID) async throws {
        print("📸 Starting photo sync for item: \(item.name ?? "unnamed") (ID: \(itemId.uuidString))")
        
        // STEP 1: Get what photos SHOULD exist (from Core Data)
        let currentPhotoIds: Set<String>
        if let photos = item.photos as? Set<Photo> {
            currentPhotoIds = Set(photos.compactMap { $0.id?.uuidString })
            print("📸 Core Data shows \(currentPhotoIds.count) photos for this item")
        } else {
            currentPhotoIds = Set()
            print("📸 Core Data shows 0 photos for this item")
        }
        
        // STEP 2: Get what photos currently exist in Supabase (BEFORE making any changes)
        let existingPhotosResponse = try await supabaseService.supabaseClient.from("item_photos")
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
                    try await supabaseService.deletePhoto(
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
                    
                    guard let session = supabaseService.currentSession else {
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
                    try await supabaseService.supabaseClient.from("item_photos")
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
        if let photos = item.photos as? Set<Photo> {
            print("📸 Upserting \(photos.count) current photos to Supabase")
            for photo in photos {
                try await syncPhoto(photo, itemId: itemId, userId: userId)
            }
            print("✅ Finished syncing \(photos.count) photos")
        } else {
            print("📸 No photos in Core Data")
        }
    }
    
    /// Target max payload size for R2 worker (5 MB); stay slightly under for safety.
    private static let r2WorkerSafeMaxBytes = 4_800_000

    /// Hard ceiling (5 MiB); reject encoded output that still exceeds worker limits.
    private static let r2WorkerHardMaxBytes = 5 * 1024 * 1024

    /// Ensures image bytes respect the worker cap. When re-encoding, updates `photo.data` so Core Data matches the CDN.
    private func imageDataPreparedForR2Upload(original: Data, photo: Photo) throws -> Data {
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
    private func syncPhoto(_ photo: Photo, itemId: UUID, userId: UUID) async throws {
        guard let context = context else {
            throw SyncError.noContext
        }
        
        guard let photoId = photo.id else {
            print("⚠️ Photo missing ID, skipping sync")
            return
        }
        
        var imageUrl: String? = nil
        var thumbnailUrl: String? = nil
        
        // Check if we have existing R2 URLs (not base64)
        let hasValidImageUrl = photo.imageUrl != nil && 
                              !photo.imageUrl!.isEmpty && 
                              !photo.imageUrl!.starts(with: "data:")
        
        let hasValidThumbnailUrl = photo.thumbnailUrl != nil && 
                                   !photo.thumbnailUrl!.isEmpty && 
                                   !photo.thumbnailUrl!.starts(with: "data:")
        
        // STEP 1: Upload full image if needed
        if let imageData = photo.data, !imageData.isEmpty {
            let payload = try imageDataPreparedForR2Upload(original: imageData, photo: photo)
            if context.hasChanges {
                try context.save()
            }
            imageUrl = try await supabaseService.uploadPhoto(
                imageData: payload,
                itemId: itemId,
                photoId: photoId,
                userId: userId
            )
            photo.imageUrl = imageUrl
            try context.save()
            print("✅ Uploaded new image to R2: \(imageUrl ?? "nil")")
        } else if hasValidImageUrl {
            // Use existing R2 URL
            imageUrl = photo.imageUrl
            print("✅ Using existing image URL: \(imageUrl ?? "nil")")
        } else {
            print("⚠️ No image data and no valid R2 URL for photo \(photoId)")
        }
        
        // STEP 2: Upload thumbnail
        if let thumbnailData = photo.thumbnailData, !thumbnailData.isEmpty {
            // We have thumbnail data - upload it to R2
            thumbnailUrl = try await supabaseService.uploadThumbnail(
                imageData: thumbnailData,
                itemId: itemId,
                photoId: photoId,
                userId: userId
            )
            photo.thumbnailUrl = thumbnailUrl
            try context.save()
            print("✅ Uploaded new thumbnail to R2: \(thumbnailUrl ?? "nil")")
        } else if hasValidThumbnailUrl {
            // Use existing R2 URL
            thumbnailUrl = photo.thumbnailUrl
            print("✅ Using existing thumbnail URL: \(thumbnailUrl ?? "nil")")
        } else {
            // MIGRATION: If we have base64 thumbnail, re-generate from image
            if let existingThumb = photo.thumbnailUrl, existingThumb.starts(with: "data:") {
                print("🔄 Migrating base64 thumbnail to R2 for photo \(photoId)")
                
                // Try to get thumbnail data from the base64 string or re-generate from full image
                if let imageData = photo.data, !imageData.isEmpty {
                    // Generate thumbnail from full image
                    if let thumbnailData = generateThumbnail(from: imageData) {
                        thumbnailUrl = try await supabaseService.uploadThumbnail(
                            imageData: thumbnailData,
                            itemId: itemId,
                            photoId: photoId,
                            userId: userId
                        )
                        photo.thumbnailUrl = thumbnailUrl
                        photo.thumbnailData = thumbnailData  // Store for future use
                        try context.save()
                        print("✅ Migrated thumbnail to R2: \(thumbnailUrl ?? "nil")")
                    }
                } else {
                    print("⚠️ Cannot migrate thumbnail - no image data available")
                }
            }
        }
        
        // STEP 3: Update metadata in Supabase
        try await updatePhotoMetadata(photo, itemId: itemId, userId: userId, imageUrl: imageUrl, thumbnailUrl: thumbnailUrl)
    }
    
    /// Updates photo metadata in Supabase
    /// Uses thumbnail URL from R2 instead of base64 for storage efficiency
    private func updatePhotoMetadata(_ photo: Photo, itemId: UUID, userId: UUID, imageUrl: String? = nil, thumbnailUrl: String? = nil) async throws {
        guard let photoId = photo.id else { return }
        
        let url = imageUrl ?? photo.imageUrl
        // Use provided thumbnailUrl or get from photo entity (which should have R2 URL stored)
        let thumbUrl = thumbnailUrl ?? photo.thumbnailUrl
        
        // Prepare photo data using Codable struct
        // thumbnailUrl is now a URL string from R2, not base64
        let photoData = SyncPhotoData(
            id: photoId.uuidString,
            itemId: itemId.uuidString,
            userId: userId.uuidString,
            imageUrl: url,
            isPrimary: photo.isPrimary,
            type: photo.type,
            createdAt: photo.createdAt?.ISO8601String ?? photo.timestamp?.ISO8601String,
            thumbnailUrl: thumbUrl, // Now a URL from R2, not base64!
            timestamp: photo.timestamp?.ISO8601String,
            updatedAt: Date().ISO8601String
        )
        
        try await supabaseService.supabaseClient.from("item_photos")
            .upsert(photoData, onConflict: "id")
            .execute()
        
        print("✅ Updated photo metadata in Supabase: \(photoId.uuidString)")
        if let thumbUrl = thumbUrl {
            print("   Thumbnail URL: \(thumbUrl)")
        }
    }
    
    /// Generates a thumbnail from full image data
    private func generateThumbnail(from imageData: Data, maxSize: CGFloat = 200) -> Data? {
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
    private func downloadImage(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "SyncService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
    
    /// Syncs item relationships (colors, seasons, tags, wardrobes, pairs)
    /// Handles deletion of orphaned relationships when they're removed from items
    private func syncItemRelationships(_ item: Item, userId: UUID) async throws {
        guard let itemId = item.id else { return }
        
        // Sync item_colors with proper deletion handling
        print("🎨 Starting color sync for item: \(item.name ?? "unnamed") (ID: \(itemId.uuidString))")
        
        // STEP 1: Get what colors SHOULD exist (from Core Data)
        let currentColorIds: Set<String>
        if let colors = item.colors as? Set<AppColor> {
            currentColorIds = Set(colors.compactMap { $0.id?.uuidString })
            print("🎨 Core Data shows \(currentColorIds.count) colors for this item")
        } else {
            currentColorIds = Set()
            print("🎨 Core Data shows 0 colors for this item")
        }
        
        // STEP 2: Get what colors currently exist in Supabase (BEFORE making any changes)
        let existingColorsResponse = try await supabaseService.supabaseClient.from("item_colors")
            .select("color_id")
            .eq("item_id", value: itemId.uuidString)
            .execute()
        
        let colorsData: Data = existingColorsResponse.data
        let existingColorIds: Set<String>
        if let existingColors = try? JSONDecoder().decode([ItemColorResponse].self, from: colorsData) {
            existingColorIds = Set(existingColors.compactMap { $0.colorId })
            print("🎨 Supabase shows \(existingColorIds.count) existing colors")
        } else {
            existingColorIds = Set()
            print("🎨 Supabase shows 0 existing colors (or failed to decode)")
        }
        
        // STEP 3: Delete colors that no longer exist in Core Data
        let colorsToDelete = existingColorIds.subtracting(currentColorIds)
        if !colorsToDelete.isEmpty {
            print("🗑️ Deleting \(colorsToDelete.count) orphaned colors from Supabase")
            for colorIdToDelete in colorsToDelete {
                do {
                    try await supabaseService.supabaseClient.from("item_colors")
                        .delete()
                        .eq("item_id", value: itemId.uuidString)
                        .eq("color_id", value: colorIdToDelete)
                        .execute()
                    print("✅ Deleted color: \(colorIdToDelete)")
                } catch {
                    print("⚠️ Failed to delete color \(colorIdToDelete): \(error)")
                }
            }
        } else {
            print("🎨 No orphaned colors to delete")
        }
        
        // STEP 4: Now sync current colors (upsert new/existing)
        if let colors = item.colors as? Set<AppColor> {
            print("🎨 Upserting \(colors.count) current colors to Supabase")
            for color in colors {
                guard let colorId = color.id else { continue }
                let junctionData = ItemColorJunction(
                    itemId: itemId.uuidString,
                    colorId: colorId.uuidString
                )
                try await supabaseService.supabaseClient.from("item_colors")
                    .upsert(junctionData, onConflict: "item_id,color_id")
                    .execute()
            }
            print("✅ Finished syncing \(colors.count) colors")
        } else {
            print("🎨 No colors in Core Data")
        }
        
        // Sync item_seasons with proper deletion handling
        print("🍂 Starting season sync for item: \(item.name ?? "unnamed") (ID: \(itemId.uuidString))")
        
        // STEP 1: Get what seasons SHOULD exist (from Core Data)
        let currentSeasonIds: Set<String>
        if let seasons = item.seasons as? Set<Season> {
            currentSeasonIds = Set(seasons.compactMap { $0.id?.uuidString })
            print("🍂 Core Data shows \(currentSeasonIds.count) seasons for this item")
        } else {
            currentSeasonIds = Set()
            print("🍂 Core Data shows 0 seasons for this item")
        }
        
        // STEP 2: Get what seasons currently exist in Supabase (BEFORE making any changes)
        let existingSeasonsResponse = try await supabaseService.supabaseClient.from("item_seasons")
            .select("season_id")
            .eq("item_id", value: itemId.uuidString)
            .execute()
        
        let seasonsData: Data = existingSeasonsResponse.data
        let existingSeasonIds: Set<String>
        if let existingSeasons = try? JSONDecoder().decode([ItemSeasonResponse].self, from: seasonsData) {
            existingSeasonIds = Set(existingSeasons.compactMap { $0.seasonId })
            print("🍂 Supabase shows \(existingSeasonIds.count) existing seasons")
        } else {
            existingSeasonIds = Set()
            print("🍂 Supabase shows 0 existing seasons (or failed to decode)")
        }
        
        // STEP 3: Delete seasons that no longer exist in Core Data
        let seasonsToDelete = existingSeasonIds.subtracting(currentSeasonIds)
        if !seasonsToDelete.isEmpty {
            print("🗑️ Deleting \(seasonsToDelete.count) orphaned seasons from Supabase")
            for seasonIdToDelete in seasonsToDelete {
                do {
                    try await supabaseService.supabaseClient.from("item_seasons")
                        .delete()
                        .eq("item_id", value: itemId.uuidString)
                        .eq("season_id", value: seasonIdToDelete)
                        .execute()
                    print("✅ Deleted season: \(seasonIdToDelete)")
                } catch {
                    print("⚠️ Failed to delete season \(seasonIdToDelete): \(error)")
                }
            }
        } else {
            print("🍂 No orphaned seasons to delete")
        }
        
        // STEP 4: Now sync current seasons (upsert new/existing)
        if let seasons = item.seasons as? Set<Season> {
            print("🍂 Upserting \(seasons.count) current seasons to Supabase")
            for season in seasons {
                guard let seasonId = season.id else { continue }
                let junctionData = ItemSeasonJunction(
                    itemId: itemId.uuidString,
                    seasonId: seasonId.uuidString
                )
                try await supabaseService.supabaseClient.from("item_seasons")
                    .upsert(junctionData, onConflict: "item_id,season_id")
                    .execute()
            }
            print("✅ Finished syncing \(seasons.count) seasons")
        } else {
            print("🍂 No seasons in Core Data")
        }
        
        // Sync item_tags with proper deletion handling
        print("🏷️ Starting tag sync for item: \(item.name ?? "unnamed") (ID: \(itemId.uuidString))")
        
        // STEP 1: Get what tags SHOULD exist (from Core Data)
        let currentTagIds: Set<String>
        if let tags = item.tags as? Set<Tag> {
            currentTagIds = Set(tags.compactMap { $0.id?.uuidString })
            print("🏷️ Core Data shows \(currentTagIds.count) tags for this item")
        } else {
            currentTagIds = Set()
            print("🏷️ Core Data shows 0 tags for this item")
        }
        
        // STEP 2: Get what tags currently exist in Supabase (BEFORE making any changes)
        let existingTagsResponse = try await supabaseService.supabaseClient.from("item_tags")
            .select("tag_id")
            .eq("item_id", value: itemId.uuidString)
            .execute()
        
        let tagsData: Data = existingTagsResponse.data
        let existingTagIds: Set<String>
        if let existingTags = try? JSONDecoder().decode([ItemTagResponse].self, from: tagsData) {
            existingTagIds = Set(existingTags.compactMap { $0.tagId })
            print("🏷️ Supabase shows \(existingTagIds.count) existing tags")
        } else {
            existingTagIds = Set()
            print("🏷️ Supabase shows 0 existing tags (or failed to decode)")
        }
        
        // STEP 3: Delete tags that no longer exist in Core Data
        let tagsToDelete = existingTagIds.subtracting(currentTagIds)
        if !tagsToDelete.isEmpty {
            print("🗑️ Deleting \(tagsToDelete.count) orphaned tags from Supabase")
            for tagIdToDelete in tagsToDelete {
                do {
                    try await supabaseService.supabaseClient.from("item_tags")
                        .delete()
                        .eq("item_id", value: itemId.uuidString)
                        .eq("tag_id", value: tagIdToDelete)
                        .execute()
                    print("✅ Deleted tag: \(tagIdToDelete)")
                } catch {
                    print("⚠️ Failed to delete tag \(tagIdToDelete): \(error)")
                }
            }
        } else {
            print("🏷️ No orphaned tags to delete")
        }
        
        // STEP 4: Now sync current tags (upsert new/existing)
        if let tags = item.tags as? Set<Tag> {
            print("🏷️ Upserting \(tags.count) current tags to Supabase")
            for tag in tags {
                guard let tagId = tag.id else { continue }
                let junctionData = ItemTagJunction(
                    itemId: itemId.uuidString,
                    tagId: tagId.uuidString
                )
                try await supabaseService.supabaseClient.from("item_tags")
                    .upsert(junctionData, onConflict: "item_id,tag_id")
                    .execute()
            }
            print("✅ Finished syncing \(tags.count) tags")
        } else {
            print("🏷️ No tags in Core Data")
        }
        
        // Sync item_wardrobes with proper deletion handling
        print("👔 Starting wardrobe sync for item: \(item.name ?? "unnamed") (ID: \(itemId.uuidString))")
        
        // STEP 1: Get what wardrobes SHOULD exist (from Core Data)
        let currentWardrobeIds: Set<String>
        if let wardrobes = item.wardrobes as? Set<Wardrobe> {
            currentWardrobeIds = Set(wardrobes.compactMap { $0.id?.uuidString })
            print("👔 Core Data shows \(currentWardrobeIds.count) wardrobes for this item")
        } else {
            currentWardrobeIds = Set()
            print("👔 Core Data shows 0 wardrobes for this item")
        }
        
        // STEP 2: Get what wardrobes currently exist in Supabase (BEFORE making any changes)
        let existingWardrobesResponse = try await supabaseService.supabaseClient.from("item_wardrobes")
            .select("wardrobe_id")
            .eq("item_id", value: itemId.uuidString)
            .execute()
        
        let wardrobesData: Data = existingWardrobesResponse.data
        let existingWardrobeIds: Set<String>
        if let existingWardrobes = try? JSONDecoder().decode([ItemWardrobeResponse].self, from: wardrobesData) {
            existingWardrobeIds = Set(existingWardrobes.compactMap { $0.wardrobeId })
            print("👔 Supabase shows \(existingWardrobeIds.count) existing wardrobes")
        } else {
            existingWardrobeIds = Set()
            print("👔 Supabase shows 0 existing wardrobes (or failed to decode)")
        }
        
        // STEP 3: Delete wardrobes that no longer exist in Core Data
        let wardrobesToDelete = existingWardrobeIds.subtracting(currentWardrobeIds)
        if !wardrobesToDelete.isEmpty {
            print("🗑️ Deleting \(wardrobesToDelete.count) orphaned wardrobes from Supabase")
            for wardrobeIdToDelete in wardrobesToDelete {
                do {
                    try await supabaseService.supabaseClient.from("item_wardrobes")
                        .delete()
                        .eq("item_id", value: itemId.uuidString)
                        .eq("wardrobe_id", value: wardrobeIdToDelete)
                        .execute()
                    print("✅ Deleted wardrobe: \(wardrobeIdToDelete)")
                } catch {
                    print("⚠️ Failed to delete wardrobe \(wardrobeIdToDelete): \(error)")
                }
            }
        } else {
            print("👔 No orphaned wardrobes to delete")
        }
        
        // STEP 4: Now sync current wardrobes (upsert new/existing)
        if let wardrobes = item.wardrobes as? Set<Wardrobe> {
            print("👔 Upserting \(wardrobes.count) current wardrobes to Supabase")
            for wardrobe in wardrobes {
                guard let wardrobeId = wardrobe.id else { continue }
                let junctionData = ItemWardrobeJunction(
                    itemId: itemId.uuidString,
                    wardrobeId: wardrobeId.uuidString
                )
                try await supabaseService.supabaseClient.from("item_wardrobes")
                    .upsert(junctionData, onConflict: "item_id,wardrobe_id")
                    .execute()
            }
            print("✅ Finished syncing \(wardrobes.count) wardrobes")
        } else {
            print("👔 No wardrobes in Core Data")
        }
        
        // Sync item_pairs with proper deletion handling
        // Note: Pairs are bidirectional in Core Data, but we store them bidirectionally in Supabase
        // to make queries easier. We sync both directions: (item_id, paired_item_id) and (paired_item_id, item_id)
        print("🔗 Starting pair sync for item: \(item.name ?? "unnamed") (ID: \(itemId.uuidString))")
        
        // STEP 1: Get what pairs SHOULD exist (from Core Data)
        let currentPairedItemIds: Set<String>
        if let pairedItems = item.pairedItems as? Set<Item> {
            currentPairedItemIds = Set(pairedItems.compactMap { $0.id?.uuidString })
            print("🔗 Core Data shows \(currentPairedItemIds.count) pairs for this item")
            for (idx, pairedId) in currentPairedItemIds.enumerated() {
                print("   Pair #\(idx + 1): \(pairedId)")
            }
        } else {
            currentPairedItemIds = Set()
            print("🔗 Core Data shows 0 pairs for this item")
        }
        
        // STEP 2: Get what pairs currently exist in Supabase (BEFORE making any changes)
        let existingPairsResponse = try await supabaseService.supabaseClient.from("item_pairs")
            .select("paired_item_id")
            .eq("item_id", value: itemId.uuidString)
            .execute()
        
        let data: Data = existingPairsResponse.data
        let existingPairedItemIds: Set<String>
        if let existingPairs = try? JSONDecoder().decode([ItemPairResponse].self, from: data) {
            existingPairedItemIds = Set(existingPairs.compactMap { $0.pairedItemId })
            print("🔗 Supabase shows \(existingPairedItemIds.count) existing pairs")
            for (idx, pairedId) in existingPairedItemIds.enumerated() {
                print("   Existing pair #\(idx + 1): \(pairedId)")
            }
        } else {
            existingPairedItemIds = Set()
            print("🔗 Supabase shows 0 existing pairs (or failed to decode)")
        }
        
        // STEP 3: Delete pairs that no longer exist in Core Data
        let pairsToDelete = existingPairedItemIds.subtracting(currentPairedItemIds)
        if !pairsToDelete.isEmpty {
            print("🗑️ Deleting \(pairsToDelete.count) orphaned pairs from Supabase")
            for pairedItemIdToDelete in pairsToDelete {
                print("🗑️ Deleting pair: \(itemId.uuidString) <-> \(pairedItemIdToDelete)")
                
                // Delete direction 1: item -> pairedItem
                do {
                    try await supabaseService.supabaseClient.from("item_pairs")
                        .delete()
                        .eq("item_id", value: itemId.uuidString)
                        .eq("paired_item_id", value: pairedItemIdToDelete)
                        .execute()
                    print("✅ Deleted: \(itemId.uuidString) -> \(pairedItemIdToDelete)")
                } catch {
                    print("⚠️ Failed to delete pair \(itemId.uuidString) -> \(pairedItemIdToDelete): \(error)")
                }
                
                // Delete direction 2: pairedItem -> item
                do {
                    try await supabaseService.supabaseClient.from("item_pairs")
                        .delete()
                        .eq("item_id", value: pairedItemIdToDelete)
                        .eq("paired_item_id", value: itemId.uuidString)
                        .execute()
                    print("✅ Deleted: \(pairedItemIdToDelete) -> \(itemId.uuidString)")
                } catch {
                    print("⚠️ Failed to delete pair \(pairedItemIdToDelete) -> \(itemId.uuidString): \(error)")
                }
            }
        } else {
            print("🔗 No orphaned pairs to delete")
        }
        
        // STEP 4: Now sync current pairs (upsert new/existing)
        if !currentPairedItemIds.isEmpty {
            print("🔗 Upserting \(currentPairedItemIds.count) current pairs to Supabase")
            let pairedItemArray = Array(currentPairedItemIds)
            
            for (index, pairedItemId) in pairedItemArray.enumerated() {
                print("🔗 Processing pair #\(index + 1): \(itemId.uuidString) <-> \(pairedItemId)")
                
                // Sync both directions
                // Direction 1: item -> pairedItem
                let junctionData1 = ItemPairJunction(
                    itemId: itemId.uuidString,
                    pairedItemId: pairedItemId
                )
                do {
                    try await supabaseService.supabaseClient.from("item_pairs")
                        .upsert(junctionData1, onConflict: "item_id,paired_item_id")
                        .execute()
                    print("✅ Upserted: \(itemId.uuidString) -> \(pairedItemId)")
                } catch {
                    print("❌ Failed to upsert pair \(itemId.uuidString) -> \(pairedItemId): \(error)")
                    print("❌ Error: \(error.localizedDescription)")
                }
                
                // Direction 2: pairedItem -> item (bidirectional)
                let junctionData2 = ItemPairJunction(
                    itemId: pairedItemId,
                    pairedItemId: itemId.uuidString
                )
                do {
                    try await supabaseService.supabaseClient.from("item_pairs")
                        .upsert(junctionData2, onConflict: "item_id,paired_item_id")
                        .execute()
                    print("✅ Upserted: \(pairedItemId) -> \(itemId.uuidString)")
                } catch {
                    print("❌ Failed to upsert pair \(pairedItemId) -> \(itemId.uuidString): \(error)")
                    print("❌ Error: \(error.localizedDescription)")
                }
            }
            
            print("✅ Finished syncing \(currentPairedItemIds.count) pairs")
        } else {
            // No paired items in Core Data
            print("🔗 No paired items in Core Data")
            
            // Delete all pairs for this item if any exist in Supabase
            if !existingPairedItemIds.isEmpty {
                print("🗑️ Deleting all \(existingPairedItemIds.count) pairs from Supabase")
                do {
                    try await supabaseService.supabaseClient.from("item_pairs")
                        .delete()
                        .eq("item_id", value: itemId.uuidString)
                        .execute()
                    
                    try await supabaseService.supabaseClient.from("item_pairs")
                        .delete()
                        .eq("paired_item_id", value: itemId.uuidString)
                        .execute()
                    print("✅ Deleted all pairs for item")
                } catch {
                    print("⚠️ Failed to delete all pairs: \(error)")
                }
            }
        }
    }
    
    /// Syncs item price
    private func syncPrice(_ price: Price, itemId: UUID, userId: UUID) async throws {
        // item_id is the primary key — one price per item
        let amount: Decimal
        if let nsDecimal = price.amount {
            amount = nsDecimal as Decimal
        } else {
            amount = 0.0
        }
        
        let priceData = SyncPriceData(
            itemId: itemId.uuidString,
            amount: amount,
            currency: price.currency ?? "USD"
        )
        
        try await supabaseService.supabaseClient.from("item_prices")
            .upsert(priceData, onConflict: "item_id")
            .execute()
    }
    
    /// Syncs item links with proper deletion handling
    private func syncItemLinks(_ item: Item, itemId: UUID, userId: UUID) async throws {
        print("🔗 Starting link sync for item: \(item.name ?? "unnamed") (ID: \(itemId.uuidString))")
        
        // STEP 1: Get what links SHOULD exist (from Core Data)
        let currentLinkIds: Set<String>
        if let links = item.links as? Set<Link> {
            currentLinkIds = Set(links.compactMap { $0.id?.uuidString })
            print("🔗 Core Data shows \(currentLinkIds.count) links for this item")
        } else {
            currentLinkIds = Set()
            print("🔗 Core Data shows 0 links for this item")
        }
        
        // STEP 2: Get what links currently exist in Supabase (BEFORE making any changes)
        let existingLinksResponse = try await supabaseService.supabaseClient.from("item_links")
            .select("id")
            .eq("item_id", value: itemId.uuidString)
            .execute()
        
        let data: Data = existingLinksResponse.data
        let existingLinkIds: Set<String>
        if let existingLinks = try? JSONDecoder().decode([ItemLinkResponse].self, from: data) {
            existingLinkIds = Set(existingLinks.compactMap { $0.id })
            print("🔗 Supabase shows \(existingLinkIds.count) existing links")
        } else {
            existingLinkIds = Set()
            print("🔗 Supabase shows 0 existing links (or failed to decode)")
        }
        
        // STEP 3: Delete links that no longer exist in Core Data
        let linksToDelete = existingLinkIds.subtracting(currentLinkIds)
        if !linksToDelete.isEmpty {
            print("🗑️ Deleting \(linksToDelete.count) orphaned links from Supabase")
            for linkIdToDelete in linksToDelete {
                do {
                    try await supabaseService.supabaseClient.from("item_links")
                        .delete()
                        .eq("id", value: linkIdToDelete)
                        .execute()
                    print("✅ Deleted link: \(linkIdToDelete)")
                } catch {
                    print("⚠️ Failed to delete link \(linkIdToDelete): \(error)")
                }
            }
        } else {
            print("🔗 No orphaned links to delete")
        }
        
        // STEP 4: Now sync current links (upsert new/existing)
        if let links = item.links as? Set<Link> {
            print("🔗 Upserting \(links.count) current links to Supabase")
            for link in links {
                try await syncLink(link, itemId: itemId, userId: userId)
            }
            print("✅ Finished syncing \(links.count) links")
        } else {
            print("🔗 No links in Core Data")
        }
    }
    
    private func syncLink(_ link: Link, itemId: UUID, userId: UUID) async throws {
        guard let linkId = link.id else { return }
        
        let linkData = SyncLinkData(
            id: linkId.uuidString,
            itemId: itemId.uuidString,
          //  userId: userId.uuidString,
            name: link.name,
            url: link.url?.absoluteString
        )
        
        try await supabaseService.supabaseClient.from("item_links")
            .upsert(linkData, onConflict: "id")
            .execute()
    }
}

// MARK: - Sync Errors

enum SyncError: LocalizedError {
    case notAuthenticated
    case noContext
    case uploadFailed
    case networkError
    /// Raw `photo.data` could not be decoded and exceeded the worker size limit.
    case photoExceedsWorkerLimit
    /// Could not re-encode image bytes for R2 upload.
    case photoEncodingFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .noContext:
            return "Core Data context not set"
        case .uploadFailed:
            return "Failed to upload photo"
        case .networkError:
            return "Network error during sync"
        case .photoExceedsWorkerLimit:
            return "Photo file is too large for upload and could not be compressed"
        case .photoEncodingFailed:
            return "Failed to compress photo for upload"
        }
    }
}

// MARK: - Codable Structs for Sync

/// Codable struct for syncing item data
private struct SyncItemData: Codable {
    let id: String
    let userId: String
    let name: String
    let notes: String?
    let isFavorite: Bool
    // isWishlist removed - replaced by item_wardrobes junction table
    let isDraft: Bool
    let minTemperature: Double?
    let maxTemperature: Double?
    let temperatureUnit: String?
    let weight: Double?
    let weightUnit: String?
    let isSoftDeleted: Bool
    let createdAt: String?
    let updatedAt: String?
    let brandId: String?
    let categoryId: String?
    let subcategoryId: String?
    let sizeId: String?
    let locationId: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case notes
        case isFavorite = "is_favorite"
        // isWishlist removed - replaced by item_wardrobes junction table
        case isDraft = "is_draft"
        case minTemperature = "min_temperature"
        case maxTemperature = "max_temperature"
        case temperatureUnit = "temperature_unit"
        case weight
        case weightUnit = "weight_unit"
        case isSoftDeleted = "is_soft_deleted"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case brandId = "brand_id"
        case categoryId = "category_id"
        case subcategoryId = "subcategory_id"
        case sizeId = "size_id"
        case locationId = "location_id"
    }
}

/// Codable struct for syncing photo data
private struct SyncPhotoData: Codable {
    let id: String
    let itemId: String
    let userId: String
    let imageUrl: String?
    let isPrimary: Bool
    let type: String?
    let createdAt: String?
    let thumbnailUrl: String?
    let timestamp: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case itemId = "item_id"
        case userId = "user_id"
        case imageUrl = "image_url"
        case isPrimary = "is_primary"
        case type
        case createdAt = "created_at"
        case thumbnailUrl = "thumbnail_url"
        case timestamp
        case updatedAt = "updated_at"
    }
}

/// Codable structs for junction tables
private struct ItemColorJunction: Codable {
    let itemId: String
    let colorId: String
 //   let userId: String
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case colorId = "color_id"
      //  case userId = "user_id"
    }
}

private struct ItemSeasonJunction: Codable {
    let itemId: String
    let seasonId: String
  //  let userId: String
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case seasonId = "season_id"
      //  case userId = "user_id"
    }
}

private struct ItemTagJunction: Codable {
    let itemId: String
    let tagId: String
  //  let userId: String
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case tagId = "tag_id"
      //  case userId = "user_id"
    }
}

private struct ItemWardrobeJunction: Codable {
    let itemId: String
    let wardrobeId: String
  //  let userId: String
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case wardrobeId = "wardrobe_id"
      //  case userId = "user_id"
    }
}

private struct ItemPairJunction: Codable {
    let itemId: String
    let pairedItemId: String
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case pairedItemId = "paired_item_id"
    }
}

private struct ItemPairResponse: Codable {
    let pairedItemId: String
    
    enum CodingKeys: String, CodingKey {
        case pairedItemId = "paired_item_id"
    }
}

private struct ItemLinkResponse: Codable {
    let id: String
    
    enum CodingKeys: String, CodingKey {
        case id
    }
}

private struct ItemPhotoResponse: Codable {
    let id: String
    
    enum CodingKeys: String, CodingKey {
        case id
    }
}

private struct ItemColorResponse: Codable {
    let colorId: String
    
    enum CodingKeys: String, CodingKey {
        case colorId = "color_id"
    }
}

private struct ItemSeasonResponse: Codable {
    let seasonId: String
    
    enum CodingKeys: String, CodingKey {
        case seasonId = "season_id"
    }
}

private struct ItemTagResponse: Codable {
    let tagId: String
    
    enum CodingKeys: String, CodingKey {
        case tagId = "tag_id"
    }
}

private struct ItemWardrobeResponse: Codable {
    let wardrobeId: String
    
    enum CodingKeys: String, CodingKey {
        case wardrobeId = "wardrobe_id"
    }
}

private struct SyncPriceData: Codable {
    let itemId: String      // Primary key — one price per item
    let amount: Decimal
    let currency: String
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case amount
        case currency
    }
}

private struct SyncLinkData: Codable {
    let id: String
    let itemId: String
  //  let userId: String
    let name: String?
    let url: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case itemId = "item_id"
       // case userId = "user_id"
        case name
        case url
    }
}

// MARK: - Reference Data Codable Structs

private struct SyncBrandData: Codable {
    let id: String
    let userId: String
    let name: String
    let isVisible: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case isVisible = "is_visible"
    }
}

private struct SyncCategoryData: Codable {
    let id: String
    let userId: String
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
    }
}

private struct SyncSubcategoryData: Codable {
    let id: String
    let categoryId: String
    let userId: String
    let name: String
    let sortOrder: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case categoryId = "category_id"
        case userId = "user_id"
        case name
        case sortOrder = "sort_order"
    }
}

private struct SyncColorData: Codable {
    let id: String
    let userId: String
    let name: String
    let hexCode: String?
    let isVisible: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case hexCode = "hex_code"
        case isVisible = "is_visible"
    }
}

private struct SyncSeasonData: Codable {
    let id: String
    let userId: String
    let name: String
    let isVisible: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case isVisible = "is_visible"
    }
}

private struct SyncSizeData: Codable {
    let id: String
    let categoryId: String? // Optional - sizes are now independent of categories
    let userId: String
    let value: String
    let scale: String?
    let sortOrder: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case categoryId = "category_id"
        case userId = "user_id"
        case value
        case scale
        case sortOrder = "sort_order"
    }
}

private struct SyncTagData: Codable {
    let id: String
    let userId: String
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
    }
}

private struct SyncPackingChecklistSectionData: Codable {
    let id: String
    let userId: String
    let wardrobeId: String
    let kind: Int
    let title: String
    let sortIndex: Int
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case wardrobeId = "wardrobe_id"
        case kind
        case title
        case sortIndex = "sort_index"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct SyncPackingChecklistItemData: Codable {
    let id: String
    let userId: String
    let wardrobeId: String
    let sectionId: String?
    let kind: Int
    let checklistText: String
    let isCompleted: Bool
    let sortIndex: Int
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case wardrobeId = "wardrobe_id"
        case sectionId = "section_id"
        case kind
        case checklistText = "checklist_text"
        case isCompleted = "is_completed"
        case sortIndex = "sort_index"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct SyncLocationData: Codable {
    let id: String
    let userId: String
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
    }
}

private struct SyncWardrobeData: Codable {
    let id: String
    let userId: String
    let name: String
    let type: String?
    let isSoftDeleted: Bool
    let isDefault: Bool
    let packingChecklistSectionTitle: String
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case type
        case isSoftDeleted = "is_soft_deleted"
        case isDefault = "is_default"
        case packingChecklistSectionTitle = "packing_checklist_section_title"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct SyncOutfitData: Codable {
    let id: String
    let userId: String
    let name: String?
    let notes: String?
    let isFavorite: Bool
    let isDraft: Bool
    let isSoftDeleted: Bool
    let category: String?
    let createdAt: String?
    let updatedAt: String?
    let imageUrl: String?          // R2 CDN URL of the pre-rendered collage
    let wornImageUrl: String?      // R2 CDN URL of the "worn" photo
    let transformationJson: String? // JSON string of [SavedOutfitItem] with portable UUIDs

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case notes
        case isFavorite = "is_favorite"
        case isDraft = "is_draft"
        case isSoftDeleted = "is_soft_deleted"
        case category
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case imageUrl = "image_url"
        case wornImageUrl = "worn_image_url"
        case transformationJson = "transformation_json"
    }
}

private struct OutfitItemJunction: Codable {
    let outfitId: String
    let itemId: String

    enum CodingKeys: String, CodingKey {
        case outfitId = "outfit_id"
        case itemId = "item_id"
    }
}

private struct OutfitTagJunction: Codable {
    let outfitId: String
    let tagId: String

    enum CodingKeys: String, CodingKey {
        case outfitId = "outfit_id"
        case tagId = "tag_id"
    }
}

private struct OutfitItemResponse: Codable {
    let itemId: String

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
    }
}

private struct OutfitTagResponse: Codable {
    let tagId: String

    enum CodingKeys: String, CodingKey {
        case tagId = "tag_id"
    }
}

private struct SyncUserProfileData: Codable {
    let userId: String
    let weightKg: Double?
    let weightUnit: String?
    let username: String?
    let displayName: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case weightKg = "weight_kg"
        case weightUnit = "weight_unit"
        case username
        case displayName = "display_name"
        case updatedAt = "updated_at"
    }
}


// MARK: - Date Extension

extension Date {
    var ISO8601String: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}

