//
//  ItemFilterSortSearchBar.swift
//  closet
//

import SwiftUI

/// Filter / Sort / Search action row shared by item grids (e.g. `ItemGridView`, outfit add items sheet).
struct ItemFilterSortSearchBar: View {
    @Binding var sortOrder: ItemSortOrder
    @Binding var searchQuery: String
    @Binding var isSearchActive: Bool
    var isSearchFocused: FocusState<Bool>.Binding
    var onFilter: () -> Void
    var onDismissSearch: () -> Void
    var onPack: (() -> Void)? = nil
    /// Optional trailing Redress action (profile outfits tab). Shown after Search / Pack.
    var onRedress: (() -> Void)? = nil
    /// When true, Redress button uses a selected background (toggle on).
    var isRedressFilterActive: Bool = false
    /// Active filter-dimension count shown as a red badge on Filter (0 hides the badge).
    var activeFilterCount: Int = 0
    var searchPlaceholder: String = "Name, brand, category, color, tag"
    var barHeight: CGFloat = 44
    var backgroundColor: Color = Color(.systemBackground)
    @Environment(\.usesProfileSerifTypography) private var usesProfileSerifTypography

    private func labelFont(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        usesProfileSerifTypography
            ? .system(style, design: .serif).weight(weight)
            : .system(style).weight(weight)
    }

    var body: some View {
        Group {
            if isSearchActive {
                searchBar
            } else {
                buttonsBar
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(height: barHeight)
        .background(backgroundColor)
    }

    private var buttonsBar: some View {
        HStack(spacing: 0) {
            Button(action: onFilter) {
                filterActionLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                activeFilterCount > 0
                    ? "Filter, \(activeFilterCount) applied"
                    : "Filter"
            )

            Menu {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(ItemSortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
            } label: {
                actionLabel(title: "Sort", systemImage: "arrow.up.arrow.down")
            }
            .buttonStyle(.plain)

            Button {
                isSearchActive = true
                isSearchFocused.wrappedValue = true
            } label: {
                actionLabel(title: "Search", systemImage: "magnifyingglass")
            }
            .buttonStyle(.plain)

            if let onPack {
                Button(action: onPack) {
                    actionLabel(title: "Pack", systemImage: "suitcase")
                }
                .buttonStyle(.plain)
            }

            if let onRedress {
                Button(action: onRedress) {
                    HStack(spacing: 4) {
                        Image("Redress.SFSymbol")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(isRedressFilterActive ? Color.white : Color.black)
                            .frame(width: 16, height: 16)
                            .fixedSize(horizontal: true, vertical: true)
                            .transaction { $0.animation = nil }
                        Text("Redress")
                            .font(labelFont(.subheadline))
                            .foregroundStyle(isRedressFilterActive ? Color.white : Color.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background {
                        if isRedressFilterActive {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.cayenne.gradient)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Redress")
                .accessibilityAddTraits(isRedressFilterActive ? .isSelected : [])
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(labelFont(.body))
                .foregroundStyle(.secondary)

            TextField(searchPlaceholder, text: $searchQuery)
                .textFieldStyle(.plain)
                .font(labelFont(.subheadline))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused(isSearchFocused)
                .submitLabel(.search)

            Button("Cancel") {
                onDismissSearch()
            }
            .font(labelFont(.subheadline))
        }
        .onAppear {
            isSearchFocused.wrappedValue = true
        }
    }

    private var filterActionLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(labelFont(.body))
                .overlay(alignment: .topTrailing) {
                    FilterSelectionCountBadge(count: activeFilterCount)
                        .offset(x: 6, y: -6)
                }
            Text("Filter")
                .font(labelFont(.subheadline))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func actionLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(labelFont(.body))
            Text(title)
                .font(labelFont(.subheadline))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// Red circle count badge used on Filter and on `ItemFilterView` / `OutfitFilterView` row labels.
struct FilterSelectionCountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, count > 9 ? 3 : 0)
                .frame(minWidth: 14, minHeight: 14)
                .background(Circle().fill(Color.red))
        }
    }
}

/// Full-width cayenne reset control shared by item and outfit filter screens.
struct FilterResetAllButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Reset All")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(.cayenne.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
