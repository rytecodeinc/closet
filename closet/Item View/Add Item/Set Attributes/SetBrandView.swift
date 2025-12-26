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

    @State private var brands: [Brand] = []
    @State private var newBrandName: String = ""
    
    var filteredBrands: [Brand] {
        guard !newBrandName.isEmpty else { return brands }
        let lowercaseInput = newBrandName.lowercased()
        return brands.filter { ($0.name ?? "").lowercased().contains(lowercaseInput) }
    }
    
    var body: some View {
        SelectionHeader(title: "Select a Brand")
        
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
                            // Toggle selection
                            if item.brand == brand {
                                item.brand = nil
                            } else {
                                item.brand = brand
                            }
                            // Don't save - let parent view decide
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
        let request: NSFetchRequest<Brand> = Brand.fetchRequest()
        request.predicate = NSPredicate(format: "isVisible == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Brand.name, ascending: true)]
        do {
            brands = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch brands: \(error)")
            brands = []
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
                // Don't save - let parent view decide
                dismiss()
            }
            return
        }

        // Create new brand in the same context (child context)
        let newBrand = Brand(context: viewContext)
        newBrand.id = UUID()
        newBrand.name = trimmed
        newBrand.isVisible = true

        item.brand = newBrand
        // Don't save - the new brand and assignment stay in child context
        
        newBrandName = ""
        fetchBrands()
        dismiss()
    }
}
