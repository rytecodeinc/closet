//
//  ColorSelectionView.swift
//  closet
//
//  Created by Dan Warner on 10/25/25.
//

import SwiftUI
import CoreData

struct SetColorView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedColorNames: Set<String> = []

    var body: some View {
        Section(header: SelectionHeader(title: "Select a Color")) {
            ColorListView(selectedColorNames: $selectedColorNames)
        }
        .onAppear {
            if let colors = item.colors as? Set<AppColor> {
                selectedColorNames = Set(colors.compactMap { $0.name })
            }
        }
        .onDisappear {
            // Sync changes back to item (but DON'T save context)
            applyColorSelectionToItem()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Apply Selection (without saving)
    
    private func applyColorSelectionToItem() {
        // Remove colors that are no longer selected
        if let existingColors = item.colors as? Set<AppColor> {
            for color in existingColors {
                if !selectedColorNames.contains(color.name ?? "") {
                    item.removeFromColors(color)
                }
            }
        }

        // Add newly selected colors
        for name in selectedColorNames {
            // Check if this color is already assigned
            let alreadyAssigned = (item.colors as? Set<AppColor>)?.contains { $0.name == name } ?? false
            if !alreadyAssigned {
                let color = fetchOrCreateColor(named: name)
                item.addToColors(color)
            }
        }
        
        // CRITICAL: Do NOT save here
        // The changes stay in the child context
        // ItemAddView will save when user taps "Save" or rollback when user taps "Cancel"
    }

    private func fetchOrCreateColor(named name: String) -> AppColor {
        let fetchRequest: NSFetchRequest<AppColor> = AppColor.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name ==[c] %@", name)
        do {
            if let match = try viewContext.fetch(fetchRequest).first {
                return match
            }
        } catch {
            print("Fetch error: \(error)")
        }

        // Create new color in the same context (child context)
        let newColor = AppColor(context: viewContext)
        newColor.id = UUID()
        newColor.name = name
        newColor.isVisible = true
        return newColor
    }
}
