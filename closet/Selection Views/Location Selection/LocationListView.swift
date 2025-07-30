//
//  BrandListView.swift
//  closet
//
//  Created by Dan Warner on 7/29/25.
//


import SwiftUI
import CoreData
import Foundation
/*
struct LocationListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedBrand: Brand?
    
    @State private var locations: [Location] = []

    var body: some View {
        List {
            if locations.isEmpty {
                Text("Locations added to your closet will appear here.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(locations, id: \.self) { brand in
                    let name = location.name ?? ""
                    Button {
                        selectedLocation = location
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
*/
