//
//  AddItemsByCategoryView.swift
//  closet
//
//  Created by Dan Warner on 12/19/25.
//

import SwiftUI
import CoreData

struct AddItemsByCategoryView: View {
    @ObservedObject var wardrobe: Wardrobe
    @EnvironmentObject private var authSession: AuthSession
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var categories: [Category] = []
    @State private var expanded: Set<NSManagedObjectID> = []
    @State private var selectedCategory: Category?
    @State private var selectedSubcategory: Subcategory?
    @State private var isAddingItems = false
    @State private var showAddConfirmation = false
    @State private var pendingCategory: Category?
    @State private var pendingSubcategory: Subcategory?

    private var wardrobeDisplayName: String {
        wardrobe.name ?? "this wardrobe"
    }

    private var pendingCategoryLabel: String {
        guard let category = pendingCategory else { return "" }
        let categoryName = category.name ?? ""
        if let sub = pendingSubcategory, let subName = sub.name, !subName.isEmpty {
            return "\(categoryName) › \(subName)"
        }
        return categoryName
    }
    
    var body: some View {
        VStack(spacing: 0) {
            SelectionPanelHeader(title: "Add by Category")

            List {
                if categories.isEmpty {
                    Text("No categories available. Add categories to items first.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(categories, id: \.self) { category in
                        let catName = category.name ?? ""
                        let subs = sortedSubcategories(for: category)
                        let hasSubs = !subs.isEmpty
                        let isOpen = expanded.contains(category.objectID)
                        let isCategorySelected = selectedCategory?.objectID == category.objectID && selectedSubcategory == nil

                        // Category Row
                        HStack {
                            Text(catName)
                                .foregroundColor(.primary)

                            Spacer()

                            if isCategorySelected {
                                if isAddingItems {
                                    ProgressView()
                                } else {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }

                            if hasSubs {
                                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if hasSubs {
                                toggle(category)
                                if isOpen {
                                    selectCategory(category, subcategory: nil)
                                }
                            } else {
                                selectCategory(category, subcategory: nil)
                            }
                        }
                        .disabled(isAddingItems)

                        // Subcategories (only when expanded)
                        if isOpen {
                            ForEach(subs, id: \.self) { sub in
                                let subName = sub.name ?? ""
                                let isSubSelected = selectedCategory?.objectID == category.objectID && selectedSubcategory?.objectID == sub.objectID

                                HStack {
                                    Text(subName)
                                        .padding(.leading, 20)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    if isSubSelected {
                                        if isAddingItems {
                                            ProgressView()
                                        } else {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectCategory(category, subcategory: sub)
                                }
                                .disabled(isAddingItems)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .onAppear {
            fetchCategories()
        }
        .alert("Add Items by Category", isPresented: $showAddConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingCategory = nil
                pendingSubcategory = nil
            }
            Button("Add") {
                guard let category = pendingCategory else { return }
                selectedCategory = category
                selectedSubcategory = pendingSubcategory
                if let subcategory = pendingSubcategory {
                    addItemsByCategoryAndSubcategory(category: category, subcategory: subcategory)
                } else {
                    addItemsByCategory(category)
                }
                pendingCategory = nil
                pendingSubcategory = nil
            }
        } message: {
            Text("Add all items in \"\(pendingCategoryLabel)\" to \"\(wardrobeDisplayName)\"?")
        }
    }
    
    /// Same account scope as `ItemFilterView` → `CategoryFilterListView`.
    private var currentUserId: String? {
        authSession.userId?.uuidString
    }

    private func fetchCategories() {
        do {
            categories = try viewContext.fetchCategoriesForFilterList(userId: currentUserId)
        } catch {
            print("❌ Failed to fetch categories: \(error.localizedDescription)")
            categories = []
        }
    }
    
    private func sortedSubcategories(for category: Category) -> [Subcategory] {
        viewContext.sortedSubcategoriesForFilterList(category, userId: currentUserId)
    }
    
    private func toggle(_ category: Category) {
        let id = category.objectID
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }
    
    private func selectCategory(_ category: Category, subcategory: Subcategory?) {
        pendingCategory = category
        pendingSubcategory = subcategory
        showAddConfirmation = true
    }
    
    private func addItemsByCategory(_ category: Category) {
        guard let uid = currentUserId else { return }
        
        isAddingItems = true
        
        let request = NSFetchRequest<Item>(entityName: "Item")
        request.predicate = NSPredicate(
            format: "category == %@ AND userId == %@ AND isDraft != YES AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
            category,
            uid
        )
        
        do {
            let allItemsWithCategory = try viewContext.fetch(request)
            
            // Get items already in this wardrobe
            let itemsInWardrobe = (wardrobe.items as? Set<Item>) ?? []
            
            // Filter to only items not already in this wardrobe
            let itemsToAdd = allItemsWithCategory.filter { !itemsInWardrobe.contains($0) }
            
            // Add all items to the wardrobe
            for item in itemsToAdd {
                wardrobe.addToItems(item)
            }
            
            try viewContext.save()
            
            print("✅ Added \(itemsToAdd.count) items with category '\(category.name ?? "")' to wardrobe '\(wardrobe.name ?? "unknown")'")
            
            // Dismiss after a short delay to show success
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismiss()
            }
        } catch {
            print("❌ Failed to add items by category: \(error.localizedDescription)")
            isAddingItems = false
        }
    }
    
    private func addItemsByCategoryAndSubcategory(category: Category, subcategory: Subcategory) {
        guard let uid = currentUserId else { return }
        
        isAddingItems = true
        
        let request = NSFetchRequest<Item>(entityName: "Item")
        request.predicate = NSPredicate(
            format: "category == %@ AND subcategory == %@ AND userId == %@ AND isDraft != YES AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
            category,
            subcategory,
            uid
        )
        
        do {
            let allItemsWithCategoryAndSub = try viewContext.fetch(request)
            
            // Get items already in this wardrobe
            let itemsInWardrobe = (wardrobe.items as? Set<Item>) ?? []
            
            // Filter to only items not already in this wardrobe
            let itemsToAdd = allItemsWithCategoryAndSub.filter { !itemsInWardrobe.contains($0) }
            
            // Add all items to the wardrobe
            for item in itemsToAdd {
                wardrobe.addToItems(item)
            }
            
            try viewContext.save()
            
            print("✅ Added \(itemsToAdd.count) items with category '\(category.name ?? "")' and subcategory '\(subcategory.name ?? "")' to wardrobe '\(wardrobe.name ?? "unknown")'")
            
            // Dismiss after a short delay to show success
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismiss()
            }
        } catch {
            print("❌ Failed to add items by category and subcategory: \(error.localizedDescription)")
            isAddingItems = false
        }
    }
}

