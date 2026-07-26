//
//  CategoryFilterListView.swift
//  closet
//
//  Created by Dan Warner on 1/1/25.
//

import SwiftUI
import CoreData

struct CategoryFilterListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedCategoryName: String?
    @Binding var selectedSubcategoryName: String?
    /// When set, only categories owned by or used by this user's items appear.
    var userId: String? = nil
    /// When non-empty, only categories on items in all of these wardrobes (AND) appear.
    var wardrobes: [Wardrobe] = []
    /// `"closet"` or `"wishlist"` — empty-state copy in ItemFilterView.
    var wardrobeType: String = "closet"

    @State private var categories: [Category] = []

    // Track which categories are expanded (use objectID which is always present and Hashable)
    @State private var expanded: Set<NSManagedObjectID> = []

    private var emptyCategoriesMessage: String {
        wardrobeType == "wishlist"
            ? "Categories added to items in your wishlist will appear here."
            : "Categories added to items in your closet will appear here."
    }

    private var isCategoryNotSetSelected: Bool {
        selectedCategoryName == ItemFilterModel.categoryNotSetFilterValue
    }

    var body: some View {
        List {
            categoryNotSetRow

            if categories.isEmpty {
                Text(emptyCategoriesMessage)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
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
        }
        .listStyle(.plain)
        .navigationTitle("Select Category")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchCategories()
            // Auto-expand the selected category if a subcategory is already chosen
            if let cat = categories.first(where: { $0.name == selectedCategoryName }),
               selectedSubcategoryName != nil {
                expanded.insert(cat.objectID)
            }
        }
    }

    private var categoryNotSetRow: some View {
        HStack {
            Text("None")
                .foregroundColor(.black)

            Spacer()

            if isCategoryNotSetSelected {
                Image(systemName: "checkmark").foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedCategoryName = ItemFilterModel.categoryNotSetFilterValue
            selectedSubcategoryName = nil
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

    private func fetchCategories() {
        do {
            categories = try viewContext.fetchCategoriesForFilterList(userId: userId, wardrobes: wardrobes)
        } catch {
            print("❌ Failed to fetch categories: \(error.localizedDescription)")
            categories = []
        }
    }

    private func sortedSubcategories(for category: Category) -> [Subcategory] {
        viewContext.sortedSubcategoriesForFilterList(category, userId: userId, wardrobes: wardrobes)
    }
}
