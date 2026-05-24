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
    @EnvironmentObject private var authSession: AuthSession

    let wardrobeType: String
    let selectedWardrobe: Wardrobe?

    /// Called when the user taps a draft to continue editing it.
    var onSelectDraft: ((Outfit) -> Void)? = nil
    
    @FetchRequest(
        entity: Outfit.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Outfit.createdAt, ascending: false)],
        predicate: NSPredicate(format: "isDraft == YES AND (isSoftDeleted != YES OR isSoftDeleted == nil)")
    ) private var allDrafts: FetchedResults<Outfit>
    
    private var currentUserId: String? {
        authSession.userId?.uuidString
    }

    /// Active wardrobe for draft filtering — explicit selection, or primary for `wardrobeType`.
    private var resolvedActiveWardrobe: Wardrobe? {
        guard let userId = currentUserId else { return nil }
        if let selected = selectedWardrobe,
           selected.userId == userId,
           selected.isSoftDeleted != true {
            return selected
        }
        return try? WardrobeBootstrap.fetchPrimaryWardrobe(
            forType: wardrobeType,
            userIdString: userId,
            in: viewContext
        )
    }

    // Filter drafts by user, then active wardrobe (never wardrobe-type-only fallback).
    private var drafts: [Outfit] {
        guard let userId = currentUserId,
              let wardrobe = resolvedActiveWardrobe else { return [] }
        return allDrafts.filter { outfit in
            guard outfit.userId == userId else { return false }
            guard let items = outfit.items as? Set<Item>, !items.isEmpty else { return false }
            return outfitItemsMatchWardrobe(items: items, wardrobe: wardrobe)
        }
    }

    /// Same wardrobe rules as ItemGridView outfit filtering.
    private func outfitItemsMatchWardrobe(items: Set<Item>, wardrobe: Wardrobe) -> Bool {
        let isWishlist = wardrobe.type?.lowercased() == "wishlist"
        if isWishlist {
            let hasItemFromThisWishlist = items.contains { item in
                guard let wardrobes = item.wardrobes as? Set<Wardrobe> else { return false }
                return wardrobes.contains(wardrobe)
            }
            guard hasItemFromThisWishlist else { return false }
            return items.allSatisfy { item in
                guard let wardrobes = item.wardrobes as? Set<Wardrobe> else { return false }
                let wishlistWardrobes = wardrobes.filter { $0.type?.lowercased() == "wishlist" }
                if wishlistWardrobes.isEmpty { return true }
                return wishlistWardrobes.contains(wardrobe)
            }
        }
        return items.allSatisfy { item in
            guard let wardrobes = item.wardrobes as? Set<Wardrobe> else { return false }
            return wardrobes.contains(wardrobe)
        }
    }
    
    @State private var isEditing: Bool = false
    @State private var draftToDelete: Outfit? = nil
    @State private var showingDeleteConfirmation: Bool = false
    
    init(wardrobeType: String = "closet", selectedWardrobe: Wardrobe? = nil, onSelectDraft: ((Outfit) -> Void)? = nil) {
        self.wardrobeType = wardrobeType
        self.selectedWardrobe = selectedWardrobe
        self.onSelectDraft = onSelectDraft
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
                                Button {
                                    if !isEditing {
                                        onSelectDraft?(draft)
                                    }
                                } label: {
                                    OutfitView(outfit: draft)
                                }
                                .buttonStyle(.plain)

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

