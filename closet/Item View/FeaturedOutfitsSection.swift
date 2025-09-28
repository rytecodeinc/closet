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
        Section(header: Text("Featured In")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(outfits, id: \.objectID) { outfit in
                        NavigationLink(destination: OutfitDetailView(outfit: outfit)) {
                            VStack {
                                if let imageData = outfit.image,
                                   let uiImage = UIImage(data: imageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(1, contentMode: .fill)
                                        .frame(width: 80, height: 80)
                                        .clipped()
                                        .cornerRadius(8)
                                        .border(.gray.opacity(0.3))
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.systemGray5))
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .foregroundColor(.gray)
                                        )
                                }

                                Text(outfit.name ?? "Outfit")
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
