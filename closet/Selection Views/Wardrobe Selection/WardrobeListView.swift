//
//  WardrobeListView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct WardrobeListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selectedWardrobes: Set<Wardrobe>
    
    // Optional parameters to control default wardrobe and filtering
    var defaultWardrobeType: String? = nil
    var excludeWardrobeType: String? = nil
    /// Only show wardrobes belonging to this user. Orphaned/unowned wardrobes are hidden.
    var userId: String? = nil

    @State private var wardrobes: [Wardrobe] = []
    
    // Computed property to get filtered and sorted wardrobes
    private var displayedWardrobes: [Wardrobe] {
        var filtered = Array(wardrobes)

        // Always exclude soft-deleted wardrobes
        filtered = filtered.filter { $0.isSoftDeleted != true }

        // Always filter to the current user's wardrobes — this prevents orphaned
        // wardrobes (userId == nil or a different user) from appearing in the list.
        if let uid = userId {
            filtered = filtered.filter { $0.userId == uid }
        }

        // If defaultWardrobeType is provided, ONLY show wardrobes of that type
        if let defaultType = defaultWardrobeType {
            filtered = filtered.filter { $0.type?.lowercased() == defaultType.lowercased() }
            
            // Sort by timestamp first (like ClosetView), then by name
            filtered.sort { wardrobe1, wardrobe2 in
                let timestamp1 = wardrobe1.timestamp ?? Date.distantFuture
                let timestamp2 = wardrobe2.timestamp ?? Date.distantFuture
                if timestamp1 != timestamp2 {
                    return timestamp1 < timestamp2
                }
                // If timestamps are equal, sort by name
                let name1 = wardrobe1.name ?? ""
                let name2 = wardrobe2.name ?? ""
                return name1 < name2
            }
        } else {
            // If no default type specified, filter out excluded wardrobe types
            if let excludeType = excludeWardrobeType {
                filtered = filtered.filter { $0.type?.lowercased() != excludeType.lowercased() }
            }
            
            // Sort by name when no default type
            filtered.sort { wardrobe1, wardrobe2 in
                let name1 = wardrobe1.name ?? ""
                let name2 = wardrobe2.name ?? ""
                return name1 < name2
            }
        }
        
        return filtered
    }
    
    // Get the default wardrobe (first one of the default type)
    private var defaultWardrobe: Wardrobe? {
        guard let defaultType = defaultWardrobeType else { return nil }
        return displayedWardrobes.first { $0.type?.lowercased() == defaultType.lowercased() }
    }

    var body: some View {
        List {
            ForEach(displayedWardrobes, id: \.self) { wardrobe in
                let name = wardrobe.name ?? "Untitled"
                let isDefault = wardrobe == defaultWardrobe
                
                HStack {
                    Text(name)
                        .foregroundColor(.black)

                    Spacer()

                    if isDefault {
                        // Replace the checkmark with a "Default" pill — makes it
                        // visually clear the row is always selected and non-removable.
                        Text("Default")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(UIColor.secondarySystemBackground))
                            )
                    } else if selectedWardrobes.contains(wardrobe) {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedWardrobes.contains(wardrobe) {
                        // The primary/default wardrobe can never be deselected —
                        // an item must always belong to at least the base wardrobe.
                        guard !isDefault else { return }
                        selectedWardrobes.remove(wardrobe)
                    } else {
                        selectedWardrobes.insert(wardrobe)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Select Wardrobes")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchWardrobes()
            // Ensure default wardrobe is always selected
            if let defaultWardrobe = defaultWardrobe {
                selectedWardrobes.insert(defaultWardrobe)
            }
        }
    }
    
    private func fetchWardrobes() {
        let request = NSFetchRequest<Wardrobe>(entityName: "Wardrobe")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Wardrobe.name, ascending: true)]
        do {
            wardrobes = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch wardrobes: \(error.localizedDescription)")
            wardrobes = []
        }
    }
}
