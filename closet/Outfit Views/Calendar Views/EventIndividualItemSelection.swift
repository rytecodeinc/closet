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
    @EnvironmentObject private var authSession: AuthSession

    @ObservedObject var event: Event
    /// When nil, the user's primary closet wardrobe is used.
    let selectedWardrobe: Wardrobe?

    @State private var closetItems: [Item] = []
    @State private var selectedItemIDs: [UUID] = [] // Use array to preserve selection order

    private let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    private var squareSize = UIScreen.main.bounds.width / 3.05

    init(event: Event, selectedWardrobe: Wardrobe? = nil) {
        self.event = event
        self.selectedWardrobe = selectedWardrobe
    }

    var body: some View {
        VStack {
            if closetItems.isEmpty {
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
                        ForEach(closetItems, id: \.objectID) { item in
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
                                }
                            }
                        }
                    }
                }
            }
            
            Button("Done") {
                saveSelectedItems()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Select Items for Event")
        .onAppear {
            fetchClosetItems()
            preselectExistingItems()
        }
        .onChange(of: authSession.userId) { _, _ in
            fetchClosetItems()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Fetch closet items scoped to one active wardrobe
    private func fetchClosetItems() {
        guard let userId = authSession.userId?.uuidString, !userId.isEmpty else {
            closetItems = []
            return
        }

        let wardrobe: Wardrobe
        if let selected = selectedWardrobe,
           selected.userId == userId,
           (selected.type ?? "").lowercased() == "closet",
           selected.isSoftDeleted != true {
            wardrobe = selected
        } else if let primary = try? WardrobeBootstrap.fetchPrimaryWardrobe(
            forType: "closet",
            userIdString: userId,
            in: viewContext
        ) {
            wardrobe = primary
        } else {
            closetItems = []
            return
        }

        let request: NSFetchRequest<Item> = Item.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.createdAt, ascending: false)]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "ANY wardrobes == %@", wardrobe),
            NSPredicate(format: "isDraft != YES"),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        ])

        do {
            let results = try viewContext.fetch(request)
            let wardrobeID = wardrobe.objectID
            closetItems = results.filter { item in
                guard let wardrobes = item.wardrobes as? Set<Wardrobe> else { return false }
                return wardrobes.contains { $0.objectID == wardrobeID }
            }
        } catch {
            print("Failed to fetch closet items: \(error)")
            closetItems = []
        }
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
        let itemsById: [UUID: Item] = Dictionary(uniqueKeysWithValues: closetItems.compactMap { item in
            guard let id = item.id else { return nil }
            return (id, item)
        })
        
        if let existingItems = event.items as? NSOrderedSet {
            event.removeFromItems(existingItems)
        }
        
        for id in selectedItemIDs {
            if let item = itemsById[id] {
                event.addToItems(item)
            }
        }
        syncEventUserIdFromLinkedEntities(event)
        
        if !event.objectID.isTemporaryID {
            do {
                try viewContext.save()
            } catch {
                print("Failed to save items to event: \(error)")
            }
        }
    }
}

