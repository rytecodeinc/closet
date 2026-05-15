//
//  CategorySelectionView 2.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct SetCategoryView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSession

    @State private var selectedCategoryName: String?
    @State private var selectedSubcategoryName: String?
    @State private var categories: [Category] = []
    @State private var expanded: Set<NSManagedObjectID> = []

    private var referenceUserId: String? {
        effectiveReferenceDataUserId(signedInUserId: authSession.userId, entityUserId: item.userId)
    }

    var body: some View {
        VStack {
            SelectionHeader(title: "Select Category")

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
                                .onTapGesture {
                                    // Select the category (does NOT affect expansion)
                                    if selectedCategoryName == name && selectedSubcategoryName == nil {
                                        selectedCategoryName = nil
                                    } else {
                                        selectedCategoryName = name
                                        selectedSubcategoryName = nil
                                    }
                                }

                            Spacer()
                            
                            if selectedCategoryName == name && selectedSubcategoryName == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                            
                            if hasSubs {
                                // Chevron is the expand/collapse button
                                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                                    .onTapGesture {
                                        toggle(category)
                                    }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggle(category)
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
                                    // Toggle this subcategory selection
                                    let isThisSelected = (selectedCategoryName == name && selectedSubcategoryName == subName)
                                    if isThisSelected {
                                        // Deselect completely
                                        selectedCategoryName = nil
                                        selectedSubcategoryName = nil
                                    } else {
                                        // Select this subcategory (and its parent)
                                        selectedCategoryName = name
                                        selectedSubcategoryName = subName
                                    }
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
                if let match = categories.first(where: { $0.objectID == currentCat.objectID }) {
                    expanded.insert(match.objectID)
                }
            } else {
                selectedSubcategoryName = nil
            }
        }
        .onDisappear {
            // Apply selection to the item object (but DON'T save context)
            applySelectionToItem()
            // Let the parent view (ItemAddView) decide when to save
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Apply Selection
    
    private func applySelectionToItem() {
        guard let catName = selectedCategoryName, !catName.isEmpty else {
            item.category = nil
            item.subcategory = nil
            
            // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
            if viewContext.parent == nil {
                do {
                    try viewContext.save()
                } catch {
                    print("❌ Failed to save category: \(error.localizedDescription)")
                }
            }
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
        
        // Set updatedAt since we're modifying the item
        setUpdatedAt(item)
        
        // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
        // If viewContext has a parent, we're in a child context and shouldn't save
        if viewContext.parent == nil {
            // We're in a parent context (ItemDetailView), save immediately
            do {
                try viewContext.save()
                
                // Trigger automatic sync for the modified item
                SyncService.shared.syncItemIfNeeded(item)
            } catch {
                print("❌ Failed to save category: \(error.localizedDescription)")
            }
        }
        // Otherwise, we're in a child context (ItemAddView), don't save - let parent handle it
    }

    // MARK: - Fetchers

    private func fetchCategories() {
        let request = NSFetchRequest<Category>(entityName: "Category")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
        if let uid = referenceUserId, !uid.isEmpty {
            let owned = NSPredicate(format: "userId == %@", uid)
            let usedByUserItems = NSPredicate(
                format: "SUBQUERY(items, $i, $i.userId == %@ AND ($i.isSoftDeleted != YES OR $i.isSoftDeleted == nil)).@count > 0",
                uid
            )
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [owned, usedByUserItems])
        }
        do {
            let fetched = try viewContext.fetch(request)
            if let uid = referenceUserId, !uid.isEmpty {
                categories = dedupeNamedReferenceRows(fetched, preferredUserId: uid)
            } else {
                categories = fetched
            }
            print("✅ Fetched \(categories.count) categories")
        } catch {
            print("❌ Failed to fetch categories: \(error)")
            categories = []
        }
    }

    private func sortedSubcategories(for category: Category) -> [Subcategory] {
        let set = (category.subcategories as? Set<Subcategory>) ?? []
        let filtered: [Subcategory]
        if let uid = referenceUserId, !uid.isEmpty {
            filtered = set.filter { sub in
                if sub.userId == uid { return true }
                let items = sub.items as? Set<Item> ?? []
                return items.contains {
                    $0.userId == uid && ($0.isSoftDeleted != true)
                }
            }
        } else {
            filtered = Array(set)
        }
        let deduped: [Subcategory]
        if let uid = referenceUserId, !uid.isEmpty {
            deduped = dedupeNamedReferenceRows(filtered, preferredUserId: uid)
        } else {
            deduped = filtered
        }
        return deduped.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return ($0.name ?? "") < ($1.name ?? "")
        }
    }

    private func fetchOrCreateCategory(named name: String) -> Category {
        let request = NSFetchRequest<Category>(entityName: "Category")
        if let uid = referenceUserId, !uid.isEmpty {
            request.predicate = NSPredicate(format: "name ==[c] %@ AND userId == %@", name, uid)
        } else {
            request.predicate = NSPredicate(format: "name ==[c] %@", name)
        }
        do {
            if let match = try viewContext.fetch(request).first {
                return match
            }
        } catch {
            print("❌ Fetch category error: \(error)")
        }

        let newCategory = Category(context: viewContext)
        newCategory.name = name
        newCategory.id = UUID()
        newCategory.userId = referenceUserId ?? item.userId
        return newCategory
    }

    private func fetchSubcategory(named name: String, in category: Category) -> Subcategory? {
        let req = NSFetchRequest<Subcategory>(entityName: "Subcategory")
        req.fetchLimit = 1
        if let uid = referenceUserId, !uid.isEmpty {
            req.predicate = NSPredicate(format: "name ==[c] %@ AND category == %@ AND userId == %@", name, category, uid)
        } else {
            req.predicate = NSPredicate(format: "name ==[c] %@ AND category == %@", name, category)
        }
        return try? viewContext.fetch(req).first
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
}
