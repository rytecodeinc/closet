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
    @Environment(\.appCapabilities) private var appCapabilities
    @EnvironmentObject private var authSession: AuthSession
    @StateObject var filterModel = ItemFilterModel()
    @StateObject var outfitFilterModel = OutfitFilterModel()
    @StateObject private var tabBarHideState = TabBarHideState()
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.createdAt, ascending: true)],
        predicate: NSPredicate(format: "type == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)", "wishlist")
    ) private var allWishlistsOfType: FetchedResults<Wardrobe>

    private var currentUserId: String? {
        authSession.userId?.uuidString
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
    @State private var showRenameWardrobeAlert = false
    @State private var renameTargetWardrobe: Wardrobe?
    @State private var renameDraft: String = ""
    @State private var isItemGridInSelectionMode = false
    @State private var isItemGridReplacingNavTitle = false
    @State private var wardrobePendingDelete: Wardrobe?
    @State private var showDeleteWardrobeConfirmation = false
    @State private var navigationPath = NavigationPath()
    @StateObject private var itemAddQueueCoordinator = ImageQueueCoordinator()

    private var newWishlistNameValidation: WardrobeNaming.Validation {
        WardrobeNaming.validate(newWishlistName, type: "wishlist", existing: userWishlists)
    }

    private var renameWishlistNameValidation: WardrobeNaming.Validation {
        WardrobeNaming.validate(
            renameDraft,
            type: "wishlist",
            existing: userWishlists,
            excluding: renameTargetWardrobe?.objectID
        )
    }
    
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
                            wardrobeType: "wishlist",
                            selectedWardrobe: selectedWishlist
                        )
                    case .outfitFilter:
                        OutfitFilterView(
                            filterModel: outfitFilterModel,
                            wardrobeType: "wishlist",
                            selectedWardrobe: selectedWishlist
                        )
                    case .addItem:
                        itemAddPathDestination(queued: false)
                    case .addItemQueued:
                        itemAddPathDestination(queued: true)
                    case .addOutfit(let sessionID):
                        outfitAddPathDestination(sessionID: sessionID)
                    case .itemDetail(let uri):
                        itemDetailPathDestination(uri: uri)
                    case .outfitDetail(let uri):
                        outfitDetailPathDestination(uri: uri)
                    case .createOutfitFromItem(let itemURI, let sessionID):
                        createOutfitFromItemPathDestination(itemURI: itemURI, sessionID: sessionID)
                    case .packing:
                        EmptyView()
                    case .packingChecklist:
                        EmptyView()
                    }
                }
                .onAppear {
                    if let uid = authSession.userId {
                        try? WardrobeBootstrap.ensureDefaultWardrobes(for: uid, in: viewContext)
                    }
                    setInitialWishlist()
                }
                .alert("New Wishlist", isPresented: $isCreatingNewWishlist) {
                    createWishlistAlertButtons()
                } message: {
                    Text(newWishlistNameValidation.alertMessage(emptyPrompt: "Enter a name for your new wishlist"))
                }
                .onChange(of: newWishlistName) { _, value in
                    let limited = WardrobeNaming.limitingTyping(value)
                    if limited != value { newWishlistName = limited }
                }
                .onChange(of: renameDraft) { _, value in
                    let limited = WardrobeNaming.limitingTyping(value)
                    if limited != value { renameDraft = limited }
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
        ZStack(alignment: .bottom) {
            if let selected = selectedWishlist {
                ItemGridView(
                    filterModel: filterModel,
                    outfitFilterModel: outfitFilterModel,
                    wardrobeType: "wishlist",
                    selectedWardrobe: selected,
                    isInSelectionMode: $isItemGridInSelectionMode,
                    isReplacingNavigationTitle: $isItemGridReplacingNavTitle,
                    onOpenItemFilter: {
                        tabBarHideState.shouldHideTabBar = true
                        navigationPath.append(ItemGridFilterRoute.itemFilter)
                    },
                    onOpenOutfitFilter: {
                        tabBarHideState.shouldHideTabBar = true
                        navigationPath.append(ItemGridFilterRoute.outfitFilter)
                    },
                    onOpenAddItem: { queued in
                        tabBarHideState.shouldHideTabBar = true
                        navigationPath.append(queued ? ItemGridFilterRoute.addItemQueued : .addItem)
                    },
                    onOpenAddOutfit: { sessionID in
                        tabBarHideState.shouldHideTabBar = true
                        navigationPath.append(ItemGridFilterRoute.addOutfit(sessionID: sessionID))
                    },
                    onOpenItemDetail: { uri in
                        tabBarHideState.shouldHideTabBar = true
                        navigationPath.append(ItemGridFilterRoute.itemDetail(uri: uri))
                    },
                    onOpenOutfitDetail: { uri in
                        tabBarHideState.shouldHideTabBar = true
                        navigationPath.append(ItemGridFilterRoute.outfitDetail(uri: uri))
                    },
                    tabBarHideState: tabBarHideState,
                    queueCoordinator: itemAddQueueCoordinator
                )
                .id(selected.objectID)
            } else {
                Text("No Wishlist Selected")
                    .foregroundColor(.secondary)
            }
            BulkImportProgressOverlay()
        }
    }

    @ViewBuilder
    func itemAddPathDestination(queued: Bool) -> some View {
        Group {
            if queued {
                ItemAddView(
                    parentContext: viewContext,
                    selectedWardrobe: selectedWishlist,
                    queueCoordinator: itemAddQueueCoordinator,
                    sessionAccountId: authSession.userId?.uuidString
                )
            } else {
                ItemAddView(
                    parentContext: viewContext,
                    selectedWardrobe: selectedWishlist,
                    sessionAccountId: authSession.userId?.uuidString
                )
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear { tabBarHideState.shouldHideTabBar = true }
        .onDisappear { itemAddQueueCoordinator.noteAddViewDismissed() }
    }

    @ViewBuilder
    func outfitAddPathDestination(sessionID: UUID) -> some View {
        OutfitAddView(
            wardrobeType: "wishlist",
            initialWardrobe: selectedWishlist,
            lockWardrobeSource: false,
            wardrobeMembershipOnSave: (selectedWishlist?.isDefault != true) ? selectedWishlist : nil,
            sessionID: sessionID,
            navigationPath: $navigationPath
        )
        .id(sessionID)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { tabBarHideState.shouldHideTabBar = true }
        .onDisappear { tabBarHideState.noteOutfitAddDismissed() }
    }

    @ViewBuilder
    func itemDetailPathDestination(uri: String) -> some View {
        if let item = managedItem(forURI: uri) {
            ItemDetailView(item: item, isReadOnly: false, navigationPath: $navigationPath)
                .id(item.objectID)
                .toolbar(.hidden, for: .tabBar)
                .onAppear { tabBarHideState.shouldHideTabBar = true }
        } else {
            Text("This item is no longer available.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func outfitDetailPathDestination(uri: String) -> some View {
        if let outfit = managedOutfit(forURI: uri) {
            OutfitDetailView(
                outfit: outfit,
                isReadOnly: false,
                navigationPath: $navigationPath,
                initialWardrobe: selectedWishlist,
                lockWardrobeSource: selectedWishlist?.isDefault != true
            )
                .id(outfit.objectID)
                .toolbar(.hidden, for: .tabBar)
                .onAppear { tabBarHideState.shouldHideTabBar = true }
        } else {
            Text("This outfit is no longer available.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func createOutfitFromItemPathDestination(itemURI: String, sessionID: UUID) -> some View {
        let item = managedItem(forURI: itemURI)
        let wardrobe = preferredWardrobeForNewOutfit(from: item) ?? selectedWishlist
        OutfitAddView(
            outfitToEdit: nil,
            wardrobeType: wardrobe?.type ?? "wishlist",
            initialWardrobe: wardrobe,
            lockWardrobeSource: false,
            wardrobeMembershipOnSave: (wardrobe?.isDefault != true) ? wardrobe : nil,
            preselectedItemURI: itemURI,
            sessionID: sessionID,
            navigationPath: $navigationPath
        )
        .id(sessionID)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { tabBarHideState.shouldHideTabBar = true }
    }

    private func managedItem(forURI uriString: String) -> Item? {
        guard let url = URL(string: uriString),
              let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
              let item = try? viewContext.existingObject(with: objectID) as? Item,
              item.isSoftDeleted != true else {
            return nil
        }
        return item
    }

    private func managedOutfit(forURI uriString: String) -> Outfit? {
        guard let url = URL(string: uriString),
              let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
              let outfit = try? viewContext.existingObject(with: objectID) as? Outfit,
              outfit.isSoftDeleted != true else {
            return nil
        }
        return outfit
    }

    private func preferredWardrobeForNewOutfit(from item: Item?) -> Wardrobe? {
        guard let set = item?.wardrobes as? Set<Wardrobe> else { return nil }
        let wishlists = set.filter { ($0.type ?? "").lowercased() == "wishlist" }
        let closets = set.filter { ($0.type ?? "").lowercased() == "closet" }
        return wishlists.first ?? closets.first ?? set.first
    }
    
    @ToolbarContentBuilder
    func navigationBarToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if isItemGridReplacingNavTitle {
                EmptyView()
            } else if isItemGridInSelectionMode {
                Text(selectedWishlist?.name ?? "Select Wishlist")
                    .font(.headline)
            } else {
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
                destination: ItemAddView(
                    parentContext: viewContext,
                    selectedWardrobe: selectedWishlist,
                    sessionAccountId: authSession.userId?.uuidString
                )
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
            Button("Create") {
                if let newWishlist = createNewWishlist(named: newWishlistName) {
                    selectedWishlist = newWishlist
                }
                showWishlistSheet = false
            }
            .disabled(!newWishlistNameValidation.isValid)
            Button("Cancel", role: .cancel) { }
        }
    }
    
    @ViewBuilder
    func wishlistSelectionSheet() -> some View {
        NavigationView {
            List {
                ForEach(userWishlists, id: \.objectID) { wishlist in
                    Button {
                        if selectedWishlist?.objectID != wishlist.objectID {
                            filterModel.clearAll()
                            outfitFilterModel.clearAll()
                            navigationPath = NavigationPath()
                        }
                        selectedWishlist = wishlist
                        showWishlistSheet = false
                    } label: {
                        HStack {
                            Text(wishlist.name ?? "Untitled")
                                .foregroundColor(.primary)

                            Spacer()

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

                            if wishlist == selectedWishlist {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if wishlist.isDefault != true {
                            Button {
                                renameTargetWardrobe = wishlist
                                renameDraft = WardrobeNaming.normalizedUserName(wishlist.name ?? "")
                                showRenameWardrobeAlert = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.blue)

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
        .alert("Rename Wishlist", isPresented: $showRenameWardrobeAlert) {
            TextField("Wishlist name", text: $renameDraft)
                .textInputAutocapitalization(.words)
            Button("Save") {
                if let wardrobe = renameTargetWardrobe {
                    updateWardrobeName(wardrobe, to: renameDraft)
                    selectedWishlist = wardrobe
                }
                renameTargetWardrobe = nil
                renameDraft = ""
            }
            .disabled(!renameWishlistNameValidation.isValid)
            Button("Cancel", role: .cancel) {
                renameTargetWardrobe = nil
                renameDraft = ""
            }
        } message: {
            Text(renameWishlistNameValidation.alertMessage(emptyPrompt: "Enter a new name for this wishlist"))
        }
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
        guard case .valid(let normalized) = WardrobeNaming.validate(
            name,
            type: "wishlist",
            existing: userWishlists
        ) else { return nil }

        let newWishlist = Wardrobe(context: viewContext)
        newWishlist.id = UUID()
        newWishlist.type = "wishlist"
        newWishlist.name = normalized
        // Public only when cloud sync can surface wardrobes; TestFlight stays private.
        newWishlist.wardrobeVisibility = appCapabilities.enablesCloudSync ? .public : .private
        
        // Set userId for sync
        if let userId = authSession.userId?.uuidString {
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
           let userId = authSession.userId?.uuidString {
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
        guard case .valid(let normalized) = WardrobeNaming.validate(
            newName,
            type: "wishlist",
            existing: userWishlists,
            excluding: wardrobe.objectID
        ) else { return }

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


