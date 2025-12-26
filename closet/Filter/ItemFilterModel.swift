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
    
    func clearAll() {
        selectedColors.removeAll()
        selectedSeasons.removeAll()
        selectedBrand = nil
        selectedTags.removeAll()
        minPrice = nil
        maxPrice = nil
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


    if subpredicates.isEmpty {
        return nil
    } else if subpredicates.count == 1 {
        return subpredicates.first
    } else {
        return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
    }
    
}


