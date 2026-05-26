//
//  CategoryPickerList.swift
//  closet
//

import SwiftUI
import CoreData

/// Expandable category / subcategory list for attribute pickers and bulk set-category.
struct CategoryPickerList: View {
    let title: String
    let userId: String
    @Binding var expanded: Set<NSManagedObjectID>
    var onCategoriesLoaded: (([Category]) -> Void)? = nil
    var showsCategoryCheckmark: (Category) -> Bool
    var showsSubcategoryCheckmark: (Category, Subcategory) -> Bool
    var onCategoryTap: (Category) -> Void
    var onSubcategoryTap: (Category, Subcategory) -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @State private var categories: [Category] = []

    var body: some View {
        VStack {
            SelectionHeader(title: title)

            if categories.isEmpty {
                Text("No categories have been added.")
                    .foregroundColor(.gray)
                    .padding()
                Spacer()
            } else {
                List {
                    ForEach(categories, id: \.objectID) { category in
                        categoryRows(for: category)
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            reloadCategories()
        }
    }

    @ViewBuilder
    private func categoryRows(for category: Category) -> some View {
        let name = category.name ?? ""
        let subs = sortedSubcategories(for: category)
        let hasSubs = !subs.isEmpty
        let isOpen = expanded.contains(category.objectID)

        HStack {
            Text(name)
                .foregroundColor(.black)
                .onTapGesture {
                    onCategoryTap(category)
                }

            Spacer()

            if showsCategoryCheckmark(category) {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
            }

            if hasSubs {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
                    .onTapGesture {
                        toggleExpansion(category)
                    }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleExpansion(category)
        }

        if isOpen {
            ForEach(subs, id: \.objectID) { sub in
                let subName = sub.name ?? ""
                HStack {
                    Text(subName)
                        .padding(.leading, 20)
                        .foregroundColor(.black)
                    Spacer()
                    if showsSubcategoryCheckmark(category, sub) {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onSubcategoryTap(category, sub)
                }
            }
        }
    }

    private func reloadCategories() {
        guard !userId.isEmpty else {
            categories = []
            onCategoriesLoaded?([])
            return
        }
        do {
            categories = try viewContext.fetchCategoriesForAttributePicker(userId: userId)
            onCategoriesLoaded?(categories)
        } catch {
            print("❌ Failed to fetch categories: \(error.localizedDescription)")
            categories = []
            onCategoriesLoaded?([])
        }
    }

    private func sortedSubcategories(for category: Category) -> [Subcategory] {
        guard !userId.isEmpty else { return [] }
        return viewContext.sortedSubcategoriesForAttributePicker(category, userId: userId)
    }

    private func toggleExpansion(_ category: Category) {
        let id = category.objectID
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }
}
