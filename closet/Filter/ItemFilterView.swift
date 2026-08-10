//
//  FilterView.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//

import SwiftUI
import Foundation
import CoreData

struct ItemFilterView: View {
    /// Live model owned by Closet / Wishlist / Profile — only updated on Apply.
    @ObservedObject var filterModel: ItemFilterModel
    /// Tab-bar visibility driven by `ItemGridView`.
    @ObservedObject var tabBarHideState: TabBarHideState
    /// Working copy edited in this screen; discarded if the user navigates Back.
    @StateObject private var draftFilterModel = ItemFilterModel()
    @State private var didSeedDraft = false

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appCapabilities) private var appCapabilities
    @EnvironmentObject private var authSession: AuthSession

    var wardrobeType: String = "closet" // Default to "closet" for backward compatibility
    /// When true (e.g. profile wardrobe preview), hide filters for attributes not shown in read-only detail.
    var attributesReadOnly: Bool = false
    /// When true (other-user profile grid), only show filters backed by visible wardrobe RPC fields.
    var remoteProfileMode: Bool = false
    /// Current closet/wishlist tab; when non-default, wardrobe filter row is hidden.
    var selectedWardrobe: Wardrobe?

    private var showsWardrobeFilter: Bool {
        selectedWardrobe?.isDefault == true
    }

    private var currentUserId: String? {
        authSession.userId?.uuidString
    }

    private var filterWardrobeScope: [Wardrobe] {
        guard let selectedWardrobe else { return [] }
        return draftFilterModel.wardrobeScopeForFilter(
            viewingWardrobe: selectedWardrobe,
            wardrobeType: wardrobeType
        )
    }

    /// Label when no secondary wardrobes are selected in the filter sheet (current default tab wardrobe).
    private var defaultWardrobeFilterLabel: String {
        let trimmed = selectedWardrobe?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return wardrobeType == "wishlist" ? "Wishlist" : "Closet"
    }

    var body: some View {
        List {
                Picker("Sort", selection: $draftFilterModel.sortOrder) {
                    ForEach(ItemSortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)

                if !remoteProfileMode {
                    Toggle("Favorites", isOn: $draftFilterModel.favoritesOnly)
                }

                if showsWardrobeFilter, !attributesReadOnly, !remoteProfileMode {
                    NavigationLink(value: ItemFilterAttributeRoute.wardrobes) {
                        HStack {
                            filterAttributeLabel(
                                "Wardrobes",
                                selectionCount: draftFilterModel
                                    .secondaryFilterWardrobes(matchingType: wardrobeType)
                                    .count
                            )
                            Spacer()
                            let secondaryNames = draftFilterModel
                                .secondaryFilterWardrobes(matchingType: wardrobeType)
                                .compactMap(\.name)
                                .sorted()
                            if secondaryNames.isEmpty {
                                Text(defaultWardrobeFilterLabel)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            } else {
                                Text(secondaryNames.joined(separator: ", "))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                NavigationLink(value: ItemFilterAttributeRoute.category) {
                    HStack {
                        filterAttributeLabel(
                            "Category",
                            selectionCount: draftFilterModel.selectedCategoryName == nil ? 0 : 1
                        )
                        Spacer()
                        if let categoryName = draftFilterModel.selectedCategoryDisplayName {
                            if let subcategoryName = draftFilterModel.selectedSubcategoryName,
                               !draftFilterModel.isCategoryNotSetFilter {
                                Text("\(categoryName) • \(subcategoryName)")
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            } else {
                                Text(categoryName)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                NavigationLink(value: ItemFilterAttributeRoute.brand) {
                    HStack {
                        filterAttributeLabel(
                            "Brand",
                            selectionCount: draftFilterModel.selectedBrandName == nil ? 0 : 1
                        )
                        Spacer()
                        if let brandName = draftFilterModel.selectedBrandDisplayName {
                            Text(brandName)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }

                NavigationLink(value: ItemFilterAttributeRoute.size) {
                    HStack {
                        filterAttributeLabel(
                            "Size",
                            selectionCount: (draftFilterModel.selectedSizeValue?.isEmpty == false) ? 1 : 0
                        )
                        Spacer()
                        if let sizeValue = draftFilterModel.selectedSizeDisplayName {
                            Text(sizeValue)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }

                if !remoteProfileMode {
                    NavigationLink(value: ItemFilterAttributeRoute.colors) {
                        HStack {
                            filterAttributeLabel(
                                "Colors",
                                selectionCount: draftFilterModel.isColorNotSetFilter
                                    ? 1
                                    : draftFilterModel.selectedColors.count
                            )
                            Spacer()
                            if let colorsLabel = draftFilterModel.selectedColorsDisplayLabel {
                                Text(colorsLabel)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                /*
                // Season filter
                NavigationLink(destination: SeasonListView(selectedSeasonNames: $draftFilterModel.selectedSeasons)) {
                    HStack {
                        Text("Seasons")
                        Spacer()
                        if !draftFilterModel.selectedSeasons.isEmpty {
                            Text(draftFilterModel.selectedSeasons.sorted().joined(separator: ", "))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }
                */

                if !attributesReadOnly, !remoteProfileMode {
                    NavigationLink(value: ItemFilterAttributeRoute.location) {
                        HStack {
                            filterAttributeLabel(
                                "Location",
                                selectionCount: (draftFilterModel.selectedLocation != nil
                                    || draftFilterModel.filterLocationNotSet) ? 1 : 0
                            )
                            Spacer()
                            if let locationName = draftFilterModel.selectedLocationDisplayName {
                                Text(locationName)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                if !remoteProfileMode {
                    NavigationLink(value: ItemFilterAttributeRoute.tags) {
                        HStack {
                            filterAttributeLabel(
                                "Tags",
                                selectionCount: draftFilterModel.filterTagsNotSet
                                    ? 1
                                    : draftFilterModel.selectedTags.count
                            )
                            Spacer()
                            if let tagsLabel = draftFilterModel.selectedTagsDisplayLabel {
                                Text(tagsLabel)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                if !attributesReadOnly, !remoteProfileMode {
                HStack {
                    Text("Price")
                    Spacer()
                    HStack {
                        TextField("Min Price", value: $draftFilterModel.minPrice, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .padding(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                            )
                            .frame(width: 100)
                        Text("—")
                            .foregroundColor(.black)
                            .frame(minWidth: 10)
                        TextField("Max Price", value: $draftFilterModel.maxPrice, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .padding(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                            )
                            .frame(width: 100)

                    }
                }
                }

                if !attributesReadOnly, !remoteProfileMode, appCapabilities.showsWeightAttribute {
                    HStack {
                        Text("Weight")
                            .foregroundColor(.primary)
                        Spacer()

                        if draftFilterModel.filterByWeight {
                            let repository = UserProfileRepository(context: viewContext)
                            let userWeightKg = repository.getWeightKg()
                            let userWeightUnit = repository.getWeightUnit()

                            if userWeightKg > 0 {
                                let displayWeight = userWeightUnit == "kg" ? userWeightKg : userWeightKg * 2.20462
                                Text("\(String(format: "%.1f", displayWeight)) \(userWeightUnit)")
                                    .foregroundColor(.gray)
                                    .font(.subheadline)
                            } else {
                                Text("Set in Profile")
                                    .foregroundColor(.orange)
                                    .font(.subheadline)
                            }
                        }

                        Toggle("", isOn: $draftFilterModel.filterByWeight)
                            .labelsHidden()
                    }
                }

                Section {
                    FilterResetAllButton {
                        draftFilterModel.clearAll()
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ItemFilterAttributeRoute.self) { route in
                attributeDestinationView(route)
            }
            .toolbar {
                if remoteProfileMode {
                    ToolbarItem(placement: .principal) {
                        Text("Filter")
                            .font(.profileSerif(.headline, weight: .semibold))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ItemFilterApplyButton {
                        filterModel.copyValues(from: draftFilterModel)
                    }
                }
            }
            .toolbar(tabBarHideState.shouldHideTabBar ? .hidden : .automatic, for: .tabBar)
            .modifier(OtherUserProfileSerifModifier(isActive: remoteProfileMode))
            .onAppear {
                tabBarHideState.shouldHideTabBar = true
                guard !didSeedDraft else { return }
                draftFilterModel.copyValues(from: filterModel)
                didSeedDraft = true
            }
    }

    private func filterAttributeLabel(_ title: String, selectionCount: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
            FilterSelectionCountBadge(count: selectionCount)
        }
    }

    @ViewBuilder
    private func attributeDestinationView(_ route: ItemFilterAttributeRoute) -> some View {
        switch route {
        case .wardrobes:
            WardrobeListView(
                selectedWardrobes: $draftFilterModel.selectedWardrobes,
                defaultWardrobeType: wardrobeType,
                userId: currentUserId,
                filterSelectionMode: true
            )
        case .category:
            CategoryFilterListView(
                selectedCategoryName: $draftFilterModel.selectedCategoryName,
                selectedSubcategoryName: $draftFilterModel.selectedSubcategoryName,
                userId: currentUserId,
                wardrobes: filterWardrobeScope,
                wardrobeType: wardrobeType
            )
        case .brand:
            BrandListView(
                selectedBrandName: $draftFilterModel.selectedBrandName,
                userId: currentUserId,
                wardrobes: filterWardrobeScope,
                wardrobeType: wardrobeType
            )
        case .size:
            SizeFilterListView(
                selectedSizeValue: $draftFilterModel.selectedSizeValue,
                userId: currentUserId,
                itemsOnly: true,
                wardrobes: filterWardrobeScope,
                wardrobeType: wardrobeType
            )
        case .colors:
            ColorListView(
                selectedColorNames: $draftFilterModel.selectedColors,
                userId: currentUserId,
                itemsOnly: true,
                wardrobes: filterWardrobeScope,
                wardrobeType: wardrobeType
            )
        case .location:
            LocationListView(
                selectedLocation: $draftFilterModel.selectedLocation,
                filterNotSet: $draftFilterModel.filterLocationNotSet,
                userId: currentUserId,
                wardrobes: filterWardrobeScope,
                wardrobeType: wardrobeType
            )
        case .tags:
            TagFilterListView(
                selectedTags: $draftFilterModel.selectedTags,
                filterNotSet: $draftFilterModel.filterTagsNotSet,
                source: .items,
                wardrobeType: wardrobeType,
                userId: currentUserId,
                wardrobes: filterWardrobeScope
            )
        }
    }
}

/// Holds `dismiss` so `ItemFilterView` (which owns navigation) does not — avoids SwiftUI freeze.
private struct ItemFilterApplyButton: View {
    @Environment(\.dismiss) private var dismiss
    let onApply: () -> Void

    var body: some View {
        Button("Apply") {
            onApply()
            dismiss()
        }
    }
}
