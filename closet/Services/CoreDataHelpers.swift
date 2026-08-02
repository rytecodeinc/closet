//
//  CoreDataHelpers.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import Foundation
import CoreData

// MARK: - Wardrobe naming

enum WardrobeNaming {
    /// Trims whitespace for names entered in the UI.
    /// Returns empty string if the trimmed name is empty (caller should reject saves).
    static func normalizedUserName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
    }
}

/// Helper function to set updatedAt timestamp on entities before saving
func setUpdatedAt<T: NSManagedObject>(_ entity: T) {
    // Check if entity has updatedAt property and set it
    if entity.entity.attributesByName["updatedAt"] != nil {
        entity.setValue(Date(), forKey: "updatedAt")
    }
}

/// Helper function to set updatedAt on multiple entities
func setUpdatedAt<T: NSManagedObject>(_ entities: [T]) {
    for entity in entities {
        setUpdatedAt(entity)
    }
}

/// Helper function to set createdAt and updatedAt when creating new entities
func setCreatedAndUpdatedAt<T: NSManagedObject>(_ entity: T) {
    let now = Date()
    if entity.entity.attributesByName["createdAt"] != nil {
        entity.setValue(now, forKey: "createdAt")
    }
    if entity.entity.attributesByName["updatedAt"] != nil {
        entity.setValue(now, forKey: "updatedAt")
    }
}

// MARK: - Item lifecycle dates (wishlist → closet)

enum ItemLifecycleDates {
    static func itemHasWishlistWardrobe(_ item: Item) -> Bool {
        (item.wardrobes as? Set<Wardrobe>)?.contains { $0.type?.lowercased() == "wishlist" } ?? false
    }

    static func itemHasClosetWardrobe(_ item: Item) -> Bool {
        (item.wardrobes as? Set<Wardrobe>)?.contains { $0.type?.lowercased() == "closet" } ?? false
    }

    /// Stamps `wishedAt` / `purchasedAt` from wardrobe membership. Never overwrites existing values.
    static func applyOnSave(for item: Item, at date: Date = Date()) {
        if itemHasWishlistWardrobe(item), item.wishedAt == nil {
            item.wishedAt = date
        }
        if itemHasClosetWardrobe(item), !itemHasWishlistWardrobe(item), item.purchasedAt == nil {
            item.purchasedAt = date
        }
    }

    /// First final save from ItemAddView: one timestamp for `createdAt` (sort order) and lifecycle dates.
    static func applyOnFirstFinalSave(for item: Item, at date: Date = Date()) {
        if item.createdAt == nil {
            item.createdAt = date
        }
        applyOnSave(for: item, at: date)
    }

    /// When moving a wishlist item into the closet: set `purchasedAt` and bump `createdAt` to the same time so it sorts as newest in closet. Preserves `wishedAt`.
    static func stampPurchasedOnMoveToCloset(for item: Item, at date: Date = Date()) {
        item.purchasedAt = date
        item.createdAt = date
    }

    /// One-time backfill for items created before `wishedAt` / `purchasedAt` existed locally.
    static func migrateLifecycleDates(context: NSManagedObjectContext) {
        let migrationKey = "hasMigratedItemLifecycleDates"
        if UserDefaults.standard.bool(forKey: migrationKey) { return }

        var hasChanges = false
        do {
            let items = try context.fetch(Item.fetchRequest())
            for item in items {
                let referenceDate = item.createdAt ?? item.timestamp
                let hasWishlist = itemHasWishlistWardrobe(item)
                let hasCloset = itemHasClosetWardrobe(item)

                if hasWishlist, item.wishedAt == nil, let referenceDate {
                    item.wishedAt = referenceDate
                    hasChanges = true
                }
                if hasCloset, !hasWishlist, item.purchasedAt == nil, let referenceDate {
                    item.purchasedAt = referenceDate
                    hasChanges = true
                }
                if hasCloset, !hasWishlist, item.wishedAt != nil, item.purchasedAt == nil {
                    item.purchasedAt = item.updatedAt ?? referenceDate
                    hasChanges = true
                }
            }
            if hasChanges {
                try context.save()
            }
            UserDefaults.standard.set(true, forKey: migrationKey)
            print("✅ Item lifecycle date migration completed")
        } catch {
            print("❌ Item lifecycle date migration failed: \(error)")
        }
    }
}

// MARK: - Wardrobe delete confirmation (closet / wishlist)

