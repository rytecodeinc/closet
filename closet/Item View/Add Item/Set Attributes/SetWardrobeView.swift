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
    
    // Determine default wardrobe type and exclusion based on item's current wardrobes
    private var defaultWardrobeType: String? {
        let currentWardrobes = item.wardrobes as? Set<Wardrobe> ?? []
        
        // If item has a closet wardrobe, use "closet" as default
        if currentWardrobes.contains(where: { $0.type?.lowercased() == "closet" }) {
            return "closet"
        }
        
        // If item has a wishlist wardrobe, use "wishlist" as default
        if currentWardrobes.contains(where: { $0.type?.lowercased() == "wishlist" }) {
            return "wishlist"
        }
        
        // If no wardrobes, default to "closet"
        if currentWardrobes.isEmpty {
            return "closet"
        }
        
        return nil
    }
    
    // Exclude opposite wardrobe type based on context
    private var excludeWardrobeType: String? {
        let currentWardrobes = item.wardrobes as? Set<Wardrobe> ?? []
        
        // If item has a closet wardrobe, exclude wishlist
        if currentWardrobes.contains(where: { $0.type?.lowercased() == "closet" }) {
            return "wishlist"
        }
        
        // If item has a wishlist wardrobe, exclude closet
        if currentWardrobes.contains(where: { $0.type?.lowercased() == "wishlist" }) {
            return "closet"
        }
        
        return nil
    }

    var body: some View {
        Section(header: SelectionHeader(title: "Select Wardrobes")) {
            WardrobeListView(
                selectedWardrobes: $selectedWardrobes,
                defaultWardrobeType: defaultWardrobeType,
                excludeWardrobeType: excludeWardrobeType,
                userId: SupabaseService.shared.currentUser?.id.uuidString
            )
        }
        .onAppear {
            let currentUserId = SupabaseService.shared.currentUser?.id.uuidString
            // Run deduplication on the parent context to ensure no duplicates
            // Get the parent context from the child context
            if let parentContext = viewContext.parent {
                deduplicateWardrobes(context: parentContext, userId: currentUserId)
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
                deduplicateWardrobes(context: viewContext, userId: currentUserId)
                if viewContext.hasChanges {
                    try? viewContext.save()
                }
            }
            
            // Preselect wardrobes the item currently belongs to
            if let wardrobes = item.wardrobes as? Set<Wardrobe>, !wardrobes.isEmpty {
                selectedWardrobes = wardrobes
            } else {
                // If no wardrobes are selected, select the default wardrobe
                // Fetch wardrobes filtered by default type
                let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
                
                // Apply exclusion filter if needed
                var predicates: [NSPredicate] = [NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")]
                
                if let excludeType = excludeWardrobeType {
                    predicates.append(NSPredicate(format: "type != %@", excludeType))
                }
                
                // If we have a default type, prefer that
                if let defaultType = defaultWardrobeType {
                    predicates.append(NSPredicate(format: "type == %@", defaultType))
                }
                
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Wardrobe.name, ascending: true)]
                if let defaultWardrobe = try? viewContext.fetch(request).first {
                    selectedWardrobes = [defaultWardrobe]
                } else {
                    // Fallback: fetch any wardrobe if default not found
                    let fallbackRequest: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
                    var fallbackPredicates: [NSPredicate] = [NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")]
                    if let excludeType = excludeWardrobeType {
                        fallbackPredicates.append(NSPredicate(format: "type != %@", excludeType))
                    }
                    fallbackRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: fallbackPredicates)
                    fallbackRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Wardrobe.name, ascending: true)]
                    if let firstWardrobe = try? viewContext.fetch(fallbackRequest).first {
                        selectedWardrobes = [firstWardrobe]
                    }
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
    
    private func ensureDefaultWardrobeIsSelected() {
        guard let defaultType = defaultWardrobeType else { return }
        
        // Check if default wardrobe is already selected
        let hasDefaultWardrobe = selectedWardrobes.contains { $0.type?.lowercased() == defaultType.lowercased() }
        
        if !hasDefaultWardrobe {
            // Fetch the default wardrobe
            let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
            request.predicate = NSPredicate(format: "type == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)", defaultType)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Wardrobe.createdAt, ascending: true)]
            
            if let defaultWardrobe = try? viewContext.fetch(request).first {
                selectedWardrobes.insert(defaultWardrobe)
            }
        }
    }
    
    private func applyWardrobeSelectionToItem() {
        // Ensure at least one wardrobe is selected
        if selectedWardrobes.isEmpty {
            // If somehow no wardrobes are selected, fetch and select the default one
            let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
            
            // Apply exclusion filter if needed
            var predicates: [NSPredicate] = [NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")]
            if let excludeType = excludeWardrobeType {
                predicates.append(NSPredicate(format: "type != %@", excludeType))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            
            // If we have a default type, prefer that
            if let defaultType = defaultWardrobeType {
                request.predicate = NSPredicate(format: "type == %@", defaultType)
            }
            
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Wardrobe.name, ascending: true)]
            if let defaultWardrobe = try? viewContext.fetch(request).first {
                selectedWardrobes = [defaultWardrobe]
            } else {
                // Fallback: fetch any wardrobe if default not found
                let fallbackRequest: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
                if let excludeType = excludeWardrobeType {
                    fallbackRequest.predicate = NSPredicate(format: "type != %@", excludeType)
                }
                fallbackRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Wardrobe.name, ascending: true)]
                if let firstWardrobe = try? viewContext.fetch(fallbackRequest).first {
                    selectedWardrobes = [firstWardrobe]
                } else {
                    // No wardrobes exist, cannot proceed
                    return
                }
            }
        }
        
        // Safety net: ensure the primary wardrobe of the correct type is always present.
        // This catches any case where the user somehow ended up with it deselected.
        if let wardrobeType = selectedWardrobes.first?.type ?? (defaultWardrobeType) {
            let primaryRequest: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
            primaryRequest.predicate = NSPredicate(
                format: "type == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
                wardrobeType
            )
            primaryRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Wardrobe.timestamp, ascending: true)]
            primaryRequest.fetchLimit = 1
            if let primary = try? viewContext.fetch(primaryRequest).first {
                selectedWardrobes.insert(primary)
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
        
        // Set updatedAt since we're modifying the item
        setUpdatedAt(item)
        
        // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
        // If viewContext has a parent, we're in a child context and shouldn't save
        if viewContext.parent == nil {
            // We're in a parent context (ItemDetailView), save immediately
            do {
                try viewContext.save()
                
                // Trigger automatic sync for the modified item
                SyncService.shared.syncItemIfNeeded(item)
            } catch {
                print("❌ Failed to save wardrobes: \(error.localizedDescription)")
            }
        }
        // Otherwise, we're in a child context (ItemAddView), don't save - let parent handle it
    }
}
