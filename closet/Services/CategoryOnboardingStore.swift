//
//  CategoryOnboardingStore.swift
//  closet
//
//  Per-user flag: category catalog was chosen during onboarding (not auto-seeded).
//

import CoreData
import Foundation

enum CategoryOnboardingStore {
    private static func key(for userId: UUID) -> String {
        "hasCompletedCategoryOnboarding.\(userId.uuidString)"
    }

    static func hasCompleted(userId: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: userId))
    }

    static func markCompleted(userId: UUID) {
        UserDefaults.standard.set(true, forKey: key(for: userId))
    }

    static func reset(userId: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: userId))
    }

    /// Existing installs that already have categories were onboarded before this flag existed.
    static func markCompletedIfLegacyUserHasCategories(userId: UUID, in context: NSManagedObjectContext) {
        guard !hasCompleted(userId: userId) else { return }
        let uid = userId.uuidString
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", uid)
        request.fetchLimit = 1
        if let count = try? context.count(for: request), count > 0 {
            markCompleted(userId: userId)
        }
    }
}
