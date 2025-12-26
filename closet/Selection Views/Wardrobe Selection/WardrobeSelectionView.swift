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
}
