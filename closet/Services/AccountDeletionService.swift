//
//  AccountDeletionService.swift
//  closet
//
//  Removes all Core Data rows scoped to a user when they delete their account.
//

import CoreData
import Foundation

enum AccountDeletionService {
    /// Entity names that include a `userId` attribute matching the signed-in account.
    private static let userScopedEntityNames = [
        "PackingChecklistItem",
        "PackingChecklistSection",
        "PackingAssignment",
        "PackingStorageLocation",
        "Item",
        "Outfit",
        "Event",
        "Wardrobe",
        "Collection",
        "Brand",
        "Category",
        "Subcategory",
        "Color",
        "Season",
        "Size",
        "Tag",
        "Location",
        "UserProfile",
    ]

    static func wipeLocalData(for userId: String, in context: NSManagedObjectContext) throws {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        for name in userScopedEntityNames {
            try deleteAll(entityName: name, userId: trimmed, in: context)
        }

        try deleteOrphanedPhotos(in: context)
        try context.save()

        if let uuid = UUID(uuidString: trimmed) {
            ProfileAvatarLocalStorage.delete(userId: uuid)
            HowToOnboardingStore.reset(userId: uuid)
            CategoryOnboardingStore.reset(userId: uuid)
        }
    }

    private static func deleteAll(
        entityName: String,
        userId: String,
        in context: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "userId == %@", userId)
        let rows = try context.fetch(request)
        guard !rows.isEmpty else { return }
        for row in rows {
            context.delete(row)
        }
    }

    /// Photos are not user-scoped; remove any left without an item after items are deleted.
    private static func deleteOrphanedPhotos(in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<Photo>(entityName: "Photo")
        request.predicate = NSPredicate(format: "item == nil")
        let orphans = try context.fetch(request)
        for photo in orphans {
            context.delete(photo)
        }
    }
}
