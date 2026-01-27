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
        
        // Filter out excluded wardrobe types
        if let excludeType = excludeWardrobeType {
            filtered = filtered.filter { $0.type?.lowercased() != excludeType.lowercased() }
        }
        
        // Sort to put default wardrobe first
        if let defaultType = defaultWardrobeType {
            filtered.sort { wardrobe1, wardrobe2 in
                let isDefault1 = wardrobe1.type?.lowercased() == defaultType.lowercased()
                let isDefault2 = wardrobe2.type?.lowercased() == defaultType.lowercased()
                
                if isDefault1 && !isDefault2 {
                    return true
                } else if !isDefault1 && isDefault2 {
                    return false
                } else if isDefault1 && isDefault2 {
                    // Both are default type - sort by timestamp first (like ClosetView), then by name
                    let timestamp1 = wardrobe1.timestamp ?? Date.distantFuture
                    let timestamp2 = wardrobe2.timestamp ?? Date.distantFuture
                    if timestamp1 != timestamp2 {
                        return timestamp1 < timestamp2
                    }
                    // If timestamps are equal, sort by name
                    let name1 = wardrobe1.name ?? ""
                    let name2 = wardrobe2.name ?? ""
                    return name1 < name2
                } else {
                    // Neither are default, sort by name
                    let name1 = wardrobe1.name ?? ""
                    let name2 = wardrobe2.name ?? ""
                    return name1 < name2
                }
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
                    // Default wardrobes cannot be deselected
                    if isDefault {
                        return
                    }
                    
                    if selectedWardrobes.contains(wardrobe) {
                        // Prevent deselecting if this is the last selected wardrobe
                        if selectedWardrobes.count > 1 {
                            selectedWardrobes.remove(wardrobe)
                        }
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
