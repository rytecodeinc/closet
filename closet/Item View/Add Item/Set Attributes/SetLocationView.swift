//
//  LocationSelectionView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct SetLocationView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var locations: [Location] = []
    @State private var newLocationName: String = ""

    var filteredLocations: [Location] {
        guard !newLocationName.isEmpty else { return locations }
        let lowercaseInput = newLocationName.lowercased()
        return locations.filter { ($0.name ?? "").lowercased().contains(lowercaseInput) }
    }

    var body: some View {
        SelectionHeader(title: "Select a Location")

        VStack(spacing: 12) {
            HStack {
                TextField("Where is this item stored?", text: $newLocationName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Add") {
                    addLocation()
                }
                .disabled(newLocationName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)

            if locations.isEmpty {
                Text("No locations have been added.")
                    .foregroundColor(.gray)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            } else {
                List {
                    ForEach(filteredLocations, id: \.self) { location in
                        Button(action: {
                            item.location = location
                            
                            // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
                            if viewContext.parent == nil {
                                do {
                                    try viewContext.save()
                                } catch {
                                    print("❌ Failed to save location: \(error.localizedDescription)")
                                }
                            }
                            
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
    private func highlightedText(for locationName: String, matching input: String) -> Text {
        let lowerName = locationName.lowercased()
        let lowerInput = input.lowercased()

        guard let range = lowerName.range(of: lowerInput) else {
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

    // MARK: - Fetch Locations
    private func fetchLocations() {
        let request: NSFetchRequest<Location> = Location.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Location.name, ascending: true)]
        do {
            locations = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch locations: \(error)")
            locations = []
        }
    }

    // MARK: - Add Location if New
    private func addLocation() {
        let trimmed = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let locationExists = locations.contains {
            ($0.name ?? "").localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }

        if locationExists {
            // Location exists - just assign it
            if let existing = locations.first(where: {
                ($0.name ?? "").localizedCaseInsensitiveCompare(trimmed) == .orderedSame
            }) {
                item.location = existing
                
                // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
                if viewContext.parent == nil {
                    do {
                        try viewContext.save()
                    } catch {
                        print("❌ Failed to save location: \(error.localizedDescription)")
                    }
                }
                
                dismiss()
            }
            return
        }

        // Create new location in the same context (child context)
        let newLocation = Location(context: viewContext)
        newLocation.id = UUID()
        newLocation.name = trimmed

        item.location = newLocation
        
        // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
        if viewContext.parent == nil {
            do {
                try viewContext.save()
            } catch {
                print("❌ Failed to save location: \(error.localizedDescription)")
            }
        }

        newLocationName = ""
        fetchLocations()
        dismiss()
    }
}
