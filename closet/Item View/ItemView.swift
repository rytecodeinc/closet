//
//  ItemView.swift
//  closet
//
//  Created by Dan Warner on 7/15/25.
//

import SwiftUI
import CoreData
import SQLite3

struct ItemView: View {
    @ObservedObject var item: Item
    @State private var isActive: Bool = false
    @Environment(\.managedObjectContext) private var viewContext

    var displayImage: UIImage? {
        // For grid views, prefer thumbnail for performance
        if let primaryPhoto = item.photos?.first(where: { ($0 as? Photo)?.isPrimary == true }) as? Photo {
            // Use thumbnail if available, fallback to full image
            if let thumbnailData = primaryPhoto.thumbnailData, !thumbnailData.isEmpty {
                return UIImage(data: thumbnailData)
            } else if let fullData = primaryPhoto.data {
                return UIImage(data: fullData)
            }
        } else if let fallbackImage = item.image {
            return UIImage(data: fallbackImage)
        }
        return nil
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let itemImage = displayImage {
                Image(uiImage: itemImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(minWidth: 120, minHeight: 120)
                    .clipped()
                  //  .border(.gray.opacity(0.3), width: 0.5)
                  //  .background(Color(red: 247/255, green: 247/255, blue: 247/255))  
                    .overlay(alignment: .bottomLeading) {
                        if item.isFavorite {
                            // Black gradient overlay fading from bottom-left corner
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.black.opacity(0.85),
                                    Color.black.opacity(0.65),
                                    Color.black.opacity(0.55),
                                    Color.gray.opacity(0.55),
                                    Color.clear
                                ]),
                                center: UnitPoint(x: -0.2, y: 1.5),
                                startRadius: 0,
                                endRadius: 100
                            )
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if item.isFavorite {
                            // White heart icon on top of gradient
                            Image(systemName: "heart.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 12))
                                .padding(.leading, 6)
                                .padding(.bottom, 6)
                        }
                    }
                   /* .background(LinearGradient(colors: [.white, .gray.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomLeading))*/
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(minWidth: 120, minHeight: 120)
                    .clipped()
                    .foregroundColor(.gray)
                   /* .background(LinearGradient(colors: [.white, .gray.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomLeading))*/
            }
        }
        
    }

    private func deleteItem() {
        // Store the brand before deletion to check if cleanup is needed
        let itemBrand = item.brand
        
        // Soft delete the item (for sync)
        softDelete(item)
        
        do {
            try viewContext.save()
            
            // Trigger sync for the soft-deleted item
            SyncService.shared.syncItemIfNeeded(item)
            
            // Cleanup brand if it's now orphaned (has 0 items)
            if let brand = itemBrand {
                cleanupBrandIfOrphaned(brand)
            }
        } catch {
            print("Failed to delete item: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Cleanup Orphaned Brand
    private func cleanupBrandIfOrphaned(_ brand: Brand) {
        // Refresh the brand to get current item count
        viewContext.refresh(brand, mergeChanges: true)
        
        // Check if brand has any items
        if let items = brand.items as? Set<Item>, items.isEmpty {
            viewContext.delete(brand)
            do {
                try viewContext.save()
                print("✅ Cleaned up orphaned brand: \(brand.name ?? "unknown")")
            } catch {
                print("❌ Failed to cleanup orphaned brand: \(error)")
            }
        }
    }
}

func migrateItemImages(context: NSManagedObjectContext) {
    // Check if migration has already been completed
    let migrationKey = "hasMigratedItemImages"
    if UserDefaults.standard.bool(forKey: migrationKey) {
        return
    }
    
    let fetchRequest: NSFetchRequest<Item> = Item.fetchRequest()

    do {
        let items = try context.fetch(fetchRequest)
        var hasChanges = false
        
        for item in items {
            if let existingImageData = item.image {
                let newImage = Photo(context: context)
                newImage.data = existingImageData
                newImage.type = "default"
                newImage.isPrimary = true
                newImage.item = item

                // Remove the old attribute's value
                item.image = nil
                hasChanges = true
            }
        }
        
        if hasChanges {
            try context.save()
            print("✅ Item images migration successful!")
        }
        
        // Mark migration as completed
        UserDefaults.standard.set(true, forKey: migrationKey)

    } catch {
        print("❌ Item images migration failed: \(error)")
    }
}

// MARK: - Compress Existing Photos
func compressExistingPhotos(context: NSManagedObjectContext) {
    // Check if compression has already been completed
    let migrationKey = "hasCompressedExistingPhotos"
    if UserDefaults.standard.bool(forKey: migrationKey) {
        return
    }
    
    let fetchRequest: NSFetchRequest<Photo> = Photo.fetchRequest()
    
    do {
        let photos = try context.fetch(fetchRequest)
        var hasChanges = false
        var compressedCount = 0
        var totalOriginalSize: Int64 = 0
        var totalCompressedSize: Int64 = 0
        
        for photo in photos {
            guard let data = photo.data,
                  let image = UIImage(data: data) else {
                continue
            }
            
            // Skip transparent images — JPEG compression destroys the alpha channel.
            // Background-removed items must stay as PNG.
            if image.hasTransparency {
                // Regenerate thumbnail in PNG if missing or was previously JPEG
                if photo.thumbnailData == nil {
                    photo.thumbnailData = image.generateThumbnail()
                    hasChanges = true
                }
                continue
            }

            let originalSize = Int64(data.count)
            totalOriginalSize += originalSize
            
            // Process and compress the image
            if let compressedData = image.processForStorage() {
                let storedImage = UIImage(data: compressedData) ?? image
                PhotoContentBounds.assignImage(storedImage, to: photo, data: compressedData)
                totalCompressedSize += Int64(compressedData.count)
                
                // Generate thumbnail if not already present
                if photo.thumbnailData == nil {
                    photo.thumbnailData = image.generateThumbnail()
                }
                
                hasChanges = true
                compressedCount += 1
            }
        }
        
        // Also compress outfit images
        let outfitFetchRequest: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        let outfits = try context.fetch(outfitFetchRequest)
        
        for outfit in outfits {
            guard let imageData = outfit.image,
                  let image = UIImage(data: imageData) else {
                continue
            }
            
            let originalSize = Int64(imageData.count)
            totalOriginalSize += originalSize
            
            if let compressedData = image.processForStorage() {
                outfit.image = compressedData
                totalCompressedSize += Int64(compressedData.count)
                hasChanges = true
                compressedCount += 1
            }
        }
        
        if hasChanges {
            try context.save()
            let savedMB = Double(totalOriginalSize - totalCompressedSize) / (1024 * 1024)
            print("✅ Compressed \(compressedCount) images. Saved \(String(format: "%.2f", savedMB)) MB")
            
            // Mark migration as completed
            UserDefaults.standard.set(true, forKey: migrationKey)
        } else {
            // Mark as completed even if no photos to compress
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
        
        // Verify compression worked
        checkPhotoSizes(context: context)
        
    } catch {
        print("❌ Photo compression migration failed: \(error)")
    }
}

// MARK: - Photo storage stats

private let photoStorage200KBThreshold = ItemPhotoStorage.reportThresholdBytes

// MARK: - Per-item photo storage (Item Detail)

enum ItemPhotoStorage {
    /// Settings / storage report threshold.
    static let reportThresholdBytes = 200 * 1024
    /// Item Detail compress: long-edge cap for PNG cutouts (no byte crush).
    static let storageMaxDimension: CGFloat = 1200
    /// Item Detail compress: byte target for opaque JPEG only.
    static let compressionMaxBytes = 450 * 1024
    static var compressionMaxKB: Int { compressionMaxBytes / 1024 }

    static func formatByteCount(_ bytes: Int) -> String {
        guard bytes > 0 else { return "No image" }
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.2f MB", kb / 1024)
    }

    static func frontPhoto(for item: Item) -> Photo? {
        let photos = item.photos as? Set<Photo> ?? []
        if let front = photos.first(where: { $0.type == "front" }) {
            return front
        }
        return photos.first(where: { $0.isPrimary && ($0.type == nil || $0.type == "") })
    }

    static func wornPhoto(for item: Item) -> Photo? {
        (item.photos as? Set<Photo> ?? []).first(where: { $0.type == "worn" })
    }

    static func dataByteCount(for photo: Photo?) -> Int {
        photo?.data?.count ?? 0
    }

    static func isOverCompressionLimit(_ bytes: Int) -> Bool {
        bytes > compressionMaxBytes
    }

    static func maxPixelDimension(for photo: Photo?) -> CGFloat? {
        guard let data = photo?.data, let image = UIImage(data: data) else { return nil }
        return max(image.size.width, image.size.height)
    }

    static func needsCompression(for photo: Photo?) -> Bool {
        guard let data = photo?.data, !data.isEmpty,
              let image = UIImage(data: data) else {
            return false
        }
        let maxDim = max(image.size.width, image.size.height)
        if maxDim > storageMaxDimension {
            return true
        }
        if image.hasTransparency {
            return false
        }
        return data.count > compressionMaxBytes
    }

    static func compressButtonTitle(for photo: Photo?, imageLabel: String) -> String {
        guard let data = photo?.data, let image = UIImage(data: data) else {
            return "Compress \(imageLabel)"
        }
        if image.hasTransparency {
            return "Resize \(imageLabel) to 1200px (PNG)"
        }
        return "Compress \(imageLabel) to under \(compressionMaxKB) KB"
    }

    static func compressSkippedMessage(for photo: Photo?, imageLabel: String) -> String {
        guard let data = photo?.data, let image = UIImage(data: data) else {
            return "\(imageLabel) has no image data."
        }
        if image.hasTransparency {
            return "\(imageLabel) is already at most 1200px on the long edge."
        }
        return "\(imageLabel) is already under \(compressionMaxKB) KB and at most 1200px."
    }

    /// Resizes/compresses `photo.data` for this item. PNG cutouts: 1200px max only. JPEG: 1200px + byte cap. Regenerates thumbnail.
    @discardableResult
    static func compressPhotoIfNeeded(
        _ photo: Photo,
        item: Item,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        guard needsCompression(for: photo),
              let data = photo.data,
              !data.isEmpty,
              let image = UIImage(data: data) else {
            return false
        }

        let compressed = image.processForStorage(
            maxDimension: storageMaxDimension,
            maxFileSizeKB: compressionMaxKB
        )

        guard let compressed, !compressed.isEmpty else { return false }
        guard compressed != data else { return false }

        if let preview = UIImage(data: compressed) {
            PhotoContentBounds.assignImage(preview, to: photo, data: compressed)
            photo.thumbnailData = preview.generateThumbnail()
        } else {
            photo.data = compressed
        }

        setUpdatedAt(item)
        try context.save()
        return true
    }
}

struct PhotoStorageStats {
    let photoDataBytes: Int64
    let thumbnailDataBytes: Int64
    let outfitImageBytes: Int64
    let outfitWornImageBytes: Int64
    let photoRecordCount: Int
    let blobsOver200KB: Int

    var totalBytes: Int64 {
        photoDataBytes + thumbnailDataBytes + outfitImageBytes + outfitWornImageBytes
    }

    var summaryMessage: String {
        [
            "Item photos: \(Self.formatMB(photoDataBytes)) (\(photoRecordCount) images)",
            "Thumbnails: \(Self.formatMB(thumbnailDataBytes))",
            "Outfit collages: \(Self.formatMB(outfitImageBytes))",
            "Outfit worn photos: \(Self.formatMB(outfitWornImageBytes))",
            "Total stored: \(Self.formatMB(totalBytes))",
            "",
            "Images over 200 KB: \(blobsOver200KB)",
        ].joined(separator: "\n")
    }

    private static func formatMB(_ bytes: Int64) -> String {
        String(format: "%.2f MB", Double(bytes) / (1024 * 1024))
    }
}

func collectPhotoStorageStats(context: NSManagedObjectContext) throws -> PhotoStorageStats {
    var photoDataBytes: Int64 = 0
    var thumbnailDataBytes: Int64 = 0
    var photoRecordCount = 0
    var blobsOver200KB = 0

    let photos = try context.fetch(Photo.fetchRequest())
    for photo in photos {
        if let data = photo.data, !data.isEmpty {
            photoDataBytes += Int64(data.count)
            photoRecordCount += 1
            if data.count > photoStorage200KBThreshold {
                blobsOver200KB += 1
            }
        }
        if let thumbnailData = photo.thumbnailData, !thumbnailData.isEmpty {
            thumbnailDataBytes += Int64(thumbnailData.count)
            if thumbnailData.count > photoStorage200KBThreshold {
                blobsOver200KB += 1
            }
        }
    }

    var outfitImageBytes: Int64 = 0
    var outfitWornImageBytes: Int64 = 0
    let outfits = try context.fetch(Outfit.fetchRequest())
    for outfit in outfits {
        if let imageData = outfit.image, !imageData.isEmpty {
            outfitImageBytes += Int64(imageData.count)
            if imageData.count > photoStorage200KBThreshold {
                blobsOver200KB += 1
            }
        }
        if let wornData = outfit.wornImage, !wornData.isEmpty {
            outfitWornImageBytes += Int64(wornData.count)
            if wornData.count > photoStorage200KBThreshold {
                blobsOver200KB += 1
            }
        }
    }

    return PhotoStorageStats(
        photoDataBytes: photoDataBytes,
        thumbnailDataBytes: thumbnailDataBytes,
        outfitImageBytes: outfitImageBytes,
        outfitWornImageBytes: outfitWornImageBytes,
        photoRecordCount: photoRecordCount,
        blobsOver200KB: blobsOver200KB
    )
}

func printPhotoStorageStats(_ stats: PhotoStorageStats, context: NSManagedObjectContext) {
    print("\n📊 Photo storage report")
    print(String(repeating: "=", count: 50))
    print(stats.summaryMessage)

    let photos = (try? context.fetch(Photo.fetchRequest())) ?? []
    for photo in photos {
        guard let data = photo.data, data.count > photoStorage200KBThreshold else { continue }
        let sizeMB = Double(data.count) / (1024 * 1024)
        print("⚠️ Photo >200 KB: \(String(format: "%.2f", sizeMB)) MB (ID: \(photo.id?.uuidString.prefix(8) ?? "unknown"))")
    }

    let outfits = (try? context.fetch(Outfit.fetchRequest())) ?? []
    for outfit in outfits {
        if let imageData = outfit.image, imageData.count > photoStorage200KBThreshold {
            let sizeMB = Double(imageData.count) / (1024 * 1024)
            print("⚠️ Outfit image >200 KB: \(String(format: "%.2f", sizeMB)) MB (ID: \(outfit.id?.uuidString.prefix(8) ?? "unknown"))")
        }
        if let wornData = outfit.wornImage, wornData.count > photoStorage200KBThreshold {
            let sizeMB = Double(wornData.count) / (1024 * 1024)
            print("⚠️ Outfit worn image >200 KB: \(String(format: "%.2f", sizeMB)) MB (ID: \(outfit.id?.uuidString.prefix(8) ?? "unknown"))")
        }
    }

    let totalGB = Double(stats.totalBytes) / (1024 * 1024 * 1024)
    if totalGB > 0.1 {
        print("\n⚠️ Total image storage is \(String(format: "%.2f", totalGB)) GB")
    } else {
        print("\n✅ Total image storage looks reasonable for local closet data.")
    }
    print(String(repeating: "=", count: 50) + "\n")
}

// MARK: - Verify Photo Compression
func checkPhotoSizes(context: NSManagedObjectContext) {
    do {
        let stats = try collectPhotoStorageStats(context: context)
        printPhotoStorageStats(stats, context: context)
    } catch {
        print("❌ Photo size check failed: \(error)")
    }
}

// MARK: - Vacuum Core Data Database
func vacuumCoreData(context: NSManagedObjectContext) {
    // Save and reset context
    do {
        try context.save()
        context.reset()
    } catch {
        print("❌ Failed to save context before vacuum: \(error)")
        return
    }
    
    // Get persistent container
    let persistentContainer = PersistenceController.shared.container
    
    // Get store URL
    guard let storeURL = persistentContainer.persistentStoreCoordinator.persistentStores.first?.url else {
        print("❌ No store URL found")
        return
    }
    
    // Perform VACUUM operation
    let coordinator = persistentContainer.persistentStoreCoordinator
    
    do {
        // Remove store
        if let store = coordinator.persistentStores.first {
            try coordinator.remove(store)
        }
        
        // Re-add store with vacuum options
        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: [
                NSMigratePersistentStoresAutomaticallyOption: true,
                NSInferMappingModelAutomaticallyOption: true,
                NSSQLitePragmasOption: ["journal_mode": "DELETE"] // Force cleanup
            ]
        )
        
        // Execute VACUUM SQL command directly on the database file
        let dbPath = storeURL.path
        var db: OpaquePointer?
        
        // Open database
        let openResult = sqlite3_open(dbPath, &db)
        guard openResult == SQLITE_OK, let database = db else {
            print("❌ Failed to open database for vacuum: \(openResult)")
            return
        }
        
        // Execute VACUUM
        let vacuumResult = sqlite3_exec(database, "VACUUM", nil, nil, nil)
        guard vacuumResult == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(database))
            print("❌ VACUUM failed: \(errorMsg)")
            sqlite3_close(database)
            return
        }
        
        // Close database
        sqlite3_close(database)
        
        print("✅ Database vacuumed successfully - space reclaimed")
        
    } catch {
        print("❌ Vacuum failed: \(error)")
    }
}

