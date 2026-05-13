//
//  OutfitFilterModel.swift
//  closet
//
//  Created by Dan Warner on 12/19/25.
//

import SwiftUI
import CoreData
import Foundation

class OutfitFilterModel: ObservableObject {
    @Published var selectedCategory: String?
    @Published var selectedTags: Set<Tag> = []
    @Published var favoritesOnly: Bool = false
    @Published var sortOrder: ItemSortOrder = .newestFirst
    
    func clearAll() {
        selectedCategory = nil
        selectedTags.removeAll()
        favoritesOnly = false
        sortOrder = .newestFirst
    }
}

func makeOutfitPredicate(for filterModel: OutfitFilterModel) -> NSPredicate? {
    var subpredicates: [NSPredicate] = []
    
    // Category filter
    if let category = filterModel.selectedCategory, !category.isEmpty {
        let categoryPredicate = NSPredicate(format: "category ==[c] %@", category)
        subpredicates.append(categoryPredicate)
    }
    
    // Tag filter
    if !filterModel.selectedTags.isEmpty {
        let tagNames = filterModel.selectedTags.compactMap { $0.name }
        let tagPredicate = NSPredicate(format: "ANY tags.name IN %@", tagNames)
        subpredicates.append(tagPredicate)
    }
    
    // Favorites-only filter
    if filterModel.favoritesOnly {
        let favoritesPredicate = NSPredicate(format: "isFavorite == YES")
        subpredicates.append(favoritesPredicate)
    }
    
    if subpredicates.isEmpty {
        return nil
    } else if subpredicates.count == 1 {
        return subpredicates.first
    } else {
        return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
    }
}

