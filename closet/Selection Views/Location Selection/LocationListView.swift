//
//  LocationListView.swift
//  closet
//
//  Created by Dan Warner on 7/29/25.
//

import SwiftUI
import CoreData
import Foundation

struct LocationListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedLocation: Location?
    /// When true, filter for items with no location. Mutually exclusive with `selectedLocation`.
    @Binding var filterNotSet: Bool
    /// When set, only locations assigned to this user's items appear.
    var userId: String? = nil
    /// When non-empty, only locations on items in all of these wardrobes (AND) appear.
    var wardrobes: [Wardrobe] = []
    /// `"closet"` or `"wishlist"` — empty-state copy in ItemFilterView.
    var wardrobeType: String = "closet"

    @State private var locations: [Location] = []

    private var emptyLocationsMessage: String {
        wardrobeType == "wishlist"
            ? "Locations added to your wishlist will appear here."
            : "Locations added to your closet will appear here."
    }

    var body: some View {
        List {
            locationNotSetRow

            if locations.isEmpty {
                Text(emptyLocationsMessage)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(locations, id: \.self) { location in
                    let name = location.name ?? ""
                    Button {
                        filterNotSet = false
                        if selectedLocation == location {
                            selectedLocation = nil // deselect
                        } else {
                            selectedLocation = location // select
                        }
                    } label: {
                        HStack {
                            Text(name)
                                .foregroundColor(.primary)
                            Spacer()
                            if !filterNotSet, selectedLocation == location {
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
        .navigationTitle("Select Location")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchLocations()
        }
    }

    private var locationNotSetRow: some View {
        HStack {
            Text("None")
                .foregroundColor(.black)

            Spacer()

            if filterNotSet {
                Image(systemName: "checkmark").foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedLocation = nil
            filterNotSet = true
        }
    }

    private func fetchLocations() {
        do {
            locations = try viewContext.fetchLocationsForFilterList(userId: userId, wardrobes: wardrobes)
        } catch {
            print("❌ Failed to fetch locations: \(error.localizedDescription)")
            locations = []
        }
    }
}
