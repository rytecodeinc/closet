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

