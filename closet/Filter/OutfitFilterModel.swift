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
    @Published var selectedCategory: OutfitCategory?
    @Published var selectedTags: Set<Tag> = []
    /// When true, filter outfits with no tags. Mutually exclusive with `selectedTags`.
    @Published var filterTagsNotSet: Bool = false
    @Published var favoritesOnly: Bool = false
    @Published var sortOrder: ItemSortOrder = .newestFirst
    @Published var searchQuery: String = ""

    var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Label shown in the filter summary row for tags (including "None").
    var selectedTagsDisplayLabel: String? {
        if filterTagsNotSet { return "None" }
        guard !selectedTags.isEmpty else { return nil }
        return selectedTags.compactMap(\.name).sorted().joined(separator: ", ")
    }

    /// OR match on name, outfit category, tags (AND-combined with other filters).
    static func outfitSearchPredicate(query: String) -> NSPredicate? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "name CONTAINS[cd] %@", trimmed),
            NSPredicate(format: "category.name CONTAINS[cd] %@", trimmed),
            NSPredicate(format: "ANY tags.name CONTAINS[cd] %@", trimmed)
        ])
    }

    func clearAll() {
        selectedCategory = nil
        selectedTags.removeAll()
        filterTagsNotSet = false
        favoritesOnly = false
        sortOrder = .newestFirst
        searchQuery = ""
    }

    /// Number of active filter dimensions (excludes sort and search).
    var activeFilterCount: Int {
        var count = 0
        if selectedCategory != nil { count += 1 }
        if !selectedTags.isEmpty || filterTagsNotSet { count += 1 }
        if favoritesOnly { count += 1 }
        return count
    }
}

func makeOutfitPredicate(for filterModel: OutfitFilterModel) -> NSPredicate? {
    var subpredicates: [NSPredicate] = []
    
    // Category filter
    if let category = filterModel.selectedCategory {
        subpredicates.append(NSPredicate(format: "category == %@", category))
    }
    
    // Tag filter
    if filterModel.filterTagsNotSet {
        subpredicates.append(NSPredicate(format: "tags.@count == 0"))
    } else if !filterModel.selectedTags.isEmpty {
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
