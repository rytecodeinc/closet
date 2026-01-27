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
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var categories: [Category] = []
    @State private var expanded: Set<NSManagedObjectID> = []
    @State private var selectedCategory: Category?
    @State private var selectedSubcategory: Subcategory?
    @State private var isAddingItems = false
    
    var body: some View {
        NavigationView {
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
                                // Toggle expansion
                                toggle(category)
                                // If already open, also select the category
                                if isOpen {
                                    selectCategory(category, subcategory: nil)
                                }
                            } else {
                                // No subcategories: select the category
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
            .navigationTitle("Add by Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                fetchCategories()
            }
        }
    }
    
    private func fetchCategories() {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
        do {
            categories = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch categories: \(error.localizedDescription)")
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
    
    private func toggle(_ category: Category) {
        let id = category.objectID
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }
    
    private func selectCategory(_ category: Category, subcategory: Subcategory?) {
        selectedCategory = category
        selectedSubcategory = subcategory
        
        // Add items immediately when selection is made
        if let subcategory = subcategory {
            addItemsByCategoryAndSubcategory(category: category, subcategory: subcategory)
        } else {
            addItemsByCategory(category)
        }
    }
    
    private func addItemsByCategory(_ category: Category) {
        guard let categoryName = category.name else { return }
        
        isAddingItems = true
        
        // Fetch all items that have this category and are not already in this wardrobe
        let request = NSFetchRequest<Item>(entityName: "Item")
        request.predicate = NSPredicate(format: "category.name ==[c] %@ AND isDraft != YES", categoryName)
        
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
            
            print("✅ Added \(itemsToAdd.count) items with category '\(categoryName)' to wardrobe '\(wardrobe.name ?? "unknown")'")
            
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
        guard let categoryName = category.name,
              let subcategoryName = subcategory.name else { return }
        
        isAddingItems = true
        
        // Fetch all items that have this category and subcategory and are not already in this wardrobe
        let request = NSFetchRequest<Item>(entityName: "Item")
        request.predicate = NSPredicate(
            format: "category.name ==[c] %@ AND subcategory.name ==[c] %@ AND isDraft != YES",
            categoryName,
            subcategoryName
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
            
            print("✅ Added \(itemsToAdd.count) items with category '\(categoryName)' and subcategory '\(subcategoryName)' to wardrobe '\(wardrobe.name ?? "unknown")'")
            
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

