//
//  FilterModel.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//

import SwiftUI
import CoreData
import Foundation

class ItemFilterModel: ObservableObject {
    @Published var selectedColors: Set<String> = []
    @Published var selectedSeasons: Set<String> = []
    @Published var selectedBrand: Brand? = nil
    @Published var selectedTags: Set<Tag> = []
    @Published var minPrice: Decimal?
    @Published var maxPrice: Decimal?
    @Published var selectedWardrobes: Set<Wardrobe> = []
    @Published var selectedCategoryName: String? = nil
    @Published var selectedSubcategoryName: String? = nil
    @Published var selectedSizeValue: String? = nil
    @Published var selectedLocation: Location? = nil
    
    func clearAll() {
        selectedColors.removeAll()
        selectedSeasons.removeAll()
        selectedBrand = nil
        selectedTags.removeAll()
        minPrice = nil
        maxPrice = nil
        selectedWardrobes.removeAll()
        selectedCategoryName = nil
        selectedSubcategoryName = nil
        selectedSizeValue = nil
        selectedLocation = nil
    }
}


func makePredicate(for filterModel: ItemFilterModel) -> NSPredicate? {
    var subpredicates: [NSPredicate] = []

    if !filterModel.selectedColors.isEmpty {
        let colorPredicate = NSPredicate(format: "ANY colors.name IN %@", Array(filterModel.selectedColors))
        subpredicates.append(colorPredicate)
    }

    if !filterModel.selectedSeasons.isEmpty {
        let seasonPredicate = NSPredicate(format: "ANY seasons.name IN %@", Array(filterModel.selectedSeasons))
        subpredicates.append(seasonPredicate)
    }

    if let brand = filterModel.selectedBrand, let brandName = brand.name, !brandName.isEmpty {
        let brandPredicate = NSPredicate(format: "brand.name ==[c] %@", brandName)
        subpredicates.append(brandPredicate)
    }

    if let minPrice = filterModel.minPrice {
        let minPricePredicate = NSPredicate(format: "price.amount >= %@", minPrice as NSDecimalNumber)
        subpredicates.append(minPricePredicate)
    }

    if let maxPrice = filterModel.maxPrice {
        let maxPricePredicate = NSPredicate(format: "price.amount <= %@", maxPrice as NSDecimalNumber)
        subpredicates.append(maxPricePredicate)
    }

    if !filterModel.selectedTags.isEmpty {
        let tagNames = filterModel.selectedTags.compactMap { $0.name }
        let tagPredicate = NSPredicate(format: "ANY tags.name IN %@", tagNames)
        subpredicates.append(tagPredicate)
    }

    // Note: Wardrobe filtering is handled separately in ItemGridView, not here
    // to avoid conflicts with the view's selectedWardrobe parameter

    // Handle category/subcategory filtering
    if let subcategoryName = filterModel.selectedSubcategoryName, !subcategoryName.isEmpty,
       let categoryName = filterModel.selectedCategoryName, !categoryName.isEmpty {
        // Filter by subcategory (which also implies the category)
        let subcategoryPredicate = NSPredicate(format: "subcategory.name ==[c] %@ AND category.name ==[c] %@", subcategoryName, categoryName)
        subpredicates.append(subcategoryPredicate)
    } else if let categoryName = filterModel.selectedCategoryName, !categoryName.isEmpty {
        // Filter by category only
        let categoryPredicate = NSPredicate(format: "category.name ==[c] %@", categoryName)
        subpredicates.append(categoryPredicate)
    }

    if let sizeValue = filterModel.selectedSizeValue, !sizeValue.isEmpty {
        let sizePredicate = NSPredicate(format: "size.value == %@", sizeValue)
        subpredicates.append(sizePredicate)
    }

    if let location = filterModel.selectedLocation {
        let locationPredicate = NSPredicate(format: "location == %@", location)
        subpredicates.append(locationPredicate)
    }

    if subpredicates.isEmpty {
        return nil
    } else if subpredicates.count == 1 {
        return subpredicates.first
    } else {
        return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
    }
    
}


