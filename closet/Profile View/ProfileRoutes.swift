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
    /// Layout lab for Event Detail — fake data only (`EventDetailLayoutPrototypeView`).
    case eventDetailLayoutPrototype
    case notifications
    /// Pending event invite preview (`EventInviteeView`).
    case eventInvite(eventId: UUID)
    case users
    case friends(userId: UUID, followersCount: Int, followingCount: Int, initialSegment: FriendsSegment = .followers)
    /// Dedicated mutual-friends list (not Followers / Following).
    case friendsList(userId: UUID)
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
    /// Own-profile pending Redress suggestion → `PendingOutfitDetailView`.
    case pendingRedress(PendingRedressNavigationDestination)
    /// Profile calendar: pick items/outfits for a quick-add OOTD draft.
    case profileOotdItems(eventURI: String)
    case profileOotdItemsFilter
    case profileOotdOutfitsFilter
}

/// Nested Redress push from read-only item detail.
struct ItemRedressDestination: Identifiable, Hashable {
    let id: UUID
    let recipient: PublicUserProfile
    let item: VisibleWardrobeItem
    let wardrobeType: String
    /// Wardrobe the user was browsing — items sheet opens here.
    let wardrobeId: UUID
}
