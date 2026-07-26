//
//  FilterModel.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//

import SwiftUI
import CoreData
import Foundation

/// Sort order for items/outfits by date (createdAt).
enum ItemSortOrder: String, CaseIterable {
    case newestFirst = "New to Old"
    case oldestFirst = "Old to New"
    
    var sortAscending: Bool {
        self == .oldestFirst
    }
}

class ItemFilterModel: ObservableObject {
    /// Sentinel for filtering items with no category (`category == nil`). Not a real category name.
    static let categoryNotSetFilterValue = "__category_not_set__"
    /// Sentinel for filtering items with no brand (`brand == nil`). Not a real brand name.
    static let brandNotSetFilterValue = "__brand_not_set__"
    /// Sentinel for filtering items with no size (`itemSize == nil`). Not a real size value.
    static let sizeNotSetFilterValue = "__size_not_set__"
    /// Sentinel for filtering items with no colors. Not a real color name.
    static let colorNotSetFilterValue = "__color_not_set__"

    @Published var selectedWardrobes: Set<Wardrobe> = []
    @Published var selectedCategoryName: String?
    @Published var selectedSubcategoryName: String?
    @Published var selectedBrandName: String?
    @Published var selectedSizeValue: String?
    @Published var selectedColors: Set<String> = []
    @Published var selectedSeasons: Set<String> = []
    @Published var selectedLocation: Location?
    /// When true, filter items with no location (`location == nil`). Mutually exclusive with `selectedLocation`.
    @Published var filterLocationNotSet: Bool = false
    @Published var minPrice: Decimal?
    @Published var maxPrice: Decimal?
    @Published var selectedTags: Set<Tag> = []
    /// When true, filter items with no tags. Mutually exclusive with `selectedTags`.
    @Published var filterTagsNotSet: Bool = false
    @Published var filterByWeight: Bool = false
    @Published var favoritesOnly: Bool = false
    @Published var sortOrder: ItemSortOrder = .newestFirst
    @Published var searchQuery: String = ""

    var isCategoryNotSetFilter: Bool {
        selectedCategoryName == Self.categoryNotSetFilterValue
    }

    var isBrandNotSetFilter: Bool {
        selectedBrandName == Self.brandNotSetFilterValue
    }

    var isSizeNotSetFilter: Bool {
        selectedSizeValue == Self.sizeNotSetFilterValue
    }

    var isColorNotSetFilter: Bool {
        selectedColors.contains(Self.colorNotSetFilterValue)
    }

    /// Label shown in the filter summary row when a category (or "None") is selected.
    var selectedCategoryDisplayName: String? {
        guard let selectedCategoryName else { return nil }
        if selectedCategoryName == Self.categoryNotSetFilterValue {
            return "None"
        }
        return selectedCategoryName
    }

    /// Label shown in the filter summary row when a brand (or "None") is selected.
    var selectedBrandDisplayName: String? {
        guard let selectedBrandName else { return nil }
        if selectedBrandName == Self.brandNotSetFilterValue {
            return "None"
        }
        return selectedBrandName
    }

    /// Label shown in the filter summary row when a size (or "None") is selected.
    var selectedSizeDisplayName: String? {
        guard let selectedSizeValue, !selectedSizeValue.isEmpty else { return nil }
        if selectedSizeValue == Self.sizeNotSetFilterValue {
            return "None"
        }
        return selectedSizeValue
    }

    /// Label shown in the filter summary row for color selections (including "None").
    var selectedColorsDisplayLabel: String? {
        guard !selectedColors.isEmpty else { return nil }
        if isColorNotSetFilter {
            return "None"
        }
        return selectedColors.sorted().joined(separator: ", ")
    }

    /// Label shown in the filter summary row for location (including "None").
    var selectedLocationDisplayName: String? {
        if filterLocationNotSet { return "None" }
        return selectedLocation?.name
    }

