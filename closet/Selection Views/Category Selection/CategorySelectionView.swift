//
//  CategorySelectionView.swift
//  closet
//
//  Created by Dan Warner on 8/2/25.
//

import SwiftUI
import CoreData
import Foundation

import SwiftUI
import CoreData
import Foundation

struct CategorySelectionView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategoryName: String?
    @State private var selectedSubcategoryName: String?
    @State private var categories: [Category] = []
    @State private var expanded: Set<NSManagedObjectID> = []

    var body: some View {
        VStack {
            SelectionHeader(title: "Select a Category")

            if categories.isEmpty {
                Text("No categories have been added.")
                    .foregroundColor(.gray)
                    .padding()
                Spacer()
            } else {
                List {
                    ForEach(categories, id: \.self) { category in
                        let name = category.name ?? ""
                        let subs = sortedSubcategories(for: category)
                        let hasSubs = !subs.isEmpty
                        let isOpen = expanded.contains(category.objectID)

                        // Category row
                        HStack {
                            Text(name)
                                .foregroundColor(.black)
                            Spacer()
                            if selectedCategoryName == name && selectedSubcategoryName == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                            if hasSubs {
                                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if hasSubs {
                                // If already open, a tap selects the parent category (no subcategory)
                                if isOpen {
                                    selectedCategoryName = name
                                    selectedSubcategoryName = nil
                                }
                                toggle(category)
                            } else {
                                // No subcategories: select the category outright
                                selectedCategoryName = name
                                selectedSubcategoryName = nil
                            }
                        }

                        // Subcategory rows (only when expanded)
                        if isOpen {
                            ForEach(subs, id: \.self) { sub in
                                let subName = sub.name ?? ""
                                HStack {
                                    Text(subName)
                                        .padding(.leading, 20)
                                        .foregroundColor(.black)
                                    Spacer()
                                    if selectedCategoryName == name && selectedSubcategoryName == subName {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedCategoryName = name
                                    selectedSubcategoryName = subName
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            fetchCategories()
            selectedCategoryName = item.category?.name

            if let currentCat = item.category,
               let currentSub = item.subcategory,
               currentSub.category == currentCat {
                selectedSubcategoryName = currentSub.name
                // Auto-expand the selected category so the chosen sub shows
                if let match = categories.first(where: { $0.objectID == currentCat.objectID }) {
                    expanded.insert(match.objectID)
                }
            } else {
                selectedSubcategoryName = nil
            }
        }
        .onDisappear {
            // Persist selection
            guard let catName = selectedCategoryName, !catName.isEmpty else {
                item.category = nil
                item.subcategory = nil
                saveContext()
                return
            }

            let category = fetchOrCreateCategory(named: catName)
            item.category = category

            if let subName = selectedSubcategoryName, !subName.isEmpty,
               let sub = fetchSubcategory(named: subName, in: category) {
                item.subcategory = sub
            } else {
                item.subcategory = nil
            }

            saveContext()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Fetchers

    private func fetchCategories() {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
        do {
            categories = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch categories: \(error)")
            categories = []
        }
    }

    private func sortedSubcategories(for category: Category) -> [Subcategory] {
        let set = (category.subcategories as? Set<Subcategory>) ?? []
        return set.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return ($0.name ?? "") < ($1.name ?? "")
        }
    }

    private func fetchOrCreateCategory(named name: String) -> Category {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name)
        do {
            if let match = try viewContext.fetch(request).first {
                return match
            }
        } catch {
            print("❌ Fetch category error: \(error)")
        }

        // Create on demand if not found
        let newCategory = Category(context: viewContext)
        newCategory.name = name
        newCategory.id = UUID()
        return newCategory
    }

    private func fetchSubcategory(named name: String, in category: Category) -> Subcategory? {
        let req: NSFetchRequest<Subcategory> = Subcategory.fetchRequest()
        req.fetchLimit = 1
        req.predicate = NSPredicate(format: "name ==[c] %@ AND category == %@", name, category)
        do {
            return try viewContext.fetch(req).first
        } catch {
            print("❌ Fetch subcategory error: \(error)")
            return nil
        }
    }

    // MARK: - UI State

    private func toggle(_ category: Category) {
        let id = category.objectID
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }

    // MARK: - Save

    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            print("❌ Failed to save selected category/subcategory: \(error)")
        }
    }
}




