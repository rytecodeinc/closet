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
            if let wardrobes = item.wardrobes as? Set<Wardrobe>, !wardrobes.isEmpty {
                selectedWardrobes = wardrobes
            } else {
                // If no wardrobes are selected, ensure at least one is selected
                // Fetch all wardrobes and select the first one
                let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Wardrobe.name, ascending: true)]
                if let firstWardrobe = try? viewContext.fetch(request).first {
                    selectedWardrobes = [firstWardrobe]
                }
            }
        }
        .onDisappear {
            // Apply wardrobe selection to item (but DON'T save context)
            applyWardrobeSelectionToItem()
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Apply Selection
    
    private func applyWardrobeSelectionToItem() {
        // Ensure at least one wardrobe is selected
        if selectedWardrobes.isEmpty {
            // If somehow no wardrobes are selected, fetch and select the first one
            let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Wardrobe.name, ascending: true)]
            if let firstWardrobe = try? viewContext.fetch(request).first {
                selectedWardrobes = [firstWardrobe]
            } else {
                // No wardrobes exist, cannot proceed
                return
            }
        }
        
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
        
        // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
        // If viewContext has a parent, we're in a child context and shouldn't save
        if viewContext.parent == nil {
            // We're in a parent context (ItemDetailView), save immediately
            do {
                try viewContext.save()
            } catch {
                print("❌ Failed to save wardrobes: \(error.localizedDescription)")
            }
        }
        // Otherwise, we're in a child context (ItemAddView), don't save - let parent handle it
    }
}
