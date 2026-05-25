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
    /// Maximum length for user-editable wardrobe (closet / wishlist) names.
    static let maxNameLength = 17

    /// Trims whitespace and clamps length for names entered in the UI.
    /// Returns empty string if the trimmed name is empty (caller should reject saves).
    static func normalizedUserName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= maxNameLength { return trimmed }
        return String(trimmed.prefix(maxNameLength))
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

    /// Categories linked to the user's non-deleted items; deduped by display name.
    func fetchCategoriesForFilterList(userId: String?) throws -> [Category] {
        guard let uid = userId, !uid.isEmpty else { return [] }
        let request = NSFetchRequest<Category>(entityName: "Category")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
        let usedByUserItems = NSPredicate(
            format: "SUBQUERY(items, $i, \(Self.activeItemSubquery)).@count > 0",
            uid
        )
        request.predicate = usedByUserItems
        return dedupeIfScoped(try fetch(request), userId: uid)
    }

    /// Subcategories linked to the user's items; deduped and sorted like `CategoryFilterListView`.
    func sortedSubcategoriesForFilterList(_ category: Category, userId: String?) -> [Subcategory] {
        let set = (category.subcategories as? Set<Subcategory>) ?? []
        let filtered: [Subcategory]
        if let uid = userId, !uid.isEmpty {
            filtered = set.filter { sub in
                let items = sub.items as? Set<Item> ?? []
                return items.contains {
                    $0.userId == uid && ($0.isSoftDeleted != true)
                }
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

    /// Categories owned by the user (attribute pickers & bulk set category). Not deduped.
    func fetchCategoriesForAttributePicker(userId: String) throws -> [Category] {
        guard !userId.isEmpty else { return [] }
        let request = NSFetchRequest<Category>(entityName: "Category")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
        request.predicate = NSPredicate(format: "userId == %@", userId)
        return try fetch(request)
    }

    /// Subcategories for a category owned by the user. Not deduped.
    func sortedSubcategoriesForAttributePicker(_ category: Category, userId: String) -> [Subcategory] {
        guard !userId.isEmpty else { return [] }
        let request = NSFetchRequest<Subcategory>(entityName: "Subcategory")
        request.predicate = NSPredicate(format: "category == %@ AND userId == %@", category, userId)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Subcategory.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Subcategory.name, ascending: true)
        ]
        do {
            return try fetch(request)
        } catch {
            print("❌ Failed to fetch subcategories: \(error.localizedDescription)")
            return []
        }
    }

    /// Visible colors for filter lists. When `itemsOnly` is true, only colors on the user's items appear (ItemFilterView). When false, the user's catalog plus used colors appear (item add pickers).
    func fetchColorsForFilterList(userId: String?, itemsOnly: Bool = false) throws -> [AppColor] {
        guard let uid = userId, !uid.isEmpty else { return [] }
        let request = NSFetchRequest<AppColor>(entityName: "Color")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AppColor.name, ascending: true)]
        let visible = NSPredicate(format: "isVisible == YES")
        let usedByUser = NSPredicate(
            format: "SUBQUERY(items, $i, \(Self.activeItemSubquery)).@count > 0",
            uid
        )
        let scope: NSPredicate
        if itemsOnly {
            scope = usedByUser
        } else {
            let owned = NSPredicate(format: "userId == %@", uid)
            scope = NSCompoundPredicate(orPredicateWithSubpredicates: [owned, usedByUser])
        }
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
    func fetchLocationsForFilterList(userId: String?) throws -> [Location] {
        guard let uid = userId, !uid.isEmpty else { return [] }
        return try fetchLocationsForItemPicker(userId: uid)
    }

    /// Sizes for filter lists. When `itemsOnly` is true, only sizes on the user's items appear (ItemFilterView).
    func fetchSizesForFilterList(userId: String?, itemsOnly: Bool = false) throws -> [Size] {
        guard let uid = userId, !uid.isEmpty else { return [] }
        let request = NSFetchRequest<Size>(entityName: "Size")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Size.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Size.value, ascending: true),
        ]
        let usedByUser = NSPredicate(
            format: "SUBQUERY(items, $i, \(Self.activeItemSubquery)).@count > 0",
            uid
        )
        if itemsOnly {
            request.predicate = usedByUser
        } else {
            let owned = NSPredicate(format: "userId == %@", uid)
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [owned, usedByUser])
        }
        return dedupeIfScoped(try fetch(request), userId: uid)
    }

    /// Brands linked to the user's non-deleted items.
    func fetchBrandsForFilterList(userId: String?) throws -> [Brand] {
        guard let uid = userId, !uid.isEmpty else { return [] }
        return try fetchBrandsForItemPicker(userId: uid)
    }

    /// Tags linked to the user's non-deleted items or outfits.
    func fetchTagsForFilterList(userId: String?, wardrobeType: String?) throws -> [Tag] {
        guard let uid = userId, !uid.isEmpty else { return [] }
        return try fetchTagsForItemPicker(userId: uid, wardrobeType: wardrobeType)
    }

    /// Brands linked to the user's non-deleted items (excludes unused seeded defaults like "Other").
    func fetchBrandsForItemPicker(userId uid: String, includingBrandOn item: Item? = nil) throws -> [Brand] {
        let request = NSFetchRequest<Brand>(entityName: "Brand")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Brand.name, ascending: true)]
        let visible = NSPredicate(format: "isVisible == YES")
        let usedByUser = NSPredicate(
            format: "SUBQUERY(items, $i, \(Self.activeItemSubquery)).@count > 0",
            uid
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
    func fetchLocationsForItemPicker(userId uid: String, includingLocationOn item: Item? = nil) throws -> [Location] {
        let request = NSFetchRequest<Location>(entityName: "Location")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Location.name, ascending: true)]
        let usedByUser = NSPredicate(
            format: "SUBQUERY(item, $i, \(Self.activeItemSubquery)).@count > 0",
            uid
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
        includingTagsOn item: Item? = nil
    ) throws -> [Tag] {
        let request = NSFetchRequest<Tag>(entityName: "Tag")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]
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
}