/// Alert title when deleting a non-default wardrobe, e.g. `Delete 'Vacation'?`
func wardrobeDeleteAlertTitle(pendingDelete: Wardrobe?, fallbackTitle: String) -> String {
    guard let wardrobe = pendingDelete else { return fallbackTitle }
    let trimmed = (wardrobe.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let displayName = trimmed.isEmpty ? "Untitled" : trimmed
    return "Delete '\(displayName)'?"
}

/// Body copy for deleting a non-default closet or wishlist. `userWardrobesSameKind` should be the signed-in user’s rows of that type (e.g. `userClosets` / `userWishlists`) so the default’s **display name** reflects renames.
func wardrobeDeleteConfirmationMessage(
    pendingDelete: Wardrobe?,
    userWardrobesSameKind: [Wardrobe],
    fallbackDefaultDisplayName: String
) -> String {
    guard let wardrobe = pendingDelete else {
        return "This action is permanent and cannot be undone."
    }
    let primary = WardrobeBootstrap.primaryWardrobe(in: userWardrobesSameKind)
    let defaultTrimmed = (primary?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let defaultDisplay = defaultTrimmed.isEmpty ? fallbackDefaultDisplayName : defaultTrimmed
    return """
This action is permanent and cannot be undone.

The items and outfits in this wardrobe will remain in your \(defaultDisplay).
"""
}

/// Helper function to soft delete an entity (sets isSoftDeleted = true)
func softDelete<T: NSManagedObject>(_ entity: T) {
    // Check if entity has isSoftDeleted property
    if entity.entity.attributesByName["isSoftDeleted"] != nil {
        entity.setValue(true, forKey: "isSoftDeleted")
        setUpdatedAt(entity)
    } else {
        // Fallback to hard delete if entity doesn't support soft delete
        entity.managedObjectContext?.delete(entity)
    }
}

/// Helper function to restore a soft-deleted entity
func restoreSoftDeleted<T: NSManagedObject>(_ entity: T) {
    if entity.entity.attributesByName["isSoftDeleted"] != nil {
        entity.setValue(false, forKey: "isSoftDeleted")
        setUpdatedAt(entity)
    }
}

/// Helper function to check if entity is soft deleted
func isSoftDeleted<T: NSManagedObject>(_ entity: T) -> Bool {
    guard entity.entity.attributesByName["isSoftDeleted"] != nil,
          let isDeleted = entity.value(forKey: "isSoftDeleted") as? Bool else {
        return false
    }
    return isDeleted
}

// MARK: - Outfit wardrobe visibility

extension Outfit {
    /// Whether this outfit appears in the given wardrobe tab (matches `ItemGridView.fetchOutfits` rules).
    func isVisible(in selectedWardrobe: Wardrobe) -> Bool {
        guard let items = items as? Set<Item>, !items.isEmpty else { return false }

        let isWishlist = selectedWardrobe.type?.lowercased() == "wishlist"
        if isWishlist {
            let hasItemFromThisWishlist = items.contains { item in
                guard let wardrobes = item.wardrobes as? Set<Wardrobe> else { return false }
                return wardrobes.contains(selectedWardrobe)
            }
            guard hasItemFromThisWishlist else { return false }
            return items.allSatisfy { item in
                guard let wardrobes = item.wardrobes as? Set<Wardrobe> else { return false }
                let wishlistWardrobes = wardrobes.filter { $0.type?.lowercased() == "wishlist" }
                if wishlistWardrobes.isEmpty { return true }
                return wishlistWardrobes.contains(selectedWardrobe)
            }
        }

        return items.allSatisfy { item in
            guard let wardrobes = item.wardrobes as? Set<Wardrobe> else { return false }
            return wardrobes.contains(selectedWardrobe)
        }
    }

    /// Whether this outfit originated from a Redress suggestion (accepted / materialized).
    var isRedressOutfit: Bool {
        redressSuggestedAt != nil
            || redressSuggesterUsername != nil
            || redressSuggesterDisplayName != nil
            || redressSuggesterUserId != nil
    }

    /// Sorted active item ids for duplicate outfit comparison (matches Supabase `outfit_active_item_ids` semantics).
    var activeItemIdsSorted: [UUID] {
        guard let items = items as? Set<Item> else { return [] }
        return items
            .filter { $0.isSoftDeleted != true && $0.isDraft != true }
            .compactMap(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }
}

/// Finds a saved outfit owned by `userId` whose active item set exactly matches `itemIds`.
func findDuplicateOutfit(
    matchingItemIds itemIds: [UUID],
    userId: String,
    excluding excludedOutfits: [Outfit] = [],
    in context: NSManagedObjectContext
) -> Outfit? {
    let targetIds = itemIds.sorted { $0.uuidString < $1.uuidString }
    guard !targetIds.isEmpty else { return nil }

    let excludedObjectIDs = Set(excludedOutfits.map(\.objectID))

    let request = NSFetchRequest<Outfit>(entityName: "Outfit")
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
        NSPredicate(format: "userId == %@", userId),
        NSPredicate(format: "isDraft != YES"),
        NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
    ])

    guard let outfits = try? context.fetch(request) else { return nil }

    return outfits.first { outfit in
        guard !excludedObjectIDs.contains(outfit.objectID) else { return false }
        return outfit.activeItemIdsSorted == targetIds
    }
}

/// Helper function to add soft delete filter to a predicate
/// Returns a compound predicate that excludes soft-deleted items
func addSoftDeleteFilter(to predicate: NSPredicate?, entityName: String) -> NSPredicate {
    let softDeleteFilter = NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
    
    if let existing = predicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [existing, softDeleteFilter])
    } else {
        return softDeleteFilter
    }
}

/// Helper function to create a predicate that excludes soft-deleted items
func notSoftDeletedPredicate() -> NSPredicate {
    return NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
}

// MARK: - Reference list deduplication

