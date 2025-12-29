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
    @StateObject var filterModel = ItemFilterModel()
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.timestamp, ascending: true)],
        predicate: NSPredicate(format: "type == %@", "wishlist")
    ) private var wishlists: FetchedResults<Wardrobe>
    
    @State private var selectedWishlist: Wardrobe?
    @State private var showWishlistSheet = false
    @State private var newWishlistName: String = ""
    @State private var isCreatingNewWishlist = false
    @State private var editingWardrobe: Wardrobe?
    @State private var editingName: String = ""
    @State private var showEditAlert = false
    
    var body: some View {
        NavigationView {
            mainContent()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { navigationBarToolbar() }
                .onAppear { setInitialWishlist() }
                .alert("New Wishlist", isPresented: $isCreatingNewWishlist) {
                    createWishlistAlertButtons()
                } message: {
                    Text("Enter a name for your new wishlist")
                }
                .alert("Edit Wardrobe", isPresented: $showEditAlert) {
                    editWishlistAlertButtons()
                } message: {
                    Text("Enter a new name for this wardrobe")
                }
                .sheet(isPresented: $showWishlistSheet) {
                    wishlistSelectionSheet()
                }
        }
    }
}

// MARK: - Body Subviews
private extension WishlistView {
    
    @ViewBuilder
    func mainContent() -> some View {
        if let selected = selectedWishlist {
            ItemGridView(
                filterModel: filterModel,
                wardrobeType: "wishlist",
                selectedWardrobe: selected
            )
        } else {
            Text("No Wishlist Selected")
                .foregroundColor(.secondary)
        }
    }
    
    @ToolbarContentBuilder
    func navigationBarToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            wishlistSelectionButton()
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
        if selectedWishlist == nil {
            if wishlists.isEmpty {
                isCreatingNewWishlist = true   // force first-time creation
            } else {
                selectedWishlist = wishlists.first
            }
        }
    }
    
    func createWishlistAlertButtons() -> some View {
        Group {
            TextField("i.e. Summer Items, Gifts", text: $newWishlistName)
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
                ForEach(wishlists, id: \.self) { wishlist in
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
                                
                                // Add "Default" badge for the first wishlist
                                if wishlist == wishlists.first {
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
                            editingName = wishlist.name ?? ""
                            showEditAlert = true
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.plain)
                    }
                    // Prevent deleting the default wishlist
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if wishlist != wishlists.first {
                            Button(role: .destructive) {
                                deleteWishlist(wishlist)
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
           /* .toolbar {
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
            }*/
        }
        .presentationDetents([.medium, .large])
    }

    
    private func createNewWishlist(named name: String) -> Wardrobe? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let newWishlist = Wardrobe(context: viewContext)
        newWishlist.id = UUID()
        newWishlist.type = "wishlist"
        newWishlist.name = trimmed
        newWishlist.timestamp = Date()
        
        do {
            try viewContext.save()
            return newWishlist
        } catch {
            print("❌ Failed to save new wishlist: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func deleteWishlist(_ wishlist: Wardrobe) {
        viewContext.delete(wishlist)
        do {
            try viewContext.save()
        } catch {
            print("❌ Failed to delete wishlist: \(error.localizedDescription)")
        }

        // If the deleted wishlist was selected, reset to the default one
        if selectedWishlist == wishlist {
            selectedWishlist = wishlists.first
        }
    }
    
    private func updateWardrobeName(_ wardrobe: Wardrobe, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        wardrobe.name = trimmed
        do {
            try viewContext.save()
        } catch {
            print("❌ Failed to update wardrobe name: \(error.localizedDescription)")
        }
    }

}


