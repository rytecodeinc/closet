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
    @EnvironmentObject private var authSession: AuthSession

    @State private var selectedColorNames: Set<String> = []

    private var referenceUserId: String? {
        effectiveReferenceDataUserId(signedInUserId: authSession.userId, entityUserId: item.userId)
    }

    var body: some View {
        Section(header: SelectionHeader(title: "Select Color")) {
            ColorListView(selectedColorNames: $selectedColorNames, userId: referenceUserId)
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

    // MARK: - Apply Selection
    
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
        
        // Set updatedAt since we're modifying the item
        setUpdatedAt(item)
        
        // Check if this is a child context (ItemAddView) or parent context (ItemDetailView)
        // If viewContext has a parent, we're in a child context and shouldn't save
        if viewContext.parent == nil {
            // We're in a parent context (ItemDetailView), save immediately
            do {
                try viewContext.save()
                
            } catch {
                print("❌ Failed to save colors: \(error.localizedDescription)")
            }
        }
        // Otherwise, we're in a child context (ItemAddView), don't save - let parent handle it
    }

    private func fetchOrCreateColor(named name: String) -> AppColor {
        let fetchRequest: NSFetchRequest<AppColor> = AppColor.fetchRequest()
        if let uid = referenceUserId, !uid.isEmpty {
            fetchRequest.predicate = NSPredicate(format: "name ==[c] %@ AND userId == %@", name, uid)
        } else {
            fetchRequest.predicate = NSPredicate(format: "name ==[c] %@", name)
        }
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
        newColor.userId = referenceUserId ?? item.userId
        return newColor
    }
}
