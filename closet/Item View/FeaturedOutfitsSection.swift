//
//  FeaturedOutfitsSection.swift
//  closet
//
//  Created by Dan Warner on 9/21/25.
//


import SwiftUI

/// Preview row for OUTFITS sections: full 3-column outfit grid with tappable chevron column.
struct OutfitsSubsectionRow: View {
    let outfits: [Outfit]
    var isReadOnly: Bool = false
    let onSelectOutfit: (Outfit) -> Void
    let onViewAll: () -> Void

    private var showsChevron: Bool {
        isReadOnly ? outfits.count >= 3 : !outfits.isEmpty
    }

    private var allowsRowViewAll: Bool {
        !outfits.isEmpty && (!isReadOnly || outfits.count >= 3)
    }

    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    private let chevronColumnWidth: CGFloat = 20

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            outfitGrid(outfits)
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
                .accessibilityLabel("View all outfits")
            }
        }
    }

    private func outfitGrid(_ outfits: [Outfit]) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 4) {
            ForEach(outfits, id: \.objectID) { outfit in
                Button {
                    onSelectOutfit(outfit)
                } label: {
                    OutfitView(outfit: outfit, usesFlexibleSizing: true, showsFavoriteOverlay: !isReadOnly)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// OUTFITS section preview for remote/read-only item detail (`VisibleWardrobeOutfit`).
struct RemoteOutfitsSubsectionRow: View {
    let outfits: [VisibleWardrobeOutfit]
    let onSelectOutfit: (VisibleWardrobeOutfit) -> Void
    let onViewAll: () -> Void

    private var showsChevron: Bool { outfits.count >= 3 }
    private var allowsRowViewAll: Bool { outfits.count >= 3 }

    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    private let chevronColumnWidth: CGFloat = 20

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            outfitGrid
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
                .accessibilityLabel("View all outfits")
            }
        }
    }

    private var outfitGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 4) {
            ForEach(outfits) { outfit in
                Button {
                    onSelectOutfit(outfit)
                } label: {
                    RemoteProfileOutfitThumb(outfit: outfit)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct RemoteProfileOutfitThumb: View {
    let outfit: VisibleWardrobeOutfit

    var body: some View {
        Group {
            if let url = outfit.collageImageURL {
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
}

struct FeaturedOutfitsSection: View {
    let outfits: [Outfit]
    let onSelectOutfit: (Outfit) -> Void
    let onViewAllOutfits: () -> Void
    var showsCreateOutfit: Bool = true
    var displayOutfits: Bool = true
    /// Trailing closure maps to Create Outfit (must be last closure parameter).
    let onCreateOutfit: () -> Void

    private var cellSize: CGFloat { (UIScreen.main.bounds.width - 6) / 3 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                if showsCreateOutfit {
                    VStack(alignment: .center, spacing: 0) {
                        Spacer(minLength: 0)

                        Button(action: onCreateOutfit) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.15))
                                .overlay {
                                    VStack(spacing: 6) {
                                        Image(systemName: "plus")
                                            .font(.title3)
                                            .foregroundStyle(.secondary)
                                        Text("Create an Outfit")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Create an outfit")
                        .frame(width: cellSize / 2, height: cellSize / 2)

                        Button(action: onViewAllOutfits) {
                            Text("View All")
                                .underline()
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        .padding(.top)
                        .buttonStyle(.plain)
                        .accessibilityLabel("View all outfits")

                        Spacer(minLength: 0)
                    }
                    .frame(width: cellSize / 2, height: cellSize, alignment: .top)
                } else if !outfits.isEmpty {
                    VStack(alignment: .center, spacing: 0) {
                        Spacer(minLength: 0)

                        Button(action: onViewAllOutfits) {
                            Text("View All")
                                .underline()
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View all outfits")

                        Spacer(minLength: 0)
                    }
                    .frame(width: cellSize / 2, height: cellSize, alignment: .top)
                }

                if displayOutfits {
                    ForEach(outfits, id: \.objectID) { outfit in
                        FeaturedOutfitCell(outfit: outfit, onTap: { onSelectOutfit(outfit) })
                    }
                }
            }
        }
    }
}

struct FeaturedOutfitCell: View {
    @ObservedObject var outfit: Outfit
    let onTap: () -> Void
    let size: CGFloat = (UIScreen.main.bounds.width - 6) / 3

    var body: some View {
        Button(action: onTap) {
            OutfitView(outfit: outfit)
                .frame(width: size, height: size)
                .clipped()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open outfit details")
    }
}

struct OutfitImageView: View {
    @ObservedObject var outfit: Outfit

    var body: some View {
        if let imageData = outfit.image,
           let uiImage = UIImage(data: imageData) {
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
