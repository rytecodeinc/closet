//
//  WardrobeVisibility.swift
//  closet
//
//  Per-wardrobe visibility for profile sharing (synced to Supabase `wardrobes.visibility`).
//

import CoreData
import Foundation

enum WardrobeVisibility: String, CaseIterable, Identifiable {
    case `public` = "public"
    case `private` = "private"
    case friends = "friends"

    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .public: return "Public"
        case .private: return "Private"
        case .friends: return "Friends"
        }
    }

    var displayLabel: String { menuLabel.uppercased() }

    var iconName: String {
        switch self {
        case .public: return "lock.slash"
        case .private: return "lock.fill"
        case .friends: return "person.2"
        }
    }
}

extension Wardrobe {
    /// Defaults to `.public` when unset (existing wardrobes pre-migration).
    var wardrobeVisibility: WardrobeVisibility {
        get {
            WardrobeVisibility(rawValue: visibility ?? "") ?? .public
        }
        set {
            visibility = newValue.rawValue
        }
    }
}

enum WardrobeVisibilityPersistence {
    static func apply(_ visibility: WardrobeVisibility, to wardrobe: Wardrobe, userId: String?) {
        wardrobe.wardrobeVisibility = visibility
        setUpdatedAt(wardrobe)
        if (wardrobe.userId == nil || wardrobe.userId?.isEmpty == true), let userId {
            wardrobe.userId = userId
        }
    }

    static func saveAndSync(_ wardrobe: Wardrobe, in context: NSManagedObjectContext) {
        guard context.hasChanges else {
            SyncService.shared.syncWardrobeIfNeeded(wardrobe)
            return
        }
        do {
            try context.save()
            SyncService.shared.syncWardrobeIfNeeded(wardrobe)
        } catch {
            print("❌ Failed to save wardrobe visibility: \(error.localizedDescription)")
        }
    }
}
