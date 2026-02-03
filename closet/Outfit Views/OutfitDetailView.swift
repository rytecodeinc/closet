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
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var attributesSheet: OutfitAttributesSectionView.Sheet?
    @State private var isFeaturedItemsExpanded = true
    
    private var screenWidth: CGFloat { UIScreen.main.bounds.width }
    
    // Computed property to get ordered items array (preserves insertion order from canvas)
    private var orderedItems: [Item] {
        // Try to use transformationData first (preserves order from canvas)
        if let transformationData = outfit.transformationData {
            let decoder = JSONDecoder()
            if let savedItems = try? decoder.decode([SavedOutfitItem].self, from: transformationData) {
                let itemsSet = outfit.items as? Set<Item> ?? []
                var itemsDict: [String: Item] = [:]
                for item in itemsSet {
                    let itemID = item.objectID.uriRepresentation().absoluteString
                    itemsDict[itemID] = item
                }
                // Return items in the order they appear in transformationData
                return savedItems.compactMap { savedItem in
                    itemsDict[savedItem.itemID]
                }
            }
        }
        // Fallback: if no transformationData, use Set (unordered, but better than nothing)
        if let itemsSet = outfit.items as? Set<Item> {
            return Array(itemsSet)
        }
        return []
    }
    
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
                
                // Featured Items Toggle Row
                featuredItemsToggleRow()
                  //  .padding(.horizontal, 6)
                // Divider before Featured Items
                Divider()
                    .padding(.leading, 12)
                // Featured Items Grid (shown when expanded)
                if isFeaturedItemsExpanded {
                    if !orderedItems.isEmpty {
                        let gridItems = [
                            GridItem(.flexible(), spacing: 4),
                            GridItem(.flexible(), spacing: 4),
                            GridItem(.flexible(), spacing: 4)
                        ]
                        LazyVGrid(columns: gridItems, spacing: 4) {
                            ForEach(orderedItems, id: \.objectID) { item in
                                NavigationLink(destination: ItemDetailView(item: item)) {
                                    ItemView(item: item)
                                }
                            }
                        }
                      //  .padding(.horizontal, 10)
                      //  .padding(.top, 4)
                    }
                }
                
                
                
                // Attributes Section
                OutfitAttributesSectionView(outfit: outfit, activeSheet: $attributesSheet)
                   // .padding(.horizontal, 6)
                
                
            }
        }
        .navigationTitle("Outfit Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            NavigationLink(destination: OutfitAddView(outfitToEdit: outfit)) {
                Image(systemName: "paintbrush.pointed")
            }
        }
        .sheet(item: $attributesSheet) { sheet in
            NavigationView {
                sheet.destination(for: outfit)
            }
            .presentationDetents([.medium, .large])
        }
    }
    
    // MARK: - Featured Items Toggle Row
    private func featuredItemsToggleRow() -> some View {
        Button { 
            withAnimation {
                isFeaturedItemsExpanded.toggle()
            }
        } label: {
            HStack {
                Text("Featured Items")
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: isFeaturedItemsExpanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
          //  .cornerRadius(8)
        }
    }
    
}
