//
//  WardrobeSelectionView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct SetWardrobeView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedWardrobes: Set<Wardrobe> = []

    var body: some View {
        Section(header: SelectionHeader(title: "Select Wardrobes")) {
            WardrobeListView(selectedWardrobes: $selectedWardrobes)
        }
        .onAppear {
            // Preselect wardrobes the item currently belongs to
            if let wardrobes = item.wardrobes as? Set<Wardrobe> {
                selectedWardrobes = wardrobes
            }
        }
        .onDisappear {
            // Apply wardrobe selection to item (but DON'T save context)
            applyWardrobeSelectionToItem()
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Apply Selection (without saving)
    
    private func applyWardrobeSelectionToItem() {
        // Remove all existing wardrobes
        if let existingWardrobes = item.wardrobes as? Set<Wardrobe> {
            for wardrobe in existingWardrobes {
                item.removeFromWardrobes(wardrobe)
            }
        }
        
        // Add selected wardrobes
        for wardrobe in selectedWardrobes {
            item.addToWardrobes(wardrobe)
        }
        
        // CRITICAL: Do NOT save here
        // The changes stay in the child context
        // ItemAddView will save when user taps "Save" or rollback when user taps "Cancel"
    }
}
