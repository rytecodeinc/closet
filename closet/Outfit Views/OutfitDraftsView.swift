//
//  OutfitDraftsView.swift
//  closet
//
//  Created for displaying outfit drafts
//

import SwiftUI
import CoreData

struct OutfitDraftsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    let wardrobeType: String
    let selectedWardrobe: Wardrobe?
    
    @FetchRequest(
        entity: Outfit.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Outfit.timestamp, ascending: false)],
        predicate: NSPredicate(format: "isDraft == YES AND (isSoftDeleted != YES OR isSoftDeleted == nil)")
    ) private var allDrafts: FetchedResults<Outfit>
    
    // Filter drafts by selected wardrobe or wardrobe type
    private var drafts: [Outfit] {
        allDrafts.filter { outfit in
            guard let items = outfit.items as? Set<Item> else { return false }
            
            // If a specific wardrobe is selected, filter by that wardrobe
            if let selectedWardrobe = selectedWardrobe {
                return items.contains { item in
                    guard let wardrobes = item.wardrobes as? Set<Wardrobe> else { return false }
                    return wardrobes.contains(selectedWardrobe)
                }
            }
            
            // Otherwise, filter by wardrobe type
            return items.contains { item in
                guard let wardrobes = item.wardrobes as? Set<Wardrobe> else { return false }
                return wardrobes.contains { $0.type == wardrobeType }
            }
        }
    }
    
    @State private var isEditing: Bool = false
    @State private var draftToDelete: Outfit? = nil
    @State private var showingDeleteConfirmation: Bool = false
    
    init(wardrobeType: String = "closet", selectedWardrobe: Wardrobe? = nil) {
        self.wardrobeType = wardrobeType
        self.selectedWardrobe = selectedWardrobe
    }
    
    private let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        Group {
            if drafts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No drafts yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Save outfits as drafts to view them here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(drafts, id: \.objectID) { draft in
                            ZStack(alignment: .topTrailing) {
                                NavigationLink(destination: OutfitAddView(outfitToEdit: draft, wardrobeType: wardrobeType)) {
                                    OutfitView(outfit: draft)
                                }
                                .buttonStyle(.plain)
                                .disabled(isEditing)
                                
                                // Delete button overlay in edit mode
                                if isEditing {
                                    Button {
                                        draftToDelete = draft
                                        showingDeleteConfirmation = true
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                            .font(.system(size: 14))
                                            .padding(6)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .navigationTitle("Outfit Drafts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Toggle Edit Mode
                Button(isEditing ? "Done" : "Edit") {
                    isEditing.toggle()
                }
            }
        }
        // Confirmation alert before deleting
        .alert("Delete Draft?", isPresented: $showingDeleteConfirmation, presenting: draftToDelete) { draft in
            Button("Delete", role: .destructive) {
                deleteDraft(draft)
            }
            Button("Cancel", role: .cancel) {}
        } message: { draft in
            Text("Are you sure you want to delete this outfit?")
        }
    }
    
    // MARK: - Delete Draft
    private func deleteDraft(_ draft: Outfit) {
        // Soft delete the draft (for sync)
        softDelete(draft)
        do {
            try viewContext.save()
        } catch {
            print("Failed to delete draft: \(error)")
        }
    }
}

