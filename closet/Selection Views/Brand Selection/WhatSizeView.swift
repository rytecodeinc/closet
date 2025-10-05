//
//  WhatSizeView.swift
//  closet
//
//  Created by Dan Warner on 10/5/25.
//

import SwiftUI
import CoreData

struct WhatSizeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var brands: [Brand] = []
    @State private var selectedBrand: Brand? = nil
    @State private var searchText: String = ""
    
    var filteredBrands: [Brand] {
        if searchText.isEmpty { return brands }
        return brands.filter { $0.name?.localizedCaseInsensitiveContains(searchText) ?? false }
    }

    var body: some View {
        NavigationStack {
            VStack {
                TextField("Search Brands in your closet", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                List(filteredBrands, id: \.self) { brand in
                    let sizes = fetchSizes(for: brand)
                    
                    NavigationLink(destination: BrandItemsView(brand: brand)
                                    .environment(\.managedObjectContext, viewContext)) {
                        HStack {
                            Text(brand.name ?? "")
                            Spacer()
                            Text(sizes.joined(separator: ", "))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("What size am I?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear { fetchBrands() }
        }
    }

    // Fetch all visible brands
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
    
    // Fetch unique sizes for a brand from the user's items
    private func fetchSizes(for brand: Brand) -> [String] {
        let request: NSFetchRequest<Item> = Item.fetchRequest()
        request.predicate = NSPredicate(format: "brand == %@", brand)
        
        do {
            let items = try viewContext.fetch(request)
            let sizes = items.compactMap { $0.size?.value }
            return Array(Set(sizes)).sorted() // unique and sorted
        } catch {
            print("❌ Failed to fetch items for brand \(brand.name ?? ""): \(error.localizedDescription)")
            return []
        }
    }
}

struct BrandItemsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    let brand: Brand
    
    @State private var items: [Item] = []

    var body: some View {
        List(items, id: \.self) { item in
            HStack {
                if let imageData = item.image, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 50, height: 50)
                }
                
                VStack(alignment: .leading) {
                    Text(item.category?.name ?? "Unknown")
                        .font(.subheadline)
                    Text(item.size?.value ?? "N/A")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle(brand.name ?? "Brand Items")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { fetchItems() }
    }
    
    private func fetchItems() {
        let request: NSFetchRequest<Item> = Item.fetchRequest()
        request.predicate = NSPredicate(format: "brand == %@", brand)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.timestamp, ascending: true)]
        
        do {
            items = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch items for brand \(brand.name ?? ""): \(error.localizedDescription)")
            items = []
        }
    }
}