/// User id for scoping reference-data pickers (same rule as `ItemFilterView`’s `currentUserId`): prefer the signed-in account, then non-empty `Item.userId` (e.g. drafts before session is stamped on the item).
func effectiveReferenceDataUserId(signedInUserId: UUID?, entityUserId: String?) -> String? {
    if let id = signedInUserId {
        return id.uuidString
    }
    let trimmed = entityUserId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

/// After user-scoped defaults are merged (`ReferenceDataBootstrap`), legacy rows with `userId == nil` can still match "used by my items" while new rows match `userId == preferredUserId`, so the same display name appears twice in pickers. Prefer the user-scoped row when names collide (case-insensitive).
func dedupeNamedReferenceRows<T: NSManagedObject>(_ rows: [T], preferredUserId: String) -> [T] {
    var bestByKey: [String: T] = [:]
    for row in rows {
        let rawName = (row.value(forKey: "name") as? String) ?? ""
        let key = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { continue }
        let uid = (row.value(forKey: "userId") as? String) ?? ""
        if let existing = bestByKey[key] {
            let existingUid = (existing.value(forKey: "userId") as? String) ?? ""
            let newIsOwned = uid == preferredUserId
            let oldIsOwned = existingUid == preferredUserId
            if newIsOwned && !oldIsOwned {
                bestByKey[key] = row
            }
        } else {
            bestByKey[key] = row
        }
    }
    return bestByKey.values.sorted { a, b in
        let na = (a.value(forKey: "name") as? String) ?? ""
        let nb = (b.value(forKey: "name") as? String) ?? ""
        return na.localizedCaseInsensitiveCompare(nb) == .orderedAscending
    }
}

// MARK: - Reference data lists (filters & attribute pickers)

extension NSManagedObjectContext {
    fileprivate static let activeItemSubquery = "$i.userId == %@ AND ($i.isSoftDeleted != YES OR $i.isSoftDeleted == nil)"

    fileprivate func dedupeIfScoped<T: NSManagedObject>(_ rows: [T], userId: String?) -> [T] {
        guard let uid = userId else { return rows }
        return dedupeNamedReferenceRows(rows, preferredUserId: uid)
    }

    /// `relationshipName` is the to-many Item key on the entity (`items` for Brand/Color/Size, `item` for Location).
    private func itemsInWardrobeScopePredicate(
        relationshipName: String,
        wardrobes: [Wardrobe],
        userId uid: String
    ) -> NSPredicate {
        let format: String
        if wardrobes.isEmpty {
            format = "SUBQUERY(\(relationshipName), $i, \(Self.activeItemSubquery)).@count > 0"
            return NSPredicate(format: format, uid)
        }
        let wardrobeClauses = wardrobes.map { _ in "ANY $i.wardrobes == %@" }.joined(separator: " AND ")
        format = "SUBQUERY(\(relationshipName), $i, \(Self.activeItemSubquery) AND \(wardrobeClauses)).@count > 0"
        var args: [Any] = [uid]
        args.append(contentsOf: wardrobes)
        return NSPredicate(format: format, argumentArray: args)
    }

    private func itemInWardrobeScope(_ item: Item, wardrobes: [Wardrobe], userId uid: String) -> Bool {
        guard item.userId == uid, item.isSoftDeleted != true else { return false }
        guard !wardrobes.isEmpty else { return true }
        let itemWardrobes = item.wardrobes as? Set<Wardrobe> ?? []
        return wardrobes.allSatisfy { required in
            itemWardrobes.contains { $0.objectID == required.objectID }
        }
    }

    /// Categories linked to the user's non-deleted items; deduped by display name.
    func fetchCategoriesForFilterList(userId: String?, wardrobes: [Wardrobe] = []) throws -> [Category] {
        guard let uid = userId, !uid.isEmpty else { return [] }
        let request = NSFetchRequest<Category>(entityName: "Category")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
        request.predicate = itemsInWardrobeScopePredicate(relationshipName: "items", wardrobes: wardrobes, userId: uid)
        return dedupeIfScoped(try fetch(request), userId: uid)
    }

    /// Subcategories linked to the user's items; deduped and sorted like `CategoryFilterListView`.
    func sortedSubcategoriesForFilterList(
        _ category: Category,
        userId: String?,
        wardrobes: [Wardrobe] = []
    ) -> [Subcategory] {
        let set = (category.subcategories as? Set<Subcategory>) ?? []
        let filtered: [Subcategory]
        if let uid = userId, !uid.isEmpty {
            filtered = set.filter { sub in
                let items = sub.items as? Set<Item> ?? []
                return items.contains { itemInWardrobeScope($0, wardrobes: wardrobes, userId: uid) }
            }
        } else {
            filtered = []
        }
        let deduped = dedupeIfScoped(filtered, userId: userId)
        return deduped.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return ($0.name ?? "") < ($1.name ?? "")
        }
    }

    /// Categories owned by the user (attribute pickers & bulk set category). Deduped by display name.
    func fetchCategoriesForAttributePicker(userId: String) throws -> [Category] {
        guard !userId.isEmpty else { return [] }
        let request = NSFetchRequest<Category>(entityName: "Category")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
        request.predicate = NSPredicate(format: "userId == %@ AND isVisible == YES", userId)
        return dedupeNamedReferenceRows(try fetch(request), preferredUserId: userId)
    }

    /// Subcategories for a category owned by the user. Deduped by display name.
    func sortedSubcategoriesForAttributePicker(_ category: Category, userId: String) -> [Subcategory] {
        guard !userId.isEmpty else { return [] }
        let request = NSFetchRequest<Subcategory>(entityName: "Subcategory")
        request.predicate = NSPredicate(
            format: "category == %@ AND userId == %@ AND isVisible == YES",
            category,
            userId
        )
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Subcategory.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Subcategory.name, ascending: true)
        ]
        do {
            let subs = try fetch(request)
            return dedupeNamedReferenceRows(subs, preferredUserId: userId).sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return ($0.name ?? "") < ($1.name ?? "")
            }
        } catch {
            print("❌ Failed to fetch subcategories: \(error.localizedDescription)")
            return []
        }
    }

    /// Maps an assigned category to the canonical user-scoped picker row when legacy duplicates exist.
    func canonicalCategoryForAttributePicker(_ category: Category, userId: String) -> Category {
        guard !userId.isEmpty else { return category }
        if let list = try? fetchCategoriesForAttributePicker(userId: userId),
           let resolved = resolveCategoryInPickerList(category, categories: list) {
            return resolved
        }
        return category
    }

    /// Maps an assigned subcategory to the canonical picker row under the canonical parent category.
    func canonicalSubcategoryForAttributePicker(
        _ subcategory: Subcategory,
        parent: Category,
        userId: String
    ) -> Subcategory {
        guard !userId.isEmpty else { return subcategory }
        let canonicalParent = canonicalCategoryForAttributePicker(parent, userId: userId)
        let subs = sortedSubcategoriesForAttributePicker(canonicalParent, userId: userId)
        if let resolved = resolveSubcategoryInPickerList(subcategory, subcategories: subs) {
            return resolved
        }
        return subcategory
    }
}