// MARK: - Resolve Size Constraint Conflicts
func resolveSizeConstraintConflicts(context: NSManagedObjectContext) {
    // Check if this migration has already been completed
    let migrationKey = "hasResolvedSizeConstraintConflicts"
    if UserDefaults.standard.bool(forKey: migrationKey) {
        return
    }
    
    let fetchRequest: NSFetchRequest<Size> = Size.fetchRequest()
    fetchRequest.predicate = NSPredicate(format: "category == nil")
    
    do {
        let sizes = try context.fetch(fetchRequest)
        
        // Group sizes by value (since category is nil, we need to deduplicate by value+scale)
        var sizeGroups: [String: [Size]] = [:]
        
        for size in sizes {
            let key = "\(size.value ?? "nil")|\(size.scale ?? "nil")"
            sizeGroups[key, default: []].append(size)
        }
        
        var hasChanges = false
        var resolvedCount = 0
        
        // For each group, if there are duplicates with same value but different scales and nil category,
        // we need to ensure they're unique by scale
        for (key, group) in sizeGroups {
            if group.count > 1 {
                // Multiple sizes with same value+scale - this shouldn't happen, but handle it
                let first = group[0]
                for duplicate in group.dropFirst() {
                    // Transfer items to first
                    if let items = duplicate.items as? Set<Item> {
                        for item in items {
                            item.size = first
                        }
                    }
                    context.delete(duplicate)
                    hasChanges = true
                    resolvedCount += 1
                }
            }
        }
        
        // Also check for sizes with same value but different scales (these should be allowed now)
        // But if they have nil category and same value, they might conflict
        var valueGroups: [String: [Size]] = [:]
        for size in sizes {
            guard size.category == nil, let value = size.value else { continue }
            valueGroups[value, default: []].append(size)
        }
        
        // If we have sizes with same value but different scales, that's now allowed with the new constraint
        // But we should verify they have different scales
        for (value, group) in valueGroups {
            if group.count > 1 {
                let scales = Set(group.compactMap { $0.scale })
                if scales.count < group.count {
                    // Some have same scale - these are true duplicates
                    let groupedByScale = Dictionary(grouping: group) { $0.scale ?? "" }
                    for (scale, sizesWithScale) in groupedByScale {
                        if sizesWithScale.count > 1 {
                            let first = sizesWithScale[0]
                            for duplicate in sizesWithScale.dropFirst() {
                                if let items = duplicate.items as? Set<Item> {
                                    for item in items {
                                        item.size = first
                                    }
                                }
                                context.delete(duplicate)
                                hasChanges = true
                                resolvedCount += 1
                            }
                        }
                    }
                }
            }
        }
        
        if hasChanges {
            try context.save()
            print("✅ Resolved \(resolvedCount) Size constraint conflicts")
            UserDefaults.standard.set(true, forKey: migrationKey)
        } else {
            // Mark as completed even if no conflicts found
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
        
    } catch {
        print("❌ Failed to resolve Size constraint conflicts: \(error)")
    }
}

// MARK: - Migrate Photo Types
func migratePhotoTypes(context: NSManagedObjectContext) {
    // Check if migration has already been completed
    let migrationKey = "hasMigratedPhotoTypes"
    if UserDefaults.standard.bool(forKey: migrationKey) {
        return
    }
    
    let fetchRequest: NSFetchRequest<Photo> = Photo.fetchRequest()
    fetchRequest.predicate = NSPredicate(format: "isPrimary == YES AND (type == nil OR type == '')")
    
    do {
        let photos = try context.fetch(fetchRequest)
        var hasChanges = false
        
        for photo in photos {
            // Set type to "front" for existing isPrimary photos
            photo.type = "front"
            hasChanges = true
        }
        
        if hasChanges {
            try context.save()
            print("✅ Photo types migration successful! Migrated \(photos.count) photos to type 'front'.")
        } else {
            print("✅ Photo types migration: No photos needed migration.")
        }
        
        // Mark migration as completed
        UserDefaults.standard.set(true, forKey: migrationKey)
        
    } catch {
        print("❌ Photo types migration failed: \(error)")
    }
}

// MARK: - Deduplicate Wardrobes
/// Pass the current user's ID string from the calling `@MainActor` context so this
/// free function doesn't need to touch `SupabaseService.shared.currentUser` directly.
func deduplicateWardrobes(context: NSManagedObjectContext, userId: String? = nil) {
    do {
        // Only deduplicate wardrobes belonging to the current user.
        // Scoping to userId prevents orphaned/unowned wardrobes from being
        // merged with newly created user wardrobes that happen to share a name.
        let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        if let userId = userId {
            // Only consider active (non-soft-deleted) wardrobes belonging to this user.
            // Soft-deleted wardrobes are pending removal and should not be deduplicated
            // against newly created wardrobes with the same name.
            request.predicate = NSPredicate(
                format: "userId == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
                userId
            )
        } else {
            // Not authenticated — skip deduplication entirely to avoid data loss.
            print("⚠️ deduplicateWardrobes: skipping — no authenticated user")
            return
        }
        let allWardrobes = try context.fetch(request)
        
        print("🔍 Checking \(allWardrobes.count) wardrobes for duplicates...")
        
        // Group wardrobes by name (case-insensitive, trimmed) and type
        // This will catch duplicates with the same name and type
        var wardrobesByNameAndType: [String: [Wardrobe]] = [:]
        for wardrobe in allWardrobes {
            let name = (wardrobe.name ?? "unnamed").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let type = wardrobe.type ?? "unknown"
            let key = "\(name)|\(type)"
            wardrobesByNameAndType[key, default: []].append(wardrobe)
        }
        
        var hasChanges = false
        var deletedCount = 0
        
        // For each group, if there are duplicates, merge them
        for (key, wardrobes) in wardrobesByNameAndType {
            if wardrobes.count > 1 {
                // Keep the wardrobe with the most items (or oldest if equal)
                let primaryWardrobe = wardrobes.max { wardrobe1, wardrobe2 in
                    let count1 = wardrobe1.items?.count ?? 0
                    let count2 = wardrobe2.items?.count ?? 0
                    if count1 != count2 {
                        return count1 < count2
                    }
                    // If same item count, prefer the older one (earlier timestamp)
                    let date1 = wardrobe1.timestamp ?? Date.distantFuture
                    let date2 = wardrobe2.timestamp ?? Date.distantFuture
                    return date1 > date2
                } ?? wardrobes.first!
                
                let duplicates = wardrobes.filter { $0 != primaryWardrobe }
                
                let wardrobeName = primaryWardrobe.name ?? "unnamed"
                let wardrobeType = primaryWardrobe.type ?? "unknown"
                print("🔧 Found \(duplicates.count) duplicate wardrobes named '\(wardrobeName)' (type: '\(wardrobeType)'). Merging into primary wardrobe.")
                
                // Merge items from duplicates into primary wardrobe
                for duplicate in duplicates {
                    if let items = duplicate.items as? Set<Item> {
                        print("   Merging \(items.count) items from duplicate '\(duplicate.name ?? "unnamed")'")
                        for item in items {
                            // Remove from duplicate and add to primary
                            duplicate.removeFromItems(item)
                            primaryWardrobe.addToItems(item)
                        }
                    }
                    // Delete the duplicate wardrobe
                    context.delete(duplicate)
                    deletedCount += 1
                }
                
                hasChanges = true
            }
        }
        
        if hasChanges {
            try context.save()
            print("✅ Wardrobe deduplication completed! Removed \(deletedCount) duplicate wardrobe(s).")
        } else {
            print("✅ No duplicate wardrobes found.")
        }
        
    } catch {
        print("❌ Wardrobe deduplication failed: \(error)")
    }
}

// MARK: Migration
func migrateWishlistItems(context: NSManagedObjectContext) {
    // Check if migration has already been completed
    let migrationKey = "hasMigratedWishlistItems"
    if UserDefaults.standard.bool(forKey: migrationKey) {
        return
    }
    
    // Fetch (or create) Closet wardrobe
    let closetWardrobe: Wardrobe = {
        let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        request.predicate = NSPredicate(format: "type == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)", "closet")
        if let existing = try? context.fetch(request).first {
            return existing
        } else {
            let newWardrobe = Wardrobe(context: context)
            newWardrobe.id = UUID()
            newWardrobe.type = "closet"
            newWardrobe.name = "Closet"
            
            // Set userId for sync if authenticated
            // Note: Migration runs synchronously, so userId may not be available yet
            // Items will get userId set when synced or when user logs in
            // For now, leave userId nil - it will be set on first sync
            
            // Set timestamps using helper
            setCreatedAndUpdatedAt(newWardrobe)
            let now = Date()
            newWardrobe.timestamp = now
            
            return newWardrobe
        }
    }()
    
    // Fetch (or create) Wishlist wardrobe
    let wishlistWardrobe: Wardrobe = {
        let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        request.predicate = NSPredicate(format: "type == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)", "wishlist")
        if let existing = try? context.fetch(request).first {
            return existing
        } else {
            let newWardrobe = Wardrobe(context: context)
            newWardrobe.id = UUID()
            newWardrobe.type = "wishlist"
            newWardrobe.name = "Wishlist"
            
            // Set userId for sync if authenticated
            // Note: Migration runs synchronously, so userId may not be available yet
            // Items will get userId set when synced or when user logs in
            // For now, leave userId nil - it will be set on first sync
            
            // Set timestamps using helper
            setCreatedAndUpdatedAt(newWardrobe)
            let now = Date()
            newWardrobe.timestamp = now
            
            return newWardrobe
        }
    }()
    
    // Fetch all items
    let itemRequest: NSFetchRequest<Item> = Item.fetchRequest()
    
    do {
        let allItems = try context.fetch(itemRequest)
        var hasChanges = false
        
        for item in allItems {
            // Convert wardrobes to mutable set
            var currentWardrobes = item.wardrobes as? Set<Wardrobe> ?? []
            let originalCount = currentWardrobes.count
            
            // Assign Wishlist if flagged
            if item.isWishlist {
                currentWardrobes.insert(wishlistWardrobe)
            }
            
            // Assign Closet if item has no wardrobes yet
            if currentWardrobes.isEmpty {
                currentWardrobes.insert(closetWardrobe)
            }
            
            // Only update if something changed
            if currentWardrobes.count != originalCount || item.isWishlist {
                item.wardrobes = currentWardrobes as NSSet
                hasChanges = true
            }
        }
        
        if hasChanges {
            try context.save()
            print("✅ Wishlist items migration completed successfully!")
        }
        
        // Mark migration as completed
        UserDefaults.standard.set(true, forKey: migrationKey)
        
    } catch {
        print("❌ Wishlist items migration failed:", error)
    }
}

// MARK: - Migrate User Weight from UserDefaults to CoreData
func migrateUserWeightFromUserDefaults(context: NSManagedObjectContext) {
    // Check if migration has already been completed
    let migrationKey = "hasMigratedUserWeightToCoreData"
    if UserDefaults.standard.bool(forKey: migrationKey) {
        return
    }
    
    let weightKg = UserDefaults.standard.double(forKey: "userWeightKg")
    let weightUnit = UserDefaults.standard.string(forKey: "userWeightUnit") ?? "kg"
    
    // Only migrate if weight is set and valid
    guard weightKg > 0, weightKg.isFinite && !weightKg.isNaN else {
        // No weight to migrate, mark as completed
        UserDefaults.standard.set(true, forKey: migrationKey)
        return
    }
    
    do {
        let repository = UserProfileRepository(context: context)
        try repository.updateWeight(weightKg: weightKg, unit: weightUnit)
        
        // Clear old UserDefaults values
        UserDefaults.standard.removeObject(forKey: "userWeightKg")
        UserDefaults.standard.removeObject(forKey: "userWeightUnit")
        UserDefaults.standard.set(true, forKey: migrationKey)
        
        print("✅ Migrated user weight to CoreData: \(weightKg) kg (\(weightUnit))")
    } catch {
        print("❌ Failed to migrate user weight: \(error)")
        // Don't mark as completed if migration failed, so it can retry
    }
}

// MARK: - Migrate Timestamp to CreatedAt
func migrateTimestampToCreatedAt(context: NSManagedObjectContext) {
    // Check if migration has already been completed
    let migrationKey = "hasMigratedTimestampToCreatedAt"
    if UserDefaults.standard.bool(forKey: migrationKey) {
        return
    }
    
    var hasChanges = false
    
    do {
        // Migrate Items
        let itemsRequest: NSFetchRequest<Item> = Item.fetchRequest()
        itemsRequest.predicate = NSPredicate(format: "createdAt == nil AND timestamp != nil")
        let items = try context.fetch(itemsRequest)
        for item in items {
            if let timestamp = item.timestamp {
                item.createdAt = timestamp
                hasChanges = true
            }
        }
        print("✅ Migrated \(items.count) Items: timestamp → createdAt")
        
        // Migrate Outfits
        let outfitsRequest: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        outfitsRequest.predicate = NSPredicate(format: "createdAt == nil AND timestamp != nil")
        let outfits = try context.fetch(outfitsRequest)
        for outfit in outfits {
            if let timestamp = outfit.timestamp {
                outfit.createdAt = timestamp
                hasChanges = true
            }
        }
        print("✅ Migrated \(outfits.count) Outfits: timestamp → createdAt")
        
        // Migrate Wardrobes
        let wardrobesRequest: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        wardrobesRequest.predicate = NSPredicate(format: "createdAt == nil AND timestamp != nil")
        let wardrobes = try context.fetch(wardrobesRequest)
        for wardrobe in wardrobes {
            if let timestamp = wardrobe.timestamp {
                wardrobe.createdAt = timestamp
                hasChanges = true
            }
        }
        print("✅ Migrated \(wardrobes.count) Wardrobes: timestamp → createdAt")
        
        // Migrate Events
        let eventsRequest: NSFetchRequest<Event> = Event.fetchRequest()
        eventsRequest.predicate = NSPredicate(format: "createdAt == nil AND timestamp != nil")
        let events = try context.fetch(eventsRequest)
        for event in events {
            if let timestamp = event.timestamp {
                event.createdAt = timestamp
                hasChanges = true
            }
        }
        print("✅ Migrated \(events.count) Events: timestamp → createdAt")
        
        // Migrate Collections
        let collectionsRequest: NSFetchRequest<Collection> = Collection.fetchRequest()
        collectionsRequest.predicate = NSPredicate(format: "createdAt == nil AND timestamp != nil")
        let collections = try context.fetch(collectionsRequest)
        for collection in collections {
            if let timestamp = collection.timestamp {
                collection.createdAt = timestamp
                hasChanges = true
            }
        }
        print("✅ Migrated \(collections.count) Collections: timestamp → createdAt")
        
        // Migrate Photos
        let photosRequest: NSFetchRequest<Photo> = Photo.fetchRequest()
        photosRequest.predicate = NSPredicate(format: "createdAt == nil AND timestamp != nil")
        let photos = try context.fetch(photosRequest)
        for photo in photos {
            if let timestamp = photo.timestamp {
                photo.createdAt = timestamp
                hasChanges = true
            }
        }
        print("✅ Migrated \(photos.count) Photos: timestamp → createdAt")
        
        if hasChanges {
            try context.save()
            print("✅ Timestamp to createdAt migration completed successfully!")
        }
        
        // Mark migration as completed
        UserDefaults.standard.set(true, forKey: migrationKey)
        
    } catch {
        print("❌ Timestamp to createdAt migration failed: \(error)")
        // Don't mark as completed if migration failed, so it can retry
    }
}

/// Assigns `userId` on events missing it by inferring from linked items/outfits (safe for multi-account devices).
func migrateEventUserIdsFromRelationships(context: NSManagedObjectContext) {
    let req = Event.fetchRequest()
    req.predicate = NSPredicate(format: "userId == nil OR userId == \"\"")
    guard let events = try? context.fetch(req), !events.isEmpty else { return }
    var altered = 0
    for event in events {
        guard let uid = inferredUserIdForEvent(event), !uid.isEmpty else { continue }
        event.userId = uid
        setUpdatedAt(event)
        altered += 1
    }
    guard altered > 0, context.hasChanges else { return }
    do {
        try context.save()
        print("✅ Migrated \(altered) calendar event(s): inferred userId from linked items/outfits")
    } catch {
        print("❌ migrateEventUserIdsFromRelationships: \(error)")
    }
}

/// One-time: set `isDefault` on canonical closet/wishlist per user (earliest timestamp, then createdAt). See `WardrobeBootstrap.normalizeDefaultFlagsForUser`.
func migrateWardrobeIsDefaultBackfill(context: NSManagedObjectContext) {
    let migrationKey = "hasMigratedWardrobeIsDefaultBackfill_v1"
    if UserDefaults.standard.bool(forKey: migrationKey) {
        return
    }
    do {
        try WardrobeBootstrap.normalizeAllWardrobeDefaultFlags(in: context)
        if context.hasChanges {
            try context.save()
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
        print("✅ Wardrobe isDefault backfill completed")
    } catch {
        print("❌ Wardrobe isDefault backfill failed: \(error)")
    }
}


