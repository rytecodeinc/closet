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
    @Binding var selectedCategory: String?
    /// Only outfit categories used by this user's outfits.
    var userId: String? = nil
    
    @State private var categories: [String] = []

    var body: some View {
        List {
            if categories.isEmpty {
                Text("No categories have been added.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(categories, id: \.self) { category in
                    Button {
                        if selectedCategory == category {
                            selectedCategory = nil
                        } else {
                            selectedCategory = category
                        }
                    } label: {
                        HStack {
                            Text(category)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedCategory == category {
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
        let request: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        request.propertiesToFetch = ["category"]
        if let uid = userId {
            request.predicate = NSPredicate(format: "userId == %@", uid)
        }

        do {
            let allOutfits = try viewContext.fetch(request)
            let allCategories = allOutfits.compactMap { $0.category }.filter { !$0.isEmpty }
            categories = Array(Set(allCategories)).sorted()
        } catch {
            print("❌ Failed to fetch categories: \(error)")
            categories = []
        }
    }
}

