//
//  OutfitFilterView.swift
//  closet
//
//  Created by Dan Warner on 12/19/25.
//

import SwiftUI
import Foundation
import CoreData

struct OutfitFilterView: View {
    @ObservedObject var filterModel: OutfitFilterModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var authSession: AuthSession

    private var currentUserId: String? {
        authSession.userId?.uuidString
    }

    var body: some View {
        NavigationStack {
            List {
                // Sort row
                Picker("Sort", selection: $filterModel.sortOrder) {
                    ForEach(ItemSortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                
                // Favorites-only filter (matches ItemFilterView)
                Toggle("Favorites", isOn: $filterModel.favoritesOnly)
                
                // Category filter
                NavigationLink(destination: OutfitCategoryFilterListView(selectedCategory: $filterModel.selectedCategory, userId: currentUserId)) {
                    HStack {
                        Text("Category")
                        Spacer()
                        if let category = filterModel.selectedCategory {
                            Text(category)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }
                
                // Tag filter (nil = show all tags, since outfits can use tags from items and outfits)
                NavigationLink(destination: TagListView(selectedTags: $filterModel.selectedTags, wardrobeType: nil, userId: currentUserId)) {
                    HStack {
                        Text("Tags")
                        Spacer()
                        if !filterModel.selectedTags.isEmpty {
                            Text(filterModel.selectedTags.compactMap { $0.name }.sorted().joined(separator: ", "))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .listStyle(.plain)
            Button("Reset All") {
                filterModel.clearAll()
            }
            .foregroundColor(Color.red)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        dismiss()
                    }
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }
}

