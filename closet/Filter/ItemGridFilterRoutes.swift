//
//  ItemGridFilterRoutes.swift
//  closet
//
//  Path entries for item/outfit filters on the tab NavigationStack path.
//

import Foundation
import Combine

/// Shared tab-bar visibility driven by `ItemGridView` and read by pushed Filter screens.
final class TabBarHideState: ObservableObject {
    @Published var shouldHideTabBar = false
    /// Closet/Wishlist path-pop of `OutfitAddView` — grid clears `isOutfitAddOnPath`.
    @Published var outfitAddDismissTick: Int = 0
    /// Closet path-pop of `ItemPackView` (not Checklist covering Pack) — grid clears `isPackingOnPath`.
    @Published var packingDismissTick: Int = 0

    func noteOutfitAddDismissed() {
        outfitAddDismissTick += 1
    }

    /// Call only when Pack leaves the navigation stack — not when Checklist is pushed on top.
    func notePackingDismissed() {
        packingDismissTick += 1
    }
}

/// Pushed from the Items / Outfits action bar (and Closet/Wishlist +). Stays on the path until Back pops it.
/// Do **not** use `navigationDestination(item:)` + nil-on-appear for these — blank-pops on iOS 18+/26.
enum ItemGridFilterRoute: Hashable {
    case itemFilter
    case outfitFilter
    case addItem
    case addItemQueued
    /// Outfits tab + — `sessionID` keeps each push identity stable (like OutfitAddView).
    case addOutfit(sessionID: UUID)
    /// Item grid / paired-item / outfit-item → `ItemDetailView`.
    case itemDetail(uri: String)
    /// Outfit grid / item outfits → `OutfitDetailView`.
    case outfitDetail(uri: String)
    /// Item detail “Create Outfit” → `OutfitAddView` with preselected item.
    case createOutfitFromItem(itemURI: String, sessionID: UUID)
    /// Items action bar Pack → `ItemPackView`.
    case packing
    /// Pack → Checklist → `PackingChecklistView`.
    case packingChecklist
}

/// Pushed from `ItemFilterView` onto the same path (Filter remains underneath).
enum ItemFilterAttributeRoute: Hashable {
    case wardrobes
    case category
    case brand
    case size
    case colors
    case location
    case tags
}

/// Pushed from `OutfitFilterView` onto the same path.
enum OutfitFilterAttributeRoute: Hashable {
    case category
    case tags
}
