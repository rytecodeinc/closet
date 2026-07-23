//
//  OutfitCategoryFilterListView.swift
//  closet
//
//  Created by Dan Warner on 12/19/25.
//

import SwiftUI
import CoreData

struct OutfitCategoryFilterListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedCategory: OutfitCategory?
    /// Only outfit categories used by this user's visible outfits.
    var userId: String? = nil
    /// When set, only categories on outfits visible in this wardrobe tab appear.
    var outfitFilterWardrobe: Wardrobe? = nil

    @State private var categories: [OutfitCategory] = []

    private var emptyStateLabel: String {
        if outfitFilterWardrobe?.type?.lowercased() == "wishlist" {
            return "Categories added to outfits in this wishlist will appear here."
        }
        if outfitFilterWardrobe?.type?.lowercased() == "closet" {
            return "Categories added to outfits in this closet will appear here."
        }
        return "No categories have been added."
    }

    var body: some View {
        List {
            if categories.isEmpty {
                Text(emptyStateLabel)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(categories, id: \.objectID) { category in
                    Button {
                        if selectedCategory?.objectID == category.objectID {
                            selectedCategory = nil
                        } else {
                            selectedCategory = category
                        }
                    } label: {
                        HStack {
                            Text(category.name ?? "")
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedCategory?.objectID == category.objectID {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Select Category")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchCategories()
        }
    }

    // MARK: - Fetch Categories
    private func fetchCategories() {
        guard let uid = userId, !uid.isEmpty else {
            categories = []
            return
        }
        do {
            categories = try viewContext.fetchOutfitCategoriesForFilterList(
                userId: uid,
                wardrobe: outfitFilterWardrobe
            )
        } catch {
            print("❌ Failed to fetch categories: \(error)")
            categories = []
        }
    }
}
