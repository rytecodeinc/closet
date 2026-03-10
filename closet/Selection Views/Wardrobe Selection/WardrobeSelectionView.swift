//
//  WardrobeSelectionView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct WardrobeSelectionView: View {
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
                excludeWardrobeType: excludeWardrobeType
            )
        }
        .onAppear {
            // Preselect wardrobes the item currently belongs to
            if let wardrobes = item.wardrobes as? Set<Wardrobe> {
                selectedWardrobes = wardrobes
            }
        }
        .onDisappear {
            // Sync selections to item.wardrobes
            item.wardrobes?.forEach { item.removeFromWardrobes($0 as! Wardrobe) }
            for wardrobe in selectedWardrobes {
                item.addToWardrobes(wardrobe)
            }

            do {
                try viewContext.save()
            } catch {
                print("❌ Failed to save wardrobe selection: \(error)")
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Helper Methods
    
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
}
