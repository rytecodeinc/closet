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
    @Binding var selectedBrand: Brand?
    /// When set, only brands referenced by this user's items appear.
    var userId: String? = nil
    
    @State private var brands: [Brand] = []

    var body: some View {
        List {
            if brands.isEmpty {
                Text("Brands added to your closet will appear here.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(brands, id: \.self) { brand in
                    let name = brand.name ?? ""
                    Button {
                        if selectedBrand == brand {
                            selectedBrand = nil // deselect
                        } else {
                            selectedBrand = brand // select
                        }
                    } label: {
                        HStack {
                            Text(name)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedBrand == brand {
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

    private func fetchBrands() {
        do {
            brands = try viewContext.fetchBrandsForFilterList(userId: userId)
        } catch {
            print("❌ Failed to fetch brands: \(error.localizedDescription)")
            brands = []
        }
    }
}