// MARK: - Category picker identity (stable id + duplicate rows)

/// Whether a subcategory belongs to a picker category row (matches id, object, or display name).
func subcategoryBelongsToPickerCategory(_ subcategory: Subcategory, listCategory: Category) -> Bool {
    guard let parent = subcategory.category else { return false }
    if parent.objectID == listCategory.objectID { return true }
    if let parentId = parent.id, let listId = listCategory.id, parentId == listId { return true }
    return (parent.name ?? "").localizedCaseInsensitiveCompare(listCategory.name ?? "") == .orderedSame
}

/// Resolves an assigned category to the row shown in a deduped picker list.
func resolveCategoryInPickerList(_ category: Category, categories: [Category]) -> Category? {
    if let id = category.id, let match = categories.first(where: { $0.id == id }) {
        return match
    }
    if let match = categories.first(where: { $0.objectID == category.objectID }) {
        return match
    }
    if let name = category.name, !name.isEmpty,
       let match = categories.first(where: {
           ($0.name ?? "").localizedCaseInsensitiveCompare(name) == .orderedSame
       }) {
        return match
    }
    return nil
}

/// Resolves an assigned subcategory to the row shown under a picker category.
func resolveSubcategoryInPickerList(_ subcategory: Subcategory, subcategories: [Subcategory]) -> Subcategory? {
    if let id = subcategory.id, let match = subcategories.first(where: { $0.id == id }) {
        return match
    }
    if let match = subcategories.first(where: { $0.objectID == subcategory.objectID }) {
        return match
    }
    if let name = subcategory.name, !name.isEmpty,
       let match = subcategories.first(where: {
           ($0.name ?? "").localizedCaseInsensitiveCompare(name) == .orderedSame
       }) {
        return match
    }
    return nil
}

/// Whether two picker categories represent the same assignment (stable id, then name).
func pickerCategoriesMatch(_ lhs: Category?, _ rhs: Category?) -> Bool {
    guard let lhs, let rhs else { return lhs == nil && rhs == nil }
    if let lid = lhs.id, let rid = rhs.id { return lid == rid }
    if lhs.objectID == rhs.objectID { return true }
    return (lhs.name ?? "").localizedCaseInsensitiveCompare(rhs.name ?? "") == .orderedSame
}

/// Whether two picker subcategories represent the same assignment (stable id, then name).
func pickerSubcategoriesMatch(_ lhs: Subcategory?, _ rhs: Subcategory?) -> Bool {
    guard let lhs, let rhs else { return lhs == nil && rhs == nil }
    if let lid = lhs.id, let rid = rhs.id { return lid == rid }
    if lhs.objectID == rhs.objectID { return true }
    return (lhs.name ?? "").localizedCaseInsensitiveCompare(rhs.name ?? "") == .orderedSame
}

extension NSManagedObjectContext {

