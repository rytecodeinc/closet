//
//  OutfitGeneratorView.swift
//  closet
//
//  Created by Dan Warner on 8/4/25.
//


import SwiftUI

struct OutfitGeneratorView: View {
    let selectedCategories: [Category]
    
    // Computed property to get combinations of one item from each selected category
    private var outfitCombinations: [[Item]] {
        let itemArrays = selectedCategories.map { Array($0.items) }
        return cartesianProduct(itemArrays)
    }

    // 2 columns per row
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(outfitCombinations.indices, id: \.self) { index in
                    let outfit = outfitCombinations[index]
                    OutfitView(items: outfit)
                        .aspectRatio(1, contentMode: .fit)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                        .overlay(
                            // Placeholder for a save button
                            VStack {
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        // TODO: Implement save functionality
                                    }) {
                                        Image(systemName: "heart")
                                            .padding(8)
                                            .background(Color.white.opacity(0.8))
                                            .clipShape(Circle())
                                    }
                                }
                                Spacer()
                            }
                            .padding(8)
                        )
                }
            }
            .padding()
        }
        .navigationTitle("Outfit Suggestions")
    }
}
