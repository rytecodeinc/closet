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
    @ObservedObject var outfit: Outfit
    @Environment(\.dismiss) private var dismiss
    
    private var screenWidth: CGFloat { UIScreen.main.bounds.width }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                // Outfit image in a 1:1 square
                if let imageData = outfit.image,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                        .frame(width: screenWidth, height: screenWidth)
                        .clipped()
                      //  .border(.gray.opacity(0.3), width: 0.5)
                }
                
                LazyVStack(spacing: 4, pinnedViews: [.sectionHeaders]) {
                    Section(header:
                                Text("ITEMS FEATURED")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color(.systemBackground)) // prevents overlay artifacts
                    ) {
                        if let itemsSet = outfit.items as? Set<Item>, !itemsSet.isEmpty {
                            let gridItems = [
                                GridItem(.flexible(), spacing: 4),
                                GridItem(.flexible(), spacing: 4)
                            ]
                            LazyVGrid(columns: gridItems, spacing: 4) {
                                ForEach(Array(itemsSet), id: \.objectID) { item in
                                    NavigationLink(destination: ItemDetailView(item: item)) {
                                        ItemView(item: item)
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
                

            }
        }
        .navigationTitle("Outfit Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            NavigationLink(destination: OutfitCanvasView(outfitToEdit: outfit)) {
                Image(systemName: "paintbrush.pointed")
            }
        }
    }
}
