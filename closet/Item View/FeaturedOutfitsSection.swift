//
//  FeaturedOutfitsSection.swift
//  closet
//
//  Created by Dan Warner on 9/21/25.
//


import SwiftUI

struct FeaturedOutfitsSection: View {
    let outfits: [Outfit]

    var body: some View {
        Section(header: Text("FEATURED OUTFITS")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(outfits, id: \.objectID) { outfit in
                        FeaturedOutfitCell(outfit: outfit)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct FeaturedOutfitCell: View {
    let outfit: Outfit

    var body: some View {
        NavigationLink(destination: OutfitDetailView(outfit: outfit)) {
            VStack {
                OutfitImageView(outfit: outfit)
                    .frame(width: 80, height: 80)
                    .cornerRadius(8)
                    .border(.gray.opacity(0.3))
            }
        }
    }
}

struct OutfitImageView: View {
    let outfit: Outfit

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