    /// Colors on items in the given wardrobe scope (at least one non-draft, non-deleted item per color).
    private func fetchColorsUsedOnItemsInWardrobeScope(
        userId uid: String,
        wardrobes: [Wardrobe],
        wardrobeType: String?
    ) throws -> [AppColor] {
        var itemPredicates: [NSPredicate] = [
            NSPredicate(format: "userId == %@", uid),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil"),
            NSPredicate(format: "isDraft != YES"),
        ]
        if !wardrobes.isEmpty {
            let wardrobeMembership = wardrobes.map { NSPredicate(format: "ANY wardrobes == %@", $0) }
            if wardrobeMembership.count == 1 {
                itemPredicates.append(wardrobeMembership[0])
            } else {
                itemPredicates.append(NSCompoundPredicate(andPredicateWithSubpredicates: wardrobeMembership))
            }
        } else if let wardrobeType {
            itemPredicates.append(NSPredicate(format: "ANY wardrobes.type == %@", wardrobeType))
        }

        let itemRequest = NSFetchRequest<Item>(entityName: "Item")
        itemRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: itemPredicates)
        itemRequest.relationshipKeyPathsForPrefetching = ["colors"]
        let items = try fetch(itemRequest)

        var seenNames = Set<String>()
        var colors: [AppColor] = []
        for item in items {
            guard let itemColors = item.colors as? Set<AppColor> else { continue }
            for color in itemColors where color.isVisible {
                let name = (color.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let key = name.lowercased()
                guard !seenNames.contains(key) else { continue }
                seenNames.insert(key)
                colors.append(color)
            }
        }
        return dedupeIfScoped(colors, userId: uid).sorted {
            ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
        }
    }

