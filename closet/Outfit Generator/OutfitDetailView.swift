//
//  OutfitDetailView.swift
//  closet
//
//  Created by Dan Warner on 9/20/25.
//

import Foundation
import SwiftUI
import CoreData

struct OutfitDetailView: View {
    let outfit: Outfit
    private var screenWidth: CGFloat { UIScreen.main.bounds.width }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Outfit image in a 1:1 square
                if let imageData = outfit.image,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                        .frame(width: screenWidth, height: screenWidth)
                        .clipped()
                        .border(.gray.opacity(0.3), width: 0.5)
                }
                
                // List of items in the outfit
                if let itemsSet = outfit.items as? Set<Item> {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(itemsSet), id: \.objectID) { item in
                            HStack {
                                NavigationLink(destination: ItemDetailView(item: item)) {
                                    if let photoData = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary })?.data,
                                       let uiImage = UIImage(data: photoData) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .aspectRatio(1, contentMode: .fill)
                                            .frame(width: 50, height: 50)
                                            .clipped()
                                            .cornerRadius(6)
                                    } else {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(.systemGray5))
                                            .frame(width: 50, height: 50)
                                    }
                                    
                                    Text(item.name ?? "Unknown Item")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .navigationTitle("Outfit Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
