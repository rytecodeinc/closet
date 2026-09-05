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
        case .public: return "lock.open"
        case .private: return "lock.fill"
        case .friends: return "person.2"
        }
    }

    /// Profile / read-only surfaces. Private is never shown; friends-only is shown to friends and the owner.
    func isVisibleOnPublicProfile(viewerIsOwner: Bool, viewerIsFriend: Bool) -> Bool {
        switch self {
        case .public:
            return true
        case .friends:
            return viewerIsOwner || viewerIsFriend
        case .private:
            return false
        }
    }

    /// Profile calendar strip visibility for **hosted** events.
    /// - public: anyone viewing the host profile
    /// - friends: host's friends, and friends of accepted guests (when that audience is wired)
    /// - private: host only — does **not** appear on guest profiles
    func isVisibleOnProfileCalendar(viewerIsOwner: Bool, viewerIsFriend: Bool) -> Bool {
        switch self {
        case .public:
            return true
        case .friends:
            return viewerIsOwner || viewerIsFriend
        case .private:
            return viewerIsOwner
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

extension Event {
    /// Defaults to `.private` when unset (calendar events are private by default).
    var eventVisibility: WardrobeVisibility {
        get {
            WardrobeVisibility(rawValue: visibility ?? "") ?? .private
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
