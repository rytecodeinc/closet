//
//  ItemDraftsView.swift
//  closet
//
//  Created for displaying item drafts
//

import SwiftUI
import UIKit
import CoreData

struct ItemDraftsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var authSession: AuthSession

    /// Called when the user taps a draft to continue editing it.
    var onSelectDraft: ((Item) -> Void)? = nil

    @FetchRequest(
        entity: Item.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Item.updatedAt, ascending: false),
            NSSortDescriptor(keyPath: \Item.timestamp, ascending: false)
        ],
        predicate: NSPredicate(format: "isDraft == YES AND (isSoftDeleted != YES OR isSoftDeleted == nil)")
    ) private var allDrafts: FetchedResults<Item>

    private var currentUserId: String? {
        authSession.userId?.uuidString
    }

    private var drafts: [Item] {
        guard let userId = currentUserId else { return [] }
        return allDrafts.filter { $0.userId == userId }
    }
    
    // Selection mode state
    @State private var isInSelectionMode: Bool = false
    @State private var selectedItems: Set<Item> = []
    
    @State private var draftToDelete: Item? = nil
    @State private var showingDeleteConfirmation: Bool = false
    
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
                    Text("Save items as drafts to view them here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(drafts, id: \.objectID) { draft in
                            ItemView(item: draft)
                                .overlay(
                                    // Transparent white overlay when in selection mode
                                    Group {
                                        if isInSelectionMode && selectedItems.contains(draft) {
                                            Rectangle()
                                                .fill(Color.white.opacity(0.35))
                                        }
                                    }
                                )
                                .overlay(
                                    // Show selection checkmark when in selection mode (on top of white overlay)
                                    Group {
                                        if isInSelectionMode {
                                            VStack {
                                                Spacer()
                                                HStack {
                                                    Spacer()
                                                    Image(systemName: selectedItems.contains(draft) ? "checkmark.circle" : "circle")
                                                        .foregroundColor(.white)
                                                        .background(
                                                            Circle()
                                                                .fill(selectedItems.contains(draft) ? Color.blue : Color.clear)
                                                                .padding(2)
                                                        )
                                                        .font(.system(size: 22))
                                                        .shadow(radius: 1)
                                                        .padding(8)
                                                }
                                            }
                                        }
                                    }
                                )
                                .contentShape(Rectangle()) // Make entire area tappable
                                .onTapGesture {
                                    handleTap(for: draft)
                                }
                                .onLongPressGesture(minimumDuration: 0.5) {
                                    handleLongPress(for: draft)
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle(isInSelectionMode ? "\(selectedItems.count) Selected" : "Item Drafts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isInSelectionMode {
                    HStack(spacing: 16) {
                        Button {
                            if !selectedItems.isEmpty {
                                showingDeleteConfirmation = true
                            }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .disabled(selectedItems.isEmpty)
                        
                        Button("Cancel") {
                            isInSelectionMode = false
                            selectedItems.removeAll()
                        }
                    }
                } else {
                    // No toolbar button when not in selection mode
                    EmptyView()
                }
            }
        }
        // Confirmation alert before deleting
        .alert("Delete Draft\(isInSelectionMode && selectedItems.count > 1 ? "s" : "")?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if isInSelectionMode && !selectedItems.isEmpty {
                    // Delete all selected items (even if just one)
                    deleteSelectedDrafts()
                } else if let draft = draftToDelete {
                    // Delete single draft (fallback for non-selection mode)
                    deleteDraft(draft)
                    draftToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                draftToDelete = nil
            }
        } message: {
            if isInSelectionMode && selectedItems.count > 1 {
                Text("Are you sure you want to delete \(selectedItems.count) drafts? This action cannot be undone.")
            } else {
                Text("Are you sure you want to delete this draft? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Gesture Handlers
    
    private func handleTap(for draft: Item) {
        if isInSelectionMode {
            // Toggle selection
            if selectedItems.contains(draft) {
                selectedItems.remove(draft)
            } else {
                selectedItems.insert(draft)
            }
            
            // Exit selection mode if no items selected
            if selectedItems.isEmpty {
                isInSelectionMode = false
            }
        } else {
            // Open draft for editing
            onSelectDraft?(draft)
        }
    }
    
    private func handleLongPress(for draft: Item) {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Enter selection mode and select this item
        if !isInSelectionMode {
            isInSelectionMode = true
        }
        
        selectedItems.insert(draft)
    }
    
    // MARK: - Delete Draft
    
    private func deleteDraft(_ draft: Item) {
        // Store the brand before deletion to check if cleanup is needed
        let itemBrand = draft.brand
        
        // Soft delete the draft (for sync)
        softDelete(draft)
        
        do {
            try viewContext.save()
            
            // Trigger sync for the soft-deleted draft
            SyncService.shared.syncItemIfNeeded(draft)
            
            // Cleanup brand if it's now orphaned (has 0 items)
            if let brand = itemBrand {
                cleanupBrandIfOrphaned(brand)
            }
        } catch {
            print("Failed to delete draft: \(error)")
        }
    }
    
    private func deleteSelectedDrafts() {
        // Store brands before deletion for cleanup
        var brandsToCheck: Set<Brand> = []
        
        for draft in selectedItems {
            if let brand = draft.brand {
                brandsToCheck.insert(brand)
            }
            // Soft delete the draft (for sync)
            softDelete(draft)
        }
        
        do {
            try viewContext.save()
            
            // Trigger sync for all soft-deleted drafts
            for draft in selectedItems {
                SyncService.shared.syncItemIfNeeded(draft)
            }
            
            // Cleanup orphaned brands
            for brand in brandsToCheck {
                cleanupBrandIfOrphaned(brand)
            }
            
            // Exit selection mode
            isInSelectionMode = false
            selectedItems.removeAll()
        } catch {
            print("Failed to delete drafts: \(error)")
        }
    }
    
    // MARK: - Cleanup Orphaned Brand
    private func cleanupBrandIfOrphaned(_ brand: Brand) {
        // Refresh the brand to get current item count
        viewContext.refresh(brand, mergeChanges: true)
        
        // Check if brand has any items
        if let items = brand.items as? Set<Item>, items.isEmpty {
            viewContext.delete(brand)
            do {
                try viewContext.save()
                print("✅ Cleaned up orphaned brand: \(brand.name ?? "unknown")")
            } catch {
                print("❌ Failed to cleanup orphaned brand: \(error)")
            }
        }
    }
}

