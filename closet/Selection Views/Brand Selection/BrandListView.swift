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
        let request: NSFetchRequest<Brand> = Brand.fetchRequest()
        request.predicate = NSPredicate(format: "isVisible == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Brand.name, ascending: true)]
        do {
            brands = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch brands: \(error.localizedDescription)")
            brands = []
        }
    }
}