    /// Visible colors for filter lists. When `itemsOnly` is true, only colors on items in `wardrobes` appear (ItemFilterView). When false, the user's catalog plus used colors appear (item add pickers).
    func fetchColorsForFilterList(
        userId: String?,
        itemsOnly: Bool = false,
        wardrobeType: String? = nil,
        wardrobes: [Wardrobe] = []
    ) throws -> [AppColor] {
        guard let uid = userId, !uid.isEmpty else { return [] }
        if itemsOnly {
            return try fetchColorsUsedOnItemsInWardrobeScope(
                userId: uid,
                wardrobes: wardrobes,
                wardrobeType: wardrobeType
            )
        }
        let request = NSFetchRequest<AppColor>(entityName: "Color")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AppColor.name, ascending: true)]
        let visible = NSPredicate(format: "isVisible == YES")
        let usedByUser = itemsInWardrobeScopePredicate(
            relationshipName: "items",
            wardrobes: wardrobes,
            userId: uid
        )
        let owned = NSPredicate(format: "userId == %@", uid)
        let scope = NSCompoundPredicate(orPredicateWithSubpredicates: [owned, usedByUser])
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [visible, scope])
        return dedupeIfScoped(try fetch(request), userId: uid)
    }

    /// Visible seasons owned by the user or linked to their items.
    func fetchSeasonsForFilterList(userId: String?) throws -> [Season] {
        let request = NSFetchRequest<Season>(entityName: "Season")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Season.name, ascending: true)]
        if let uid = userId {
            let visible = NSPredicate(format: "isVisible == YES")
            let owned = NSPredicate(format: "userId == %@", uid)
            let usedByUser = NSPredicate(
                format: "SUBQUERY(item, $i, \(Self.activeItemSubquery)).@count > 0",
                uid
            )
            let scope = NSCompoundPredicate(orPredicateWithSubpredicates: [owned, usedByUser])
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [visible, scope])
        }
        return dedupeIfScoped(try fetch(request), userId: userId)
    }

    /// Locations linked to the user's non-deleted items.
    func fetchLocationsForFilterList(userId: String?, wardrobes: [Wardrobe] = []) throws -> [Location] {
        guard let uid = userId, !uid.isEmpty else { return [] }
        return try fetchLocationsForItemPicker(userId: uid, wardrobes: wardrobes)
    }

    /// Sizes for filter lists. When `itemsOnly` is true, only sizes on the user's items appear (ItemFilterView).
    func fetchSizesForFilterList(
        userId: String?,
        itemsOnly: Bool = false,
        wardrobes: [Wardrobe] = []
    ) throws -> [Size] {
        guard let uid = userId, !uid.isEmpty else { return [] }
        let request = NSFetchRequest<Size>(entityName: "Size")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Size.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Size.value, ascending: true),
        ]
        let usedByUser = itemsInWardrobeScopePredicate(
            relationshipName: "items",
            wardrobes: wardrobes,
            userId: uid
        )
        if itemsOnly {
            request.predicate = usedByUser
        } else {
            let owned = NSPredicate(format: "userId == %@", uid)
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [owned, usedByUser])
        }
        // `Size` uses `value` (not `name`), so generic name-based dedupe is not applicable.
        // Callers (e.g. `SizeListView`) already dedupe by `value`.
        return try fetch(request)
    }

    /// Brands linked to the user's non-deleted items.
    func fetchBrandsForFilterList(userId: String?, wardrobes: [Wardrobe] = []) throws -> [Brand] {
        guard let uid = userId, !uid.isEmpty else { return [] }
        return try fetchBrandsForItemPicker(userId: uid, wardrobes: wardrobes)
    }

    /// Tags linked to the user's non-deleted items or outfits.
    func fetchTagsForFilterList(
        userId: String?,
        wardrobeType: String? = nil,
        wardrobes: [Wardrobe] = []
    ) throws -> [Tag] {
        guard let uid = userId, !uid.isEmpty else { return [] }
        return try fetchTagsForItemPicker(userId: uid, wardrobeType: wardrobeType, wardrobes: wardrobes)
    }

    /// Tags linked to the user's non-deleted outfits (strict outfit tags; excludes item tags).
    /// When `wardrobe` is set, only tags on outfits visible in that wardrobe tab are returned.
    func fetchOutfitTagsForFilterList(userId: String?, wardrobe: Wardrobe? = nil) throws -> [Tag] {
        guard let uid = userId, !uid.isEmpty else { return [] }

        if let wardrobe {
            let request = NSFetchRequest<Outfit>(entityName: "Outfit")
            request.predicate = NSPredicate(
                format: "userId == %@ AND isDraft != YES AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
                uid
            )
            let visibleOutfits = try fetch(request).filter { $0.isVisible(in: wardrobe) }

            var tagsByID: [NSManagedObjectID: Tag] = [:]
            for outfit in visibleOutfits {
                for tag in (outfit.tags as? Set<Tag>) ?? [] {
                    tagsByID[tag.objectID] = tag
                }
            }

            let sorted = tagsByID.values.sorted {
                ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
            }
            return dedupeIfScoped(sorted, userId: uid)
        }

        let request = NSFetchRequest<Tag>(entityName: "Tag")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]
        request.predicate = NSPredicate(
            format: "SUBQUERY(outfits, $o, $o.userId == %@ AND ($o.isSoftDeleted != YES OR $o.isSoftDeleted == nil)).@count > 0",
            uid
        )
        return dedupeIfScoped(try fetch(request), userId: uid)
    }

    /// Outfit categories linked to the user's visible outfits (non-draft, non-deleted).
    /// When `wardrobe` is set, only categories on outfits visible in that wardrobe tab are returned.
    func fetchOutfitCategoriesForFilterList(userId: String?, wardrobe: Wardrobe? = nil) throws -> [OutfitCategory] {
        guard let uid = userId, !uid.isEmpty else { return [] }

        if let wardrobe {
            let request = NSFetchRequest<Outfit>(entityName: "Outfit")
            request.predicate = NSPredicate(
                format: "userId == %@ AND isDraft != YES AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
                uid
            )
            let visibleOutfits = try fetch(request).filter { $0.isVisible(in: wardrobe) }

            var categoriesByID: [NSManagedObjectID: OutfitCategory] = [:]
            for outfit in visibleOutfits {
                if let category = outfit.category {
                    categoriesByID[category.objectID] = category
                }
            }

            let sorted = categoriesByID.values.sorted {
                ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
            }
            return dedupeIfScoped(sorted, userId: uid)
        }

        return try fetchOutfitCategoriesForAttributePicker(userId: uid)
    }

    /// Outfit categories linked to the user's visible outfits (non-draft, non-deleted).
    func fetchOutfitCategoriesForAttributePicker(userId: String) throws -> [OutfitCategory] {
        let request = NSFetchRequest<OutfitCategory>(entityName: "OutfitCategory")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \OutfitCategory.name, ascending: true)]
        request.predicate = NSPredicate(
            format: "SUBQUERY(outfits, $o, $o.userId == %@ AND $o.isDraft != YES AND ($o.isSoftDeleted != YES OR $o.isSoftDeleted == nil)).@count > 0",
            userId
        )
        return dedupeIfScoped(try fetch(request), userId: userId)
    }

    /// Finds or creates an outfit category for the given user (case-insensitive name match).
    func fetchOrCreateOutfitCategory(named name: String, userId: String) throws -> OutfitCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "OutfitCategory", code: 1, userInfo: [NSLocalizedDescriptionKey: "Category name cannot be empty"])
        }
        let request = NSFetchRequest<OutfitCategory>(entityName: "OutfitCategory")
        request.predicate = NSPredicate(format: "userId == %@ AND name ==[c] %@", userId, trimmed)
        request.fetchLimit = 1
        if let existing = try fetch(request).first {
            return existing
        }
        let category = OutfitCategory(context: self)
        category.id = UUID()
        category.name = trimmed
        category.userId = userId
        setUpdatedAt(category)
        return category
    }

    /// Brands linked to the user's non-deleted items (excludes unused seeded defaults like "Other").
    func fetchBrandsForItemPicker(
        userId uid: String,
        includingBrandOn item: Item? = nil,
        wardrobes: [Wardrobe] = []
    ) throws -> [Brand] {
        let request = NSFetchRequest<Brand>(entityName: "Brand")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Brand.name, ascending: true)]
        let visible = NSPredicate(format: "isVisible == YES")
        let usedByUser = itemsInWardrobeScopePredicate(
            relationshipName: "items",
            wardrobes: wardrobes,
            userId: uid
        )
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [visible, usedByUser])
        var result = dedupeIfScoped(try fetch(request), userId: uid)
        if let brand = item?.brand,
           !result.contains(where: { $0.objectID == brand.objectID }) {
            result.append(brand)
            result.sort { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
        }
        return result
    }

    /// Locations linked to the user's non-deleted items (excludes unused seeded defaults like "Closet").
    func fetchLocationsForItemPicker(
        userId uid: String,
        includingLocationOn item: Item? = nil,
        wardrobes: [Wardrobe] = []
    ) throws -> [Location] {
        let request = NSFetchRequest<Location>(entityName: "Location")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Location.name, ascending: true)]
        let usedByUser = itemsInWardrobeScopePredicate(
            relationshipName: "item",
            wardrobes: wardrobes,
            userId: uid
        )
        request.predicate = usedByUser
        var result = dedupeIfScoped(try fetch(request), userId: uid)
        if let location = item?.location,
           !result.contains(where: { $0.objectID == location.objectID }) {
            result.append(location)
            result.sort { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
        }
        return result
    }

    /// Tags linked to the user's non-deleted items or outfits.
    func fetchTagsForItemPicker(
        userId uid: String,
        wardrobeType: String? = nil,
        includingTagsOn item: Item? = nil,
        wardrobes: [Wardrobe] = []
    ) throws -> [Tag] {
        let request = NSFetchRequest<Tag>(entityName: "Tag")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]
        if !wardrobes.isEmpty {
            request.predicate = itemsInWardrobeScopePredicate(
                relationshipName: "items",
                wardrobes: wardrobes,
                userId: uid
            )
        } else {
            let usedByUserItems: NSPredicate
            if let wardrobeType {
                usedByUserItems = NSPredicate(
                    format: "SUBQUERY(items, $i, ANY $i.wardrobes.type == %@ AND \(Self.activeItemSubquery)).@count > 0",
                    wardrobeType,
                    uid
                )
            } else {
                usedByUserItems = NSPredicate(
                    format: "SUBQUERY(items, $i, \(Self.activeItemSubquery)).@count > 0",
                    uid
                )
            }
            let usedByUserOutfits = NSPredicate(
                format: "SUBQUERY(outfits, $o, $o.userId == %@ AND ($o.isSoftDeleted != YES OR $o.isSoftDeleted == nil)).@count > 0",
                uid
            )
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [usedByUserItems, usedByUserOutfits])
        }
        var result = try fetch(request)
        if let itemTags = item?.tags as? Set<Tag> {
            for tag in itemTags where !result.contains(where: { $0.objectID == tag.objectID }) {
                result.append(tag)
            }
            result.sort { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
        }
        return result
    }
}

