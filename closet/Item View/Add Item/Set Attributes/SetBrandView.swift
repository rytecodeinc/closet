//
//  BrandSelectionView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct SetBrandView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSession

    @State private var brands: [Brand] = []
    @State private var newBrandName: String = ""

    private var referenceUserId: String? {
        effectiveReferenceDataUserId(signedInUserId: authSession.userId, entityUserId: item.userId)
    }
    
    var filteredBrands: [Brand] {
        guard !newBrandName.isEmpty else { return brands }
        let lowercaseInput = newBrandName.lowercased()
        return brands.filter { ($0.name ?? "").lowercased().contains(lowercaseInput) }
    }
    
    var body: some View {
        SelectionPanelHeader(title: "Select Brand")
        
        VStack(spacing: 12) {
            HStack {
                TextField("Add or select a brand", text: $newBrandName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textInputAutocapitalization(.words)

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
                            
                            // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
                            if viewContext.parent == nil {
                                do {
                                    try viewContext.save()
                                    // If we unassigned a brand, check if it needs cleanup
                                    if previousBrand == brand {
                                        cleanupBrandIfOrphaned(previousBrand)
                                    }
                                } catch {
                                    print("❌ Failed to save brand: \(error.localizedDescription)")
                                }
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
        guard let uid = referenceUserId, !uid.isEmpty else {
            brands = []
            return
        }
        do {
            brands = try viewContext.fetchBrandsForItemPicker(userId: uid, includingBrandOn: item)
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
            
            // Only save if we're in parent context (ItemDetailView), not child context (ItemAddView)
            if viewContext.parent == nil && !orphanedBrands.isEmpty {
                try viewContext.save()
                print("✅ Cleaned up \(orphanedBrands.count) orphaned brand(s)")
            }
        } catch {
            print("❌ Failed to cleanup orphaned brands: \(error)")
        }
    }

    // MARK: - Add Brand if New
    private func addBrand() {
        let trimmed = newBrandName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let brandExists = brands.contains { ($0.name ?? "").localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        
        if brandExists {
            // Brand exists - just assign it
            print("✅ Brand already exists — assigning it without duplication.")
            if let existing = brands.first(where: { ($0.name ?? "").localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
                item.brand = existing
                
                // Set updatedAt since we're modifying the item
                setUpdatedAt(item)
                
                // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
                if viewContext.parent == nil {
                    do {
                        try viewContext.save()
                        
                        // Trigger automatic sync for the modified item
                        SyncService.shared.syncItemIfNeeded(item)
                    } catch {
                        print("❌ Failed to save brand: \(error.localizedDescription)")
                    }
                }
                
                dismiss()
            }
            return
        }

        // Create new brand in the same context (child context)
        let newBrand = Brand(context: viewContext)
        newBrand.id = UUID()
        newBrand.name = trimmed
        newBrand.isVisible = true
        newBrand.userId = referenceUserId ?? item.userId

        item.brand = newBrand
        
        // Set updatedAt since we're modifying the item
        setUpdatedAt(item)
        
        // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
        if viewContext.parent == nil {
            do {
                try viewContext.save()
                
                // Trigger automatic sync for the modified item
                SyncService.shared.syncItemIfNeeded(item)
            } catch {
                print("❌ Failed to save brand: \(error.localizedDescription)")
            }
        }
        
        newBrandName = ""
        fetchBrands()
        dismiss()
    }
    
    // MARK: - Cleanup Single Brand
    private func cleanupBrandIfOrphaned(_ brand: Brand?) {
        guard let brand = brand else { return }
        
        // Use the parent context if we're in a child context
        let context = viewContext.parent ?? viewContext
        
        // Refresh the brand to get current item count
        context.refresh(brand, mergeChanges: true)
        
        // Check if brand has any items
        if let items = brand.items as? Set<Item>, items.isEmpty {
            context.delete(brand)
            
            // Only save if we're in parent context
            if viewContext.parent == nil {
                do {
                    try context.save()
                    print("✅ Cleaned up orphaned brand: \(brand.name ?? "unknown")")
                } catch {
                    print("❌ Failed to cleanup orphaned brand: \(error)")
                }
            }
        }
    }
}
