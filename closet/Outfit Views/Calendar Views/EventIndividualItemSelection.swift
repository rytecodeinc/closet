//
//  EventIndividualItemSelection.swift
//  closet
//
//  Created by Dan Warner on 10/8/25.
//

import SwiftUI
import CoreData

struct EventIndividualItemSelection: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var event: Event

    @State private var selectedItemIDs: [UUID] = [] // Use array to preserve selection order

    private let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    private var squareSize = UIScreen.main.bounds.width / 3.05

    // MARK: - FetchRequest for closet items only
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: false)],
        predicate: NSPredicate(format: "ANY wardrobes.type == %@", "closet")
    ) private var items: FetchedResults<Item>

    // MARK: - Explicit initializer
    init(event: Event) {
        self.event = event
    }

    var body: some View {
        VStack {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tshirt")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No closet items yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Add items to your closet to see them here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(items, id: \.objectID) { item in
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    toggleSelection(for: item)
                                } label: {
                                    ItemView(item: item)
                                        .frame(width: squareSize, height: squareSize)
                                        .border(selectedItemIDs.contains(item.id ?? UUID()) ? Color.blue : Color.gray.opacity(0), width: 2)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                if let itemId = item.id, selectedItemIDs.contains(itemId) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 20))
                                      //  .padding(6)
                                }
                            }
                        }
                    }
                  //  .padding(4)
                }
            }
            
            Button("Done") {
                saveSelectedItems()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        //    .padding()
        }
        .navigationTitle("Select Items for Event")
        .onAppear {
            preselectExistingItems()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Preselect items already linked to event
    private func preselectExistingItems() {
        if let existingItems = event.items as? NSOrderedSet {
            selectedItemIDs = existingItems.compactMap { ($0 as? Item)?.id }
        }
    }

    // MARK: - Selection
    private func toggleSelection(for item: Item) {
        guard let id = item.id else { return }
        if let index = selectedItemIDs.firstIndex(of: id) {
            selectedItemIDs.remove(at: index)
        } else {
            selectedItemIDs.append(id) // Append to preserve selection order
        }
    }

    // MARK: - Save selection
    private func saveSelectedItems() {
        // Create a dictionary for quick lookup
        let itemsById: [UUID: Item] = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            guard let id = item.id else { return nil }
            return (id, item)
        })
        
        // Clear all existing items to ensure correct order
        if let existingItems = event.items as? NSOrderedSet {
            event.removeFromItems(existingItems)
        }
        
        // Add items in selection order
        for id in selectedItemIDs {
            if let item = itemsById[id] {
                event.addToItems(item)
            }
        }
        
        // Only save context if event is already persisted (not a temporary/new event)
        if !event.objectID.isTemporaryID {
            do {
                try viewContext.save()
            } catch {
                print("Failed to save items to event: \(error)")
            }
        }
    }
}

