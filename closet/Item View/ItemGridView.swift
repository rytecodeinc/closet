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
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var closetItems: [Item] = []
    @State private var isImagePickerPresented = false
    @State private var pickedImage: UIImage? = nil
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var path = NavigationPath()
    @State private var selectedTab: String = "Items"
    
    @State private var outfits: [Outfit] = []
    @State private var sortAscending: Bool = false // false = descending (newest first), true = ascending (oldest first)
    @StateObject private var outfitFilterModel = OutfitFilterModel()
    
    // Selection mode state
    @State private var selectedItemForNavigation: Item?
    @State private var selectedItems: Set<Item> = []
    @State private var selectedOutfitForNavigation: Outfit?
    @State private var selectedOutfits: Set<Outfit> = []
    @State private var showWardrobeSelectionSheet = false
    @State private var showDeleteConfirmation = false
    @State private var showOutfitDeleteConfirmation = false
    @State private var showTagSelectionSheet = false
    @State private var showTagAddedConfirmation = false
    @State private var addedTagName: String = ""
    @State private var addedTagItemCount: Int = 0
    
    // Multi-image picker state
    @StateObject private var queueCoordinator = ImageQueueCoordinator()
    @State private var showMultiImagePicker = false
    @State private var showCropperForQueue = false
    @State private var shouldNavigateToItemAdd = false
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
        if filterModel.filterByWeight {
            // Include user weight in key so it refreshes when user updates their weight
            let repository = UserProfileRepository(context: viewContext)
            let userWeightKg = repository.getWeightKg()
            key += "weight:\(userWeightKg)"
        }
        return key
    }
    
    // Computed property to track outfit filter changes
    private var outfitFilterKey: String {
        var key = ""
        key += outfitFilterModel.selectedCategory ?? ""
        key += outfitFilterModel.selectedTags.map { $0.objectID.uriRepresentation().absoluteString }.sorted().joined(separator: ",")
        return key
    }

    var body: some View {
        VStack(spacing: 0) {
          //  Divider()
            UnderlineTabBar(
                selectedTab: $selectedTab,
                tabs: ["Items (\(closetItems.count))", "Outfits (\(outfits.count))"]
            )
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
            // Refresh items when context saves (items added/deleted/updated elsewhere)
            if let context = notification.object as? NSManagedObjectContext,
               context === viewContext || context.parent === viewContext {
                fetchItems()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                leadingToolbarContent()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                trailingToolbarContent()
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
                        isEditing: false
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                // Show confirmation if queue is active (has current image or more images)
                                if queueCoordinator.isQueueActive {
                                    showCropperCancelConfirmation = true
                                } else {
                                    // Queue not active, just dismiss
                                    showCropperForQueue = false
                                }
                            }
                        }
                    }
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
        .background {
            // Hidden NavigationLink that is programmatically triggered
            NavigationLink(
                destination: ItemAddView(
                    parentContext: viewContext,
                    selectedWardrobe: selectedWardrobe,
                    queueCoordinator: queueCoordinator
                )
                .onDisappear {
                    handleItemAddViewDismiss()
                },
                isActive: $shouldNavigateToItemAdd
            ) {
                EmptyView()
            }
            .hidden()
        }
        .sheet(isPresented: $showWardrobeSelectionSheet) {
            wardrobeSelectionSheet()
        }
        .sheet(isPresented: $showTagSelectionSheet) {
            tagSelectionSheet()
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
        .alert("Tag Added", isPresented: $showTagAddedConfirmation) {
            Button("OK") {
                // Exit selection mode after confirmation
                isInSelectionMode = false
                selectedItems.removeAll()
            }
        } message: {
            Text("Tag \"\(addedTagName)\" has been added to \(addedTagItemCount) item\(addedTagItemCount == 1 ? "" : "s").")
        }
        .navigationDestination(item: $selectedItemForNavigation) { item in
            ItemDetailView(item: item)
        }
        .navigationDestination(item: $selectedOutfitForNavigation) { outfit in
            OutfitDetailView(outfit: outfit)
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
        guard let userId = SupabaseService.shared.currentUser?.id.uuidString else {
            DispatchQueue.main.async {
                self.closetItems = []
            }
            return
        }
        
        let request = NSFetchRequest<Item>(entityName: "Item")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.timestamp, ascending: sortAscending)]
        
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
        
        // Handle wardrobe filtering: use filterModel.selectedWardrobes if set, otherwise use selectedWardrobe
        // Filter out wardrobes of the wrong type as a safeguard
        let filteredWardrobes = filterModel.selectedWardrobes.filter { $0.type == wardrobeType }
        let wardrobePredicate: NSPredicate
        if !filteredWardrobes.isEmpty {
            // If user selected specific wardrobes in filter, use those (only of the correct type)
            wardrobePredicate = NSPredicate(format: "ANY wardrobes IN %@", Array(filteredWardrobes))
        } else {
            // Otherwise, use the view's selected wardrobe
            wardrobePredicate = NSPredicate(format: "ANY wardrobes == %@", selectedWardrobe)
        }
        subpredicates.append(wardrobePredicate)
        
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
            
            // Debug: Log results if weight filter is active
            if filterModel.filterByWeight {
                let repository = UserProfileRepository(context: viewContext)
                let userWeightKg = repository.getWeightKg()
                print("🔍 Fetched \(results.count) items with weight filter")
                // Sample a few items to check their weights
                for (index, item) in results.prefix(5).enumerated() {
                    if let weight = item.primitiveValue(forKey: "weight") as? Double {
                        print("🔍 Item \(index + 1): weight = \(String(format: "%.2f", weight)) kg (>= \(String(format: "%.2f", userWeightKg))? \(weight >= userWeightKg))")
                    } else {
                        print("🔍 Item \(index + 1): weight = nil (no limit)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.closetItems = results
            }
        } catch {
            print("❌ Failed to fetch items: \(error)")
            if let nsError = error as NSError? {
                print("❌ Error details: \(nsError.userInfo)")
            }
            DispatchQueue.main.async {
                self.closetItems = []
            }
        }
    }
    
    func fetchOutfits() {
        // Require authentication - get userId
        guard let userId = SupabaseService.shared.currentUser?.id.uuidString else {
            DispatchQueue.main.async {
                self.outfits = []
            }
            return
        }
        
        let request = NSFetchRequest<Outfit>(entityName: "Outfit")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Outfit.timestamp, ascending: sortAscending)]
        
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
            // Filter by wardrobe (items must belong to selected wardrobe)
            let filtered = allOutfits.filter { outfit in
                (outfit.items as? Set<Item>)?.contains(where: { $0.wardrobes?.contains(selectedWardrobe) ?? false }) ?? false
            }
            DispatchQueue.main.async {
                self.outfits = filtered
            }
        } catch {
            print("Failed to fetch outfits: \(error)")
            DispatchQueue.main.async {
                self.outfits = []
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
            photo.data = imageData
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
    
    private var itemsTab: some View {
        Group {
            if closetItems.isEmpty {
                EmptyItemStateView(wardrobe: selectedWardrobe, wardrobeType: wardrobeType)
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
                                        if isInSelectionMode {
                                            VStack {
                                                Spacer()
                                                HStack {
                                                    Spacer()
                                                    Image(systemName: selectedItems.contains(item) ? "checkmark.circle" : "circle")
                                                        .foregroundColor(.white)
                                                        .background(
                                                            Circle()
                                                                .fill(selectedItems.contains(item) ? Color.blue : Color.clear)
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
        
        // Tag button
        Button {
            showTagSelectionSheet = true
        } label: {
            Image(systemName: "tag")
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
        Menu {
            Button {
                sortAscending = false
                fetchItems()
                fetchOutfits()
            } label: {
                if !sortAscending {
                    Label("Newest First", systemImage: "checkmark")
                } else {
                    Text("Newest First")
                }
            }
            Button {
                sortAscending = true
                fetchItems()
                fetchOutfits()
            } label: {
                if sortAscending {
                    Label("Oldest First", systemImage: "checkmark")
                } else {
                    Text("Oldest First")
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
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
        HStack(spacing: 16) {
            // Delete button
            Button {
                if selectedTab == "Items" {
                    showDeleteConfirmation = true
                } else {
                    showOutfitDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .disabled(selectedTab == "Outfits" && selectedOutfits.isEmpty)
            
            // Cancel button
            Button("Cancel") {
                isInSelectionMode = false
                if selectedTab == "Items" {
                    selectedItems.removeAll()
                } else {
                    selectedOutfits.removeAll()
                }
            }
        }
    }
    
    @ViewBuilder
    private func nonSelectionModeTrailingToolbar() -> some View {
        HStack(spacing: 16) {
            if selectedTab == "Items" {
                NavigationLink(destination: ItemDraftsView()) {
                    Image(systemName: "folder")
                }
                NavigationLink(destination: ItemAddView(parentContext: viewContext, selectedWardrobe: selectedWardrobe)) {
                    Image(systemName: "plus")
                }
            } else {
                NavigationLink(destination: OutfitDraftsView(wardrobeType: wardrobeType, selectedWardrobe: selectedWardrobe)) {
                    Image(systemName: "folder")
                }
                NavigationLink(destination: OutfitAddView(wardrobeType: wardrobeType, initialWardrobe: selectedWardrobe)) {
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
                    let isDefault = wardrobe == wardrobes.first
                    
                    Button {
                        addSelectedItemsToWardrobe(wardrobe)
                        showWardrobeSelectionSheet = false
                    } label: {
                        HStack {
                            Text(wardrobe.name ?? "Untitled")
                            
                            // Add "Default" label next to the first wardrobe
                            if isDefault {
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
                                .foregroundColor(allItemsInWardrobe ? .green : .blue)
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
        .presentationDetents([.medium, .large])
    }
    
    private func areAllSelectedItemsInWardrobe(_ wardrobe: Wardrobe) -> Bool {
        guard !selectedItems.isEmpty else { return false }
        
        let itemsInWardrobe = (wardrobe.items as? Set<Item>) ?? []
        
        // Check if all selected items are already in this wardrobe
        return selectedItems.allSatisfy { itemsInWardrobe.contains($0) }
    }
    
    private func fetchAllWardrobes() -> [Wardrobe] {
        let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        // Filter by wardrobeType (closet or wishlist) and exclude soft-deleted
        request.predicate = NSPredicate(format: "type == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)", wardrobeType)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Wardrobe.timestamp, ascending: true)
        ]
        
        do {
            return try viewContext.fetch(request)
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
    
    private func deleteSelectedItems() {
        guard !selectedItems.isEmpty else { return }
        
        // Store brands before deletion to check if cleanup is needed
        var brandsToCheck: Set<Brand> = []
        for item in selectedItems {
            if let brand = item.brand {
                brandsToCheck.insert(brand)
            }
        }
        
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
        NavigationView {
            List {
                ForEach(fetchAllTags(), id: \.self) { tag in
                    let allItemsHaveTag = doAllSelectedItemsHaveTag(tag)
                    
                    Button {
                        addTagToSelectedItems(tag)
                        showTagSelectionSheet = false
                    } label: {
                        HStack {
                            Text(tag.name ?? "Untitled")
                            
                            Spacer()
                            
                            Image(systemName: allItemsHaveTag ? "checkmark" : "plus")
                                .foregroundColor(allItemsHaveTag ? .green : .blue)
                                .font(.system(size: 16, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Add Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
        let request: NSFetchRequest<Tag> = Tag.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch tags: \(error.localizedDescription)")
            return []
        }
    }
    
    private func addTagToSelectedItems(_ tag: Tag) {
        guard !selectedItems.isEmpty else { return }
        
        // Count how many items actually get the tag (excluding items that already have it)
        var itemsAdded = 0
        
        // Add tag to all selected items (Core Data will handle duplicates)
        for item in selectedItems {
            if let tags = item.tags as? Set<Tag>, !tags.contains(tag) {
                item.addToTags(tag)
                itemsAdded += 1
            }
        }
        
        do {
            try viewContext.save()
            print("✅ Added tag '\(tag.name ?? "unknown")' to \(itemsAdded) items")
            
            // Show confirmation alert
            addedTagName = tag.name ?? "Untitled"
            addedTagItemCount = itemsAdded
            showTagAddedConfirmation = true
        } catch {
            print("❌ Failed to add tag to items: \(error.localizedDescription)")
        }
    }

    private var outfitsTab: some View {
        Group {
            if outfits.isEmpty {
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
