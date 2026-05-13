//
//  OutfitView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//


import SwiftUI
import CoreData

struct OutfitView: View {
    @ObservedObject var outfit: Outfit

    // Matches the soft neutral color you used for items
    private let backgroundColor = Color(red: 247/255, green: 247/255, blue: 247/255)

    var body: some View {
        VStack(spacing: 2) {
            // Outfit image
            if let imageData = outfit.image,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(minWidth: 120, minHeight: 120)
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        if outfit.isFavorite {
                            // Match `ItemView` favorites styling
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.black.opacity(0.85),
                                    Color.black.opacity(0.65),
                                    Color.black.opacity(0.55),
                                    Color.gray.opacity(0.55),
                                    Color.clear
                                ]),
                                center: UnitPoint(x: -0.2, y: 1.5),
                                startRadius: 0,
                                endRadius: 100
                            )
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if outfit.isFavorite {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 12))
                                .padding(.leading, 6)
                                .padding(.bottom, 6)
                        }
                    }
                   // .background(backgroundColor)
            } else {
                Rectangle()
                  //  .fill(backgroundColor)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(minWidth: 120, minHeight: 120)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                            .font(.system(size: 20))
                    )
                    .overlay(alignment: .bottomLeading) {
                        if outfit.isFavorite {
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.black.opacity(0.85),
                                    Color.black.opacity(0.65),
                                    Color.black.opacity(0.55),
                                    Color.gray.opacity(0.55),
                                    Color.clear
                                ]),
                                center: UnitPoint(x: -0.2, y: 1.5),
                                startRadius: 0,
                                endRadius: 100
                            )
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if outfit.isFavorite {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 12))
                                .padding(.leading, 6)
                                .padding(.bottom, 6)
                        }
                    }
            }

            /* Optional outfit info below the image
            VStack(alignment: .leading, spacing: 2) {
                if let name = outfit.name, !name.isEmpty {
                    Text(name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                if let timestamp = outfit.timestamp {
                    Text(timestamp, style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 2)*/
        }
        .contentShape(Rectangle()) // ensures full tap area in NavigationLink
    }
}
