//
//  WishlistView.swift
//  closet
//
//  Created by Dan Warner on 7/24/25.
//


import SwiftUI
import CoreData

struct WishlistView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var supabaseService: SupabaseService
    @StateObject var filterModel = ItemFilterModel()
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.createdAt, ascending: true)],
        predicate: NSPredicate(format: "type == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)", "wishlist")
    ) private var allWishlistsOfType: FetchedResults<Wardrobe>

    private var currentUserId: String? {
        supabaseService.currentUser?.id.uuidString
    }

    /// Wishlists for the signed-in user only.
    private var userWishlists: [Wardrobe] {
        guard let uid = currentUserId else { return [] }
        return allWishlistsOfType.filter { $0.userId == uid }
    }
    
    @State private var selectedWishlist: Wardrobe?
    @State private var showWishlistSheet = false
    @State private var newWishlistName: String = ""
    @State private var isCreatingNewWishlist = false
    @State private var editingWardrobe: Wardrobe?
    @State private var editingName: String = ""
    @State private var showEditAlert = false
    @State private var isItemGridInSelectionMode = false
    @State private var wardrobePendingDelete: Wardrobe?
    @State private var showDeleteWardrobeConfirmation = false
    
    var body: some View {
       // NavigationView {
            mainContent()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { navigationBarToolbar() }
                .onAppear {
                    if let uid = supabaseService.currentUser?.id {
                        try? WardrobeBootstrap.ensureDefaultWardrobes(for: uid, in: viewContext)
                    }
                    setInitialWishlist()
                }
                .alert("New Wishlist", isPresented: $isCreatingNewWishlist) {
                    createWishlistAlertButtons()
                } message: {
                    Text("Enter a name for your new wishlist (max \(WardrobeNaming.maxNameLength) characters)")
                }
                .alert("Edit Wardrobe", isPresented: $showEditAlert) {
                    editWishlistAlertButtons()
                } message: {
                    Text("Enter a new name for this wardrobe (max \(WardrobeNaming.maxNameLength) characters)")
                }
                .sheet(isPresented: $showWishlistSheet) {
                    wishlistSelectionSheet()
                }
       // }
    }
}

// MARK: - Body Subviews
private extension WishlistView {
    
    @ViewBuilder
    func mainContent() -> some View {
        ZStack(alignment: .bottom) {
            if let selected = selectedWishlist {
                ItemGridView(
                    filterModel: filterModel,
                    wardrobeType: "wishlist",
                    selectedWardrobe: selected,
                    isInSelectionMode: $isItemGridInSelectionMode
                )
            } else {
                Text("No Wishlist Selected")
                    .foregroundColor(.secondary)
            }
            BulkImportProgressOverlay()
        }
    }
    