    /// Label shown in the filter summary row for tags (including "None").
    var selectedTagsDisplayLabel: String? {
        if filterTagsNotSet { return "None" }
        guard !selectedTags.isEmpty else { return nil }
        return selectedTags.compactMap(\.name).sorted().joined(separator: ", ")
    }

    /// Predicate for the selected category / subcategory filter, if any.
    static func categoryFilterPredicate(
        categoryName: String?,
        subcategoryName: String?
    ) -> NSPredicate? {
        guard let categoryName, !categoryName.isEmpty else { return nil }
        if categoryName == categoryNotSetFilterValue {
            return NSPredicate(format: "category == nil")
        }
        if let subcategoryName, !subcategoryName.isEmpty {
            return NSPredicate(
                format: "subcategory.name ==[c] %@ AND category.name ==[c] %@",
                subcategoryName,
                categoryName
            )
        }
        return NSPredicate(format: "category.name ==[c] %@", categoryName)
    }

    /// Predicate for the selected brand filter, if any.
    static func brandFilterPredicate(brandName: String?) -> NSPredicate? {
        guard let brandName, !brandName.isEmpty else { return nil }
        if brandName == brandNotSetFilterValue {
            return NSPredicate(format: "brand == nil")
        }
        return NSPredicate(format: "brand.name ==[c] %@", brandName)
    }

    /// Predicate for the selected size filter, if any.
    static func sizeFilterPredicate(sizeValue: String?, context: NSManagedObjectContext) -> NSPredicate? {
        guard let sizeValue, !sizeValue.isEmpty else { return nil }
        if sizeValue == sizeNotSetFilterValue {
            return NSPredicate(format: "itemSize == nil")
        }
        // Avoid keypath traversal `size.value` in Core Data predicates; it can crash with
        // "Unsupported function expression SIZE.value" on some runtimes.
        // Resolve matching Size rows, then filter items by relationship membership.
        let sizeRequest = NSFetchRequest<Size>(entityName: "Size")
        sizeRequest.fetchBatchSize = 0
        sizeRequest.predicate = NSPredicate(format: "value == %@", sizeValue)
        if let matchingSizes = try? context.fetch(sizeRequest), !matchingSizes.isEmpty {
            // Avoid `IN` against a relationship (can fail SQL generation). Use OR-of-equalities.
            if matchingSizes.count == 1, let only = matchingSizes.first {
                return NSPredicate(format: "itemSize == %@", only)
            }
            let ors = matchingSizes.map { NSPredicate(format: "itemSize == %@", $0) }
            return NSCompoundPredicate(orPredicateWithSubpredicates: ors)
        }
        return NSPredicate(value: false)
    }

    /// Predicate for the selected colors filter, if any.
    static func colorsFilterPredicate(selectedColors: Set<String>) -> NSPredicate? {
        guard !selectedColors.isEmpty else { return nil }
        if selectedColors.contains(colorNotSetFilterValue) {
            return NSPredicate(format: "colors.@count == 0")
        }
        return NSPredicate(format: "ANY colors.name IN %@", Array(selectedColors))
    }

    /// Predicate for the selected location filter, if any.
    static func locationFilterPredicate(location: Location?, filterNotSet: Bool) -> NSPredicate? {
        if filterNotSet {
            return NSPredicate(format: "location == nil")
        }
        guard let location else { return nil }
        return NSPredicate(format: "location == %@", location)
    }

    /// Predicate for the selected tags filter, if any.
    static func tagsFilterPredicate(selectedTags: Set<Tag>, filterNotSet: Bool) -> NSPredicate? {
        if filterNotSet {
            return NSPredicate(format: "tags.@count == 0")
        }
        guard !selectedTags.isEmpty else { return nil }
        let tagNames = selectedTags.compactMap(\.name)
        guard !tagNames.isEmpty else { return nil }
        return NSPredicate(format: "ANY tags.name IN %@", tagNames)
    }

