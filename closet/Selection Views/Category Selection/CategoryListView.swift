//
//  CategoryListView.swift
//  closet
//
//  Created by Dan Warner on 8/2/25.
//


import SwiftUI
import CoreData
import Foundation

import SwiftUI
import CoreData

struct CategoryListView: View {
    @Binding var selectedCategoryName: String?
    @Binding var selectedSubcategoryName: String? // ← NEW

    @FetchRequest(
        entity: Category.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
    ) private var categories: FetchedResults<Category>

    // Track which categories are expanded (use objectID which is always present and Hashable)
    @State private var expanded: Set<NSManagedObjectID> = []

    var body: some View {
        List {
            ForEach(categories, id: \.self) { category in
                let catName = category.name ?? ""
                let subs = sortedSubcategories(for: category)
                let hasSubs = !subs.isEmpty
                let isOpen = expanded.contains(category.objectID)

                // Category Row
                HStack {
                    Text(catName)
                        .foregroundColor(.black)

                    Spacer()

                    // Show checkmark if this category is selected AND no subcategory is selected
                    if selectedCategoryName == catName && selectedSubcategoryName == nil {
                        Image(systemName: "checkmark").foregroundColor(.blue)
                    }

                    // Disclosure indicator for expand/collapse if there are subcategories
                    if hasSubs {
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                            .foregroundColor(.gray)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if hasSubs {
                        // If already open, treat tap as "select the parent category"
                        if isOpen {
                            selectedCategoryName = catName
                            selectedSubcategoryName = nil
                        }
                        toggle(category)
                    } else {
                        // No subcategories: just select the category
                        selectedCategoryName = catName
                        selectedSubcategoryName = nil
                    }
                }

                // Subcategories (only when expanded)
                if isOpen {
                    ForEach(subs, id: \.self) { sub in
                        let subName = sub.name ?? ""
                        HStack {
                            Text(subName)
                                .padding(.leading, 20)
                                .foregroundColor(.black)

                            Spacer()

                            // Checkmark on selected subcategory
                            if selectedCategoryName == catName && selectedSubcategoryName == subName {
                                Image(systemName: "checkmark").foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCategoryName = catName
                            selectedSubcategoryName = subName
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Select Category")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Auto-expand the selected category if a subcategory is already chosen
            if let cat = categories.first(where: { $0.name == selectedCategoryName }),
               selectedSubcategoryName != nil {
                expanded.insert(cat.objectID)
            }
        }
    }

    // MARK: - Helpers

    private func toggle(_ category: Category) {
        let id = category.objectID
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }

    private func sortedSubcategories(for category: Category) -> [Subcategory] {
        let set = (category.subcategories as? Set<Subcategory>) ?? []
        return set.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return ($0.name ?? "") < ($1.name ?? "")
        }
    }
}

