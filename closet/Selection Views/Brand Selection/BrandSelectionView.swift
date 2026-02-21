//
//  BrandSelectionView.swift
//  closet
//
//  Created by Dan Warner on 7/25/25.
//


import SwiftUI
import CoreData

struct BrandSelectionView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var brands: [Brand] = []
    @State private var newBrandName: String = ""
    
    var filteredBrands: [Brand] {
        guard !newBrandName.isEmpty else { return brands }
        let lowercaseInput = newBrandName.lowercased()
        return brands.filter { ($0.name ?? "").lowercased().contains(lowercaseInput) }
    }
    
    var body: some View {
        SelectionHeader(title: "Select Brand")
        
        VStack(spacing: 12) {
            HStack {
                TextField("Add or select a brand", text: $newBrandName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Add") {
                    addBrand()
                }
                .disabled(newBrandName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
            
            if brands.isEmpty {
                Text("No brands have been added.")
                    .foregroundColor(.gray)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            } else {
                List {
                    ForEach(filteredBrands, id: \.self) { brand in
                        Button(action: {
                            // Store the brand being unassigned to check if cleanup is needed
                            let previousBrand = item.brand
                            
                            // Toggle selection
                            if item.brand == brand {
                                item.brand = nil
                            } else {
                                item.brand = brand
                            }
                            saveContext()
                            
                            // If we unassigned a brand, check if it needs cleanup
                            if previousBrand == brand {
                                cleanupBrandIfOrphaned(previousBrand)
                            }
                            
                            dismiss()
                        }) {
                            HStack {
                                highlightedText(for: brand.name ?? "", matching: newBrandName)
                                    .foregroundColor(.black)
                                Spacer()
                                if brand == item.brand {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .onAppear {
            fetchBrands()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Highlight Matching Text
    private func highlightedText(for brandName: String, matching input: String) -> Text {
        let lowerBrand = brandName.lowercased()
        let lowerInput = input.lowercased()
        
        guard let range = lowerBrand.range(of: lowerInput) else {
            return Text(brandName)
        }

        let nsRange = NSRange(range, in: brandName)
        let start = brandName.startIndex
        let matchStart = brandName.index(start, offsetBy: nsRange.location)
        let matchEnd = brandName.index(matchStart, offsetBy: nsRange.length)

        let before = String(brandName[..<matchStart])
        let match = String(brandName[matchStart..<matchEnd])
        let after = String(brandName[matchEnd...])

        return Text(before) + Text(match).bold() + Text(after)
    }

    // MARK: - Fetch Brands
    private func fetchBrands() {
        // First, cleanup brands with 0 items
        cleanupOrphanedBrands()
        
        let request: NSFetchRequest<Brand> = Brand.fetchRequest()
        request.predicate = NSPredicate(format: "isVisible == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Brand.name, ascending: true)]
        do {
            let allBrands = try viewContext.fetch(request)
            // Filter to only show brands that have at least one item
            brands = allBrands.filter { brand in
                if let items = brand.items as? Set<Item> {
                    return !items.isEmpty
                }
                return false
            }
        } catch {
            print("❌ Failed to fetch brands: \(error)")
            brands = []
        }
    }
    
    // MARK: - Cleanup Orphaned Brands
    private func cleanupOrphanedBrands() {
        let request: NSFetchRequest<Brand> = Brand.fetchRequest()
        request.predicate = NSPredicate(format: "isVisible == YES")
        
        do {
            let allBrands = try viewContext.fetch(request)
            let orphanedBrands = allBrands.filter { brand in
                if let items = brand.items as? Set<Item> {
                    return items.isEmpty
                }
                return true // If no items relationship, consider it orphaned
            }
            
            for brand in orphanedBrands {
                viewContext.delete(brand)
            }
            
            if !orphanedBrands.isEmpty {
                try viewContext.save()
                print("✅ Cleaned up \(orphanedBrands.count) orphaned brand(s)")
            }
        } catch {
            print("❌ Failed to cleanup orphaned brands: \(error)")
        }
    }

    // MARK: - Save Context
    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            print("❌ Failed to save context: \(error)")
        }
    }

    // MARK: - Add Brand if New
    private func addBrand() {
        let trimmed = newBrandName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let brandExists = brands.contains { ($0.name ?? "").localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        guard !brandExists else {
            print("✅ Brand already exists — assigning it without duplication.")
            if let existing = brands.first(where: { ($0.name ?? "").localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
                item.brand = existing
                saveContext()
                dismiss()
            }
            return
        }

        let newBrand = Brand(context: viewContext)
        newBrand.id = UUID()
        newBrand.name = trimmed
        newBrand.isVisible = true

        item.brand = newBrand
        saveContext()

        newBrandName = ""
        fetchBrands()
    }
    
    // MARK: - Cleanup Single Brand
    private func cleanupBrandIfOrphaned(_ brand: Brand?) {
        guard let brand = brand else { return }
        
        // Refresh the brand to get current item count
        viewContext.refresh(brand, mergeChanges: true)
        
        // Check if brand has any items
        if let items = brand.items as? Set<Item>, items.isEmpty {
            viewContext.delete(brand)
            do {
                try viewContext.save()
                print("✅ Cleaned up orphaned brand: \(brand.name ?? "unknown")")
            } catch {
                print("❌ Failed to cleanup orphaned brand: \(error)")
            }
        }
    }
}






