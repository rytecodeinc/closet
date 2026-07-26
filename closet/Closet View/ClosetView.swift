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
    @EnvironmentObject private var authSession: AuthSession
    @StateObject var filterModel = ItemFilterModel()
    @StateObject var outfitFilterModel = OutfitFilterModel()
    @StateObject private var tabBarHideState = TabBarHideState()
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.createdAt, ascending: true)],
        predicate: NSPredicate(format: "type == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)", "closet")
    ) private var allClosetsOfType: FetchedResults<Wardrobe>

    private var currentUserId: String? {
        authSession.userId?.uuidString
    }

    /// Closets belonging to the signed-in user only (same-store multi-account safe).
    private var userClosets: [Wardrobe] {
        guard let uid = currentUserId else { return [] }
        return allClosetsOfType.filter { $0.userId == uid }
    }
    
    @State private var selectedWardrobe: Wardrobe?
    @State private var showClosetSheet = false
    @State private var newClosetName: String = ""
    @State private var isCreatingNewCloset = false
    @State private var showRenameWardrobeAlert = false
    @State private var renameTargetWardrobe: Wardrobe?
    @State private var renameDraft: String = ""
    @State private var isItemGridInSelectionMode = false
    @State private var wardrobePendingDelete: Wardrobe?
    @State private var showDeleteWardrobeConfirmation = false
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            mainContent()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { navigationBarToolbar() }
                .navigationDestination(for: ItemGridFilterRoute.self) { route in
                    switch route {
                    case .itemFilter:
                        ItemFilterView(
                            filterModel: filterModel,
                            tabBarHideState: tabBarHideState,
                            wardrobeType: "closet",
                            selectedWardrobe: selectedWardrobe
                        )
                    case .outfitFilter:
                        OutfitFilterView(
                            filterModel: outfitFilterModel,
                            wardrobeType: "closet",
                            selectedWardrobe: selectedWardrobe
                        )
                    }
                }
                .onAppear {
                    if let uid = authSession.userId {
                        try? WardrobeBootstrap.ensureDefaultWardrobes(for: uid, in: viewContext)
                    }
                    setInitialCloset()
                }
                .alert("New Wardrobe", isPresented: $isCreatingNewCloset) {
                    createClosetAlertButtons()
                } message: {
                    Text("Enter a name for your new closet")
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
        ZStack(alignment: .bottom) {
            if let selected = selectedWardrobe {
                ItemGridView(
                    filterModel: filterModel,
                    outfitFilterModel: outfitFilterModel,
                    wardrobeType: "closet",
                    selectedWardrobe: selected,
                    isInSelectionMode: $isItemGridInSelectionMode,
                    onOpenItemFilter: {
                        tabBarHideState.shouldHideTabBar = true
                        navigationPath.append(ItemGridFilterRoute.itemFilter)
                    },
                    onOpenOutfitFilter: {
                        tabBarHideState.shouldHideTabBar = true
                        navigationPath.append(ItemGridFilterRoute.outfitFilter)
                    },
                    tabBarHideState: tabBarHideState
                )
                .id(selected.objectID)
            } else {
                Text("No Closet Selected")
                    .foregroundColor(.secondary)
            }
            BulkImportProgressOverlay()
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
                destination: ItemAddView(
                    parentContext: viewContext,
                    selectedWardrobe: selectedWardrobe,
                    sessionAccountId: authSession.userId?.uuidString
                )
            ) {
                Image(systemName: "plus")
            }
        }
    }
    
    /// Ensure the default "Closet" (seeded) is always used first
    func setInitialCloset() {
        guard currentUserId != nil else { return }

        if let selected = selectedWardrobe,
           !userClosets.contains(where: { $0.objectID == selected.objectID }) {
            selectedWardrobe = nil
        }
        if selectedWardrobe == nil {
            if userClosets.isEmpty {
                isCreatingNewCloset = true   // force first-time creation
            } else {
                selectedWardrobe = WardrobeBootstrap.primaryWardrobe(in: userClosets)
            }
        }
    }

    
    func createClosetAlertButtons() -> some View {
        Group {
            TextField("i.e. Vacation, Business Trip", text: $newClosetName)
                .textInputAutocapitalization(.words)
            Button("Create") {
                if let newCloset = createNewCloset(named: newClosetName) {
                    selectedWardrobe = newCloset
                }
                showClosetSheet = false
            }
            Button("Cancel", role: .cancel) { }
        }
    }
    
    @ViewBuilder
    func closetSelectionSheet() -> some View {
        NavigationView {
            List {
                ForEach(userClosets, id: \.objectID) { closet in
                    Button {
                        if selectedWardrobe?.objectID != closet.objectID {
                            filterModel.clearAll()
                            outfitFilterModel.clearAll()
                            navigationPath = NavigationPath()
                        }
                        selectedWardrobe = closet
                        showClosetSheet = false
                    } label: {
                        HStack {
                            Text(closet.name ?? "Untitled")
                                .foregroundColor(.primary)

                            Spacer()

                            if closet.isDefault == true {
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

                            if closet == selectedWardrobe {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    // Prevent swipe-to-delete on the default closet
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if closet.isDefault != true {
                            Button {
                                renameTargetWardrobe = closet
                                renameDraft = WardrobeNaming.normalizedUserName(closet.name ?? "")
                                showRenameWardrobeAlert = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.blue)

                            Button(role: .destructive) {
                                wardrobePendingDelete = closet
                                showDeleteWardrobeConfirmation = true
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
                        showClosetSheet = false
                       // DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            isCreatingNewCloset = true
                       // }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .alert("Rename Wardrobe", isPresented: $showRenameWardrobeAlert) {
            TextField("Wardrobe name", text: $renameDraft)
                .textInputAutocapitalization(.words)
            Button("Save") {
                if let wardrobe = renameTargetWardrobe {
                    updateWardrobeName(wardrobe, to: renameDraft)
                    selectedWardrobe = wardrobe
                }
                renameTargetWardrobe = nil
                renameDraft = ""
            }
            Button("Cancel", role: .cancel) {
                renameTargetWardrobe = nil
                renameDraft = ""
            }
        } message: {
            Text("Enter a new name for this wardrobe")
        }
        .alert(
            wardrobeDeleteAlertTitle(pendingDelete: wardrobePendingDelete, fallbackTitle: "Delete Closet?"),
            isPresented: $showDeleteWardrobeConfirmation
        ) {
            Button("Delete", role: .destructive) {
                if let wardrobe = wardrobePendingDelete {
                    deleteCloset(wardrobe)
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
                    userWardrobesSameKind: userClosets,
                    fallbackDefaultDisplayName: "Closet"
                )
            )
        }
    }

    private func createNewCloset(named name: String) -> Wardrobe? {
        let normalized = WardrobeNaming.normalizedUserName(name)
        guard !normalized.isEmpty else { return nil }

        let newCloset = Wardrobe(context: viewContext)
        newCloset.id = UUID()
        newCloset.type = "closet"
        newCloset.name = normalized
        newCloset.wardrobeVisibility = .public
        
        // Set userId for sync
        if let userId = authSession.userId?.uuidString {
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
           let userId = authSession.userId?.uuidString {
            closet.userId = userId
        }
        
        // Soft delete the wardrobe (for sync) - this also sets updatedAt
        softDelete(closet)
        
        // Reset selectedCloset if the deleted one was selected (before save)
        if selectedWardrobe == closet {
            selectedWardrobe = WardrobeBootstrap.primaryWardrobe(in: userClosets)
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
        let normalized = WardrobeNaming.normalizedUserName(newName)
        guard !normalized.isEmpty else { return }

        wardrobe.name = normalized
        
        // Set updatedAt for sync
        setUpdatedAt(wardrobe)
        
        // Ensure userId is set if missing
        if wardrobe.userId == nil || wardrobe.userId?.isEmpty == true,
           let userId = authSession.userId?.uuidString {
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





