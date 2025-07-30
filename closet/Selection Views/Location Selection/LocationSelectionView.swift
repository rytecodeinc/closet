//
//  BrandSelectionView.swift
//  closet
//
//  Created by Dan Warner on 7/29/25.
//


import SwiftUI
import CoreData
/*
struct LocationSelectionView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var locations: [Location] = []
    @State private var newLocationName: String = ""
    
    var filteredBrands: [Location] {
        guard !newLocationName.isEmpty else { return brands }
        let lowercaseInput = newLocationName.lowercased()
        return brands.filter { ($0.name ?? "").lowercased().contains(lowercaseInput) }
    }
    
    var body: some View {
        SelectionHeader(title: "Select a Location")
        
        VStack(spacing: 12) {
            HStack {
                TextField("Add or select a location", text: $newLocationName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Add") {
                    addLocation()
                }
                .disabled(newLocationName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
            
            if brands.isEmpty {
                Text("No locations have been added.")
                    .foregroundColor(.gray)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            } else {
                List {
                    ForEach(filteredLocations, id: \.self) { location in
                        Button(action: {
                            item.location = brand
                            saveContext()
                            dismiss()
                        }) {
                            HStack {
                                highlightedText(for: location.name ?? "", matching: newLocationName)
                                    .foregroundColor(.black)
                                Spacer()
                                if location == item.location {
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
            fetchLocations()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Highlight Matching Text
    private func highlightedText(for brandName: String, matching input: String) -> Text {
        let lowerLocation = locationName.lowercased()
        let lowerInput = input.lowercased()
        
        guard let range = lowerLocation.range(of: lowerInput) else {
            return Text(locationName)
        }

        let nsRange = NSRange(range, in: locationName)
        let start = locationName.startIndex
        let matchStart = locationName.index(start, offsetBy: nsRange.location)
        let matchEnd = locationName.index(matchStart, offsetBy: nsRange.length)

        let before = String(locationName[..<matchStart])
        let match = String(locationName[matchStart..<matchEnd])
        let after = String(locationName[matchEnd...])

        return Text(before) + Text(match).bold() + Text(after)
    }

    // MARK: - Fetch Brands
    private func fetchLocations() {
        let request: NSFetchRequest<Location> = Location.fetchRequest()
        request.predicate = NSPredicate(format: "isVisible == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Location.name, ascending: true)]
        do {
            locations = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch locations: \(error)")
            locations = []
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
    private func addLocation() {
        let trimmed = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let locationExists = locations.contains { ($0.name ?? "").localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        guard !locationExists else {
            print("✅ Location already exists — assigning it without duplication.")
            if let existing = locations.first(where: { ($0.name ?? "").localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
                item.brand = existing
                saveContext()
                dismiss()
            }
            return
        }

        let newBrand = Brand(context: viewContext)
        newBrand.name = trimmed
        newBrand.isVisible = true

        item.brand = newBrand
        saveContext()

        newBrandName = ""
        fetchBrands()
    }
}
*/
