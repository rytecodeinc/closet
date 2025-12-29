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
            // Run deduplication on the parent context to ensure no duplicates
            // Get the parent context from the child context
            if let parentContext = viewContext.parent {
                deduplicateWardrobes(context: parentContext)
                // Save parent context to persist deduplication
                if parentContext.hasChanges {
                    try? parentContext.save()
                }
                // Refresh the child context to see changes from parent
                viewContext.refreshAllObjects()
                // Process pending changes to update fetched results
                viewContext.processPendingChanges()
            } else {
                // If no parent, run on current context
                deduplicateWardrobes(context: viewContext)
                if viewContext.hasChanges {
                    try? viewContext.save()
                }
            }
            
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
