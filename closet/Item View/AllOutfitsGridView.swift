//
//  AllOutfitsGridView.swift
//  closet
//
//  Created by Dan Warner on 10/8/25.
//

import SwiftUI
import CoreData

struct AllOutfitsGridView: View {
    let item: Item  // Pass the item instead of outfits array
    
    @FetchRequest private var outfits: FetchedResults<Outfit>
    
    init(item: Item) {
        self.item = item
        // Fetch outfits that contain this item (excluding drafts)
        _outfits = FetchRequest(
            entity: Outfit.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Outfit.createdAt, ascending: false)],
            predicate: NSPredicate(format: "items CONTAINS %@ AND isDraft != YES", item)
        )
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(outfits, id: \.objectID) { outfit in
                    NavigationLink(destination: OutfitDetailView(outfit: outfit)) {
                        OutfitGridCell(outfit: outfit)
                    }
                }
            }
        }
        .navigationTitle("Featured Outfits")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OutfitGridCell: View {
    @ObservedObject var outfit: Outfit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            OutfitImageView(outfit: outfit)
                .frame(height: UIScreen.main.bounds.width * 0.3)
               // .cornerRadius(10)
               /* .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.2))
                )*/

           /* if let name = outfit.name, !name.isEmpty {
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }*/
        }
    }
}
