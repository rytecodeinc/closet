//
//  SyncEngine+ReferenceEntities
//  closet
//

import CoreData
import Foundation
import Supabase
import UIKit


extension SyncEngine {
    func fetchUnsyncedItemObjectIDs(userId: UUID) async throws -> [NSManagedObjectID] {
        try await performOnSyncContext { ctx in
            let request: NSFetchRequest<Item> = Item.fetchRequest()
            request.predicate = NSPredicate(
                format: "userId == %@ AND isDraft != YES AND (syncedAt == nil OR updatedAt > syncedAt)",
                userId.uuidString
            )
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.createdAt, ascending: true)]
            return try ctx.fetch(request).map { $0.objectID }
        }
    }

    func itemName(for objectID: NSManagedObjectID) async -> String {
        (try? await withSyncItem(objectID) { $0.name ?? "unnamed" }) ?? "unnamed"
    }

    func itemIdString(for objectID: NSManagedObjectID) async -> String {
        (try? await withSyncItem(objectID) { $0.id?.uuidString ?? "no ID" }) ?? "no ID"
    }
    
    // MARK: - Reference Data Sync Methods
    
    /// Ensures all referenced entities for an item are synced before syncing the item
    /// This prevents foreign key constraint violations
    func ensureReferencedEntitiesSynced(forItemObjectID itemObjectID: NSManagedObjectID, userId: UUID) async throws {
        struct ReferencedEntityIDs {
            var brandID: NSManagedObjectID?
            var categoryID: NSManagedObjectID?
            var subcategoryID: NSManagedObjectID?
            var subcategoryParentCategoryID: NSManagedObjectID?
            var sizeID: NSManagedObjectID?
            var locationID: NSManagedObjectID?
        }

        let refs = try await performOnSyncContext { ctx -> ReferencedEntityIDs in
            guard let item = try ctx.existingObject(with: itemObjectID) as? Item else {
                return ReferencedEntityIDs()
            }
            var refs = ReferencedEntityIDs()

            if let brand = item.brand {
                if brand.userId == nil || brand.userId?.isEmpty == true {
                    brand.userId = userId.uuidString
                }
                refs.brandID = brand.objectID
            }
            if let category = item.category {
                if category.userId == nil || category.userId?.isEmpty == true {
                    category.userId = userId.uuidString
                }
                refs.categoryID = category.objectID
            }
            if let subcategory = item.subcategory {
                if let category = subcategory.category {
                    if category.userId == nil || category.userId?.isEmpty == true {
                        category.userId = userId.uuidString
                    }
                    refs.subcategoryParentCategoryID = category.objectID
                }
                if subcategory.userId == nil || subcategory.userId?.isEmpty == true {
                    subcategory.userId = userId.uuidString
                }
                refs.subcategoryID = subcategory.objectID
            }
            if let size = item.itemSize {
                if size.userId == nil || size.userId?.isEmpty == true {
                    size.userId = userId.uuidString
                    if size.updatedAt == nil {
                        size.updatedAt = Date.distantPast
                    }
                }
                refs.sizeID = size.objectID
            }
            if let location = item.location {
                if location.userId == nil || location.userId?.isEmpty == true {
                    location.userId = userId.uuidString
                }
                refs.locationID = location.objectID
            }

            if ctx.hasChanges {
                try ctx.save()
            }
            return refs
        }

        if let brandID = refs.brandID {
            try await syncBrand(objectID: brandID, userId: userId)
        }
        if let categoryID = refs.categoryID {
            try await syncCategory(objectID: categoryID, userId: userId)
        }
        if let parentCategoryID = refs.subcategoryParentCategoryID {
            try await syncCategory(objectID: parentCategoryID, userId: userId)
        }
        if let subcategoryID = refs.subcategoryID {
            try await syncSubcategory(objectID: subcategoryID, userId: userId)
        }
        if let sizeID = refs.sizeID {
            try await syncSize(objectID: sizeID, userId: userId)
        }
        if let locationID = refs.locationID {
            try await syncLocation(objectID: locationID, userId: userId)
        }
    }
    
    /// Syncs a brand to Supabase.
    /// Upserts by `id`. If another row already owns `(user_id, name)`, adopts that remote id locally
    /// so bootstrap / duplicate local brands do not fail session sync.
    func syncBrand(objectID: NSManagedObjectID, userId: UUID) async throws {
        let brandData = try await performOnSyncContext { ctx -> SyncBrandData? in
            guard let brand = try ctx.existingObject(with: objectID) as? Brand,
                  let brandId = brand.id else { return nil }
            let name = (brand.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return SyncBrandData(
                id: brandId.uuidString,
                userId: userId.uuidString,
                name: name,
                isVisible: brand.isVisible
            )
        }
        guard let brandData else { return }

        do {
            try await (await getSupabase()).supabaseClient.from("brands")
                .upsert(brandData, onConflict: "id")
                .execute()
        } catch {
            guard isUniqueConstraintViolation(error, constraintHint: "brands_user_id_name") else {
                throw error
            }
            print("ℹ️ Brand upsert hit user_id+name conflict for \"\(brandData.name)\"; adopting remote id")
            try await adoptRemoteBrandIdentity(
                localObjectID: objectID,
                userId: userId,
                name: brandData.name,
                isVisible: brandData.isVisible
            )
            return
        }

        try await performOnSyncContext { ctx in
            guard let brand = try ctx.existingObject(with: objectID) as? Brand else { return }
            brand.syncedAt = Date()
            try ctx.save()
        }
    }

    func syncBrand(_ brand: Brand, userId: UUID) async throws {
        try await syncBrand(objectID: brand.objectID, userId: userId)
    }

    /// When Supabase already has `(user_id, name)`, point the local brand at that row's id,
    /// merge any other local duplicates with the same name, then upsert + mark synced.
    private func adoptRemoteBrandIdentity(
        localObjectID: NSManagedObjectID,
        userId: UUID,
        name: String,
        isVisible: Bool
    ) async throws {
        struct RemoteBrandRow: Decodable {
            let id: String
            let name: String
            let isVisible: Bool?

            enum CodingKeys: String, CodingKey {
                case id
                case name
                case isVisible = "is_visible"
            }
        }

        let response = try await (await getSupabase()).supabaseClient.from("brands")
            .select("id, name, is_visible")
            .eq("user_id", value: userId.uuidString)
            .eq("name", value: name)
            .limit(1)
            .execute()

        let rows = try JSONDecoder().decode([RemoteBrandRow].self, from: response.data)
        guard let remote = rows.first, let remoteUUID = UUID(uuidString: remote.id) else {
            throw NSError(
                domain: "SyncEngine",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Brand name conflict for \"\(name)\" but no remote row found"]
            )
        }

        let resolvedVisible = remote.isVisible ?? isVisible
        let resolvedData = SyncBrandData(
            id: remote.id,
            userId: userId.uuidString,
            name: name,
            isVisible: resolvedVisible
        )
        try await (await getSupabase()).supabaseClient.from("brands")
            .upsert(resolvedData, onConflict: "id")
            .execute()

        try await performOnSyncContext { ctx in
            guard let local = try ctx.existingObject(with: localObjectID) as? Brand else { return }

            let dupRequest: NSFetchRequest<Brand> = Brand.fetchRequest()
            dupRequest.predicate = NSPredicate(
                format: "userId == %@ AND name ==[c] %@ AND SELF != %@",
                userId.uuidString,
                name,
                local
            )
            let duplicates = try ctx.fetch(dupRequest)
            for dup in duplicates {
                if let items = dup.items as? Set<Item> {
                    for item in items {
                        item.brand = local
                        setUpdatedAt(item)
                    }
                }
                ctx.delete(dup)
            }

            local.id = remoteUUID
            local.name = name
            local.isVisible = resolvedVisible
            local.userId = userId.uuidString
            local.syncedAt = Date()
            setUpdatedAt(local)
            try ctx.save()
        }

        print("✅ Adopted remote brand id \(remote.id.prefix(8))… for \"\(name)\"")
    }

    private func isUniqueConstraintViolation(_ error: Error, constraintHint: String) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("duplicate key")
            || message.contains(constraintHint.lowercased())
            || message.contains("unique constraint")
    }
    
    /// Syncs a category to Supabase
    func syncCategory(objectID: NSManagedObjectID, userId: UUID) async throws {
        let categoryData = try await performOnSyncContext { ctx -> SyncCategoryData? in
            guard let category = try ctx.existingObject(with: objectID) as? Category,
                  let categoryId = category.id else { return nil }
            return SyncCategoryData(
                id: categoryId.uuidString,
                userId: userId.uuidString,
                name: category.name ?? ""
            )
        }
        guard let categoryData else { return }
        try await (await getSupabase()).supabaseClient.from("categories")
            .upsert(categoryData, onConflict: "id")
            .execute()
        try await performOnSyncContext { ctx in
            guard let category = try ctx.existingObject(with: objectID) as? Category else { return }
            category.syncedAt = Date()
            try ctx.save()
        }
    }

    func syncCategory(_ category: Category, userId: UUID) async throws {
        try await syncCategory(objectID: category.objectID, userId: userId)
    }
    
    /// Syncs a subcategory to Supabase
    func syncSubcategory(objectID: NSManagedObjectID, userId: UUID) async throws {
        let subcategoryData = try await performOnSyncContext { ctx -> SyncSubcategoryData? in
            guard let subcategory = try ctx.existingObject(with: objectID) as? Subcategory,
                  let subcategoryId = subcategory.id,
                  let categoryId = subcategory.category?.id else { return nil }
            return SyncSubcategoryData(
                id: subcategoryId.uuidString,
                categoryId: categoryId.uuidString,
                userId: userId.uuidString,
                name: subcategory.name ?? "",
                sortOrder: Int(subcategory.sortOrder)
            )
        }
        guard let subcategoryData else { return }
        try await (await getSupabase()).supabaseClient.from("subcategories")
            .upsert(subcategoryData, onConflict: "id")
            .execute()
        try await performOnSyncContext { ctx in
            guard let subcategory = try ctx.existingObject(with: objectID) as? Subcategory else { return }
            subcategory.syncedAt = Date()
            try ctx.save()
        }
    }

    func syncSubcategory(_ subcategory: Subcategory, userId: UUID) async throws {
        try await syncSubcategory(objectID: subcategory.objectID, userId: userId)
    }
    
    /// Syncs a color to Supabase
    func syncColor(objectID: NSManagedObjectID, userId: UUID) async throws {
        let colorData = try await performOnSyncContext { ctx -> SyncColorData? in
            guard let color = try ctx.existingObject(with: objectID) as? AppColor,
                  let colorId = color.id else { return nil }
            return SyncColorData(
                id: colorId.uuidString,
                userId: userId.uuidString,
                name: color.name ?? "",
                hexCode: color.hexCode,
                isVisible: color.isVisible
            )
        }
        guard let colorData else { return }
        try await (await getSupabase()).supabaseClient.from("colors")
            .upsert(colorData, onConflict: "id")
            .execute()
        try await performOnSyncContext { ctx in
            guard let color = try ctx.existingObject(with: objectID) as? AppColor else { return }
            color.syncedAt = Date()
            try ctx.save()
        }
    }

    func syncColor(_ color: AppColor, userId: UUID) async throws {
        try await syncColor(objectID: color.objectID, userId: userId)
    }
    
    /// Syncs a season to Supabase
    func syncSeason(objectID: NSManagedObjectID, userId: UUID) async throws {
        let seasonData = try await performOnSyncContext { ctx -> SyncSeasonData? in
            guard let season = try ctx.existingObject(with: objectID) as? Season,
                  let seasonId = season.id else { return nil }
            return SyncSeasonData(
                id: seasonId.uuidString,
                userId: userId.uuidString,
                name: season.name ?? "",
                isVisible: season.isVisible
            )
        }
        guard let seasonData else { return }
        try await (await getSupabase()).supabaseClient.from("seasons")
            .upsert(seasonData, onConflict: "id")
            .execute()
        try await performOnSyncContext { ctx in
            guard let season = try ctx.existingObject(with: objectID) as? Season else { return }
            season.syncedAt = Date()
            try ctx.save()
        }
    }

    func syncSeason(_ season: Season, userId: UUID) async throws {
        try await syncSeason(objectID: season.objectID, userId: userId)
    }
    
    /// Syncs a size to Supabase
    func syncSize(objectID: NSManagedObjectID, userId: UUID) async throws {
        struct SizeSyncPayload {
            let data: SyncSizeData
            let needsSync: Bool
            let logValue: String
            let logCategory: String
        }

        let payload = try await performOnSyncContext { ctx -> SizeSyncPayload? in
            guard let size = try ctx.existingObject(with: objectID) as? Size,
                  let sizeId = size.id else {
                print("⚠️ Size missing ID, skipping sync")
                return nil
            }
            let needsSync: Bool
            if size.syncedAt == nil {
                needsSync = true
            } else if let updatedAt = size.updatedAt, let syncedAt = size.syncedAt {
                needsSync = updatedAt > syncedAt
            } else {
                needsSync = false
            }
            let data = SyncSizeData(
                id: sizeId.uuidString,
                categoryId: size.category?.id?.uuidString,
                userId: userId.uuidString,
                value: size.value ?? "",
                scale: size.scale,
                sortOrder: Int(size.sortOrder)
            )
            return SizeSyncPayload(
                data: data,
                needsSync: needsSync,
                logValue: size.value ?? "unknown",
                logCategory: size.category?.name ?? "no category"
            )
        }
        guard let payload else { return }

        try await (await getSupabase()).supabaseClient.from("sizes")
            .upsert(payload.data, onConflict: "id")
            .execute()

        try await performOnSyncContext { ctx in
            guard let size = try ctx.existingObject(with: objectID) as? Size else { return }
            let now = Date()
            size.syncedAt = now
            if size.updatedAt == nil || (size.updatedAt ?? Date.distantPast) <= (size.syncedAt ?? Date.distantPast) {
                size.updatedAt = now
            }
            try ctx.save()
        }

        if payload.needsSync {
            print("✅ Synced size: \(payload.logValue) (category: \(payload.logCategory))")
        }
    }

    func syncSize(_ size: Size, userId: UUID) async throws {
        try await syncSize(objectID: size.objectID, userId: userId)
    }
    
    /// Syncs a tag to Supabase
    func syncTag(objectID: NSManagedObjectID, userId: UUID) async throws {
        let tagData = try await performOnSyncContext { ctx -> SyncTagData? in
            guard let tag = try ctx.existingObject(with: objectID) as? Tag,
                  let tagId = tag.id else { return nil }
            return SyncTagData(
                id: tagId.uuidString,
                userId: userId.uuidString,
                name: tag.name ?? ""
            )
        }
        guard let tagData else { return }
        try await (await getSupabase()).supabaseClient.from("tags")
            .upsert(tagData, onConflict: "id")
            .execute()
        try await performOnSyncContext { ctx in
            guard let tag = try ctx.existingObject(with: objectID) as? Tag else { return }
            tag.syncedAt = Date()
            try ctx.save()
        }
    }

    func syncTag(_ tag: Tag, userId: UUID) async throws {
        try await syncTag(objectID: tag.objectID, userId: userId)
    }

    /// Syncs an outfit category to Supabase
    func syncOutfitCategory(objectID: NSManagedObjectID, userId: UUID) async throws {
        let categoryData = try await performOnSyncContext { ctx -> SyncOutfitCategoryData? in
            guard let category = try ctx.existingObject(with: objectID) as? OutfitCategory,
                  let categoryId = category.id else { return nil }
            return SyncOutfitCategoryData(
                id: categoryId.uuidString,
                userId: userId.uuidString,
                name: category.name ?? ""
            )
        }
        guard let categoryData else { return }
        try await (await getSupabase()).supabaseClient.from("outfit_categories")
            .upsert(categoryData, onConflict: "id")
            .execute()
        try await performOnSyncContext { ctx in
            guard let category = try ctx.existingObject(with: objectID) as? OutfitCategory else { return }
            category.syncedAt = Date()
            try ctx.save()
        }
    }

    func syncOutfitCategory(_ category: OutfitCategory, userId: UUID) async throws {
        try await syncOutfitCategory(objectID: category.objectID, userId: userId)
    }
    
    
    /// Syncs a location to Supabase
    func syncLocation(objectID: NSManagedObjectID, userId: UUID) async throws {
        let locationData = try await performOnSyncContext { ctx -> SyncLocationData? in
            guard let location = try ctx.existingObject(with: objectID) as? Location,
                  let locationId = location.id else { return nil }
            return SyncLocationData(
                id: locationId.uuidString,
                userId: userId.uuidString,
                name: location.name ?? ""
            )
        }
        guard let locationData else { return }
        try await (await getSupabase()).supabaseClient.from("locations")
            .upsert(locationData, onConflict: "id")
            .execute()
        try await performOnSyncContext { ctx in
            guard let location = try ctx.existingObject(with: objectID) as? Location else { return }
            location.syncedAt = Date()
            try ctx.save()
        }
    }

    func syncLocation(_ location: Location, userId: UUID) async throws {
        try await syncLocation(objectID: location.objectID, userId: userId)
    }
    
    
    /// Syncs a wardrobe to Supabase
    func syncWardrobe(objectID: NSManagedObjectID, userId: UUID) async throws {
        let payload = try await performOnSyncContext { ctx -> (data: SyncWardrobeData?, isSoftDeleted: Bool, name: String)? in
            guard let wardrobe = try ctx.existingObject(with: objectID) as? Wardrobe,
                  let wardrobeId = wardrobe.id else { return nil }
            let sectionTitleSynced = (wardrobe.packingChecklistSectionTitle ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let data = SyncWardrobeData(
                id: wardrobeId.uuidString,
                userId: userId.uuidString,
                name: wardrobe.name ?? "",
                type: wardrobe.type,
                visibility: wardrobe.wardrobeVisibility.rawValue,
                isSoftDeleted: wardrobe.isSoftDeleted,
                isDefault: wardrobe.isDefault,
                packingChecklistSectionTitle: sectionTitleSynced.isEmpty ? "" : sectionTitleSynced,
                createdAt: wardrobe.createdAt?.ISO8601String ?? wardrobe.timestamp?.ISO8601String,
                updatedAt: wardrobe.updatedAt?.ISO8601String
            )
            return (data, wardrobe.isSoftDeleted, wardrobe.name ?? "unnamed")
        }

        guard let payload, let wardrobeData = payload.data else { return }

        if payload.isSoftDeleted {
            print("🗑️ Deleting wardrobe from Supabase: \(payload.name)")
            try await (await getSupabase()).supabaseClient.from("wardrobes")
                .delete()
                .eq("id", value: wardrobeData.id)
                .execute()
            try await performOnSyncContext { ctx in
                guard let wardrobe = try ctx.existingObject(with: objectID) as? Wardrobe else { return }
                wardrobe.syncedAt = Date()
                try ctx.save()
            }
            print("✅ Successfully deleted wardrobe from Supabase")
            return
        }

        print("📤 Syncing wardrobe to Supabase: \(payload.name) (isSoftDeleted: \(payload.isSoftDeleted))")
        try await (await getSupabase()).supabaseClient.from("wardrobes")
            .upsert(wardrobeData, onConflict: "id")
            .execute()
        try await performOnSyncContext { ctx in
            guard let wardrobe = try ctx.existingObject(with: objectID) as? Wardrobe else { return }
            wardrobe.syncedAt = Date()
            try ctx.save()
        }
    }

    func syncWardrobe(_ wardrobe: Wardrobe, userId: UUID) async throws {
        try await syncWardrobe(objectID: wardrobe.objectID, userId: userId)
    }
}
