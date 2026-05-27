//
//  ItemGridView.swift
//  closet
//
//  Created by Dan Warner on 7/15/25.
//


import SwiftUI
import UIKit
import CoreData
import Combine

struct ItemGridView: View {
    @ObservedObject var filterModel: ItemFilterModel
    var wardrobeType: String
    var selectedWardrobe: Wardrobe
    
    // Binding to communicate selection state to parent
    @Binding var isInSelectionMode: Bool
    
    // Binding to show filter views
    @State private var showItemFilter = false
    @State private var showOutfitFilter = false

    @EnvironmentObject var supabaseService: SupabaseService
    @EnvironmentObject var authSession: AuthSession
    @EnvironmentObject private var syncService: SyncService
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appCapabilities) private var appCapabilities
    @State private var closetItems: [Item] = []
    @State private var hasCompletedInitialItemsFetch = false
    @State private var hasCompletedInitialOutfitsFetch = false
    @State private var isImagePickerPresented = false
    @State private var pickedImage: UIImage? = nil
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var path = NavigationPath()
    @State private var selectedTab: String = "Items"
    
    @State private var outfits: [Outfit] = []
    @StateObject private var outfitFilterModel = OutfitFilterModel()
    
    // Selection mode state
    @State private var selectedItemForNavigation: Item?
    @State private var selectedItems: Set<Item> = []
    @State private var selectedOutfitForNavigation: Outfit?
    @State private var selectedOutfits: Set<Outfit> = []
    @State private var showWardrobeSelectionSheet = false
    @State private var showWardrobeSelectionConfirmAlert = false
    @State private var pendingWardrobeSelectionTarget: Wardrobe?
    @State private var pendingWardrobeSelectionWillRemove = false
    @State private var showSharedUsersSheet = false
    @State private var sharedUsersSearchText = ""
    @State private var sharedUserResults: [PublicUserProfile] = []
    @State private var isSearchingSharedUsers = false
    @State private var sharedUsersError: String?
    @State private var pendingFriendRequestUserIds: Set<UUID> = []
    @State private var friendUserIds: Set<UUID> = []
    @State private var connectedFriends: [PublicUserProfile] = []
    @State private var isLoadingConnectedFriends = false
    @State private var showUnfriendAlert = false
    @State private var unfriendTargetUserId: UUID?
    @State private var showDeleteConfirmation = false
    @State private var showOutfitDeleteConfirmation = false
    @State private var showTagSelectionSheet = false
    @State private var showColorSelectionSheet = false
    @State private var showCategorySelectionSheet = false
    @State private var bulkSetCategoryExpanded: Set<NSManagedObjectID> = []
    @State private var showCategorySelectionConfirmAlert = false
    @State private var pendingBulkCategory: Category?
    @State private var pendingBulkSubcategory: Subcategory?
    @State private var showDeletionToast = false
    @State private var deletionToastMessage: String = ""
    @State private var showTagSelectionConfirmAlert = false
    @State private var pendingTagSelectionTarget: Tag?
    @State private var pendingTagSelectionWillRemove = false
    @State private var showColorSelectionConfirmAlert = false
    @State private var pendingColorSelectionTarget: AppColor?
    @State private var pendingColorSelectionWillRemove = false
    @State private var showFavoriteSelectionConfirmAlert = false
    @State private var pendingFavoriteSelectionWillUnfavorite = false
    /// Bumps when favorites change so the bottom bar heart reflects Core Data without relying on `selectedItems` identity.
    @State private var favoriteToolbarTick = 0
    @State private var showAddFromClosetSheet = false
    
    // Multi-image picker state
    @StateObject private var queueCoordinator = ImageQueueCoordinator()
    @State private var showMultiImagePicker = false
    @State private var showCropperForQueue = false
    @State private var shouldNavigateToItemAdd = false
    @State private var shouldNavigateToItemAddDirect = false
    @State private var queuedImages: [UIImage] = []
    @State private var showCropperCancelConfirmation = false

    let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    // Computed property to track filter changes
    private var filterKey: String {
        var key = ""
        key += filterModel.selectedColors.sorted().joined(separator: ",")
        key += filterModel.selectedSeasons.sorted().joined(separator: ",")
        key += filterModel.selectedBrand?.objectID.uriRepresentation().absoluteString ?? ""
        key += filterModel.selectedTags.map { $0.objectID.uriRepresentation().absoluteString }.sorted().joined(separator: ",")
        key += filterModel.minPrice?.description ?? ""
        key += filterModel.maxPrice?.description ?? ""
        key += filterModel.selectedCategoryName ?? ""
        key += filterModel.selectedSubcategoryName ?? ""
        key += filterModel.selectedSizeValue ?? ""
        key += filterModel.selectedLocation?.objectID.uriRepresentation().absoluteString ?? ""
        key += filterModel.favoritesOnly ? "favoritesOnly" : "allItems"
        if filterModel.filterByWeight {
            // Include user weight in key so it refreshes when user updates their weight
            let repository = UserProfileRepository(context: viewContext)
            let userWeightKg = repository.getWeightKg()
            key += "weight:\(userWeightKg)"
        }
        key += filterModel.sortOrder.sortAscending ? "sortAsc" : "sortDesc"
        key += filterModel.selectedWardrobes.map { $0.objectID.uriRepresentation().absoluteString }.sorted().joined(separator: ",")
        return key
    }
    
    // Computed property to track outfit filter changes
    private var outfitFilterKey: String {
        var key = ""
        key += outfitFilterModel.selectedCategory ?? ""
        key += outfitFilterModel.selectedTags.map { $0.objectID.uriRepresentation().absoluteString }.sorted().joined(separator: ",")
        key += outfitFilterModel.favoritesOnly ? "favoritesOnly" : "allOutfits"
        key += outfitFilterModel.sortOrder.sortAscending ? "sortAsc" : "sortDesc"
        return key
    }

    private var isItemsTabLoading: Bool {
        guard authSession.userId != nil else { return true }
        if !hasCompletedInitialItemsFetch { return true }
        if appCapabilities.enablesCloudSync, syncService.isSyncing, closetItems.isEmpty { return true }
        return false
    }

    private var isOutfitsTabLoading: Bool {
        guard authSession.userId != nil else { return true }
        if !hasCompletedInitialOutfitsFetch { return true }
        if appCapabilities.enablesCloudSync, syncService.isSyncing, outfits.isEmpty { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Items (\(closetItems.count))")
                    .tag("Items")
                Text("Outfits (\(outfits.count))")
                    .tag("Outfits")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .disabled(isInSelectionMode)
            
         /*   if !isControlsHidden {
                ControlsBar
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .transition(
                        .asymmetric(
                            insertion: .push(from: .top),
                            removal: .push(from: .bottom)
                        )
                    )
            }*/
            
            TabView(selection: $selectedTab) {
                itemsTab.tag("Items")
                outfitsTab.tag("Outfits")
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
        }
        .navigationBarTitleDisplayMode(.inline)
        // Exit selection mode when switching tabs
        .onChange(of: selectedTab) { oldValue, newValue in
            if oldValue != newValue && isInSelectionMode {
                // User switched tabs while in selection mode - cancel it
                isInSelectionMode = false
                selectedItems.removeAll()
                selectedOutfits.removeAll()
            }
        }
        .onAppear {
            fetchItems()
            fetchOutfits()
        }
        .onChange(of: authSession.userId) { _, newUserId in
            guard newUserId != nil else { return }
            hasCompletedInitialItemsFetch = false
            hasCompletedInitialOutfitsFetch = false
            fetchItems()
            fetchOutfits()
        }
        .onChange(of: filterKey) {
            fetchItems()
        }
        .onChange(of: filterModel.filterByWeight) {
            fetchItems()
        }
        .onChange(of: outfitFilterKey) {
            fetchOutfits()
        }
        .onChange(of: selectedWardrobe.objectID) {
            fetchItems()
            fetchOutfits()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { notification in
            // Refresh items AND outfits when context saves (added/deleted/updated elsewhere)
            if let context = notification.object as? NSManagedObjectContext,
               context === viewContext || context.parent === viewContext {
                fetchItems()
                fetchOutfits()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("Closet.ItemDeletionToast"))) { notification in
            if let message = notification.userInfo?["message"] as? String {
                showToast(message)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                leadingToolbarContent()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                trailingToolbarContent()
            }
            if isInSelectionMode {
                ToolbarItemGroup(placement: .bottomBar) {
                    if selectedTab == "Items" {
                        Button {
                            showTagSelectionSheet = true
                        } label: {
                            VStack {
                                Image(systemName: "tag")
                                Text("Tag")
                                    .font(.caption)
                            }
                        }
                        .disabled(selectedItems.isEmpty)
                        
                        Button {
                            showCategorySelectionSheet = true
                        } label: {
                            VStack {
                                Image(systemName: "tshirt")
                                Text("Category")
                                    .font(.caption)
                            }
                        }
                        .disabled(selectedItems.isEmpty)

                        Button {
                            showColorSelectionSheet = true
                        } label: {
                            VStack {
                                Image(systemName: "paintpalette")
                                Text("Color")
                                    .font(.caption)
                            }
                        }
                        .disabled(selectedItems.isEmpty)
                        
                        Button {
                            pendingFavoriteSelectionWillUnfavorite = selectedItemsAllFavorited
                            showFavoriteSelectionConfirmAlert = true
                        } label: {
                            VStack {
                                Image(systemName: selectedItemsFavoriteToolbarIcon)
                                Text("Favorite")
                                    .font(.caption)
                            }
                        }
                        .disabled(selectedItems.isEmpty)
                    }
                    
                    Spacer()
                    
                    Button {
                        if selectedTab == "Items" {
                            showDeleteConfirmation = true
                        } else {
                            showOutfitDeleteConfirmation = true
                        }
                    } label: {
                        VStack {
                            Image(systemName: "trash")
                                .foregroundColor(selectionDeleteColor)
                            Text("Delete")
                                .font(.caption)
                                .foregroundColor(selectionDeleteColor)
                        }
                    }
                    .disabled(isSelectionDeleteDisabled)
                }
            }
            ToolbarItem(placement: .principal) {
                if selectedTab == "Items" && isInSelectionMode {
                    Button {
                        showWardrobeSelectionSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(selectedItems.count) Selected")
                                .font(.headline)
                            Image(systemName: "plus.rectangle.on.folder")
                                .font(.caption)
                        }
                    }
                } else if selectedTab == "Outfits" && isInSelectionMode {
                    Text("\(selectedOutfits.count) Selected")
                        .font(.headline)
                }
            }
        }
        .toolbar(isInSelectionMode ? .hidden : .automatic, for: .tabBar)
        .sheet(isPresented: $isImagePickerPresented) {
            ImagePicker(
                image: $pickedImage,
                sourceType: $imagePickerSource,
                allowsEditing: true
            ) { image in
                if let image = image {
                    createNewItem(with: image, in: selectedWardrobe)
                }
                isImagePickerPresented = false
            }
        }
        .sheet(isPresented: $showMultiImagePicker) {
            MultiImagePicker(selectedImages: $queuedImages) {
                showMultiImagePicker = false
                
                if !queuedImages.isEmpty {
                    // Load images into queue coordinator
                    queueCoordinator.loadQueue(queuedImages)
                    
                    // Small delay to ensure picker sheet is dismissed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        // Show cropper for the first image
                        showCropperForQueue = true
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showCropperForQueue) {
            if let imageToCrop = queueCoordinator.currentImage {
                NavigationView {
                    ImageCropperView(
                        originalImage: imageToCrop,
                        onCrop: { croppedImage in
                            // Store the cropped image in coordinator
                            queueCoordinator.storeCroppedImage(croppedImage)
                            
                            // Dismiss cropper
                            showCropperForQueue = false
                            
                            // Small delay then show ItemAddView
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                shouldNavigateToItemAdd = true
                            }
                        },
                        isEditing: false,
                        onCancel: {
                            if queueCoordinator.isQueueActive {
                                showCropperCancelConfirmation = true
                            } else {
                                showCropperForQueue = false
                            }
                        }
                    )
                    .navigationBarTitleDisplayMode(.inline)
                }
                .alert("Discard this item?", isPresented: $showCropperCancelConfirmation) {
                    Button("Discard", role: .destructive) {
                        handleCropperCancel()
                    }
                    Button("Keep", role: .cancel) {}
                } message: {
                    if queueCoordinator.hasMore {
                        Text("This image will be skipped and you'll move to the next image in the queue.")
                    } else {
                        Text("This image will be discarded.")
                    }
                }
            }
        }
        
        .sheet(isPresented: $showWardrobeSelectionSheet) {
            wardrobeSelectionSheet()
        }
        .sheet(isPresented: $showSharedUsersSheet) {
            sharedUsersSheet()
        }
        .sheet(isPresented: $showTagSelectionSheet) {
            tagSelectionSheet()
        }
        .sheet(isPresented: $showColorSelectionSheet) {
            colorSelectionSheet()
        }
        .sheet(isPresented: $showAddFromClosetSheet) {
            AddItemsFromDefaultWardrobeView(
                wardrobe: selectedWardrobe,
                onCompleted: { addedCount in
                    let dest = selectedWardrobe.name ?? "this wardrobe"
                    let sourceLabel = (selectedWardrobe.type ?? "closet").lowercased() == "wishlist" ? "wishlist" : "closet"
                    showToast("Added \(addedCount) item\(addedCount == 1 ? "" : "s") from your \(sourceLabel) to \"\(dest)\".")
                }
            )
        }
        .sheet(isPresented: $showCategorySelectionSheet) {
            categorySelectionSheet()
        }
        .alert(pendingFavoriteSelectionWillUnfavorite ? "Remove from Favorites?" : "Add to Favorites?", isPresented: $showFavoriteSelectionConfirmAlert) {
            Button(pendingFavoriteSelectionWillUnfavorite ? "Remove" : "Add", role: pendingFavoriteSelectionWillUnfavorite ? .destructive : nil) {
                let favorite = !pendingFavoriteSelectionWillUnfavorite
                if let message = applyFavoriteToSelectedItems(favorite: favorite) {
                    completeBulkSelectionAction(toast: message)
                }
                pendingFavoriteSelectionWillUnfavorite = false
            }
            Button("Cancel", role: .cancel) {
                pendingFavoriteSelectionWillUnfavorite = false
            }
        } message: {
            let count = selectedItems.count
            let itemPhrase = "\(count) selected item\(count == 1 ? "" : "s")"
            Text(pendingFavoriteSelectionWillUnfavorite
                 ? "Remove \(itemPhrase) from favorites?"
                 : "Add \(itemPhrase) to favorites?")
        }
        .alert("Delete Items", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedItems()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \(selectedItems.count) item\(selectedItems.count == 1 ? "" : "s")? This action cannot be undone.")
        }
        .alert("Delete Outfits", isPresented: $showOutfitDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedOutfits()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \(selectedOutfits.count) outfit\(selectedOutfits.count == 1 ? "" : "s")? This action cannot be undone.")
        }
        .overlay(alignment: .top) {
            if showDeletionToast {
                Text(deletionToastMessage)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(.top, 10)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationDestination(item: $selectedItemForNavigation) { item in
            ItemDetailView(item: item)
        }
        .navigationDestination(item: $selectedOutfitForNavigation) { outfit in
            OutfitDetailView(outfit: outfit)
        }
        .navigationDestination(isPresented: $shouldNavigateToItemAdd) {
            ItemAddView(
                parentContext: viewContext,
                selectedWardrobe: selectedWardrobe,
                queueCoordinator: queueCoordinator,
                sessionAccountId: authSession.userId?.uuidString
            )
            .onDisappear {
                handleItemAddViewDismiss()
            }
        }
        .navigationDestination(isPresented: $shouldNavigateToItemAddDirect) {
            ItemAddView(
                parentContext: viewContext,
                selectedWardrobe: selectedWardrobe,
                sessionAccountId: authSession.userId?.uuidString
            )
        }
    }

/*    private var ControlsBar: some View {
        HStack {
            NavigationLink(destination: FilterView(filterModel: filterModel)) {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            Spacer()
            Image(systemName: "arrow.up.arrow.down")
            Spacer()
            Image(systemName: "square.grid.3x2")
            Spacer()
            NavigationLink(
                destination: ItemAddView(parentContext: viewContext, selectedWardrobe: selectedWardrobe)
            ) {
                Image(systemName: "plus")
            }
        }
      //  .font(.system(size: 20))
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }*/
    
    // MARK: - Core Data fetch
    func fetchItems() {
        // Require authentication - get userId
        guard let userId = authSession.userId?.uuidString else {
            return
        }
        
        let request = NSFetchRequest<Item>(entityName: "Item")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.createdAt, ascending: filterModel.sortOrder.sortAscending)]
        
        // Build predicate from filterModel, but exclude wardrobe filter since we handle it separately below
        var subpredicates: [NSPredicate] = []
        
        // Add userId filter (CRITICAL: only show current user's items)
        let userIdPredicate = NSPredicate(format: "userId == %@", userId)
        subpredicates.append(userIdPredicate)
        
        // Add all filter predicates except wardrobe (we'll handle wardrobe separately)
        if !filterModel.selectedColors.isEmpty {
            let colorPredicate = NSPredicate(format: "ANY colors.name IN %@", Array(filterModel.selectedColors))
            subpredicates.append(colorPredicate)
        }
        if !filterModel.selectedSeasons.isEmpty {
            let seasonPredicate = NSPredicate(format: "ANY seasons.name IN %@", Array(filterModel.selectedSeasons))
            subpredicates.append(seasonPredicate)
        }
        if let brand = filterModel.selectedBrand, let brandName = brand.name, !brandName.isEmpty {
            let brandPredicate = NSPredicate(format: "brand.name ==[c] %@", brandName)
            subpredicates.append(brandPredicate)
        }
        if let minPrice = filterModel.minPrice {
            let minPricePredicate = NSPredicate(format: "price.amount >= %@", minPrice as NSDecimalNumber)
            subpredicates.append(minPricePredicate)
        }
        if let maxPrice = filterModel.maxPrice {
            let maxPricePredicate = NSPredicate(format: "price.amount <= %@", maxPrice as NSDecimalNumber)
            subpredicates.append(maxPricePredicate)
        }
        if !filterModel.selectedTags.isEmpty {
            let tagNames = filterModel.selectedTags.compactMap { $0.name }
            let tagPredicate = NSPredicate(format: "ANY tags.name IN %@", tagNames)
            subpredicates.append(tagPredicate)
        }
        // Handle category/subcategory filtering
        if let subcategoryName = filterModel.selectedSubcategoryName, !subcategoryName.isEmpty,
           let categoryName = filterModel.selectedCategoryName, !categoryName.isEmpty {
            // Filter by subcategory (which also implies the category)
            let subcategoryPredicate = NSPredicate(format: "subcategory.name ==[c] %@ AND category.name ==[c] %@", subcategoryName, categoryName)
            subpredicates.append(subcategoryPredicate)
        } else if let categoryName = filterModel.selectedCategoryName, !categoryName.isEmpty {
            // Filter by category only
            let categoryPredicate = NSPredicate(format: "category.name ==[c] %@", categoryName)
            subpredicates.append(categoryPredicate)
        }
        if let sizeValue = filterModel.selectedSizeValue, !sizeValue.isEmpty {
            let sizePredicate = NSPredicate(format: "size.value == %@", sizeValue)
            subpredicates.append(sizePredicate)
        }
        if let location = filterModel.selectedLocation {
            let locationPredicate = NSPredicate(format: "location == %@", location)
            subpredicates.append(locationPredicate)
        }
        
        // Favorites-only filter
        if filterModel.favoritesOnly {
            let favoritesPredicate = NSPredicate(format: "isFavorite == YES")
            subpredicates.append(favoritesPredicate)
        }
        
        // Weight filter - only show items that can support user's weight
        if filterModel.filterByWeight {
            let repository = UserProfileRepository(context: viewContext)
            let userWeightKg = repository.getWeightKg()
            if userWeightKg > 0 {
                // Show ONLY items where:
                // - Item has weight set (weight != nil) AND
                // - Item's max wearable weight <= user's weight
                // Logic: Item weight = max wearable weight the item can support
                // If item.weight > userWeight, the item CANNOT support the user (user is too heavy)
                // If item.weight <= userWeight, the item CAN support the user
                // Items without weight are EXCLUDED when filter is active
                // Note: weight is stored in kg in Core Data
                let weightExistsPredicate = NSPredicate(format: "weight != nil")
                let weightSupportedPredicate = NSPredicate(format: "weight <= %@", userWeightKg as NSNumber)
                
                // weight != nil AND weight <= userWeight
                let weightPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [weightExistsPredicate, weightSupportedPredicate])
                
                subpredicates.append(weightPredicate)
                print("🔍 Weight filter active: showing ONLY items with max wearable weight <= \(String(format: "%.2f", userWeightKg)) kg (excluding items without weight)")
                print("🔍 Weight predicate: \(weightPredicate)")
            } else {
                print("⚠️ Weight filter enabled but user weight not set in Profile")
            }
            // If user hasn't set their weight, don't filter (show all items)
        }
        
        // Always scope to the wardrobe the user is viewing in the closet/wishlist picker.
        // Do not replace with filterModel.selectedWardrobes alone — that shows items from other
        // wardrobes (e.g. default) while the secondary closet tab is selected.
        subpredicates.append(NSPredicate(format: "ANY wardrobes == %@", selectedWardrobe))
        
        // If the filter sheet also narrowed wardrobes, intersect so both apply.
        let filteredWardrobes = filterModel.selectedWardrobes.filter { $0.type == wardrobeType }
        if !filteredWardrobes.isEmpty {
            subpredicates.append(NSPredicate(format: "ANY wardrobes IN %@", Array(filteredWardrobes)))
        }
        
        // Exclude drafts from item listings
        let draftPredicate = NSPredicate(format: "isDraft != YES")
        subpredicates.append(draftPredicate)
        
        // Exclude soft-deleted items
        let softDeleteFilter = NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        subpredicates.append(softDeleteFilter)
        
        // Combine all predicates
        let finalPredicate: NSPredicate
        if subpredicates.count == 1 {
            finalPredicate = subpredicates.first!
        } else {
            finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        }
        request.predicate = finalPredicate
        
        // Debug: Log predicate if weight filter is active
        if filterModel.filterByWeight {
            print("🔍 Final predicate: \(finalPredicate)")
        }
        
        do {
            let results = try viewContext.fetch(request)
            let selectedWardrobeID = selectedWardrobe.objectID
            let scoped = results.filter { item in
                guard let wardrobes = item.wardrobes as? Set<Wardrobe> else { return false }
                return wardrobes.contains { $0.objectID == selectedWardrobeID }
            }
            
            // Debug: Log results if weight filter is active
            if filterModel.filterByWeight {
                let repository = UserProfileRepository(context: viewContext)
                let userWeightKg = repository.getWeightKg()
                print("🔍 Fetched \(scoped.count) items with weight filter")
                // Sample a few items to check their weights
                for (index, item) in scoped.prefix(5).enumerated() {
                    if let weight = item.primitiveValue(forKey: "weight") as? Double {
                        print("🔍 Item \(index + 1): weight = \(String(format: "%.2f", weight)) kg (>= \(String(format: "%.2f", userWeightKg))? \(weight >= userWeightKg))")
                    } else {
                        print("🔍 Item \(index + 1): weight = nil (no limit)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.closetItems = scoped
                self.hasCompletedInitialItemsFetch = true
            }
        } catch {
            print("❌ Failed to fetch items: \(error)")
            if let nsError = error as NSError? {
                print("❌ Error details: \(nsError.userInfo)")
            }
            DispatchQueue.main.async {
                self.closetItems = []
                self.hasCompletedInitialItemsFetch = true
            }
        }
    }
    
    func fetchOutfits() {
        // Require authentication - get userId
        guard let userId = authSession.userId?.uuidString else {
            return
        }
        
        let request = NSFetchRequest<Outfit>(entityName: "Outfit")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Outfit.createdAt, ascending: outfitFilterModel.sortOrder.sortAscending)]
        
        // Build predicate from outfit filter model
        let filterPredicate = makeOutfitPredicate(for: outfitFilterModel)
        
        // Base predicate: exclude drafts and soft-deleted items, filter by userId
        let draftPredicate = NSPredicate(format: "isDraft != YES")
        let softDeleteFilter = NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        let userIdPredicate = NSPredicate(format: "userId == %@", userId)
        
        // Combine predicates
        let basePredicates = [draftPredicate, softDeleteFilter, userIdPredicate]
        let finalPredicate: NSPredicate
        if let filter = filterPredicate {
            finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: basePredicates + [filter])
        } else {
            finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: basePredicates)
        }
        
        request.predicate = finalPredicate

        do {
            let allOutfits = try viewContext.fetch(request)
            // Filter by wardrobe
            let isWishlist = selectedWardrobe.type?.lowercased() == "wishlist"
            let filtered = allOutfits.filter { outfit in
                guard let items = outfit.items as? Set<Item>, !items.isEmpty else { return false }
                if isWishlist {
                    // Wishlist: at least 1 item from this wardrobe; all wishlist items must be from it; closet items allowed
                    let hasItemFromThisWishlist = items.contains { item in
                        guard let wardrobes = item.wardrobes as? Set<Wardrobe> else { return false }
                        return wardrobes.contains(selectedWardrobe)
                    }
                    guard hasItemFromThisWishlist else { return false }
                    return items.allSatisfy { item in
                        guard let wardrobes = item.wardrobes as? Set<Wardrobe> else { return false }
                        let wishlistWardrobes = wardrobes.filter { $0.type?.lowercased() == "wishlist" }
                        if wishlistWardrobes.isEmpty { return true } // Closet item, allowed
                        return wishlistWardrobes.contains(selectedWardrobe)
                    }
                } else {
                    // Closet: every item must be in the selected wardrobe
                    return items.allSatisfy { item in
                        guard let wardrobes = item.wardrobes as? Set<Wardrobe> else { return false }
                        return wardrobes.contains(selectedWardrobe)
                    }
                }
            }
            DispatchQueue.main.async {
                self.outfits = filtered
                self.hasCompletedInitialOutfitsFetch = true
            }
        } catch {
            print("Failed to fetch outfits: \(error)")
            DispatchQueue.main.async {
                self.outfits = []
                self.hasCompletedInitialOutfitsFetch = true
            }
        }
    }


    // MARK: - Create New Item
    private func createNewItem(with image: UIImage, in wardrobe: Wardrobe) {
        let item = Item(context: viewContext)
        item.id = UUID()
        let now = Date()
        item.timestamp = now
        item.createdAt = now
        item.updatedAt = now // Set updatedAt for sync tracking
        
        // Process and compress image
        if let imageData = image.processForStorage() {
            let photo = Photo(context: viewContext)
            PhotoContentBounds.assignImage(UIImage(data: imageData) ?? image, to: photo, data: imageData)
            photo.thumbnailData = image.generateThumbnail()
            photo.isPrimary = true
            photo.id = UUID()
            photo.type = "front"
            photo.item = item
        }

        wardrobe.addToItems(item)   // <-- attach to the correct wardrobe

        do {
            try viewContext.save()
            print("✅ New item saved in \(wardrobe.name ?? "unknown wardrobe")")
            path.append(item)
            // Refresh items after adding new one
            fetchItems()
            
            // Trigger automatic sync for the new item
            SyncService.shared.syncItemIfNeeded(item)
        } catch {
            print("❌ Failed to save new item: \(error.localizedDescription)")
        }
    }
    
    private func closetContentLoadingView(syncStatus: String?) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            if let syncStatus, !syncStatus.isEmpty {
                Text(syncStatus)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var itemsTab: some View {
        Group {
            if isItemsTabLoading {
                closetContentLoadingView(
                    syncStatus: appCapabilities.enablesCloudSync && syncService.isSyncing ? syncService.syncStatus : nil
                )
            } else if closetItems.isEmpty {
                EmptyItemStateView(wardrobe: selectedWardrobe)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(closetItems, id: \.objectID) { item in
                            ItemView(item: item)
                                .overlay(
                                    // Transparent white overlay when in selection mode
                                    Group {
                                        if isInSelectionMode && selectedItems.contains(item) {
                                            Rectangle()
                                                .fill(Color.white.opacity(0.35))
                                        }
                                    }
                                )
                                .overlay(
                                    // Show selection checkmark when in selection mode (on top of white overlay)
                                    Group {
                                        if isInSelectionMode && selectedItems.contains(item) {
                                            VStack {
                                                Spacer()
                                                HStack {
                                                    Spacer()
                                                    Image(systemName: "checkmark.circle")
                                                        .foregroundColor(.white)
                                                        .background(
                                                            Circle()
                                                                .fill(Color.blue)
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
                                    print("📱 Tap gesture detected on item: \(item.id?.uuidString ?? "no-id")")
                                    handleTap(for: item)
                                }
                                .onLongPressGesture(minimumDuration: 0.5) {
                                    handleLongPress(for: item)
                                }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
    
    // MARK: - Gesture Handlers
    
    private func handleTap(for item: Item) {
        print("📱 handleTap called for item: \(item.id?.uuidString ?? "no-id"), isInSelectionMode: \(isInSelectionMode)")
        
        if isInSelectionMode {
            // Toggle selection
            if selectedItems.contains(item) {
                selectedItems.remove(item)
                print("📱 Item deselected. Total selected: \(selectedItems.count)")
            } else {
                selectedItems.insert(item)
                print("📱 Item selected. Total selected: \(selectedItems.count)")
            }
            
            // Exit selection mode if no items selected
            if selectedItems.isEmpty {
                print("📱 No items selected, exiting selection mode")
                isInSelectionMode = false
            }
        } else {
            // Navigate to detail view
            print("📱 Navigating to ItemDetailView for item: \(item.id?.uuidString ?? "no-id")")
            selectedItemForNavigation = item
        }
    }
    
    private func handleLongPress(for item: Item) {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Enter selection mode and select this item
        if !isInSelectionMode {
            isInSelectionMode = true
        }
        
        selectedItems.insert(item)
    }
    
    // MARK: - Outfit Gesture Handlers
    
    private func handleOutfitTap(for outfit: Outfit) {
        if isInSelectionMode {
            // Toggle selection
            if selectedOutfits.contains(outfit) {
                selectedOutfits.remove(outfit)
            } else {
                selectedOutfits.insert(outfit)
            }
            
            // Exit selection mode if no outfits selected
            if selectedOutfits.isEmpty {
                isInSelectionMode = false
            }
        } else {
            // Navigate to detail view
            selectedOutfitForNavigation = outfit
        }
    }
    
    private func handleOutfitLongPress(for outfit: Outfit) {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Enter selection mode and select this outfit
        if !isInSelectionMode {
            isInSelectionMode = true
        }
        
        selectedOutfits.insert(outfit)
    }
    
    // MARK: - Toolbar Content
    
    @ViewBuilder
    private func leadingToolbarContent() -> some View {
        if isInSelectionMode {
            if selectedTab == "Items" {
                itemsSelectionModeLeadingToolbar()
            } else if selectedTab == "Outfits" {
                outfitsSelectionModeLeadingToolbar()
            }
        } else {
            nonSelectionModeLeadingToolbar()
        }
    }
    
    @ViewBuilder
    private func itemsSelectionModeLeadingToolbar() -> some View {
        // Select all button
        let allSelected = !closetItems.isEmpty && selectedItems.count == closetItems.count
        Button {
            if allSelected {
                selectedItems.removeAll()
            } else {
                selectedItems = Set(closetItems)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                Text("All")
            }
        }
    }
    
    @ViewBuilder
    private func outfitsSelectionModeLeadingToolbar() -> some View {
        // Select all button
        let allSelected = !outfits.isEmpty && selectedOutfits.count == outfits.count
        Button {
            if allSelected {
                selectedOutfits.removeAll()
            } else {
                selectedOutfits = Set(outfits)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                Text("All")
            }
        }
    }
    
    @ViewBuilder
    private func nonSelectionModeLeadingToolbar() -> some View {
        if selectedTab == "Items" {
            NavigationLink(destination: ItemFilterView(filterModel: filterModel, wardrobeType: wardrobeType)) {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        } else {
            NavigationLink(destination: OutfitFilterView(filterModel: outfitFilterModel)) {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
        if appCapabilities.enablesFriendsAndSharing {
            Button {
                showSharedUsersSheet = true
            } label: {
                Image(systemName: "person.2")
            }
        }
    }
    
    @ViewBuilder
    private func trailingToolbarContent() -> some View {
        if isInSelectionMode {
            selectionModeTrailingToolbar()
        } else {
            nonSelectionModeTrailingToolbar()
        }
    }
    
    @ViewBuilder
    private func selectionModeTrailingToolbar() -> some View {
        let hasSelection =
            (selectedTab == "Items" && !selectedItems.isEmpty)
            || (selectedTab == "Outfits" && !selectedOutfits.isEmpty)
        Button(hasSelection ? "Done" : "Cancel") {
            isInSelectionMode = false
            if selectedTab == "Items" {
                selectedItems.removeAll()
            } else {
                selectedOutfits.removeAll()
            }
        }
    }
    
    @ViewBuilder
    private func nonSelectionModeTrailingToolbar() -> some View {
        HStack(spacing: 16) {
            NavigationLink(destination: TravelPackingView(selectedWardrobe: selectedWardrobe, wardrobeType: wardrobeType)) {
                Image(systemName: "airplane.circle")
            }
            if selectedTab == "Items" {
                if selectedWardrobe.isDefault == true {
                    Button {
                        shouldNavigateToItemAddDirect = true
                    } label: {
                        Image(systemName: "plus")
                    }
                } else {
                    Menu {
                        Button {
                            showAddFromClosetSheet = true
                        } label: {
                            Label("Add from Closet", systemImage: "hanger")
                        }
                        Button {
                            shouldNavigateToItemAddDirect = true
                        } label: {
                            Label("Add Item", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            } else {
                NavigationLink(
                    destination: OutfitAddView(
                        wardrobeType: wardrobeType,
                        initialWardrobe: selectedWardrobe,
                        lockWardrobeSource: selectedWardrobe.isDefault != true
                    )
                ) {
                    Image(systemName: "plus")
                }
            }
        }
    }
    
    // MARK: - Cropper Cancel Handler
    
    private func handleCropperCancel() {
        // Skip current image and move to next if available
        if queueCoordinator.isQueueActive {
            if queueCoordinator.hasMore {
                print("📸 Skipping current image, moving to next in queue")
                queueCoordinator.moveToNext()
                
                // Show cropper for next image
                if let nextImage = queueCoordinator.currentImage {
                    showCropperForQueue = false
                    // Small delay to ensure clean transition
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showCropperForQueue = true
                    }
                } else {
                    // No more images after skipping
                    print("📸 No more images after skipping, clearing queue")
                    queueCoordinator.clear()
                    showCropperForQueue = false
                }
            } else {
                // This was the last image, just clear and dismiss
                print("📸 Last image discarded, clearing queue")
                queueCoordinator.clear()
                showCropperForQueue = false
            }
        } else {
            // Queue not active, just dismiss
            showCropperForQueue = false
        }
    }
    
    // MARK: - ItemAddView Dismiss Handler
    
    private func handleItemAddViewDismiss() {
        // Reset navigation state
        shouldNavigateToItemAdd = false
        
        // Check if there's a current image available
        if queueCoordinator.isQueueActive {
            // If hasMore is false AND we have a cropped image, we just processed the last image
            // (currentCroppedImage is set when we crop, and cleared when we moveToNext)
            if !queueCoordinator.hasMore && queueCoordinator.currentCroppedImage != nil {
                print("📸 ItemAddView dismissed, last image processed (hasMore=false, croppedImage exists), clearing queue")
                queuedImages.removeAll()
                queueCoordinator.clear()
                return
            }
            
            // If hasMore is true, we moved to the next image, so show cropper for it
            // OR if hasMore is false but no croppedImage, we're on the last image that hasn't been cropped yet
            if let currentImage = queueCoordinator.currentImage {
                print("📸 ItemAddView dismissed, showing cropper for image at index \(queueCoordinator.currentIndex), hasMore: \(queueCoordinator.hasMore)")
                
                // Small delay to ensure clean transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // Double-check that we still have a current image (queue might have been cleared)
                    if queueCoordinator.isQueueActive, let _ = queueCoordinator.currentImage {
                        showCropperForQueue = true
                    }
                }
            } else {
                // No current image available - we've processed all images, clean up
                print("📸 ItemAddView dismissed, no current image available, clearing queue")
                queuedImages.removeAll()
                queueCoordinator.clear()
            }
        } else {
            // Queue not active, clean up
            print("📸 ItemAddView dismissed, queue not active")
            queuedImages.removeAll()
        }
    }
    
    // MARK: - Wardrobe Selection Sheet
    
    @ViewBuilder
    private func wardrobeSelectionSheet() -> some View {
        let wardrobes = fetchAllWardrobes()
        
        return NavigationView {
            List {
                ForEach(wardrobes, id: \.self) { wardrobe in
                    let allItemsInWardrobe = areAllSelectedItemsInWardrobe(wardrobe)
                    let isDefaultRow = wardrobe.isDefault == true
                    
                    Button {
                        let isNonDefaultCurrentWardrobe = selectedWardrobe.isDefault != true
                        if isNonDefaultCurrentWardrobe {
                            pendingWardrobeSelectionTarget = wardrobe
                            pendingWardrobeSelectionWillRemove = allItemsInWardrobe
                            showWardrobeSelectionConfirmAlert = true
                        } else {
                            addSelectedItemsToWardrobe(wardrobe)
                            showWardrobeSelectionSheet = false
                        }
                    } label: {
                        HStack {
                            Text(wardrobe.name ?? "Untitled")
                            
                            if isDefaultRow {
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
                            
                            Image(systemName: allItemsInWardrobe ? "checkmark" : "plus")
                                .foregroundColor(.blue)
                                .font(.system(size: 16, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Add to Wardrobe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .alert(pendingWardrobeSelectionWillRemove ? "Remove from Wardrobe?" : "Add to Wardrobe?", isPresented: $showWardrobeSelectionConfirmAlert) {
            Button(pendingWardrobeSelectionWillRemove ? "Remove" : "Add", role: pendingWardrobeSelectionWillRemove ? .destructive : nil) {
                guard let wardrobe = pendingWardrobeSelectionTarget else { return }
                if pendingWardrobeSelectionWillRemove {
                    removeSelectedItemsFromWardrobe(wardrobe)
                } else {
                    addSelectedItemsToWardrobe(wardrobe)
                }
                pendingWardrobeSelectionTarget = nil
                pendingWardrobeSelectionWillRemove = false
                showWardrobeSelectionSheet = false
            }
            Button("Cancel", role: .cancel) {
                pendingWardrobeSelectionTarget = nil
                pendingWardrobeSelectionWillRemove = false
            }
        } message: {
            let name = pendingWardrobeSelectionTarget?.name ?? "this wardrobe"
            Text(pendingWardrobeSelectionWillRemove
                 ? "Remove \(selectedItems.count) selected item(s) from “\(name)”?"
                 : "Add \(selectedItems.count) selected item(s) to “\(name)”?")
        }
        .presentationDetents([.medium, .large])
    }
    
    @ViewBuilder
    private func sharedUsersSheet() -> some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    TextField("Search friends", text: $sharedUsersSearchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                Group {
                    if isSearchingSharedUsers {
                        ProgressView("Searching…")
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if isLoadingConnectedFriends && sharedUsersSearchText.isEmpty {
                        ProgressView("Loading friends…")
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = sharedUsersError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if sharedUserResults.isEmpty && !sharedUsersSearchText.isEmpty {
                        Text("No users found for “\(sharedUsersSearchText)”")
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if sharedUserResults.isEmpty && connectedFriends.isEmpty {
                        Text("Search by username to find other users.")
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(sharedUsersSearchText.isEmpty ? connectedFriends : sharedUserResults) { profile in
                            HStack(spacing: 12) {
                                Button {
                                    // Placeholder until public profile view exists
                                } label: {
                                    HStack(spacing: 12) {
                                        PublicUserProfileAvatarView(profile: profile, size: 44)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(profile.username)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            if let name = profile.displayName, !name.isEmpty {
                                                Text(name)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if sharedUsersSearchText.isEmpty || friendUserIds.contains(profile.userId) {
                                    Button {
                                        unfriendTargetUserId = profile.userId
                                        showUnfriendAlert = true
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text("Friends")
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                                } else if pendingFriendRequestUserIds.contains(profile.userId) {
                                    Button("Request Sent") {
                                        Task {
                                            do {
                                                try await supabaseService.cancelFriendRequest(toUserId: profile.userId)
                                                await MainActor.run {
                                                    pendingFriendRequestUserIds.remove(profile.userId)
                                                }
                                            } catch {
                                                print("Failed to cancel friend request: \(error.localizedDescription)")
                                            }
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                                } else {
                                    Button("Add Friend") {
                                        Task {
                                            do {
                                                try await supabaseService.sendFriendRequest(
                                                    toUserId: profile.userId,
                                                    toUsername: profile.username,
                                                    toDisplayName: profile.displayName
                                                )
                                                await MainActor.run {
                                                    pendingFriendRequestUserIds.insert(profile.userId)
                                                }
                                            } catch {
                                                print("Failed to send friend request: \(error.localizedDescription)")
                                            }
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.caption)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Shared Users")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task(id: sharedUsersSearchText) {
                await searchSharedUsers()
            }
            .task(id: showSharedUsersSheet) {
                if showSharedUsersSheet {
                    await loadConnectedFriends()
                    await refreshFriendshipBadges()
                }
            }
            .alert("Unfriend?", isPresented: $showUnfriendAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Unfriend", role: .destructive) {
                    guard let targetId = unfriendTargetUserId else { return }
                    Task {
                        do {
                            try await supabaseService.unfriend(userId: targetId)
                            await MainActor.run {
                                friendUserIds.remove(targetId)
                                connectedFriends.removeAll { $0.userId == targetId }
                            }
                            supabaseService.applyFriendCountDelta(-1)
                        } catch {
                            print("Failed to unfriend: \(error.localizedDescription)")
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to remove this friend?")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func searchSharedUsers() async {
        let query = sharedUsersSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            sharedUserResults = []
            sharedUsersError = nil
            return
        }
        
        isSearchingSharedUsers = true
        sharedUsersError = nil
        
        do {
            // simple debounce
            try await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            
            let results = try await supabaseService.searchUsers(byUsername: query)
            let currentUserId = authSession.userId
            let filtered = results.filter { profile in
                guard let currentUserId = currentUserId else { return true }
                return profile.userId != currentUserId
            }
            await MainActor.run {
                sharedUserResults = filtered
            }
            await refreshFriendshipBadges()
        } catch {
            await MainActor.run {
                sharedUsersError = error.localizedDescription
                sharedUserResults = []
            }
        }
        
        await MainActor.run {
            isSearchingSharedUsers = false
        }
    }

    private func loadConnectedFriends() async {
        guard authSession.isAuthenticated else {
            await MainActor.run { connectedFriends = []; isLoadingConnectedFriends = false }
            return
        }
        await MainActor.run { isLoadingConnectedFriends = true }
        defer { Task { @MainActor in isLoadingConnectedFriends = false } }
        do {
            let friends = try await supabaseService.fetchFriends()
            await MainActor.run { connectedFriends = friends }
        } catch {
            await MainActor.run { connectedFriends = [] }
        }
    }

    private func refreshFriendshipBadges() async {
        guard authSession.isAuthenticated else {
            await MainActor.run {
                friendUserIds = []
            }
            return
        }
        
        do {
            let rows = try await supabaseService.fetchFriendshipsForCurrentUser()
            let currentId = authSession.userId
            let resultIds = Set(sharedUserResults.map(\.userId))
            
            var accepted: Set<UUID> = []
            var outgoingPending: Set<UUID> = []
            
            for row in rows {
                guard let currentId else { continue }
                let otherId: UUID
                if row.user_id == currentId {
                    otherId = row.friend_user_id
                } else if row.friend_user_id == currentId {
                    otherId = row.user_id
                } else {
                    continue
                }
                
                guard resultIds.contains(otherId) else { continue }
                
                if row.status == "accepted" {
                    accepted.insert(otherId)
                } else if row.status == "pending", row.user_id == currentId {
                    // only show outgoing pending as "Request Sent"
                    outgoingPending.insert(otherId)
                }
            }
            
            await MainActor.run {
                friendUserIds = accepted
                pendingFriendRequestUserIds.formUnion(outgoingPending)
            }
        } catch {
            print("Failed to refresh friendships: \(error.localizedDescription)")
        }
    }
    
    private func areAllSelectedItemsInWardrobe(_ wardrobe: Wardrobe) -> Bool {
        guard !selectedItems.isEmpty else { return false }
        
        let itemsInWardrobe = (wardrobe.items as? Set<Item>) ?? []
        
        // Check if all selected items are already in this wardrobe
        return selectedItems.allSatisfy { itemsInWardrobe.contains($0) }
    }
    
    private func fetchAllWardrobes() -> [Wardrobe] {
        guard let userId = authSession.userId?.uuidString, !userId.isEmpty else { return [] }

        let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "type == %@", wardrobeType),
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        ])
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Wardrobe.createdAt, ascending: true)
        ]

        do {
            let results = try viewContext.fetch(request)
            let filteredWardrobes = filterModel.selectedWardrobes.filter {
                $0.type == wardrobeType && $0.userId == userId
            }
            if filteredWardrobes.isEmpty {
                return results
            }
            let allowedIDs = Set(filteredWardrobes.map(\.objectID))
            return results.filter { allowedIDs.contains($0.objectID) }
        } catch {
            print("❌ Failed to fetch wardrobes: \(error.localizedDescription)")
            return []
        }
    }
    
    private func addSelectedItemsToWardrobe(_ wardrobe: Wardrobe) {
        guard !selectedItems.isEmpty else { return }
        
        // Get items already in this wardrobe
        let itemsInWardrobe = (wardrobe.items as? Set<Item>) ?? []
        
        // Add selected items to the wardrobe (Core Data will handle duplicates)
        for item in selectedItems {
            if !itemsInWardrobe.contains(item) {
                wardrobe.addToItems(item)
            }
        }
        
        do {
            try viewContext.save()
            print("✅ Added \(selectedItems.count) items to wardrobe '\(wardrobe.name ?? "unknown")'")
            
            // Exit selection mode after successful addition
            isInSelectionMode = false
            selectedItems.removeAll()
        } catch {
            print("❌ Failed to add items to wardrobe: \(error.localizedDescription)")
        }
    }

    private func removeSelectedItemsFromWardrobe(_ wardrobe: Wardrobe) {
        guard !selectedItems.isEmpty else { return }

        let itemsInWardrobe = (wardrobe.items as? Set<Item>) ?? []
        for item in selectedItems where itemsInWardrobe.contains(item) {
            wardrobe.removeFromItems(item)
        }

        do {
            try viewContext.save()
            print("✅ Removed \(selectedItems.count) items from wardrobe '\(wardrobe.name ?? "unknown")'")

            // Exit selection mode after successful removal
            isInSelectionMode = false
            selectedItems.removeAll()
        } catch {
            print("❌ Failed to remove items from wardrobe: \(error.localizedDescription)")
        }
    }
    
    private var isSelectionDeleteDisabled: Bool {
        selectedTab == "Items" ? selectedItems.isEmpty : selectedOutfits.isEmpty
    }

    private var selectionDeleteColor: Color {
        isSelectionDeleteDisabled ? .gray : .red
    }

    private var selectedItemsAllFavorited: Bool {
        _ = favoriteToolbarTick
        guard !selectedItems.isEmpty else { return false }
        return selectedItems.allSatisfy(\.isFavorite)
    }

    private var selectedItemsFavoriteToolbarIcon: String {
        _ = favoriteToolbarTick
        guard !selectedItems.isEmpty else { return "heart" }
        return selectedItemsAllFavorited ? "heart.fill" : "heart"
    }

    @discardableResult
    private func applyFavoriteToSelectedItems(favorite: Bool) -> String? {
        guard !selectedItems.isEmpty else { return nil }
        let selectionCount = selectedItems.count
        var itemsUpdated = 0
        for item in selectedItems where item.isFavorite != favorite {
            item.isFavorite = favorite
            setUpdatedAt(item)
            itemsUpdated += 1
        }
        do {
            try viewContext.save()
            for item in selectedItems {
                SyncService.shared.syncItemIfNeeded(item)
            }
            favoriteToolbarTick += 1
            print("✅ \(favorite ? "Favorited" : "Unfavorited") \(itemsUpdated) items")
            if favorite {
                return "Added \(selectionCount) item\(selectionCount == 1 ? "" : "s") to favorites."
            }
            return "Removed \(selectionCount) item\(selectionCount == 1 ? "" : "s") from favorites."
        } catch {
            print("❌ Failed to update favorites: \(error.localizedDescription)")
            return nil
        }
    }

    /// Removes deleted items from other items' `pairedItems` and clears deleted items' own pairs.
    /// Returns the set of non-deleted items that were modified and should be synced.
    private func sanitizePairsAfterDeleting(deletedItems: Set<Item>) -> Set<Item> {
        guard !deletedItems.isEmpty else { return [] }

        var modifiedPairedItems: Set<Item> = []

        for deleted in deletedItems {
            let paired = (deleted.pairedItems as? Set<Item>) ?? []

            // Remove the deleted item from any still-active paired items.
            for other in paired where !deletedItems.contains(other) {
                var othersPairs = (other.pairedItems as? Set<Item>) ?? []
                if othersPairs.remove(deleted) != nil {
                    other.pairedItems = othersPairs as NSSet
                    setUpdatedAt(other)
                    modifiedPairedItems.insert(other)
                }
            }

            // Clear pairs on the deleted item itself to prevent "ghost" pairs in UI.
            if !paired.isEmpty {
                deleted.pairedItems = NSSet()
                setUpdatedAt(deleted)
            }
        }

        return modifiedPairedItems
    }

    private func deleteSelectedItems() {
        guard !selectedItems.isEmpty else { return }
        
        let sanitizerResult = OutfitSanitizer.sanitizeOutfitsAfterDeleting(deletedItems: selectedItems, in: viewContext)
        let removedFromOutfitsCount = sanitizerResult.affectedOutfits.count

        // Store brands before deletion to check if cleanup is needed
        var brandsToCheck: Set<Brand> = []
        for item in selectedItems {
            if let brand = item.brand {
                brandsToCheck.insert(brand)
            }
        }

        // Sanitize pairs before soft-delete (soft delete won't trigger Core Data delete rules).
        let modifiedPairedItems = sanitizePairsAfterDeleting(deletedItems: selectedItems)
        
        // Soft delete all selected items (for sync)
        for item in selectedItems {
            softDelete(item)
        }
        
        do {
            try viewContext.save()
            print("✅ Deleted \(selectedItems.count) items")
            
            // Trigger sync for all soft-deleted items
            for item in selectedItems {
                SyncService.shared.syncItemIfNeeded(item)
            }

            // Also sync any items whose pair relationships were updated
            for item in modifiedPairedItems {
                SyncService.shared.syncItemIfNeeded(item)
            }

            // Sync outfits that were sanitized (after the single save)
            for outfit in sanitizerResult.affectedOutfits {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }

            NotificationCenter.default.post(
                name: Notification.Name("Closet.ItemDeletionToast"),
                object: nil,
                userInfo: [
                    "message": "Deleted \(selectedItems.count) item\(selectedItems.count == 1 ? "" : "s"). Removed from \(removedFromOutfitsCount) outfit\(removedFromOutfitsCount == 1 ? "" : "s")."
                ]
            )
            
            // Cleanup orphaned brands
            for brand in brandsToCheck {
                cleanupBrandIfOrphaned(brand)
            }
            
            // Exit selection mode and refresh items after deletion
            isInSelectionMode = false
            selectedItems.removeAll()
            fetchItems()
        } catch {
            print("❌ Failed to delete items: \(error.localizedDescription)")
        }
    }

    private func showToast(_ message: String) {
        deletionToastMessage = message
        withAnimation(.easeInOut(duration: 0.18)) {
            showDeletionToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeInOut(duration: 0.22)) {
                showDeletionToast = false
            }
        }
    }

    private func completeBulkSelectionAction(toast message: String) {
        showTagSelectionSheet = false
        showColorSelectionSheet = false
        showCategorySelectionSheet = false
        isInSelectionMode = false
        selectedItems.removeAll()
        showToast(message)
    }

    // Outfit sanitation is handled by `OutfitSanitizer` at delete-time.
    
    private func deleteSelectedOutfits() {
        guard !selectedOutfits.isEmpty else { return }
        
        // Soft delete all selected outfits (for sync)
        for outfit in selectedOutfits {
            softDelete(outfit)
        }
        
        do {
            try viewContext.save()
            print("✅ Deleted \(selectedOutfits.count) outfits")
            
            // Exit selection mode and refresh outfits after deletion
            isInSelectionMode = false
            selectedOutfits.removeAll()
            fetchOutfits()
        } catch {
            print("❌ Failed to delete outfits: \(error.localizedDescription)")
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
    
    // MARK: - Tag Selection Sheet
    
    @ViewBuilder
    private func tagSelectionSheet() -> some View {
        let tagsForContext = fetchAllTags()
        return NavigationView {
            List {
                if tagsForContext.isEmpty {
                    Text(wardrobeType == "wishlist"
                        ? "Tags used on wishlist items will appear here."
                        : "Tags added to your closet will appear here.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(tagsForContext, id: \.self) { tag in
                    let allItemsHaveTag = doAllSelectedItemsHaveTag(tag)
                    
                    Button {
                        pendingTagSelectionTarget = tag
                        pendingTagSelectionWillRemove = allItemsHaveTag
                        showTagSelectionConfirmAlert = true
                    } label: {
                        HStack {
                            Text(tag.name ?? "Untitled")
                            
                            Spacer()
                            
                            Image(systemName: allItemsHaveTag ? "checkmark" : "plus")
                                .foregroundColor(.blue)
                                .font(.system(size: 16, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Add Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .alert(pendingTagSelectionWillRemove ? "Remove Tag?" : "Add Tag?", isPresented: $showTagSelectionConfirmAlert) {
            Button(pendingTagSelectionWillRemove ? "Remove" : "Add", role: pendingTagSelectionWillRemove ? .destructive : nil) {
                guard let tag = pendingTagSelectionTarget else { return }
                let message: String?
                if pendingTagSelectionWillRemove {
                    message = removeTagFromSelectedItems(tag)
                } else {
                    message = addTagToSelectedItems(tag)
                }
                if let message {
                    completeBulkSelectionAction(toast: message)
                }
                pendingTagSelectionTarget = nil
                pendingTagSelectionWillRemove = false
            }
            Button("Cancel", role: .cancel) {
                pendingTagSelectionTarget = nil
                pendingTagSelectionWillRemove = false
            }
        } message: {
            let name = pendingTagSelectionTarget?.name ?? "this tag"
            Text(pendingTagSelectionWillRemove
                 ? "Remove tag “\(name)” from \(selectedItems.count) selected item(s)?"
                 : "Add tag “\(name)” to \(selectedItems.count) selected item(s)?")
        }
        .presentationDetents([.medium, .large])
    }
    
    private func doAllSelectedItemsHaveTag(_ tag: Tag) -> Bool {
        guard !selectedItems.isEmpty else { return false }
        
        // Check if all selected items already have this tag
        return selectedItems.allSatisfy { item in
            if let tags = item.tags as? Set<Tag> {
                return tags.contains(tag)
            }
            return false
        }
    }
    
    private func fetchAllTags() -> [Tag] {
        guard let userId = authSession.userId?.uuidString, !userId.isEmpty else { return [] }

        let request: NSFetchRequest<Tag> = Tag.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]
        request.predicate = NSPredicate(
            format: "SUBQUERY(items, $i, $i.userId == %@ AND ($i.isSoftDeleted != YES OR $i.isSoftDeleted == nil) AND ANY $i.wardrobes == %@).@count > 0",
            userId,
            selectedWardrobe
        )

        do {
            var tags = try viewContext.fetch(request)
            for item in selectedItems {
                guard let itemTags = item.tags as? Set<Tag> else { continue }
                for tag in itemTags where !tags.contains(where: { $0.objectID == tag.objectID }) {
                    tags.append(tag)
                }
            }
            tags.sort { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
            return tags
        } catch {
            print("❌ Failed to fetch tags: \(error.localizedDescription)")
            return []
        }
    }
    
    @discardableResult
    private func addTagToSelectedItems(_ tag: Tag) -> String? {
        guard !selectedItems.isEmpty else { return nil }

        let selectionCount = selectedItems.count
        var itemsAdded = 0
        for item in selectedItems {
            if let tags = item.tags as? Set<Tag>, !tags.contains(tag) {
                item.addToTags(tag)
                setUpdatedAt(item)
                itemsAdded += 1
            }
        }

        do {
            try viewContext.save()
            for item in selectedItems {
                SyncService.shared.syncItemIfNeeded(item)
            }
            print("✅ Added tag '\(tag.name ?? "unknown")' to \(itemsAdded) items")
            let name = tag.name ?? "tag"
            return "Added tag “\(name)” to \(selectionCount) item\(selectionCount == 1 ? "" : "s")."
        } catch {
            print("❌ Failed to add tag to items: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    private func removeTagFromSelectedItems(_ tag: Tag) -> String? {
        guard !selectedItems.isEmpty else { return nil }

        let selectionCount = selectedItems.count
        for item in selectedItems {
            if let tags = item.tags as? Set<Tag>, tags.contains(tag) {
                item.removeFromTags(tag)
                setUpdatedAt(item)
            }
        }

        do {
            try viewContext.save()
            for item in selectedItems {
                SyncService.shared.syncItemIfNeeded(item)
            }
            print("✅ Removed tag '\(tag.name ?? "unknown")' from \(selectionCount) items")
            let name = tag.name ?? "tag"
            return "Removed tag “\(name)” from \(selectionCount) item\(selectionCount == 1 ? "" : "s")."
        } catch {
            print("❌ Failed to remove tag from items: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Color Selection Sheet

    @ViewBuilder
    private func colorSelectionSheet() -> some View {
        let colorsForContext = fetchAllColorsForBulkSet()
        return NavigationView {
            List {
                if colorsForContext.isEmpty {
                    Text("Colors added to your closet will appear here.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(colorsForContext, id: \.objectID) { color in
                        let allItemsHaveColor = doAllSelectedItemsHaveColor(color)
                        let name = color.name ?? ""

                        Button {
                            pendingColorSelectionTarget = color
                            pendingColorSelectionWillRemove = allItemsHaveColor
                            showColorSelectionConfirmAlert = true
                        } label: {
                            HStack {
                                Circle()
                                    .fill(colorFromName(name))
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))

                                Text(name)

                                Spacer()

                                Image(systemName: allItemsHaveColor ? "checkmark" : "plus")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Add Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .alert(pendingColorSelectionWillRemove ? "Remove Color?" : "Add Color?", isPresented: $showColorSelectionConfirmAlert) {
            Button(pendingColorSelectionWillRemove ? "Remove" : "Add", role: pendingColorSelectionWillRemove ? .destructive : nil) {
                guard let color = pendingColorSelectionTarget else { return }
                let message: String?
                if pendingColorSelectionWillRemove {
                    message = removeColorFromSelectedItems(color)
                } else {
                    message = addColorToSelectedItems(color)
                }
                if let message {
                    completeBulkSelectionAction(toast: message)
                }
                pendingColorSelectionTarget = nil
                pendingColorSelectionWillRemove = false
            }
            Button("Cancel", role: .cancel) {
                pendingColorSelectionTarget = nil
                pendingColorSelectionWillRemove = false
            }
        } message: {
            let name = pendingColorSelectionTarget?.name ?? "this color"
            Text(pendingColorSelectionWillRemove
                 ? "Remove color “\(name)” from \(selectedItems.count) selected item(s)?"
                 : "Add color “\(name)” to \(selectedItems.count) selected item(s)?")
        }
        .presentationDetents([.medium, .large])
    }

    private func doAllSelectedItemsHaveColor(_ color: AppColor) -> Bool {
        guard !selectedItems.isEmpty else { return false }
        return selectedItems.allSatisfy { item in
            (item.colors as? Set<AppColor>)?.contains(color) ?? false
        }
    }

    private func fetchAllColorsForBulkSet() -> [AppColor] {
        guard let userId = authSession.userId?.uuidString, !userId.isEmpty else { return [] }

        do {
            var colors = try viewContext.fetchColorsForFilterList(userId: userId, itemsOnly: false)
            for item in selectedItems {
                guard let itemColors = item.colors as? Set<AppColor> else { continue }
                for color in itemColors where !colors.contains(where: { $0.objectID == color.objectID }) {
                    colors.append(color)
                }
            }
            colors.sort { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
            return colors
        } catch {
            print("❌ Failed to fetch colors: \(error.localizedDescription)")
            return []
        }
    }

    @discardableResult
    private func addColorToSelectedItems(_ color: AppColor) -> String? {
        guard !selectedItems.isEmpty else { return nil }

        let selectionCount = selectedItems.count
        for item in selectedItems {
            if let colors = item.colors as? Set<AppColor>, !colors.contains(color) {
                item.addToColors(color)
                setUpdatedAt(item)
            }
        }

        do {
            try viewContext.save()
            for item in selectedItems {
                SyncService.shared.syncItemIfNeeded(item)
            }
            print("✅ Added color '\(color.name ?? "unknown")' to \(selectionCount) items")
            let name = color.name ?? "color"
            return "Added color “\(name)” to \(selectionCount) item\(selectionCount == 1 ? "" : "s")."
        } catch {
            print("❌ Failed to add color to items: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    private func removeColorFromSelectedItems(_ color: AppColor) -> String? {
        guard !selectedItems.isEmpty else { return nil }

        let selectionCount = selectedItems.count
        for item in selectedItems {
            if let colors = item.colors as? Set<AppColor>, colors.contains(color) {
                item.removeFromColors(color)
                setUpdatedAt(item)
            }
        }

        do {
            try viewContext.save()
            for item in selectedItems {
                SyncService.shared.syncItemIfNeeded(item)
            }
            print("✅ Removed color '\(color.name ?? "unknown")' from \(selectionCount) items")
            let name = color.name ?? "color"
            return "Removed color “\(name)” from \(selectionCount) item\(selectionCount == 1 ? "" : "s")."
        } catch {
            print("❌ Failed to remove color from items: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Category Selection Sheet

    @ViewBuilder
    private func categorySelectionSheet() -> some View {
        CategoryPickerList(
            title: "Set Category",
            userId: authSession.userId?.uuidString ?? "",
            expanded: $bulkSetCategoryExpanded,
            onCategoriesLoaded: expandBulkSetCategoryForCurrentSelection(categories:),
            showsCategoryCheckmark: { allSelectedItemsMatch(category: $0, subcategory: nil) },
            showsSubcategoryCheckmark: { category, sub in
                allSelectedItemsMatch(category: category, subcategory: sub)
            },
            onCategoryTap: { category in
                pendingBulkCategory = category
                pendingBulkSubcategory = nil
                showCategorySelectionConfirmAlert = true
            },
            onSubcategoryTap: { category, sub in
                pendingBulkCategory = category
                pendingBulkSubcategory = sub
                showCategorySelectionConfirmAlert = true
            }
        )
        .alert("Set Category?", isPresented: $showCategorySelectionConfirmAlert) {
            Button("Apply") {
                guard let category = pendingBulkCategory else { return }
                if let message = applyCategoryToSelectedItems(category: category, subcategory: pendingBulkSubcategory) {
                    completeBulkSelectionAction(toast: message)
                }
                pendingBulkCategory = nil
                pendingBulkSubcategory = nil
            }
            Button("Cancel", role: .cancel) {
                pendingBulkCategory = nil
                pendingBulkSubcategory = nil
            }
        } message: {
            Text(bulkCategorySelectionConfirmMessage)
        }
        .presentationDetents([.medium, .large])
    }

    private var bulkCategorySelectionConfirmMessage: String {
        let count = selectedItems.count
        let itemPhrase = "\(count) selected item\(count == 1 ? "" : "s")"
        if let sub = pendingBulkSubcategory {
            let cat = pendingBulkCategory?.name ?? ""
            let subName = sub.name ?? ""
            return "Set “\(cat) › \(subName)” on \(itemPhrase)?"
        }
        let name = pendingBulkCategory?.name ?? "category"
        return "Set category “\(name)” on \(itemPhrase)?"
    }

    private func expandBulkSetCategoryForCurrentSelection(categories: [Category]) {
        bulkSetCategoryExpanded = []
        guard !selectedItems.isEmpty,
              let first = selectedItems.first,
              let sharedCategory = first.category,
              selectedItems.allSatisfy({ $0.category?.objectID == sharedCategory.objectID }),
              let listCategory = categories.first(where: { $0.objectID == sharedCategory.objectID })
        else { return }

        if let sharedSub = first.subcategory,
           sharedSub.category == sharedCategory,
           selectedItems.allSatisfy({ $0.subcategory?.objectID == sharedSub.objectID }) {
            bulkSetCategoryExpanded.insert(listCategory.objectID)
        }
    }

    private func allSelectedItemsMatch(category: Category, subcategory: Subcategory?) -> Bool {
        guard !selectedItems.isEmpty else { return false }
        return selectedItems.allSatisfy { item in
            guard item.category?.objectID == category.objectID else { return false }
            if let subcategory {
                return item.subcategory?.objectID == subcategory.objectID
            }
            return item.subcategory == nil
        }
    }

    @discardableResult
    private func applyCategoryToSelectedItems(category: Category, subcategory: Subcategory?) -> String? {
        guard !selectedItems.isEmpty else { return nil }

        let selectionCount = selectedItems.count
        for item in selectedItems {
            item.category = category
            item.subcategory = subcategory
            setUpdatedAt(item)
        }

        let label: String
        if let subName = subcategory?.name, !subName.isEmpty {
            let catName = category.name ?? "category"
            label = "\(catName) › \(subName)"
        } else {
            label = category.name ?? "category"
        }

        do {
            try viewContext.save()
            for item in selectedItems {
                SyncService.shared.syncItemIfNeeded(item)
            }
            print("✅ Set category '\(label)' on \(selectionCount) items")
            return "Set category “\(label)” on \(selectionCount) item\(selectionCount == 1 ? "" : "s")."
        } catch {
            print("❌ Failed to set category on items: \(error.localizedDescription)")
            return nil
        }
    }

    private var outfitsTab: some View {
        Group {
            if isOutfitsTabLoading {
                closetContentLoadingView(
                    syncStatus: appCapabilities.enablesCloudSync && syncService.isSyncing ? syncService.syncStatus : nil
                )
            } else if outfits.isEmpty {
                EmptyOutfitStateView()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(outfits, id: \.objectID) { outfit in
                            OutfitView(outfit: outfit)
                                .overlay(
                                    // Transparent white overlay when in selection mode
                                    Group {
                                        if isInSelectionMode && selectedOutfits.contains(outfit) {
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
                                                    Image(systemName: selectedOutfits.contains(outfit) ? "checkmark.circle" : "circle")
                                                        .foregroundColor(.white)
                                                        .background(
                                                            Circle()
                                                                .fill(selectedOutfits.contains(outfit) ? Color.blue : Color.clear)
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
                                    handleOutfitTap(for: outfit)
                                }
                                .onLongPressGesture(minimumDuration: 0.5) {
                                    handleOutfitLongPress(for: outfit)
                                }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

  /*  private func handleScroll(_ topIndex: Int) {
        if let last = currentTopIndex {
            if topIndex > last && !isControlsHidden {
                // Scrolling down
                withAnimation(.easeInOut(duration: 0.25)) {
                    isControlsHidden = true
                }
            } else if topIndex < last && isControlsHidden {
                // Scrolling up
                withAnimation(.easeInOut(duration: 0.25)) {
                    isControlsHidden = false
                }
            }
        }
        currentTopIndex = topIndex
    }*/
}

/* MARK: - Scroll Offset PreferenceKey
struct ScrollOffsetPreferenceKey: PreferenceKey {
    typealias Value = Int?
    static var defaultValue: Int? = nil
    static func reduce(value: inout Int?, nextValue: () -> Int?) {
        value = value ?? nextValue()
    }
}*/
