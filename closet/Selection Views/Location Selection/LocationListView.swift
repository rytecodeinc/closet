//
//  BrandListView.swift
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
    /// When set, only locations owned by or assigned to this user's items appear.
    var userId: String? = nil
    
    @State private var locations: [Location] = []

    var body: some View {
        List {
            if locations.isEmpty {
                Text("Locations added to your closet will appear here.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(locations, id: \.self) { location in
                    let name = location.name ?? ""
                    Button {
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
                            if selectedLocation == location {
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

    private func fetchLocations() {
        let request: NSFetchRequest<Location> = Location.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Location.name, ascending: true)]
        if let uid = userId {
            let owned = NSPredicate(format: "userId == %@", uid)
            let usedByUser = NSPredicate(
                format: "SUBQUERY(item, $i, $i.userId == %@ AND ($i.isSoftDeleted != YES OR $i.isSoftDeleted == nil)).@count > 0",
                uid
            )
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [owned, usedByUser])
        }
        do {
            locations = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch locations: \(error.localizedDescription)")
            locations = []
        }
    }
}

