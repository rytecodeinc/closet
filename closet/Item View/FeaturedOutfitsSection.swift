//
//  FeaturedOutfitsSection.swift
//  closet
//
//  Created by Dan Warner on 9/21/25.
//


import SwiftUI

struct FeaturedOutfitsSection: View {
    let outfits: [Outfit]
    let onCreateOutfit: () -> Void

    private var cellSize: CGFloat { (UIScreen.main.bounds.width - 6) / 3 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                Button(action: onCreateOutfit) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: cellSize / 2, height: cellSize / 2)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                Text("Create an Outfit")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create an outfit")
                .frame(height: cellSize)

                ForEach(outfits, id: \.objectID) { outfit in
                    FeaturedOutfitCell(outfit: outfit)
                }
            }
        }
    }
}

struct FeaturedOutfitCell: View {
    @ObservedObject var outfit: Outfit
    let size: CGFloat = (UIScreen.main.bounds.width - 6) / 3

    var body: some View {
        NavigationLink(destination: OutfitDetailView(outfit: outfit)) {
            VStack {
                OutfitImageView(outfit: outfit)
                    .frame(width: size, height: size)
                  //  .border(.gray.opacity(0.3))
            }
        }
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
