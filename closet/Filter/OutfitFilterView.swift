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
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var authSession: AuthSession

    var wardrobeType: String = "closet"
    /// When true (e.g. profile wardrobe preview), only filters for attributes visible in read-only outfit detail.
    var attributesReadOnly: Bool = false
    /// When true (other-user profile grid), only show filters backed by visible wardrobe RPC fields.
    var remoteProfileMode: Bool = false
    var selectedWardrobe: Wardrobe?

    private var currentUserId: String? {
        authSession.userId?.uuidString
    }

    var body: some View {
        List {
                Picker("Sort", selection: $filterModel.sortOrder) {
                    ForEach(ItemSortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)

                if !remoteProfileMode {
                    Toggle("Favorites", isOn: $filterModel.favoritesOnly)
                }

                NavigationLink(value: OutfitFilterAttributeRoute.category) {
                    HStack {
                        filterAttributeLabel(
                            "Category",
                            selectionCount: filterModel.selectedCategory == nil ? 0 : 1
                        )
                        Spacer()
                        if let category = filterModel.selectedCategory {
                            Text(category.name ?? "")
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }

                if !remoteProfileMode {
                    NavigationLink(value: OutfitFilterAttributeRoute.tags) {
                        HStack {
                            filterAttributeLabel(
                                "Tags",
                                selectionCount: filterModel.filterTagsNotSet
                                    ? 1
                                    : filterModel.selectedTags.count
                            )
                            Spacer()
                            if let tagsLabel = filterModel.selectedTagsDisplayLabel {
                                Text(tagsLabel)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                Section {
                    FilterResetAllButton {
                        filterModel.clearAll()
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: OutfitFilterAttributeRoute.self) { route in
                switch route {
                case .category:
                    OutfitCategoryFilterListView(
                        selectedCategory: $filterModel.selectedCategory,
                        userId: currentUserId,
                        outfitFilterWardrobe: selectedWardrobe
                    )
                case .tags:
                    TagFilterListView(
                        selectedTags: $filterModel.selectedTags,
                        filterNotSet: $filterModel.filterTagsNotSet,
                        source: .outfits,
                        wardrobeType: wardrobeType,
                        userId: currentUserId,
                        outfitFilterWardrobe: selectedWardrobe
                    )
                }
            }
            .toolbar {
                if remoteProfileMode {
                    ToolbarItem(placement: .principal) {
                        Text("Filter")
                            .font(.profileSerif(.headline, weight: .semibold))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    OutfitFilterApplyButton()
                }
            }
            .modifier(OtherUserProfileSerifModifier(isActive: remoteProfileMode))
    }

    private func filterAttributeLabel(_ title: String, selectionCount: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
            FilterSelectionCountBadge(count: selectionCount)
        }
    }
}

/// Holds `dismiss` so `OutfitFilterView` (which owns navigation) does not — matches ItemFilter Apply pattern.
private struct OutfitFilterApplyButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Apply") {
            dismiss()
        }
    }
}
