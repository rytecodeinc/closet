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
    @EnvironmentObject private var authSession: AuthSession

    @State private var selectedCategoryName: String?
    @State private var selectedSubcategoryName: String?
    @State private var expanded: Set<NSManagedObjectID> = []

    private var referenceUserId: String? {
        effectiveReferenceDataUserId(signedInUserId: authSession.userId, entityUserId: item.userId)
    }

    var body: some View {
        CategoryPickerList(
            title: "Select Category",
            userId: referenceUserId ?? "",
            expanded: $expanded,
            onCategoriesLoaded: configureInitialSelection(categories:),
            showsCategoryCheckmark: { category in
                let name = category.name ?? ""
                return selectedCategoryName == name && selectedSubcategoryName == nil
            },
            showsSubcategoryCheckmark: { category, sub in
                let name = category.name ?? ""
                let subName = sub.name ?? ""
                return selectedCategoryName == name && selectedSubcategoryName == subName
            },
            onCategoryTap: { category in
                let name = category.name ?? ""
                if selectedCategoryName == name && selectedSubcategoryName == nil {
                    selectedCategoryName = nil
                    selectedSubcategoryName = nil
                } else {
                    selectedCategoryName = name
                    selectedSubcategoryName = nil
                }
            },
            onSubcategoryTap: { category, sub in
                let name = category.name ?? ""
                let subName = sub.name ?? ""
                let isThisSelected = selectedCategoryName == name && selectedSubcategoryName == subName
                if isThisSelected {
                    selectedCategoryName = nil
                    selectedSubcategoryName = nil
                } else {
                    selectedCategoryName = name
                    selectedSubcategoryName = subName
                }
            }
        )
        .onDisappear {
            applySelectionToItem()
        }
        .presentationDetents([.medium, .large])
    }

    private func configureInitialSelection(categories: [Category]) {
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

    // MARK: - Apply Selection

    private func applySelectionToItem() {
        guard let catName = selectedCategoryName, !catName.isEmpty else {
            item.category = nil
            item.subcategory = nil

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

        setUpdatedAt(item)

        if viewContext.parent == nil {
            do {
                try viewContext.save()
                SyncService.shared.syncItemIfNeeded(item)
            } catch {
                print("❌ Failed to save category: \(error.localizedDescription)")
            }
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
}
