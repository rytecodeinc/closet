//
//  PairItemSelectionView.swift
//  closet
//
//  Created by Dan Warner on 12/19/25.
//

import SwiftUI
import CoreData

struct PairItemSelectionView: View {
    @ObservedObject var item: Item
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSession
    
    @State private var closetItems: [Item] = []
    @State private var selectedWardrobe: Wardrobe?
    @State private var showUnpairConfirmation = false
    @State private var itemToUnpair: Item?
    
    private let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if closetItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tshirt")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No closet items yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Add items to your closet to pair them.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 2) {
                            ForEach(closetItems, id: \.objectID) { closetItem in
                                // Don't show the current item
                                if closetItem.objectID != item.objectID {
                                    Button {
                                        pairItem(closetItem)
                                    } label: {
                                        ItemView(item: closetItem)
                                            .overlay(
                                                // Show checkmark for already paired items
                                                Group {
                                                    if isAlreadyPaired(closetItem) {
                                                        VStack {
                                                            Spacer()
                                                            HStack {
                                                                Spacer()
                                                                Image(systemName: "checkmark.circle.fill")
                                                                    .foregroundColor(.blue)
                                                                    .font(.system(size: 22))
                                                                    .shadow(radius: 1)
                                                                    .padding(8)
                                                            }
                                                        }
                                                    }
                                                }
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
            .navigationTitle("Pair Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                fetchClosetItems()
            }
            .alert("Unpair Item", isPresented: $showUnpairConfirmation) {
                Button("Cancel", role: .cancel) {
                    itemToUnpair = nil
                }
                Button("Unpair", role: .destructive) {
                    if let item = itemToUnpair {
                        unpairItem(item)
                    }
                }
            } message: {
                Text("Remove the pairing between this item and the selected item?")
            }
        }
    }
    
    private func fetchClosetItems() {
        let uid = item.userId ?? authSession.userId?.uuidString
        if let uid, !uid.isEmpty,
           let wardrobe = try? WardrobeBootstrap.fetchPrimaryWardrobe(forType: "closet", userIdString: uid, in: viewContext) {
            selectedWardrobe = wardrobe
        } else {
            let wardrobeRequest: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
            wardrobeRequest.predicate = NSPredicate(format: "type == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)", "closet")
            do {
                let wardrobes = try viewContext.fetch(wardrobeRequest)
                selectedWardrobe = WardrobeBootstrap.primaryWardrobe(in: wardrobes)
            } catch {
                selectedWardrobe = nil
            }
        }
        
        do {
            guard let wardrobe = selectedWardrobe else {
                closetItems = []
                return
            }
            
            // Fetch items from closet wardrobe, excluding drafts and the current item
            let request: NSFetchRequest<Item> = Item.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.createdAt, ascending: false)]
            
            let wardrobePredicate = NSPredicate(format: "ANY wardrobes == %@", wardrobe)
            let draftPredicate = NSPredicate(format: "isDraft != YES")
            let notSoftDeletedPredicate = NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
            let notCurrentItemPredicate = NSPredicate(format: "SELF != %@", item)
            
            let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                wardrobePredicate,
                draftPredicate,
                notSoftDeletedPredicate,
                notCurrentItemPredicate
            ])
            
            request.predicate = finalPredicate
            
            closetItems = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch closet items: \(error)")
            closetItems = []
        }
    }
    
    private func isAlreadyPaired(_ closetItem: Item) -> Bool {
        if let pairedItemsSet = item.pairedItems as? Set<Item> {
            return pairedItemsSet.contains(closetItem)
        }
        return false
    }
    
    private func pairItem(_ pairedItem: Item) {
        // Check if already paired
        if isAlreadyPaired(pairedItem) {
            // Show confirmation alert to un-pair
            itemToUnpair = pairedItem
            showUnpairConfirmation = true
            return
        }
        
        // Add bidirectional pairing
        // Since we're using a many-to-many relationship, we need to add both directions
        
        // Get current paired items as a mutable set
        var currentPairedItems = item.pairedItems as? Set<Item> ?? []
        
        // Add the new paired item
        currentPairedItems.insert(pairedItem)
        item.pairedItems = currentPairedItems as NSSet
        
        // Also add this item to the paired item's set (bidirectional)
        var pairedItemSet = pairedItem.pairedItems as? Set<Item> ?? []
        pairedItemSet.insert(item)
        pairedItem.pairedItems = pairedItemSet as NSSet
        
        do {
            // Set updatedAt on both items since we're modifying them
            setUpdatedAt(item)
            setUpdatedAt(pairedItem)
            
            try viewContext.save()
            
            // Trigger automatic sync for both items
            SyncService.shared.syncItemIfNeeded(item)
            SyncService.shared.syncItemIfNeeded(pairedItem)
            
            dismiss()
        } catch {
            print("❌ Failed to save paired item: \(error)")
        }
    }
    
    private func unpairItem(_ itemToRemove: Item) {
        // Remove bidirectional pairing
        
        // Remove from current item's paired items
        var currentPairedItems = item.pairedItems as? Set<Item> ?? []
        currentPairedItems.remove(itemToRemove)
        item.pairedItems = currentPairedItems as NSSet
        
        // Remove from the other item's paired items
        var otherItemPairedItems = itemToRemove.pairedItems as? Set<Item> ?? []
        otherItemPairedItems.remove(item)
        itemToRemove.pairedItems = otherItemPairedItems as NSSet
        
        do {
            // Set updatedAt on both items since we're modifying them
            setUpdatedAt(item)
            setUpdatedAt(itemToRemove)
            
            try viewContext.save()
            
            // Trigger automatic sync for both items
            SyncService.shared.syncItemIfNeeded(item)
            SyncService.shared.syncItemIfNeeded(itemToRemove)
            
            // Clear the state variable and allow user to continue pairing/unpairing
            itemToUnpair = nil
        } catch {
            print("❌ Failed to un-pair item: \(error)")
        }
    }
}

