//
//  BrandListView.swift
//  closet
//
//  Created by Dan Warner on 7/26/25.
//

import SwiftUI
import CoreData
import Foundation

struct BrandListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedBrandName: String?
    /// When set, only brands referenced by this user's items appear.
    var userId: String? = nil
    /// When non-empty, only brands on items in all of these wardrobes (AND) appear.
    var wardrobes: [Wardrobe] = []
    /// `"closet"` or `"wishlist"` — empty-state copy in ItemFilterView.
    var wardrobeType: String = "closet"

    @State private var brands: [Brand] = []

    private var emptyBrandsMessage: String {
        wardrobeType == "wishlist"
            ? "Brands added to your wishlist will appear here."
            : "Brands added to your closet will appear here."
    }

    private var isBrandNotSetSelected: Bool {
        selectedBrandName == ItemFilterModel.brandNotSetFilterValue
    }

    var body: some View {
        List {
            brandNotSetRow

            if brands.isEmpty {
                Text(emptyBrandsMessage)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(brands, id: \.self) { brand in
                    let name = brand.name ?? ""
                    Button {
                        if selectedBrandName == name {
                            selectedBrandName = nil // deselect
                        } else {
                            selectedBrandName = name // select
                        }
                    } label: {
                        HStack {
                            Text(name)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedBrandName == name {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Select Brand")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchBrands()
        }
    }

    private var brandNotSetRow: some View {
        HStack {
            Text("None")
                .foregroundColor(.black)

            Spacer()

            if isBrandNotSetSelected {
                Image(systemName: "checkmark").foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedBrandName = ItemFilterModel.brandNotSetFilterValue
        }
    }

    private func fetchBrands() {
        do {
            brands = try viewContext.fetchBrandsForFilterList(userId: userId, wardrobes: wardrobes)
        } catch {
            print("❌ Failed to fetch brands: \(error.localizedDescription)")
            brands = []
        }
    }
}
