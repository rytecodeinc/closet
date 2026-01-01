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
    
    @State private var isNotesSheetPresented = false
    @State private var isFeaturedItemsExpanded = true
    
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
                
                // Featured Items Toggle Row
                featuredItemsToggleRow()
                    .padding(.horizontal, 6)
                
                // Featured Items Grid (shown when expanded)
                if isFeaturedItemsExpanded {
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
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                    }
                }
                
                // Divider before Notes
                Divider()
                
                // Notes Row
                notesRow()
                    .padding(.horizontal, 6)
            }
        }
        .navigationTitle("Outfit Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            NavigationLink(destination: OutfitAddView(outfitToEdit: outfit)) {
                Image(systemName: "paintbrush.pointed")
            }
        }
        .sheet(isPresented: $isNotesSheetPresented) {
            NavigationView {
                SetOutfitNotesView(outfit: outfit)
            }
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
            .cornerRadius(8)
        }
    }
    
    // MARK: - Notes Row
    private func notesRow() -> some View {
        Button { isNotesSheetPresented = true } label: {
            HStack {
                Text("Notes")
                    .foregroundColor(.primary)
                Spacer()
                if let notes = outfit.notes, !notes.isEmpty {
                    Text(notes.prefix(30))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(8)
        }
    }
}
