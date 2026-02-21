//
//  WardrobeListView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct WardrobeListView: View {
    @Binding var selectedWardrobes: Set<Wardrobe>
    
    // Optional parameters to control default wardrobe and filtering
    var defaultWardrobeType: String? = nil
    var excludeWardrobeType: String? = nil

    @FetchRequest(
        entity: Wardrobe.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.name, ascending: true)]
    ) private var wardrobes: FetchedResults<Wardrobe>
    
    // Computed property to get filtered and sorted wardrobes
    private var displayedWardrobes: [Wardrobe] {
        var filtered = Array(wardrobes)
        
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
                    
                    // Add "Default" pill next to the default wardrobe
                    if isDefault {
                        Text("Default")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(UIColor.secondarySystemBackground))
                            )
                    }
                    
                    Spacer()
                    if selectedWardrobes.contains(wardrobe) {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedWardrobes.contains(wardrobe) {
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
            // Ensure default wardrobe is always selected
            if let defaultWardrobe = defaultWardrobe {
                selectedWardrobes.insert(defaultWardrobe)
            }
        }
    }
}
