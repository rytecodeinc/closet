//
//  SyncEngine+ReferenceData
//  closet
//

import CoreData
import Foundation
import Supabase
import UIKit


extension SyncEngine {
    func syncAllReferenceData(userId: UUID) async throws {
        // Sync brands - only if changed
        let brandRequest: NSFetchRequest<Brand> = Brand.fetchRequest()
        brandRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let brandsIDs = try await performOnSyncContext { ctx in
            try ctx.fetch(brandRequest).map { $0.objectID }
        }
        for objectID in brandsIDs {
            try await syncBrand(objectID: objectID, userId: userId)
        }
        
        // Sync categories - only if changed
        let categoryRequest: NSFetchRequest<Category> = Category.fetchRequest()
        categoryRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let categoriesIDs = try await performOnSyncContext { ctx in
            try ctx.fetch(categoryRequest).map { $0.objectID }
        }
        for objectID in categoriesIDs {
            try await syncCategory(objectID: objectID, userId: userId)
        }
        
        // Sync subcategories - only if changed
        let subcategoryRequest: NSFetchRequest<Subcategory> = Subcategory.fetchRequest()
        subcategoryRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let subcategoriesIDs = try await performOnSyncContext { ctx in
            try ctx.fetch(subcategoryRequest).map { $0.objectID }
        }
        for objectID in subcategoriesIDs {
            try await syncSubcategory(objectID: objectID, userId: userId)
        }
        
        // Sync colors - only if changed
        let colorRequest: NSFetchRequest<AppColor> = AppColor.fetchRequest()
        colorRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let colorsIDs = try await performOnSyncContext { ctx in
            try ctx.fetch(colorRequest).map { $0.objectID }
        }
        for objectID in colorsIDs {
            try await syncColor(objectID: objectID, userId: userId)
        }
        
        // Sync seasons - only if changed
        let seasonRequest: NSFetchRequest<Season> = Season.fetchRequest()
        seasonRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let seasonsIDs = try await performOnSyncContext { ctx in
            try ctx.fetch(seasonRequest).map { $0.objectID }
        }
        for objectID in seasonsIDs {
            try await syncSeason(objectID: objectID, userId: userId)
        }
        
        // Sync sizes - include all sizes referenced by items, but only sync if changed
        try await performOnSyncContext { ctx in
            let allSizesRequest: NSFetchRequest<Size> = Size.fetchRequest()
            allSizesRequest.predicate = NSPredicate(format: "userId == %@ OR userId == nil OR userId == ''", userId.uuidString)
            let allSizes = try ctx.fetch(allSizesRequest)
            var hasChanges = false
            for size in allSizes {
                if size.updatedAt == nil {
                    size.updatedAt = size.syncedAt ?? Date.distantPast
                    hasChanges = true
                }
            }
            if hasChanges {
                try ctx.save()
            }
        }

        let sizeObjectIDs = try await performOnSyncContext { ctx -> [NSManagedObjectID] in
            let sizeRequest: NSFetchRequest<Size> = Size.fetchRequest()
            sizeRequest.predicate = NSPredicate(format: "(userId == %@ OR userId == nil OR userId == '') AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
            let sizes = try ctx.fetch(sizeRequest)

            let itemRequest: NSFetchRequest<Item> = Item.fetchRequest()
            itemRequest.predicate = NSPredicate(format: "userId == %@", userId.uuidString)
            let items = try ctx.fetch(itemRequest)
            var referencedSizeIds = Set<UUID>()
            for item in items {
                if let size = item.itemSize, let sizeId = size.id {
                    referencedSizeIds.insert(sizeId)
                }
            }

            var objectIDs = sizes.map { $0.objectID }
            var syncedSizeIds = Set(sizes.compactMap { $0.id })

            for sizeId in referencedSizeIds where !syncedSizeIds.contains(sizeId) {
                let sizeRequest: NSFetchRequest<Size> = Size.fetchRequest()
                sizeRequest.predicate = NSPredicate(format: "id == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", sizeId as CVarArg)
                if let size = try ctx.fetch(sizeRequest).first {
                    objectIDs.append(size.objectID)
                }
            }
            return objectIDs
        }

        for sizeObjectID in sizeObjectIDs {
            try await performOnSyncContext { ctx in
                guard let size = try ctx.existingObject(with: sizeObjectID) as? Size else { return }
                if size.userId == nil || size.userId?.isEmpty == true {
                    size.userId = userId.uuidString
                    size.updatedAt = Date()
                }
                if ctx.hasChanges { try ctx.save() }
            }
            try await syncSize(objectID: sizeObjectID, userId: userId)
        }
        
        // Sync tags - only if changed
        let tagRequest: NSFetchRequest<Tag> = Tag.fetchRequest()
        tagRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let tagsIDs = try await performOnSyncContext { ctx in
            try ctx.fetch(tagRequest).map { $0.objectID }
        }
        for objectID in tagsIDs {
            try await syncTag(objectID: objectID, userId: userId)
        }

        // Sync outfit categories - only if changed
        let outfitCategoryRequest: NSFetchRequest<OutfitCategory> = OutfitCategory.fetchRequest()
        outfitCategoryRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let outfitCategoryIDs = try await performOnSyncContext { ctx in
            try ctx.fetch(outfitCategoryRequest).map { $0.objectID }
        }
        for objectID in outfitCategoryIDs {
            try await syncOutfitCategory(objectID: objectID, userId: userId)
        }
        
        // Sync locations - only if changed
        let locationRequest: NSFetchRequest<Location> = Location.fetchRequest()
        locationRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let locationsIDs = try await performOnSyncContext { ctx in
            try ctx.fetch(locationRequest).map { $0.objectID }
        }
        for objectID in locationsIDs {
            try await syncLocation(objectID: objectID, userId: userId)
        }
        
        // Sync wardrobes - only if changed (wardrobes already have syncedAt and updatedAt)
        let wardrobeRequest: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        wardrobeRequest.predicate = NSPredicate(format: "userId == %@ AND (syncedAt == nil OR updatedAt > syncedAt)", userId.uuidString)
        let wardrobesIDs = try await performOnSyncContext { ctx in
            try ctx.fetch(wardrobeRequest).map { $0.objectID }
        }
        for objectID in wardrobesIDs {
            try await syncWardrobe(objectID: objectID, userId: userId)
        }
        
        print("✅ Synced all reference data (only changed entities)")
    }
}