    var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// OR match on name, brand, category, subcategory, colors, tags (AND-combined with other filters).
    static func itemSearchPredicate(query: String) -> NSPredicate? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "name CONTAINS[cd] %@", trimmed),
            NSPredicate(format: "brand.name CONTAINS[cd] %@", trimmed),
            NSPredicate(format: "category.name CONTAINS[cd] %@", trimmed),
            NSPredicate(format: "subcategory.name CONTAINS[cd] %@", trimmed),
            NSPredicate(format: "ANY colors.name CONTAINS[cd] %@", trimmed),
            NSPredicate(format: "ANY tags.name CONTAINS[cd] %@", trimmed)
        ])
    }

    /// Non-default wardrobes chosen in the filter sheet (same closet/wishlist type).
    func secondaryFilterWardrobes(matchingType wardrobeType: String) -> [Wardrobe] {
        let type = wardrobeType.lowercased()
        return selectedWardrobes.filter {
            ($0.type ?? "").lowercased() == type && $0.isDefault != true
        }
    }

    /// Wardrobes that scope the item grid and filter pickers on the default tab.
    /// Default row selected → viewing wardrobe only; secondary picks → AND across those wardrobes.
    func wardrobeScopeForFilter(viewingWardrobe: Wardrobe, wardrobeType: String) -> [Wardrobe] {
        if viewingWardrobe.isDefault != true {
            return [viewingWardrobe]
        }
        let secondaries = secondaryFilterWardrobes(matchingType: wardrobeType)
        if secondaries.isEmpty {
            return [viewingWardrobe]
        }
        return secondaries
    }

    /// Item membership for a closet/wishlist grid tab plus optional filter-sheet wardrobe picks.
    static func wardrobeMembershipPredicate(
        viewingWardrobe: Wardrobe,
        wardrobeType: String,
        filterModel: ItemFilterModel
    ) -> NSPredicate {
        let wardrobes = filterModel.wardrobeScopeForFilter(
            viewingWardrobe: viewingWardrobe,
            wardrobeType: wardrobeType
        )
        if wardrobes.count == 1, let only = wardrobes.first {
            return NSPredicate(format: "ANY wardrobes == %@", only)
        }
        let membership = wardrobes.map { NSPredicate(format: "ANY wardrobes == %@", $0) }
        return NSCompoundPredicate(andPredicateWithSubpredicates: membership)
    }

    func clearAll() {
        selectedWardrobes.removeAll()
        selectedCategoryName = nil
        selectedSubcategoryName = nil
        selectedBrandName = nil
        selectedSizeValue = nil
        selectedColors.removeAll()
        selectedSeasons.removeAll()
        selectedLocation = nil
        filterLocationNotSet = false
        minPrice = nil
        maxPrice = nil
        selectedTags.removeAll()
        filterTagsNotSet = false
        filterByWeight = false
        favoritesOnly = false
        searchQuery = ""
    }

    /// Copies filter fields from another model (used for draft Apply / cancel).
    func copyValues(from other: ItemFilterModel) {
        selectedWardrobes = other.selectedWardrobes
        selectedCategoryName = other.selectedCategoryName
        selectedSubcategoryName = other.selectedSubcategoryName
        selectedBrandName = other.selectedBrandName
        selectedSizeValue = other.selectedSizeValue
        selectedColors = other.selectedColors
        selectedSeasons = other.selectedSeasons
        selectedLocation = other.selectedLocation
        filterLocationNotSet = other.filterLocationNotSet
        minPrice = other.minPrice
        maxPrice = other.maxPrice
        selectedTags = other.selectedTags
        filterTagsNotSet = other.filterTagsNotSet
        filterByWeight = other.filterByWeight
        favoritesOnly = other.favoritesOnly
        sortOrder = other.sortOrder
        searchQuery = other.searchQuery
    }

    /// Number of active filter dimensions (excludes sort and search).
    var activeFilterCount: Int {
        var count = 0
        if selectedWardrobes.contains(where: { $0.isDefault != true }) { count += 1 }
        if selectedCategoryName != nil { count += 1 }
        if selectedBrandName != nil { count += 1 }
        if let selectedSizeValue, !selectedSizeValue.isEmpty { count += 1 }
        if !selectedColors.isEmpty { count += 1 }
        if !selectedSeasons.isEmpty { count += 1 }
        if selectedLocation != nil || filterLocationNotSet { count += 1 }
        if minPrice != nil || maxPrice != nil { count += 1 }
        if !selectedTags.isEmpty || filterTagsNotSet { count += 1 }
        if filterByWeight { count += 1 }
        if favoritesOnly { count += 1 }
        return count
    }
}


