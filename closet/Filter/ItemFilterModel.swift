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
    @Published var selectedWardrobes: Set<Wardrobe> = []
    @Published var selectedCategoryName: String?
    @Published var selectedSubcategoryName: String?
    @Published var selectedBrand: Brand?
    @Published var selectedSizeValue: String?
    @Published var selectedColors: Set<String> = []
    @Published var selectedSeasons: Set<String> = []
    @Published var selectedLocation: Location?
    @Published var minPrice: Decimal?
    @Published var maxPrice: Decimal?
    @Published var selectedTags: Set<Tag> = []
    @Published var filterByWeight: Bool = false
    
    func clearAll() {
        selectedWardrobes.removeAll()
        selectedCategoryName = nil
        selectedSubcategoryName = nil
        selectedBrand = nil
        selectedSizeValue = nil
        selectedColors.removeAll()
        selectedSeasons.removeAll()
        selectedLocation = nil
        minPrice = nil
        maxPrice = nil
        selectedTags.removeAll()
        filterByWeight = false
    }
}


func makePredicate(for filterModel: ItemFilterModel, context: NSManagedObjectContext) -> NSPredicate? {
    var subpredicates: [NSPredicate] = []

    // Category/Subcategory filter
    if let subcategoryName = filterModel.selectedSubcategoryName, !subcategoryName.isEmpty,
       let categoryName = filterModel.selectedCategoryName, !categoryName.isEmpty {
        let subcategoryPredicate = NSPredicate(format: "subcategory.name ==[c] %@ AND category.name ==[c] %@", subcategoryName, categoryName)
        subpredicates.append(subcategoryPredicate)
    } else if let categoryName = filterModel.selectedCategoryName, !categoryName.isEmpty {
        let categoryPredicate = NSPredicate(format: "category.name ==[c] %@", categoryName)
        subpredicates.append(categoryPredicate)
    }

    // Brand filter
    if let brand = filterModel.selectedBrand, let brandName = brand.name, !brandName.isEmpty {
        let brandPredicate = NSPredicate(format: "brand.name ==[c] %@", brandName)
        subpredicates.append(brandPredicate)
    }

    // Size filter
    if let sizeValue = filterModel.selectedSizeValue, !sizeValue.isEmpty {
        let sizePredicate = NSPredicate(format: "size.value == %@", sizeValue)
        subpredicates.append(sizePredicate)
    }

    // Color filter
    if !filterModel.selectedColors.isEmpty {
        let colorPredicate = NSPredicate(format: "ANY colors.name IN %@", Array(filterModel.selectedColors))
        subpredicates.append(colorPredicate)
    }

    // Season filter
    if !filterModel.selectedSeasons.isEmpty {
        let seasonPredicate = NSPredicate(format: "ANY seasons.name IN %@", Array(filterModel.selectedSeasons))
        subpredicates.append(seasonPredicate)
    }

    // Location filter
    if let location = filterModel.selectedLocation {
        let locationPredicate = NSPredicate(format: "location == %@", location)
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
    if !filterModel.selectedTags.isEmpty {
        let tagNames = filterModel.selectedTags.compactMap { $0.name }
        let tagPredicate = NSPredicate(format: "ANY tags.name IN %@", tagNames)
        subpredicates.append(tagPredicate)
    }

    // Weight filter - only show items that can support user's weight
    if filterModel.filterByWeight {
        let repository = UserProfileRepository(context: context)
        let userWeightKg = repository.getWeightKg()
        if userWeightKg > 0 {
            // Show ONLY items where:
            // - Item has weight set (weight != nil) AND
            // - Item's max wearable weight <= user's weight
            // Logic: Item weight = max wearable weight the item can support
            // If item.weight > userWeight, the item CANNOT support the user (user is too heavy)
            // If item.weight <= userWeight, the item CAN support the user
            // Items without weight are EXCLUDED when filter is active
            // Note: weight is stored in kg in Core Data
            let weightExistsPredicate = NSPredicate(format: "weight != nil")
            let weightSupportedPredicate = NSPredicate(format: "weight <= %@", userWeightKg as NSNumber)
            
            // weight != nil AND weight <= userWeight
            let weightPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [weightExistsPredicate, weightSupportedPredicate])
            
            subpredicates.append(weightPredicate)
            print("🔍 Weight filter active: showing ONLY items with max wearable weight <= \(String(format: "%.2f", userWeightKg)) kg (excluding items without weight)")
            print("🔍 Weight predicate: \(weightPredicate)")
        } else {
            print("⚠️ Weight filter enabled but user weight not set in Profile")
        }
        // If user hasn't set their weight, don't filter (show all items)
    }

    if subpredicates.isEmpty {
        return nil
    } else if subpredicates.count == 1 {
        return subpredicates.first
    } else {
        return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
    }
}


