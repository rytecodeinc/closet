//
//  FeaturedOutfitsSection.swift
//  closet
//
//  Created by Dan Warner on 9/21/25.
//


import SwiftUI

struct FeaturedOutfitsSection: View {
    let outfits: [Outfit]
    let onSelectOutfit: (Outfit) -> Void
    let onViewAllOutfits: () -> Void
    /// Trailing closure maps to Create Outfit (must be last closure parameter).
    let onCreateOutfit: () -> Void

    private var cellSize: CGFloat { (UIScreen.main.bounds.width - 6) / 3 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
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

                ForEach(outfits, id: \.objectID) { outfit in
                    FeaturedOutfitCell(outfit: outfit, onTap: { onSelectOutfit(outfit) })
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