    @ToolbarContentBuilder
    func navigationBarToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            // Only show wishlistSelectionButton when NOT in item selection mode
            if !isItemGridInSelectionMode {
                wishlistSelectionButton()
            }
        }
      /*  ToolbarItem(placement: .navigationBarTrailing) {
            addItemButton()
        }*/
    }
    
    func wishlistSelectionButton() -> some View {
        Button {
            showWishlistSheet = true
            isCreatingNewWishlist = false
        } label: {
            HStack(spacing: 4) {
                Text(selectedWishlist?.name ?? "Select Wishlist")
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
        }
    }
    
    @ViewBuilder
    func addItemButton() -> some View {
        if let selectedWishlist = selectedWishlist {
            NavigationLink(
                destination: ItemAddView(parentContext: viewContext, selectedWardrobe: selectedWishlist)
            ) {
                Image(systemName: "plus")
            }
        }
    }
    
    /// Ensure the default "Wishlist" (seeded) is always used first
    func setInitialWishlist() {
        guard currentUserId != nil else { return }

        if let selected = selectedWishlist,
           !userWishlists.contains(where: { $0.objectID == selected.objectID }) {
            selectedWishlist = nil
        }
        if selectedWishlist == nil {
            if userWishlists.isEmpty {
                isCreatingNewWishlist = true   // force first-time creation
            } else {
                selectedWishlist = WardrobeBootstrap.primaryWardrobe(in: userWishlists)
            }
        }
    }
    
    func createWishlistAlertButtons() -> some View {
        Group {
            TextField("i.e. Summer Items, Gifts", text: $newWishlistName)
                .textInputAutocapitalization(.words)
                .onChange(of: newWishlistName) { _, new in
                    if new.count > WardrobeNaming.maxNameLength {
                        newWishlistName = String(new.prefix(WardrobeNaming.maxNameLength))
                    }
                }
            Button("Create") {
                if let newWishlist = createNewWishlist(named: newWishlistName) {
                    selectedWishlist = newWishlist
                }
                showWishlistSheet = false
            }
            Button("Cancel", role: .cancel) { }
        }
    }
    
    func editWishlistAlertButtons() -> some View {
        Group {
            TextField("Wardrobe name", text: $editingName)
                .textInputAutocapitalization(.words)
                .onChange(of: editingName) { _, new in
                    if new.count > WardrobeNaming.maxNameLength {
                        editingName = String(new.prefix(WardrobeNaming.maxNameLength))
                    }
                }
            Button("Save") {
                if let wardrobe = editingWardrobe {
                    updateWardrobeName(wardrobe, to: editingName)
                }
                editingWardrobe = nil
                editingName = ""
            }
            Button("Cancel", role: .cancel) {
                editingWardrobe = nil
                editingName = ""
            }
        }
    }
    
    @ViewBuilder
    func wishlistSelectionSheet() -> some View {
        NavigationView {
            List {
                ForEach(userWishlists, id: \.objectID) { wishlist in
                    ZStack(alignment: .trailing) {
                        Button {
                            selectedWishlist = wishlist
                            showWishlistSheet = false
                        } label: {
                            HStack {
                                Text(wishlist.name ?? "Untitled")
                                
                                if wishlist == selectedWishlist {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                                
                                if wishlist.isDefault == true {
                                    Text("Default")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(Color(UIColor.secondarySystemBackground))
                                        )
                                }
                                
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            editingWardrobe = wishlist
                            editingName = WardrobeNaming.normalizedUserName(wishlist.name ?? "")
                            showEditAlert = true
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.plain)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if wishlist.isDefault != true {
                            Button(role: .destructive) {
                                wardrobePendingDelete = wishlist
                                showDeleteWardrobeConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Your Wishlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newWishlistName = ""
                        isCreatingNewWishlist = true
                    } label: {
                        HStack {
                            Text("Add")
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .alert(
            wardrobeDeleteAlertTitle(pendingDelete: wardrobePendingDelete, fallbackTitle: "Delete Wishlist?"),
            isPresented: $showDeleteWardrobeConfirmation
        ) {
            Button("Delete", role: .destructive) {
                if let wardrobe = wardrobePendingDelete {
                    deleteWishlist(wardrobe)
                }
                wardrobePendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                wardrobePendingDelete = nil
            }
        } message: {
            Text(
                wardrobeDeleteConfirmationMessage(
                    pendingDelete: wardrobePendingDelete,
                    userWardrobesSameKind: userWishlists,
                    fallbackDefaultDisplayName: "Wishlist"
                )
            )
        }
    }

    private func createNewWishlist(named name: String) -> Wardrobe? {
        let normalized = WardrobeNaming.normalizedUserName(name)
        guard !normalized.isEmpty else { return nil }

        let newWishlist = Wardrobe(context: viewContext)
        newWishlist.id = UUID()
        newWishlist.type = "wishlist"
        newWishlist.name = normalized
        
        // Set userId for sync
        if let userId = SupabaseService.shared.currentUser?.id.uuidString {
            newWishlist.userId = userId
        }
        
        // Set timestamps using helper
        setCreatedAndUpdatedAt(newWishlist)
        let now = Date()
        newWishlist.timestamp = now
        
        do {
            try viewContext.save()
            
            // Trigger automatic sync for the new wardrobe
            SyncService.shared.syncWardrobeIfNeeded(newWishlist)
            
            return newWishlist
        } catch {
            print("❌ Failed to save new wishlist: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func deleteWishlist(_ wishlist: Wardrobe) {
        // Ensure userId is set if missing (needed for sync)
        if wishlist.userId == nil || wishlist.userId?.isEmpty == true,
           let userId = SupabaseService.shared.currentUser?.id.uuidString {
            wishlist.userId = userId
        }
        
        // Soft delete the wardrobe (for sync) - this also sets updatedAt
        softDelete(wishlist)
        
        do {
            try viewContext.save()
            
            // Trigger automatic sync for the deleted wardrobe
            SyncService.shared.syncWardrobeIfNeeded(wishlist)
        } catch {
            print("❌ Failed to delete wishlist: \(error.localizedDescription)")
        }

        // If the deleted wishlist was selected, reset to the default one
        if selectedWishlist == wishlist {
            selectedWishlist = WardrobeBootstrap.primaryWardrobe(in: userWishlists)
        }
    }
    
    private func updateWardrobeName(_ wardrobe: Wardrobe, to newName: String) {
        let normalized = WardrobeNaming.normalizedUserName(newName)
        guard !normalized.isEmpty else { return }

        wardrobe.name = normalized
        
        // Set updatedAt for sync
        setUpdatedAt(wardrobe)
        
        // Ensure userId is set if missing
        if wardrobe.userId == nil || wardrobe.userId?.isEmpty == true,
           let userId = SupabaseService.shared.currentUser?.id.uuidString {
            wardrobe.userId = userId
        }
        
        do {
            try viewContext.save()
            
            // Trigger automatic sync for the updated wardrobe
            SyncService.shared.syncWardrobeIfNeeded(wardrobe)
        } catch {
            print("❌ Failed to update wardrobe name: \(error.localizedDescription)")
        }
    }

}