// MARK: - Calendar events (user scope)

/// Infer `userId` from items linked to the event (ordered), then from outfits.
func inferredUserIdForEvent(_ event: Event) -> String? {
    if let ordered = event.items as? NSOrderedSet {
        for case let item as Item in ordered {
            if let u = item.userId, !u.isEmpty { return u }
        }
    }
    if let outfits = event.outfits as? Set<Outfit> {
        for outfit in outfits {
            if let u = outfit.userId, !u.isEmpty { return u }
        }
    }
    return nil
}

/// Sets `event.userId` when missing, using linked items/outfits so the event matches the owning account.
func syncEventUserIdFromLinkedEntities(_ event: Event) {
    guard event.userId == nil || (event.userId ?? "").isEmpty else { return }
    guard let uid = inferredUserIdForEvent(event) else { return }
    event.userId = uid
    setUpdatedAt(event)
}

/// Deletes a tag from Core Data and Supabase if it has no remaining items or outfits.
/// Call after removing a tag from an item or outfit (main context only).
func cleanupTagIfOrphaned(_ tag: Tag) {
    guard let context = tag.managedObjectContext, context.parent == nil else { return }
    context.refresh(tag, mergeChanges: true)
    let itemsEmpty = (tag.items as? Set<Item>)?.isEmpty ?? true
    let outfitsEmpty = (tag.outfits as? Set<Outfit>)?.isEmpty ?? true
    guard itemsEmpty && outfitsEmpty else { return }
    let tagName = tag.name ?? "unknown"
    guard let tagId = tag.id else { return }
    context.delete(tag)
    do {
        try context.save()
        SyncService.shared.deleteTagFromSupabase(tagId: tagId)
        print("✅ Cleaned up orphaned tag: \(tagName)")
    } catch {
        print("❌ Failed to cleanup orphaned tag: \(error)")
    }
}

/// Deletes an outfit category from Core Data and Supabase if no outfits reference it.
/// Call after removing a category from an outfit (main context only).
func cleanupOutfitCategoryIfOrphaned(_ category: OutfitCategory) {
    guard let context = category.managedObjectContext, context.parent == nil else { return }
    context.refresh(category, mergeChanges: true)
    let outfitsEmpty = (category.outfits as? Set<Outfit>)?.isEmpty ?? true
    guard outfitsEmpty else { return }
    let categoryName = category.name ?? "unknown"
    guard let categoryId = category.id else { return }
    context.delete(category)
    do {
        try context.save()
        SyncService.shared.deleteOutfitCategoryFromSupabase(categoryId: categoryId)
        print("✅ Cleaned up orphaned outfit category: \(categoryName)")
    } catch {
        print("❌ Failed to cleanup orphaned outfit category: \(error)")
    }
}

// MARK: - Event wear history (calendar)

func eventEffectiveEndDate(_ event: Event) -> Date? {
    event.endDate ?? event.startDate
}

func isEligiblePastWornEvent(_ event: Event, now: Date = Date()) -> Bool {
    if isSoftDeleted(event) { return false }
    guard let end = eventEffectiveEndDate(event) else { return false }
    return end <= now
}

func wornEventHistoryLabel(for event: Event) -> String {
    let trimmedName = event.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmedName.isEmpty ? "Worn to Event" : "Worn to \(trimmedName)"
}

