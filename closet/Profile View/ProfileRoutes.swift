//
//  ProfileRoutes.swift
//  closet
//
//  Path entries for the Profile tab NavigationStack (Calendar-style).
//

import Foundation

/// Pushed on Profile’s stack. Settings / notifications / friends / item detail are path values,
/// not nested `isPresented` or `item:` destinations on this stack.
enum ProfileRoute: Hashable {
    case settings
    case attributePreferences
    case categoryVisibility
    case colorVisibility
    case seasonVisibility
    case developerSettings
    case developerSignIn
    case developerRegister
    case notifications
    case users
    case friends(userId: UUID, followersCount: Int, followingCount: Int)
    case editProfile
    case otherUser(PublicUserProfile)
    case readOnlyItem(ProfileReadOnlyItemDestination)
    case readOnlyOutfit(
        ownerUserId: UUID,
        wardrobeId: UUID,
        outfit: VisibleWardrobeOutfit,
        wardrobeType: String,
        ownerProfile: PublicUserProfile?
    )
    case itemRedress(ItemRedressDestination)
    case itemFilter
    case outfitFilter
}

/// Nested Redress push from read-only item detail.
struct ItemRedressDestination: Identifiable, Hashable {
    let id: UUID
    let recipient: PublicUserProfile
    let item: VisibleWardrobeItem
    let wardrobeType: String
}