func makePredicate(for filterModel: ItemFilterModel, context: NSManagedObjectContext) -> NSPredicate? {
    var subpredicates: [NSPredicate] = []

    // Category/Subcategory filter
    if let categoryPredicate = ItemFilterModel.categoryFilterPredicate(
        categoryName: filterModel.selectedCategoryName,
        subcategoryName: filterModel.selectedSubcategoryName
    ) {
        subpredicates.append(categoryPredicate)
    }

    // Brand filter
    if let brandPredicate = ItemFilterModel.brandFilterPredicate(brandName: filterModel.selectedBrandName) {
        subpredicates.append(brandPredicate)
    }

    // Size filter
    if let sizePredicate = ItemFilterModel.sizeFilterPredicate(
        sizeValue: filterModel.selectedSizeValue,
        context: context
    ) {
        subpredicates.append(sizePredicate)
    }

    // Color filter
    if let colorPredicate = ItemFilterModel.colorsFilterPredicate(selectedColors: filterModel.selectedColors) {
        subpredicates.append(colorPredicate)
    }

    // Season filter
    if !filterModel.selectedSeasons.isEmpty {
        let seasonPredicate = NSPredicate(format: "ANY seasons.name IN %@", Array(filterModel.selectedSeasons))
        subpredicates.append(seasonPredicate)
    }

    // Location filter
    if let locationPredicate = ItemFilterModel.locationFilterPredicate(
        location: filterModel.selectedLocation,
        filterNotSet: filterModel.filterLocationNotSet
    ) {
        subpredicates.append(locationPredicate)
    }

    // Price filters
    if let minPrice = filterModel.minPrice {
        let minPricePredicate = NSPredicate(format: "price.amount >= %@", minPrice as NSDecimalNumber)
        subpredicates.append(minPricePredicate)
    }

    if let maxPrice = filterModel.maxPrice {
        let maxPricePredicate = NSPredicate(format: "price.amount <= %@", maxPrice as NSDecimalNumber)
        subpredicates.append(maxPricePredicate)
    }

    // Tag filter
    if let tagPredicate = ItemFilterModel.tagsFilterPredicate(
        selectedTags: filterModel.selectedTags,
        filterNotSet: filterModel.filterTagsNotSet
    ) {
        subpredicates.append(tagPredicate)
    }

    if filterModel.favoritesOnly {
        subpredicates.append(NSPredicate(format: "isFavorite == YES"))
    }

    // Weight filter - only show items that can support user's weight
    if filterModel.filterByWeight {
        let repository = UserProfileRepository(context: context)
        let userWeightKg = repository.getWeightKg()
        if userWeightKg > 0 {
            let weightExistsPredicate = NSPredicate(format: "weight != nil")
            let weightSupportedPredicate = NSPredicate(format: "weight <= %@", userWeightKg as NSNumber)
            let weightPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [weightExistsPredicate, weightSupportedPredicate])
            subpredicates.append(weightPredicate)
            print("🔍 Weight filter active: showing ONLY items with max wearable weight <= \(String(format: "%.2f", userWeightKg)) kg (excluding items without weight)")
            print("🔍 Weight predicate: \(weightPredicate)")
        } else {
            print("⚠️ Weight filter enabled but user weight not set in Profile")
        }
    }

    if subpredicates.isEmpty {
        return nil
    } else if subpredicates.count == 1 {
        return subpredicates.first
    } else {
        return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
    }
}
