//
//  SetsSection.swift
//  closet
//
//  Created by Dan Warner on 12/19/25.
//

import SwiftUI

/// Preview for ITEMS sections: optional wardrobe labels, full 3-column item grid, chevron centered on the grid.
struct FeaturedItemsSubsectionRow: View {
    let pairedItems: [Item]
    var wishlistItems: [Item] = []
    var closetItems: [Item] = []
    var showsWardrobeLabels: Bool = false
    var isReadOnly: Bool = false
    let onSelectPairedItem: (Item) -> Void
    let onViewAll: () -> Void

    private var showsChevron: Bool {
        isReadOnly ? pairedItems.count >= 3 : !pairedItems.isEmpty
    }

    private var allowsRowViewAll: Bool {
        !pairedItems.isEmpty && (!isReadOnly || pairedItems.count >= 3)
    }

    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    private let chevronColumnWidth: CGFloat = 20

    private var shouldSplitByWardrobeType: Bool {
        showsWardrobeLabels && (!wishlistItems.isEmpty || !closetItems.isEmpty)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            VStack(alignment: .leading, spacing: 4) {
                if shouldSplitByWardrobeType {
                    if !wishlistItems.isEmpty {
                        wardrobeLabel("WISHLIST")
                            .padding(.top, 4)
                        itemGrid(wishlistItems)
                    }
                    if !closetItems.isEmpty {
                        wardrobeLabel("CLOSET")
                            .padding(.top, wishlistItems.isEmpty ? 4 : 0)
                        itemGrid(closetItems)
                    }
                } else {
                    itemGrid(pairedItems)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsChevron {
                Button(action: onViewAll) {
                    Color.clear
                        .overlay {
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: chevronColumnWidth)
                .frame(maxHeight: .infinity, alignment: .center)
                .disabled(!allowsRowViewAll)
                .accessibilityLabel("View all items")
            }
        }
    }

    private func wardrobeLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func itemGrid(_ items: [Item]) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 4) {
            ForEach(items, id: \.objectID) { item in
                SetItemCell(item: item, usesFlexibleWidth: true, showsFavoriteOverlay: !isReadOnly) {
                    onSelectPairedItem(item)
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
    }
}

struct PairsSection: View {
    let pairedItems: [Item]
    let onManagePairs: () -> Void
    let onViewAll: () -> Void
    let onSelectPairedItem: (Item) -> Void
    var showsManagePairs: Bool = true
    var displayPairedItems: Bool = true

    private var cellSize: CGFloat { (UIScreen.main.bounds.width - 6) / 3 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                if showsManagePairs {
                    VStack(alignment: .center, spacing: 0) {
                        Spacer(minLength: 0)

                        Button(action: onManagePairs) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.15))
                                .overlay {
                                    VStack(spacing: 6) {
                                        Image(systemName: "link")
                                            .font(.title3)
                                            .foregroundStyle(.secondary)
                                        Text("Select an Item")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select an item to pair")
                        .frame(width: cellSize / 2, height: cellSize / 2)

                        Button(action: onViewAll) {
                            Text("View All")
                                .underline()
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        .padding(.top)
                        .buttonStyle(.plain)
                        .accessibilityLabel("View all paired items")

                        Spacer(minLength: 0)
                    }
                    .frame(width: cellSize / 2, height: cellSize, alignment: .top)
                } else if !pairedItems.isEmpty {
                    VStack(alignment: .center, spacing: 0) {
                        Spacer(minLength: 0)

                        Button(action: onViewAll) {
                            Text("View All")
                                .underline()
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View all paired items")

                        Spacer(minLength: 0)
                    }
                    .frame(width: cellSize / 2, height: cellSize, alignment: .top)
                }

                if displayPairedItems {
                    ForEach(pairedItems, id: \.objectID) { item in
                        SetItemCell(item: item) {
                            onSelectPairedItem(item)
                        }
                    }
                }
            }
        }
    }
}

struct GridItemRemoveButton: View {
    var accessibilityLabel: String = "Remove"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .background(Color.white)
                .clipShape(Circle())
                .font(.system(size: 20))
        }
        .buttonStyle(.plain)
        .padding(4)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct SetItemCell: View {
    @ObservedObject var item: Item
    var usesFlexibleWidth: Bool = false
    var showsFavoriteOverlay: Bool = true
    let onSelect: () -> Void
    private let fixedSize: CGFloat = (UIScreen.main.bounds.width - 6) / 3

    var body: some View {
        Button(action: onSelect) {
            if usesFlexibleWidth {
                ItemView(item: item, usesFlexibleSizing: true, showsFavoriteOverlay: showsFavoriteOverlay)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
            } else {
                ItemView(item: item, showsFavoriteOverlay: showsFavoriteOverlay)
                    .frame(width: fixedSize, height: fixedSize)
            }
        }
        .buttonStyle(.plain)
    }
}

/// ITEMS section preview for Redress mode (remote recipient items on canvas).
struct RedressFeaturedItemsSubsectionRow: View {
    let pairedItems: [VisibleWardrobeItem]
    /// Named wardrobe groups when canvas items come from more than one wardrobe.
    var wardrobeSections: [RedressWardrobeItemsSection] = []
    var showsWardrobeLabels: Bool = false
    var isReadOnly: Bool = false
    let onSelectItem: (VisibleWardrobeItem) -> Void
    let onViewAll: () -> Void

    private var showsChevron: Bool {
        isReadOnly ? pairedItems.count >= 3 : !pairedItems.isEmpty
    }

    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    private let chevronColumnWidth: CGFloat = 20

    private var shouldSplitByNamedWardrobes: Bool {
        showsWardrobeLabels && wardrobeSections.count >= 2
    }

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            VStack(alignment: .leading, spacing: 4) {
                if shouldSplitByNamedWardrobes {
                    ForEach(Array(wardrobeSections.enumerated()), id: \.element.id) { index, section in
                        wardrobeLabel(section.name.uppercased())
                            .padding(.top, index == 0 ? 4 : 0)
                        itemGrid(section.items)
                    }
                } else {
                    itemGrid(pairedItems)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsChevron {
                Button(action: onViewAll) {
                    Color.clear
                        .overlay {
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: chevronColumnWidth)
                .frame(maxHeight: .infinity, alignment: .center)
                .accessibilityLabel("View all items")
            }
        }
    }

    private func wardrobeLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func itemGrid(_ items: [VisibleWardrobeItem]) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 4) {
            ForEach(items) { item in
                RedressSetItemCell(item: item) {
                    onSelectItem(item)
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
    }
}

struct RedressSetItemCell: View {
    let item: VisibleWardrobeItem
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Group {
                if let url = item.displayImageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(1, contentMode: .fill)
                        case .failure:
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        default:
                            ProgressView()
                        }
                    }
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipped()
        }
        .buttonStyle(.plain)
    }
}

struct ItemImageView: View {
    @ObservedObject var item: Item

    var displayImage: UIImage? {
        if let primaryPhoto = item.photos?.first(where: { ($0 as? Photo)?.isPrimary == true }) as? Photo {
            if let thumbnailData = primaryPhoto.thumbnailData, !thumbnailData.isEmpty {
                return UIImage(data: thumbnailData)
            } else if let fullData = primaryPhoto.data {
                return UIImage(data: fullData)
            }
        } else if let fallbackImage = item.image {
            return UIImage(data: fallbackImage)
        }
        return nil
    }

    var body: some View {
        if let uiImage = displayImage {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(1, contentMode: .fill)
                .clipped()
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.gray)
                )
        }
    }
}
