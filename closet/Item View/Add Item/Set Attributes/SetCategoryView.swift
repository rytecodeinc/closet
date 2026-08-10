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

    @State private var selectedCategoryId: UUID?
    @State private var selectedSubcategoryId: UUID?
    @State private var selectedCategoryObjectID: NSManagedObjectID?
    @State private var selectedSubcategoryObjectID: NSManagedObjectID?
    @State private var expanded: Set<NSManagedObjectID> = []
    @State private var loadedCategories: [Category] = []
    @State private var userDidChangeSelection = false

    private var referenceUserId: String? {
        effectiveReferenceDataUserId(signedInUserId: authSession.userId, entityUserId: item.userId)
    }

    var body: some View {
        CategoryPickerList(
            title: "Select Category",
            userId: referenceUserId ?? "",
            expanded: $expanded,
            pinnedCategory: item.category,
            pinnedSubcategory: item.subcategory,
            onCategoriesLoaded: { categories in
                loadedCategories = categories
                if !userDidChangeSelection {
                    seedSelectionFromItem(categories: categories)
                }
            },
            showsCategoryCheckmark: displayCategoryCheckmark(for:),
            showsSubcategoryCheckmark: { _, sub in displaySubcategoryCheckmark(for: sub) },
            onCategoryTap: { category in
                userDidChangeSelection = true
                if isCategoryRowSelected(category) {
                    clearSelection()
                } else {
                    selectedCategoryId = category.id
                    selectedCategoryObjectID = category.objectID
                    selectedSubcategoryId = nil
                    selectedSubcategoryObjectID = nil
                }
            },
            onSubcategoryTap: { category, sub in
                userDidChangeSelection = true
                if isSubcategoryRowSelected(sub) {
                    clearSelection()
                } else {
                    selectedCategoryId = category.id
                    selectedCategoryObjectID = category.objectID
                    selectedSubcategoryId = sub.id
                    selectedSubcategoryObjectID = sub.objectID
                    expanded.insert(category.objectID)
                }
            }
        )
        .onAppear {
            seedSelectionFromItem(categories: loadedCategories)
        }
        .onDisappear {
            guard userDidChangeSelection, !selectionMatchesItem() else { return }
            applySelectionToItem()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Display checkmarks (item is source of truth until user taps)

    private func displayCategoryCheckmark(for category: Category) -> Bool {
        if userDidChangeSelection {
            guard selectedSubcategoryId == nil, selectedSubcategoryObjectID == nil else { return false }
            return pickerCategoriesMatch(category, selectionCategory())
        }
        guard effectiveItemSubcategory() == nil else { return false }
        return pickerCategoriesMatch(item.category, category)
    }

    private func displaySubcategoryCheckmark(for sub: Subcategory) -> Bool {
        if userDidChangeSelection {
            return pickerSubcategoriesMatch(sub, selectionSubcategory())
        }
        return pickerSubcategoriesMatch(effectiveItemSubcategory(), sub)
    }

    private func isCategoryRowSelected(_ category: Category) -> Bool {
        if userDidChangeSelection {
            return pickerCategoriesMatch(category, selectionCategory())
                && selectedSubcategoryId == nil
                && selectedSubcategoryObjectID == nil
        }
        return pickerCategoriesMatch(item.category, category) && effectiveItemSubcategory() == nil
    }

    private func isSubcategoryRowSelected(_ sub: Subcategory) -> Bool {
        if userDidChangeSelection {
            return pickerSubcategoriesMatch(sub, selectionSubcategory())
        }
        return pickerSubcategoriesMatch(effectiveItemSubcategory(), sub)
    }

    /// Subcategory on the item when it belongs to the item's current category.
    private func effectiveItemSubcategory() -> Subcategory? {
        guard let cat = item.category, let sub = item.subcategory,
              subcategoryBelongsToPickerCategory(sub, listCategory: cat) else { return nil }
        return sub
    }

    // MARK: - Selection state

    private func clearSelection() {
        selectedCategoryId = nil
        selectedSubcategoryId = nil
        selectedCategoryObjectID = nil
        selectedSubcategoryObjectID = nil
    }

    /// Seeds pending apply state from the item (expand subcategory row when needed).
    private func seedSelectionFromItem(categories: [Category]) {
        guard let currentCat = item.category else {
            clearSelection()
            return
        }

        let listCat = categories.isEmpty
            ? currentCat
            : (resolveCategoryInPickerList(currentCat, categories: categories) ?? currentCat)
        selectedCategoryId = listCat.id ?? currentCat.id
        selectedCategoryObjectID = listCat.objectID

        if let currentSub = effectiveItemSubcategory(),
           let uid = referenceUserId {
            let subs = viewContext.sortedSubcategoriesForAttributePicker(listCat, userId: uid)
            let listSub = resolveSubcategoryInPickerList(currentSub, subcategories: subs) ?? currentSub
            selectedSubcategoryId = listSub.id ?? currentSub.id
            selectedSubcategoryObjectID = listSub.objectID
            expanded.insert(listCat.objectID)
        } else {
            selectedSubcategoryId = nil
            selectedSubcategoryObjectID = nil
        }
    }

    private func selectionCategory() -> Category? {
        guard let objectID = selectedCategoryObjectID else { return nil }
        return try? viewContext.existingObject(with: objectID) as? Category
    }

    private func selectionSubcategory() -> Subcategory? {
        guard let objectID = selectedSubcategoryObjectID else { return nil }
        return try? viewContext.existingObject(with: objectID) as? Subcategory
    }

    private func selectionMatchesItem() -> Bool {
        let itemSub = effectiveItemSubcategory()
        let pendingSub = selectionSubcategory()
        if pendingSub == nil && itemSub == nil {
            return pickerCategoriesMatch(selectionCategory(), item.category)
        }
        return pickerCategoriesMatch(selectionCategory(), item.category)
            && pickerSubcategoriesMatch(pendingSub, itemSub)
    }

    // MARK: - Apply Selection

    private func applySelectionToItem() {
        guard let categoryObjectID = selectedCategoryObjectID,
              let category = try? viewContext.existingObject(with: categoryObjectID) as? Category else {
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

        let uid = referenceUserId ?? ""
        item.category = uid.isEmpty
            ? category
            : viewContext.canonicalCategoryForAttributePicker(category, userId: uid)

        if let subcategoryObjectID = selectedSubcategoryObjectID,
           let sub = try? viewContext.existingObject(with: subcategoryObjectID) as? Subcategory,
           let parent = item.category,
           subcategoryBelongsToPickerCategory(sub, listCategory: parent) {
            item.subcategory = uid.isEmpty
                ? sub
                : viewContext.canonicalSubcategoryForAttributePicker(sub, parent: parent, userId: uid)
        } else {
            item.subcategory = nil
        }

        setUpdatedAt(item)

        if viewContext.parent == nil {
            do {
                try viewContext.save()
            } catch {
                print("❌ Failed to save category: \(error.localizedDescription)")
            }
        }
    }
}
