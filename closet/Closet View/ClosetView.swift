//
//  ClosetViewTest.swift
//  closet
//
//  Created by Dan Warner on 7/20/25.
//


import SwiftUI
import CoreData

struct ClosetView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject var filterModel = ItemFilterModel()
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.createdAt, ascending: true)],
        predicate: NSPredicate(format: "type == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)", "closet")
    ) private var closets: FetchedResults<Wardrobe>
    
    @State private var selectedWardrobe: Wardrobe?
    @State private var showClosetSheet = false
    @State private var newClosetName: String = ""
    @State private var isCreatingNewCloset = false
    @State private var editingWardrobe: Wardrobe?
    @State private var editingName: String = ""
    @State private var showEditAlert = false
    @State private var isItemGridInSelectionMode = false
    
    var body: some View {
        NavigationView {
            mainContent()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { navigationBarToolbar() }
                .onAppear { setInitialCloset() }
                .alert("New Wardrobe", isPresented: $isCreatingNewCloset) {
                    createClosetAlertButtons()
                } message: {
                    Text("Enter a name for your new closet")
                }
                .alert("Edit Wardrobe", isPresented: $showEditAlert) {
                    editClosetAlertButtons()
                } message: {
                    Text("Enter a new name for this wardrobe")
                }
                .sheet(isPresented: $showClosetSheet) {
                    closetSelectionSheet()
                }
        }
    }
}

// MARK: - Body Subviews
private extension ClosetView {
    
    @ViewBuilder
    func mainContent() -> some View {
        if let selected = selectedWardrobe {
            ItemGridView(
                filterModel: filterModel,
                wardrobeType: "closet",
                selectedWardrobe: selected,
                isInSelectionMode: $isItemGridInSelectionMode
            )
            .id(selected.objectID)
        } else {
            Text("No Closet Selected")
                .foregroundColor(.secondary)
        }
    }
    
    @ToolbarContentBuilder
    func navigationBarToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            // Only show closetSelectionButton when NOT in item selection mode
            if !isItemGridInSelectionMode {
                closetSelectionButton()
            }
        }
     /*   ToolbarItem(placement: .navigationBarTrailing) {
            addItemButton()
        }*/
        
    }
    
    func closetSelectionButton() -> some View {
        Button {
            showClosetSheet = true
            isCreatingNewCloset = false
        } label: {
            HStack(spacing: 4) {
                Text(selectedWardrobe?.name ?? "Select Closet")
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
        }
    }
    
    @ViewBuilder
    func addItemButton() -> some View {
        if let selectedWardrobe = selectedWardrobe {
            NavigationLink(
                destination: ItemAddView(parentContext: viewContext, selectedWardrobe: selectedWardrobe)
            ) {
                Image(systemName: "plus")
            }
        }
    }
    
    /// Ensure the default "Closet" (seeded) is always used first
    func setInitialCloset() {
        if selectedWardrobe == nil {
            if closets.isEmpty {
                isCreatingNewCloset = true   // force first-time creation
            } else {
                selectedWardrobe = closets.first
            }
        }
    }

    
    func createClosetAlertButtons() -> some View {
        Group {
            TextField("i.e. Vacation, Business Trip", text: $newClosetName)
            Button("Create") {
                if let newCloset = createNewCloset(named: newClosetName) {
                    selectedWardrobe = newCloset
                }
                showClosetSheet = false
            }
            Button("Cancel", role: .cancel) { }
        }
    }
    
    func editClosetAlertButtons() -> some View {
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
    func closetSelectionSheet() -> some View {
        NavigationView {
            List {
                ForEach(closets, id: \.self) { closet in
                    ZStack(alignment: .trailing) {
                        Button {
                            selectedWardrobe = closet
                            showClosetSheet = false
                        } label: {
                            HStack {
                                Text(closet.name ?? "Untitled")
                                
                                if closet == selectedWardrobe {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                                
                                // Add "Default" label next to the first closet
                                if closet == closets.first {
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
                            editingWardrobe = closet
                            editingName = closet.name ?? ""
                            showEditAlert = true
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.plain)
                    }
                    // Prevent swipe-to-delete on the first (default) closet
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if closet != closets.first {
                            Button(role: .destructive) {
                                deleteCloset(closet)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Your Wardrobes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newClosetName = ""
                        isCreatingNewCloset = true
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
    }

    
    private func createNewCloset(named name: String) -> Wardrobe? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let newCloset = Wardrobe(context: viewContext)
        newCloset.id = UUID()
        newCloset.type = "closet"
        newCloset.name = trimmed
        
        // Set userId for sync
        if let userId = SupabaseService.shared.currentUser?.id.uuidString {
            newCloset.userId = userId
        }
        
        // Set timestamps using helper
        setCreatedAndUpdatedAt(newCloset)
        let now = Date()
        newCloset.timestamp = now
        
        do {
            try viewContext.save()
            
            // Trigger automatic sync for the new wardrobe
            SyncService.shared.syncWardrobeIfNeeded(newCloset)
            
            return newCloset
        } catch {
            print("❌ Failed to save new closet: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func deleteCloset(_ closet: Wardrobe) {
        // Store the wardrobe ID before deletion (for sync)
        guard let wardrobeId = closet.id else {
            print("⚠️ Cannot delete wardrobe without ID")
            return
        }
        
        // Ensure userId is set if missing (needed for sync)
        if closet.userId == nil || closet.userId?.isEmpty == true,
           let userId = SupabaseService.shared.currentUser?.id.uuidString {
            closet.userId = userId
        }
        
        // Soft delete the wardrobe (for sync) - this also sets updatedAt
        softDelete(closet)
        
        // Reset selectedCloset if the deleted one was selected (before save)
        if selectedWardrobe == closet {
            selectedWardrobe = closets.first
        }
        
        do {
            try viewContext.save()
            print("✅ Soft deleted wardrobe: \(closet.name ?? "unnamed") (isSoftDeleted: \(closet.isSoftDeleted))")
            
            // Trigger automatic sync for the deleted wardrobe
            // Use the objectID to ensure we're syncing the correct wardrobe even after it's filtered out
            SyncService.shared.syncWardrobeIfNeeded(closet)
        } catch {
            print("❌ Failed to delete closet: \(error.localizedDescription)")
        }
    }
    
    private func updateWardrobeName(_ wardrobe: Wardrobe, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        wardrobe.name = trimmed
        
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