func wornEventHistoryLocationCaption(for event: Event) -> String? {
    let trimmed = event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

/// Whether an outfit still features this item (`outfit.items` or canvas `transformationData`).
func outfitFeaturesItem(_ outfit: Outfit, item: Item) -> Bool {
    if let items = outfit.items as? Set<Item> {
        if let itemID = item.id {
            if items.contains(where: { $0.id == itemID }) { return true }
        } else if items.contains(item) {
            return true
        }
    }

    guard let transformationData = outfit.transformationData,
          let savedItems = try? JSONDecoder().decode([SavedOutfitItem].self, from: transformationData) else {
        return false
    }

    let itemUUID = item.id?.uuidString
    let itemObjectURI = item.objectID.uriRepresentation().absoluteString
    return savedItems.contains { saved in
        if let itemUUID, saved.itemID == itemUUID { return true }
        return saved.itemID == itemObjectURI
    }
}

/// Outfits that reference this item (inverse link and/or `outfit.items` membership).
func outfitsFeaturingItem(_ item: Item) -> [Outfit] {
    var byObjectID: [NSManagedObjectID: Outfit] = [:]

    if let linkedOutfits = item.outfits as? NSSet {
        for case let outfit as Outfit in linkedOutfits {
            byObjectID[outfit.objectID] = outfit
        }
    }

    if let context = item.managedObjectContext {
        let request = NSFetchRequest<Outfit>(entityName: "Outfit")
        var predicates: [NSPredicate] = [
            NSPredicate(format: "ANY items == %@", item),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        ]
        if let userId = item.userId, !userId.isEmpty {
            predicates.append(NSPredicate(format: "userId == %@", userId))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        if let fetched = try? context.fetch(request) {
            for outfit in fetched {
                byObjectID[outfit.objectID] = outfit
            }
        }
    }

    return Array(byObjectID.values)
}

/// Past calendar events this item is tied to (directly or via outfit), deduped by event id.
func pastWornEvents(for item: Item, now: Date = Date()) -> [Event] {
    var byEventID: [UUID: Event] = [:]

    if let linkedEvents = item.events as? NSSet {
        for case let event as Event in linkedEvents {
            guard let eventID = event.id,
                  isEligiblePastWornEvent(event, now: now) else { continue }
            byEventID[eventID] = event
        }
    }

    for outfit in outfitsFeaturingItem(item) {
        if isSoftDeleted(outfit) { continue }
        guard outfitFeaturesItem(outfit, item: item) else { continue }

        if let outfitEvents = outfit.events as? Set<Event> {
            for event in outfitEvents {
                guard let eventID = event.id,
                      isEligiblePastWornEvent(event, now: now) else { continue }
                byEventID[eventID] = event
            }
        }
    }

    return byEventID.values.sorted {
        let left = eventEffectiveEndDate($0) ?? .distantPast
        let right = eventEffectiveEndDate($1) ?? .distantPast
        return left > right
    }
}

/// Past calendar events this outfit is tied to directly, deduped by event id.
func pastWornEvents(for outfit: Outfit, now: Date = Date()) -> [Event] {
    if isSoftDeleted(outfit) { return [] }

    var byEventID: [UUID: Event] = [:]

    if let linkedEvents = outfit.events as? Set<Event> {
        for event in linkedEvents {
            guard let eventID = event.id,
                  isEligiblePastWornEvent(event, now: now) else { continue }
            byEventID[eventID] = event
        }
    }

    return byEventID.values.sorted {
        let left = eventEffectiveEndDate($0) ?? .distantPast
        let right = eventEffectiveEndDate($1) ?? .distantPast
        return left > right
    }
}

// MARK: - UserProfile avatar URL

extension UserProfile {
    /// Matches `avatarUrl` on the Core Data entity (KVC avoids build failures if class codegen lags the model).
    static var avatarURLAttributeKey: String { "avatarUrl" }

    /// Trimmed public avatar URL, or nil if unset/blank.
    var storedProfileAvatarURL: String? {
        let raw = value(forKey: Self.avatarURLAttributeKey) as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    func setStoredProfileAvatarURL(_ url: String?) {
        setValue(url, forKey: Self.avatarURLAttributeKey)
    }

    static var styleTagsAttributeKey: String { "styleTags" }

    /// Decoded profile style tags (JSON array of raw values in Core Data).
    var profileStyleTags: [ProfileStyleTag] {
        get {
            guard let raw = value(forKey: Self.styleTagsAttributeKey) as? String,
                  !raw.isEmpty,
                  let data = raw.data(using: .utf8),
                  let strings = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return ProfileStyleTag.ordered(from: strings)
        }
        set {
            let limited = Array(newValue.prefix(ProfileStyleTag.maxSelectionCount))
            let strings = limited.map(\.rawValue)
            if strings.isEmpty {
                setValue(nil, forKey: Self.styleTagsAttributeKey)
                return
            }
            if let data = try? JSONEncoder().encode(strings),
               let json = String(data: data, encoding: .utf8) {
                setValue(json, forKey: Self.styleTagsAttributeKey)
            } else {
                setValue(nil, forKey: Self.styleTagsAttributeKey)
            }
        }
    }
}

