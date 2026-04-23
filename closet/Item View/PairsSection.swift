//
//  SetsSection.swift
//  closet
//
//  Created by Dan Warner on 12/19/25.
//

import SwiftUI

struct PairsSection: View {
    let pairedItems: [Item]
    let onManagePairs: () -> Void

    private var cellSize: CGFloat { (UIScreen.main.bounds.width - 6) / 3 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                Button(action: onManagePairs) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: cellSize, height: cellSize)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                Text("Select an Item")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Manage pairs")

                ForEach(pairedItems, id: \.objectID) { item in
                    SetItemCell(item: item)
                }
            }
        }
    }
}

struct SetItemCell: View {
    @ObservedObject var item: Item
    let size: CGFloat = (UIScreen.main.bounds.width - 6) / 3

    var body: some View {
        NavigationLink(destination: ItemDetailView(item: item)) {
            VStack {
                ItemImageView(item: item)
                    .frame(width: size, height: size)
            }
        }
    }
}

struct ItemImageView: View {
    @ObservedObject var item: Item

    var displayImage: UIImage? {
        // For grid views, prefer thumbnail for performance
        if let primaryPhoto = item.photos?.first(where: { ($0 as? Photo)?.isPrimary == true }) as? Photo {
            // Use thumbnail if available, fallback to full image
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

