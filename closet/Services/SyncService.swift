//
//  SyncService.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import Foundation
import CoreData
import Supabase

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
    
    /// Migrates existing local items and reference data to the authenticated user
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
        
        let collectionRequest: NSFetchRequest<Collection> = Collection.fetchRequest()
        collectionRequest.predicate = NSPredicate(format: "userId == nil OR userId == ''")
        let collections = try context.fetch(collectionRequest)
        for collection in collections {
            if collection.id == nil {
                collection.id = UUID()
            }
            collection.userId = userId.uuidString
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
    
    /// Syncs a single item to Supabase (for automatic sync after save)
    /// This is called automatically when items are created or modified
    /// Marked as nonisolated so it can be called from any context
    nonisolated func syncItemIfNeeded(_ item: Item) {
        // Only sync if authenticated - check on main actor
        Task { @MainActor in
            guard self.supabaseService.isAuthenticated,
                  let userId = self.supabaseService.currentUser?.id,
                  let itemId = item.id,
                  let context = self.context else {
                return
            }
            
            // Refresh item from context to ensure we have latest values
            context.refresh(item, mergeChanges: false)
            
            // Ensure pairedItems relationship is loaded (not a fault)
            if let pairedItems = item.pairedItems as? Set<Item> {
                print("🔍 Item '\(item.name ?? "unnamed")' has \(pairedItems.count) paired items in Core Data")
                for (idx, paired) in Array(pairedItems).enumerated() {
                    print("   Pair #\(idx + 1): \(paired.name ?? "unnamed") (ID: \(paired.id?.uuidString ?? "no ID"))")
                }
            } else {
                print("🔍 Item '\(item.name ?? "unnamed")' has no paired items")
            }
            
            // CRITICAL: Set userId on item if it's not set (for new items)
            // This ensures the item can be found by future sync queries
            if item.userId == nil || item.userId?.isEmpty == true {
                item.userId = userId.uuidString
                do {
                    try context.save()
                    print("✅ Set userId on new item: \(item.name ?? "unnamed")")
                } catch {
                    print("⚠️ Failed to set userId on item: \(error.localizedDescription)")
                    // Continue anyway - we'll try to sync
                }
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
        try await migrateLocalItemsToUser(userId: userId)
        
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
        
        // Sync collections - only if changed (collections already have updatedAt)
        let collectionRequest: NSFetchRequest<Collection> = Collection.fetchRequest()
        collectionRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let collections = try context.fetch(collectionRequest)
        for collection in collections {
            try await syncCollection(collection, userId: userId)
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
        request.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
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
    
    /// Syncs a collection to Supabase
    private func syncCollection(_ collection: Collection, userId: UUID) async throws {
        guard let context = context else { throw SyncError.noContext }
        guard let collectionId = collection.id else { return }
        
        let collectionData = SyncCollectionData(
            id: collectionId.uuidString,
            userId: userId.uuidString,
            name: collection.name ?? "",
            type: collection.type,
            createdAt: collection.createdAt?.ISO8601String ?? collection.timestamp?.ISO8601String
        )
        
        try await supabaseService.supabaseClient.from("collections")
            .upsert(collectionData, onConflict: "id")
            .execute()
        
        // Mark as synced
        collection.syncedAt = Date()
        try context.save()
    }
    
    /// Syncs a wardrobe to Supabase
    private func syncWardrobe(_ wardrobe: Wardrobe, userId: UUID) async throws {
        guard let wardrobeId = wardrobe.id else { return }
        
        let wardrobeData = SyncWardrobeData(
            id: wardrobeId.uuidString,
            userId: userId.uuidString,
            name: wardrobe.name ?? "",
            type: wardrobe.type,
            isSoftDeleted: wardrobe.isSoftDeleted,
            createdAt: wardrobe.createdAt?.ISO8601String ?? wardrobe.timestamp?.ISO8601String,
            updatedAt: wardrobe.updatedAt?.ISO8601String
        )
        
        try await supabaseService.supabaseClient.from("wardrobes")
            .upsert(wardrobeData, onConflict: "id")
            .execute()
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
        
        // Prepare item data using Codable struct
        // Sizes are now independent of categories, so we can always include size_id
        let itemData = SyncItemData(
            id: itemId.uuidString,
            userId: userId.uuidString,
            name: item.name ?? "",
            notes: item.notes,
            isFavorite: item.isFavorite,
            isWishlist: item.isWishlist,
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
        
        // Sync photos
        if let photos = item.photos as? Set<Photo> {
            for photo in photos {
                try await syncPhoto(photo, itemId: itemId, userId: userId)
            }
        }
        
        // Sync relationships (colors, seasons, tags, etc.)
        try await syncItemRelationships(item, userId: userId)
        
        // Sync price if exists
        if let price = item.price {
            try await syncPrice(price, itemId: itemId, userId: userId)
        }
        
        // Sync links if exist
        if let links = item.links as? Set<Link> {
            for link in links {
                try await syncLink(link, itemId: itemId, userId: userId)
            }
        }
        
        // Mark as synced
        item.syncedAt = Date()
        try context.save()
        
        print("✅ Synced item: \(item.name ?? "unnamed")")
    }
    
    /// Syncs a photo to Cloudflare R2 via Worker and stores URL
    /// Each photo (front, back, worn) has a unique photoId, ensuring they don't conflict
    /// Uploads both full image and thumbnail to R2 for storage efficiency
    private func syncPhoto(_ photo: Photo, itemId: UUID, userId: UUID) async throws {
        guard let context = context else {
            throw SyncError.noContext
        }
        
        guard let photoId = photo.id else {
            print("⚠️ Photo missing ID, skipping sync")
            return
        }
        
        // Check if photo already has URLs - if so, skip upload unless we have new data to upload
        let hasExistingUrls = (photo.imageUrl != nil && !photo.imageUrl!.isEmpty) && 
                              (photo.thumbnailUrl != nil && !photo.thumbnailUrl!.isEmpty)
        let hasNewData = (photo.data != nil && !photo.data!.isEmpty) || 
                         (photo.thumbnailData != nil && !photo.thumbnailData!.isEmpty)
        
        // If URLs exist and no new data, just update metadata and skip upload
        if hasExistingUrls && !hasNewData {
            try await updatePhotoMetadata(photo, itemId: itemId, userId: userId)
            return
        }
        
        var imageUrl: String? = nil
        var thumbnailUrl: String? = nil
        
        // Upload full image to Cloudflare R2 via Worker if we have data
        // Only upload if we have new data (don't re-upload if URLs already exist and no new data)
        if let imageData = photo.data, !imageData.isEmpty {
            imageUrl = try await supabaseService.uploadPhoto(
                imageData: imageData,
                itemId: itemId,
                photoId: photoId,
                userId: userId
            )
            
            // Store URL in Core Data and save immediately
            photo.imageUrl = imageUrl
            try context.save()
            print("✅ Saved image URL to Core Data: \(imageUrl ?? "nil")")
        } else if hasExistingUrls {
            // Use existing URL if we have one
            imageUrl = photo.imageUrl
        }
        
        // Upload thumbnail to R2 if we have thumbnail data
        // Only upload if we have new data (don't re-upload if URLs already exist and no new data)
        if let thumbnailData = photo.thumbnailData, !thumbnailData.isEmpty {
            thumbnailUrl = try await supabaseService.uploadThumbnail(
                imageData: thumbnailData,
                itemId: itemId,
                photoId: photoId,
                userId: userId
            )
            
            // Store thumbnail URL in Core Data and save immediately
            photo.thumbnailUrl = thumbnailUrl
            try context.save()
            print("✅ Saved thumbnail URL to Core Data: \(thumbnailUrl ?? "nil")")
        } else if hasExistingUrls {
            // Use existing thumbnail URL if we have one
            thumbnailUrl = photo.thumbnailUrl
        }
        
        // Update photo metadata in database (stores URLs, not base64)
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
    
    /// Syncs item relationships (colors, seasons, tags, collections)
    private func syncItemRelationships(_ item: Item, userId: UUID) async throws {
        guard let itemId = item.id else { return }
        
        // Sync item_colors
        if let colors = item.colors as? Set<AppColor> {
            for color in colors {
                guard let colorId = color.id else { continue }
                let junctionData = ItemColorJunction(
                    itemId: itemId.uuidString,
                    colorId: colorId.uuidString,
                  //  userId: userId.uuidString
                )
                try await supabaseService.supabaseClient.from("item_colors")
                    .upsert(junctionData, onConflict: "item_id,color_id")
                    .execute()
            }
        }
        
        // Sync item_seasons
        if let seasons = item.seasons as? Set<Season> {
            for season in seasons {
                guard let seasonId = season.id else { continue }
                let junctionData = ItemSeasonJunction(
                    itemId: itemId.uuidString,
                    seasonId: seasonId.uuidString,
                  //  userId: userId.uuidString
                )
                try await supabaseService.supabaseClient.from("item_seasons")
                    .upsert(junctionData, onConflict: "item_id,season_id")
                    .execute()
            }
        }
        
        // Sync item_tags
        if let tags = item.tags as? Set<Tag> {
            for tag in tags {
                guard let tagId = tag.id else { continue }
                let junctionData = ItemTagJunction(
                    itemId: itemId.uuidString,
                    tagId: tagId.uuidString,
                  //  userId: userId.uuidString
                )
                try await supabaseService.supabaseClient.from("item_tags")
                    .upsert(junctionData, onConflict: "item_id,tag_id")
                    .execute()
            }
        }
        
        // Sync item_collections
        if let collections = item.collections as? Set<Collection> {
            for collection in collections {
                guard let collectionId = collection.id else { continue }
                let junctionData = ItemCollectionJunction(
                    itemId: itemId.uuidString,
                    collectionId: collectionId.uuidString,
                  //  userId: userId.uuidString
                )
                try await supabaseService.supabaseClient.from("item_collections")
                    .upsert(junctionData, onConflict: "item_id,collection_id")
                    .execute()
            }
        }
        
        // Sync item_wardrobes
        if let wardrobes = item.wardrobes as? Set<Wardrobe> {
            for wardrobe in wardrobes {
                guard let wardrobeId = wardrobe.id else { continue }
                let junctionData = ItemWardrobeJunction(
                    itemId: itemId.uuidString,
                    wardrobeId: wardrobeId.uuidString,
                  //  userId: userId.uuidString
                )
                try await supabaseService.supabaseClient.from("item_wardrobes")
                    .upsert(junctionData, onConflict: "item_id,wardrobe_id")
                    .execute()
            }
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
        // Price entity doesn't have an id, so we use item_id as the unique key
        let priceId = UUID() // Generate a new ID for this price record
        
        // Convert NSDecimalNumber to Decimal
        let amount: Decimal
        if let nsDecimal = price.amount {
            amount = nsDecimal as Decimal
        } else {
            amount = 0.0
        }
        
        let priceData = SyncPriceData(
            id: priceId.uuidString,
            itemId: itemId.uuidString,
           // userId: userId.uuidString,
            amount: amount,
            currency: price.currency ?? "USD"
        )
        
        try await supabaseService.supabaseClient.from("item_prices")
            .upsert(priceData, onConflict: "item_id")
            .execute()
    }
    
    /// Syncs item link
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
    let isWishlist: Bool
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
        case isWishlist = "is_wishlist"
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

private struct ItemCollectionJunction: Codable {
    let itemId: String
    let collectionId: String
  //  let userId: String
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case collectionId = "collection_id"
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

private struct SyncPriceData: Codable {
    let id: String
    let itemId: String
   // let userId: String
    let amount: Decimal
    let currency: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case itemId = "item_id"
      //  case userId = "user_id"
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

private struct SyncCollectionData: Codable {
    let id: String
    let userId: String
    let name: String
    let type: String?
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case type
        case createdAt = "created_at"
    }
}

private struct SyncWardrobeData: Codable {
    let id: String
    let userId: String
    let name: String
    let type: String?
    let isSoftDeleted: Bool
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case type
        case isSoftDeleted = "is_soft_deleted"
        case createdAt = "created_at"
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

