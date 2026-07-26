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
}

/// Pushed from the Items / Outfits action bar. Stays on the path until Back / Apply pops it.
enum ItemGridFilterRoute: Hashable {
    case itemFilter
    case outfitFilter
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
