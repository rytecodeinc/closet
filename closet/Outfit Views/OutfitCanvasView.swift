//
//  CreateOutfitView.swift
//  closet
//
//  Created by Dan Warner on 8/5/25.
//

import SwiftUI
import CoreData
import Foundation
import UIKit
/*
struct OutfitAddView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    // Optional outfit for editing
    let outfitToEdit: Outfit?
    
    // Wardrobe type to filter by (closet or wishlist)
    let wardrobeType: String
    
    // Fetch all wardrobes (we'll filter by type)
    @FetchRequest(
        entity: Wardrobe.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.name, ascending: true)]
    ) private var allWardrobes: FetchedResults<Wardrobe>
    
    // Filter wardrobes by type
    private var wardrobes: [Wardrobe] {
        allWardrobes.filter { $0.type == wardrobeType }
    }
    
    // Get wardrobes for the currently selected segment (when in wishlist mode)
    private var currentSegmentWardrobes: [Wardrobe] {
        if wardrobeType == "wishlist" {
            let segmentType = itemTypeSegment == .wishlist ? "wishlist" : "closet"
            return allWardrobes.filter { $0.type == segmentType }
        } else {
            return wardrobes
        }
    }
    
    // Selected wardrobe for filtering items
    @State private var selectedWardrobe: Wardrobe?
    @State private var isWardrobeSelectionPresented = false
    @State private var closetItems: [Item] = []
    @StateObject private var filterModel = ItemFilterModel()
    @State private var sortAscending: Bool = false // false = descending (newest first), true = ascending (oldest first)
    
    // Segmented picker for switching between closet and wishlist items (only in wishlist mode)
    @State private var itemTypeSegment: ItemTypeSegment = .wishlist
    enum ItemTypeSegment: String, CaseIterable {
        case wishlist = "Wishlist"
        case closet = "Closet"
    }
    
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
        return key
    }
    
    // Fetch items filtered by selected wardrobe
    private func fetchClosetItems() {
        // When in wishlist mode, filter by the selected segment type
        let targetWardrobeType: String
        if wardrobeType == "wishlist" {
            targetWardrobeType = itemTypeSegment == .wishlist ? "wishlist" : "closet"
        } else {
            // In closet mode, always use closet
            targetWardrobeType = "closet"
        }
        
        // Get wardrobes of the target type
        let targetWardrobes = allWardrobes.filter { $0.type == targetWardrobeType }
        
        guard !targetWardrobes.isEmpty else {
            closetItems = []
            return
        }
        
        // If we have a selected wardrobe and it matches the target type, use it
        // Otherwise, use the first wardrobe of the target type
        let wardrobeToUse: Wardrobe?
        if let selected = selectedWardrobe, selected.type == targetWardrobeType {
            wardrobeToUse = selected
        } else {
            wardrobeToUse = targetWardrobes.first
        }
        
        guard let wardrobe = wardrobeToUse else {
            closetItems = []
            return
        }
        
        // Require authentication - get userId
        guard let userId = SupabaseService.shared.currentUser?.id.uuidString else {
            closetItems = []
            return
        }
        
        let request: NSFetchRequest<Item> = Item.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.createdAt, ascending: sortAscending)]
        
        // Use the helper function to build predicate from filterModel
        let filterPredicate = makePredicate(for: filterModel, context: viewContext)
        
        // Add userId filter (CRITICAL: only show current user's items)
        let userIdPredicate = NSPredicate(format: "userId == %@", userId)
        
        // Add wardrobe filter
        let wardrobePredicate = NSPredicate(format: "ANY wardrobes == %@", wardrobe)
        
        // Add soft delete filter
        let softDeleteFilter = NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        
        // Combine predicates
        let finalPredicate: NSPredicate
        if let filter = filterPredicate {
            finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [userIdPredicate, filter, wardrobePredicate, softDeleteFilter])
        } else {
            finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [userIdPredicate, wardrobePredicate, softDeleteFilter])
        }
        
        request.predicate = finalPredicate
        
        // Ensure we fetch all results, not just a batch
        request.fetchBatchSize = 0 // 0 means no batching limit
        
        do {
            closetItems = try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch items: \(error)")
            closetItems = []
        }
    }
    
    // State for outfit creation
    @State private var outfitItems: [OutfitItem] = []
    @State private var collageSize: CGFloat = 0
    @State private var draggedItem: OutfitItem?
    @State private var showingSaveAlert = false
    @State private var showingDraftSaveAlert = false
    @State private var showingSaveDraftConfirmation = false
    @State private var selectedItemID: UUID?
    
    // Undo/Redo state
    @State private var undoStack: [CanvasState] = []
    @State private var redoStack: [CanvasState] = []
    @State private var transformInProgress = false
    
    // Initialize with optional outfit to edit, wardrobe type, and initial wardrobe
    init(outfitToEdit: Outfit? = nil, wardrobeType: String = "closet", initialWardrobe: Wardrobe? = nil) {
        self.outfitToEdit = outfitToEdit
        self.wardrobeType = wardrobeType
        _selectedWardrobe = State(initialValue: initialWardrobe)
    }
    
    // Calculate square collage dimensions
    private var squareSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let padding: CGFloat = 0
        return screenWidth - padding
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Outfit Collage Area
            outfitCollageArea
            
            // Draft and Clear Buttons
            draftAndClearButtons
            
            // Divider
            Divider()
            
            // Closet Items Grid
            closetItemsGrid
            
            Spacer()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(outfitToEdit == nil)
        .toolbar {
            ToolbarItem(placement: .principal) {
                wardrobeSelectionButton
            }
            
            ToolbarItemGroup(placement: .navigationBarLeading) {
                leadingToolbarItems
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveOutfit()
                }
                .disabled(outfitItems.isEmpty)
            }
        }
        .alert("Outfit Saved", isPresented: $showingSaveAlert) {
            Button("OK") {
                dismiss()
            }
        }
        .alert("Draft Saved", isPresented: $showingDraftSaveAlert) {
            Button("OK") {
                dismiss()
            }
        }
        .alert("Save as draft?", isPresented: $showingSaveDraftConfirmation) {
            Button("Yes") {
                saveDraft()
            }
            Button("No", role: .cancel) {
                dismiss()
            }
        }
        .sheet(isPresented: $isWardrobeSelectionPresented) {
            NavigationView {
                SingleWardrobeSelectionView(
                    selectedWardrobe: $selectedWardrobe,
                    wardrobeType: wardrobeType == "wishlist" && itemTypeSegment == .closet ? "closet" : wardrobeType
                )
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            // Set default wardrobe to first wardrobe of appropriate type
            if selectedWardrobe == nil {
                if wardrobeType == "wishlist" {
                    // In wishlist mode, default to wishlist wardrobe
                    if let firstWishlistWardrobe = allWardrobes.first(where: { $0.type == "wishlist" }) {
                        selectedWardrobe = firstWishlistWardrobe
                    }
                } else {
                    // In closet mode, default to closet wardrobe
                    if let firstWardrobe = wardrobes.first {
                        selectedWardrobe = firstWardrobe
                    }
                }
            }
            loadOutfitIfEditing()
            fetchClosetItems()
        }
        .onChange(of: selectedWardrobe) { _ in
            fetchClosetItems()
        }
        .onChange(of: wardrobes) { newWardrobes in
            // If the selected wardrobe is no longer in the list (e.g., deleted), reset to first
            if let current = selectedWardrobe, !newWardrobes.contains(current) {
                selectedWardrobe = newWardrobes.first
            }
        }
        .onChange(of: filterKey) { _ in
            fetchClosetItems()
        }
        .onChange(of: itemTypeSegment) { _ in
            // When segment changes, update selected wardrobe to match the segment type
            if wardrobeType == "wishlist" {
                let targetType = itemTypeSegment == .wishlist ? "wishlist" : "closet"
                let targetWardrobes = allWardrobes.filter { $0.type == targetType }
                if let firstWardrobe = targetWardrobes.first {
                    selectedWardrobe = firstWardrobe
                }
            }
            fetchClosetItems()
        }
    }
    
    // MARK: - Toolbar Items
    @ViewBuilder
    private var leadingToolbarItems: some View {
        // Custom back button when creating new outfit (always show to prevent UI jumping)
        if outfitToEdit == nil {
            Button {
                if !outfitItems.isEmpty {
                    showingSaveDraftConfirmation = true
                } else {
                    dismiss()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
            }
        }
    }
    
    // MARK: - Outfit Collage Area
    private var outfitCollageArea: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 0)
                .fill(Color(.systemGray6))
                .frame(width: squareSize, height: squareSize)
               /* .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )*/
                .onTapGesture { selectedItemID = nil }
            
            // Drop zone hint when empty
            if outfitItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.dashed")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Tap items below to add to your outfit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            // Outfit items
            ForEach(outfitItems.sorted(by: { $0.zIndex < $1.zIndex })) { outfitItem in
                DraggableOutfitItemView(
                    outfitItem: outfitItem,
                    collageSize: squareSize,
                    isSelected: selectedItemID == outfitItem.id,
                    onPositionChanged: { newPosition in
                        updateItemPosition(outfitItem, newPosition)
                    },
                    onScaleChanged: { newScale in
                        updateItemScale(outfitItem, newScale)
                    },
                    onRotationChanged: { newRotation in
                        updateItemRotation(outfitItem, newRotation)
                    },
                    onTransformStart: {
                        onTransformStart()
                    },
                    onTransformEnd: {
                        onTransformEnd()
                    },
                    onSelected: {
                        selectItem(outfitItem)
                    },
                    onLongPress: {
                        bringToFront(outfitItem)
                    },
                    onDelete: {
                        removeItem(outfitItem)
                    }
                )
            }
        }
    }
    
    // MARK: - Draft and Clear Buttons
    private var draftAndClearButtons: some View {
        VStack(spacing: 0) {
            /* First row: Drafts and Save Draft buttons
            if outfitToEdit == nil {
                HStack(spacing: 0) {
                    // Drafts Button
                    Button {
                        showingDraftsSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("Drafts")
                        }
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                    }
                    
                    Divider()
                        .frame(height: 20)
                    
                    // Save Draft Button
                    Button {
                        saveDraft()
                    } label: {
                        Text("Save Draft")
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(outfitItems.isEmpty)
                }
            }
            
            // Second row: Undo, Redo, and Clear Buttons
            if outfitToEdit == nil {
                Divider()
            }*/
            
            HStack(spacing: 0) {
                // Filter icon
                NavigationLink(destination: ItemFilterView(filterModel: filterModel, wardrobeType: wardrobeType)) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(.primary)
                        .frame(maxWidth: 50)
                }
                
                Divider()
                
                // Sort menu
                Menu {
                    Button {
                        sortAscending = false
                        fetchClosetItems()
                    } label: {
                        Label("Newest First", systemImage: !sortAscending ? "checkmark" : "")
                    }
                    Button {
                        sortAscending = true
                        fetchClosetItems()
                    } label: {
                        Label("Oldest First", systemImage: sortAscending ? "checkmark" : "")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundColor(.primary)
                        .frame(maxWidth: 50)
                }
                
                Divider()
                
                // Clear Button (in the center)
                Button {
                    clearAllItems()
                } label: {
                    Text("Clear")
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                }
                .disabled(outfitItems.isEmpty)
                
                Divider()
                
                HStack(spacing: 2) {
                    // Undo Button
                    Button {
                        undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .foregroundColor(undoStack.isEmpty ? .gray : .primary)
                            .frame(maxWidth: 50)
                    }
                    .disabled(undoStack.isEmpty)
                    
                    // Redo Button (grouped with undo, right end)
                    Button {
                        redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .foregroundColor(redoStack.isEmpty ? .gray : .primary)
                            .frame(maxWidth: 50)
                    }
                    .disabled(redoStack.isEmpty)
                }
                
            }
            .frame(height: 15)
            .padding(.vertical)
        }
    }
    
    // MARK: - Wardrobe Selection Button
    private var wardrobeSelectionButton: some View {
        Button {
            isWardrobeSelectionPresented = true
        } label: {
            HStack(spacing: 4) {
                Text(selectedWardrobe?.name ?? "Select Wardrobe")
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
        }
    }
    
    // MARK: - Closet Items Grid
    private var closetItemsGrid: some View {
        VStack(spacing: 0) {
            // Segmented picker (only show in wishlist mode)
            if wardrobeType == "wishlist" {
                Picker("Item Type", selection: $itemTypeSegment) {
                    ForEach(ItemTypeSegment.allCases, id: \.self) { segment in
                        Text(segment.rawValue).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            
            ScrollView {
                if selectedWardrobe == nil {
                    VStack {
                        Text("Please select a wardrobe")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
                        ForEach(closetItems, id: \.objectID) { item in
                            ClosetItemView(
                                item: item,
                                isOnCanvas: outfitItems.contains(where: { $0.item.objectID == item.objectID }),
                                onTap: {
                                    addItemToOutfit(item)
                                },
                                onRemove: {
                                    removeItemFromCanvas(item)
                                }
                            )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Load Outfit for Editing
    private func loadOutfitIfEditing() {
        guard let outfit = outfitToEdit,
              let transformationData = outfit.transformationData else {
            return
        }
        
        // Decode the transformation data
        let decoder = JSONDecoder()
        guard let savedItems = try? decoder.decode([SavedOutfitItem].self, from: transformationData) else {
            return
        }
        
        // Reconstruct outfit items
        let items = outfit.items as? Set<Item> ?? []
        
        outfitItems = savedItems.compactMap { savedItem in
            // Find the matching item
            guard let item = items.first(where: { $0.objectID.uriRepresentation().absoluteString == savedItem.itemID }) else {
                return nil
            }
            
            return OutfitItem(
                item: item,
                position: CGPoint(x: savedItem.positionX, y: savedItem.positionY),
                scale: savedItem.scale,
                rotation: savedItem.rotation,
                zIndex: savedItem.zIndex
            )
        }
    }
    
    // MARK: - Undo/Redo Functions
    private func saveState() {
        let snapshots = outfitItems.map { outfitItem in
            CanvasStateSnapshot(
                itemID: outfitItem.item.objectID.uriRepresentation().absoluteString,
                outfitItemID: outfitItem.id,
                positionX: outfitItem.position.x,
                positionY: outfitItem.position.y,
                scale: outfitItem.scale,
                rotation: outfitItem.rotation,
                zIndex: outfitItem.zIndex
            )
        }
        undoStack.append(CanvasState(snapshots: snapshots))
        redoStack.removeAll() // Clear redo stack when new action is performed
    }
    
    private func undo() {
        guard !undoStack.isEmpty else { return }
        
        // Save current state to redo stack
        let currentSnapshots = outfitItems.map { outfitItem in
            CanvasStateSnapshot(
                itemID: outfitItem.item.objectID.uriRepresentation().absoluteString,
                outfitItemID: outfitItem.id,
                positionX: outfitItem.position.x,
                positionY: outfitItem.position.y,
                scale: outfitItem.scale,
                rotation: outfitItem.rotation,
                zIndex: outfitItem.zIndex
            )
        }
        redoStack.append(CanvasState(snapshots: currentSnapshots))
        
        // Restore previous state
        let previousState = undoStack.removeLast()
        restoreState(previousState)
    }
    
    private func redo() {
        guard !redoStack.isEmpty else { return }
        
        // Save current state to undo stack
        let currentSnapshots = outfitItems.map { outfitItem in
            CanvasStateSnapshot(
                itemID: outfitItem.item.objectID.uriRepresentation().absoluteString,
                outfitItemID: outfitItem.id,
                positionX: outfitItem.position.x,
                positionY: outfitItem.position.y,
                scale: outfitItem.scale,
                rotation: outfitItem.rotation,
                zIndex: outfitItem.zIndex
            )
        }
        undoStack.append(CanvasState(snapshots: currentSnapshots))
        
        // Restore next state
        let nextState = redoStack.removeLast()
        restoreState(nextState)
    }
    
    private func restoreState(_ state: CanvasState) {
        // Reconstruct outfitItems from snapshots
        outfitItems = state.snapshots.compactMap { snapshot in
            guard let url = URL(string: snapshot.itemID),
                  let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
                  let item = try? viewContext.existingObject(with: objectID) as? Item else {
                return nil
            }
            
            return OutfitItem(
                item: item,
                position: CGPoint(x: snapshot.positionX, y: snapshot.positionY),
                scale: snapshot.scale,
                rotation: snapshot.rotation,
                zIndex: snapshot.zIndex
            )
        }
    }
    
    // MARK: - Helper Functions
    private func addItemToOutfit(_ item: Item) {
        // Check if item is already in outfit
        guard !outfitItems.contains(where: { $0.item.objectID == item.objectID }) else {
            return
        }
        
        saveState()
        
        // Account for item size (120pts) - items are positioned by center, so need half size from edges
        let itemSize: CGFloat = 120
        let halfItemSize = itemSize / 2
        
        let randomX = CGFloat.random(in: halfItemSize...(squareSize - halfItemSize))
        let randomY = CGFloat.random(in: halfItemSize...(squareSize - halfItemSize))
        
        let outfitItem = OutfitItem(
            item: item,
            position: CGPoint(x: randomX, y: randomY),
            scale: 1.0,
            rotation: 0.0,
            zIndex: outfitItems.count
        )
        
        withAnimation(.spring()) {
            outfitItems.append(outfitItem)
        }
    }
    
    private func updateItemPosition(_ outfitItem: OutfitItem, _ newPosition: CGPoint) {
        if let index = outfitItems.firstIndex(where: { $0.id == outfitItem.id }) {
            outfitItems[index].position = newPosition
        }
    }
    
    private func updateItemScale(_ outfitItem: OutfitItem, _ newScale: CGFloat) {
        if let index = outfitItems.firstIndex(where: { $0.id == outfitItem.id }) {
            outfitItems[index].scale = newScale
        }
    }
    
    private func updateItemRotation(_ outfitItem: OutfitItem, _ newRotation: Double) {
        if let index = outfitItems.firstIndex(where: { $0.id == outfitItem.id }) {
            outfitItems[index].rotation = newRotation
        }
    }
    
    // Called when transform gesture starts
    private func onTransformStart() {
        if !transformInProgress {
            transformInProgress = true
            saveState()
        }
    }
    
    // Called when transform gesture ends
    private func onTransformEnd() {
        transformInProgress = false
    }
    
    private func selectItem(_ outfitItem: OutfitItem) {
        selectedItemID = outfitItem.id
    }
    
    private func bringToFront(_ outfitItem: OutfitItem) {
        saveState()
        selectedItemID = nil
        let maxZIndex = outfitItems.map { $0.zIndex }.max() ?? 0
        
        if let index = outfitItems.firstIndex(where: { $0.id == outfitItem.id }) {
            outfitItems[index].zIndex = maxZIndex + 1
        }
        
        selectedItemID = outfitItem.id
    }
    
    private func removeItem(_ outfitItem: OutfitItem) {
        saveState()
        outfitItems.removeAll { $0.id == outfitItem.id }
    }
    
    private func clearAllItems() {
        saveState()
        selectedItemID = nil
        withAnimation(.spring()) {
            outfitItems.removeAll()
        }
    }
    
    private func removeItemFromCanvas(_ item: Item) {
        saveState()
        selectedItemID = nil
        withAnimation(.spring()) {
            outfitItems.removeAll { $0.item.objectID == item.objectID }
        }
    }
    
    private func saveOutfit() {
        selectedItemID = nil
        
        guard let collageImage = captureCollageAsImage() else {
            print("Failed to capture collage image")
            return
        }
        
        // Use existing outfit if editing, or create new one
        let outfit = outfitToEdit ?? Outfit(context: viewContext)
        
        if outfitToEdit == nil {
            outfit.id = UUID()
        }
        let now = Date()
        outfit.timestamp = now
        outfit.createdAt = now
        
        // Save the collage image (compressed)
        if let imageData = collageImage.processForStorage() {
            outfit.image = imageData
        }
        
        // Clear existing items if editing
        if outfitToEdit != nil {
            outfit.removeFromItems(outfit.items ?? NSSet())
        }
        
        // Add items to outfit
        for outfitItem in outfitItems {
            outfit.addToItems(outfitItem.item)
        }
        
        // Save transformation data
        let savedItems = outfitItems.map { outfitItem in
            SavedOutfitItem(
                itemID: outfitItem.item.objectID.uriRepresentation().absoluteString,
                positionX: outfitItem.position.x,
                positionY: outfitItem.position.y,
                scale: outfitItem.scale,
                rotation: outfitItem.rotation,
                zIndex: outfitItem.zIndex
            )
        }
        
        let encoder = JSONEncoder()
        if let transformationData = try? encoder.encode(savedItems) {
            outfit.transformationData = transformationData
        }
        
        // Mark as not draft (explicitly set to false for regular outfits)
        outfit.isDraft = false
        
        // Set updatedAt if editing existing outfit
        if outfitToEdit != nil {
            setUpdatedAt(outfit)
        }
        
        do {
            try viewContext.save()
            showingSaveAlert = true
        } catch {
            print("Error saving outfit: \(error)")
        }
    }
    
    private func saveDraft() {
        selectedItemID = nil
        
        guard let collageImage = captureCollageAsImage() else {
            print("Failed to capture collage image")
            return
        }
        
        // Always create a new draft (don't edit existing outfits)
        let draft = Outfit(context: viewContext)
        draft.id = UUID()
        let now = Date()
        draft.timestamp = now
        draft.createdAt = now
        draft.isDraft = true
        
        // Save the collage image
        if let imageData = collageImage.pngData() {
            draft.image = imageData
        }
        
        // Add items to draft
        for outfitItem in outfitItems {
            draft.addToItems(outfitItem.item)
        }
        
        // Save transformation data (positioning information)
        let savedItems = outfitItems.map { outfitItem in
            SavedOutfitItem(
                itemID: outfitItem.item.objectID.uriRepresentation().absoluteString,
                positionX: outfitItem.position.x,
                positionY: outfitItem.position.y,
                scale: outfitItem.scale,
                rotation: outfitItem.rotation,
                zIndex: outfitItem.zIndex
            )
        }
        
        let encoder = JSONEncoder()
        if let transformationData = try? encoder.encode(savedItems) {
            draft.transformationData = transformationData
        }
        
        do {
            try viewContext.save()
            showingDraftSaveAlert = true
        } catch {
            print("Error saving draft: \(error)")
        }
    }
    
    private func captureCollageAsImage() -> UIImage? {
        let collageView = ZStack {
            Color(red: 247/255, green: 247/255, blue: 247/255)
                    .ignoresSafeArea()
            // gray background color of outfits
            ForEach(outfitItems.sorted(by: { $0.zIndex < $1.zIndex })) { outfitItem in
                DraggableOutfitItemView(
                    outfitItem: outfitItem,
                    collageSize: squareSize,
                    isSelected: false,
                    onPositionChanged: { _ in },
                    onScaleChanged: { _ in },
                    onRotationChanged: { _ in },
                    onTransformStart: {},
                    onTransformEnd: {},
                    onSelected: {},
                    onLongPress: {},
                    onDelete: {}
                )
            }
        }
        .frame(width: squareSize, height: squareSize)

        let hostingController = UIHostingController(rootView: collageView)
        hostingController.sizingOptions = .intrinsicContentSize
        hostingController.view.insetsLayoutMarginsFromSafeArea = false
        hostingController.view.frame = CGRect(origin: .zero, size: CGSize(width: squareSize, height: squareSize))
        hostingController.view.backgroundColor = .clear
        hostingController.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: squareSize, height: squareSize))
        return renderer.image { context in
            hostingController.view.drawHierarchy(in: hostingController.view.bounds, afterScreenUpdates: true)
        }
    }
}

// MARK: - Saved Outfit Item Model (for JSON encoding)
struct SavedOutfitItem: Codable {
    let itemID: String
    let positionX: CGFloat
    let positionY: CGFloat
    let scale: CGFloat
    let rotation: Double
    let zIndex: Int
}

// MARK: - Canvas State Snapshot (for undo/redo)
struct CanvasStateSnapshot: Codable {
    let itemID: String
    let outfitItemID: UUID
    let positionX: CGFloat
    let positionY: CGFloat
    let scale: CGFloat
    let rotation: Double
    let zIndex: Int
}

struct CanvasState {
    let snapshots: [CanvasStateSnapshot]
}

// MARK: - OutfitItem Model
struct OutfitItem: Identifiable {
    let id = UUID()
    let item: Item
    var position: CGPoint
    var scale: CGFloat
    var rotation: Double
    var zIndex: Int
}

// MARK: - Draggable Outfit Item View
struct DraggableOutfitItemView: View {
    let outfitItem: OutfitItem
    let collageSize: CGFloat
    let isSelected: Bool
    let onPositionChanged: (CGPoint) -> Void
    let onScaleChanged: (CGFloat) -> Void
    let onRotationChanged: (Double) -> Void
    let onTransformStart: () -> Void
    let onTransformEnd: () -> Void
    let onSelected: () -> Void
    let onLongPress: () -> Void
    let onDelete: () -> Void
    
    @State private var imageSize: CGSize = CGSize(width: 120, height: 120)
    @State private var dragOffset = CGSize.zero
    @State private var position: CGPoint
    @State private var scale: CGFloat
    @State private var baseScale: CGFloat
    @State private var rotation: Double
    @State private var baseRotation: Double
    
    private let itemSize: CGFloat = 120
    private let deleteButtonSize: CGFloat = 24
    
    init(outfitItem: OutfitItem, collageSize: CGFloat, isSelected: Bool, onPositionChanged: @escaping (CGPoint) -> Void, onScaleChanged: @escaping (CGFloat) -> Void, onRotationChanged: @escaping (Double) -> Void, onTransformStart: @escaping () -> Void, onTransformEnd: @escaping () -> Void, onSelected: @escaping () -> Void, onLongPress: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.outfitItem = outfitItem
        self.collageSize = collageSize
        self.isSelected = isSelected
        self.onPositionChanged = onPositionChanged
        self.onScaleChanged = onScaleChanged
        self.onRotationChanged = onRotationChanged
        self.onTransformStart = onTransformStart
        self.onTransformEnd = onTransformEnd
        self.onSelected = onSelected
        self.onLongPress = onLongPress
        self.onDelete = onDelete
        self._position = State(initialValue: outfitItem.position)
        self._scale = State(initialValue: outfitItem.scale)
        self._baseScale = State(initialValue: outfitItem.scale)
        self._rotation = State(initialValue: outfitItem.rotation)
        self._baseRotation = State(initialValue: outfitItem.rotation)
    }
    
    // Calculate the absolute position of the delete button (top-right corner after rotation)
    private var deleteButtonPosition: CGPoint {
        let halfWidth = (imageSize.width * scale) / 2
        let halfHeight = (imageSize.height * scale) / 2
        let rotationRadians = rotation * .pi / 180.0
        
        // Top-right corner before rotation
        let x = halfWidth * cos(rotationRadians) - (-halfHeight) * sin(rotationRadians)
        let y = halfWidth * sin(rotationRadians) + (-halfHeight) * cos(rotationRadians)
        
        return CGPoint(
            x: position.x + dragOffset.width + x,
            y: position.y + dragOffset.height + y
        )
    }
    
    var body: some View {
        ZStack {
            // Item image with border - wrapped together
            Group {
                if let primaryPhoto = (outfitItem.item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
                   let photoData = primaryPhoto.data,
                   let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: imageSize.width, height: imageSize.height)
                        .overlay(
                            isSelected ?
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
                            : nil
                        )
                        .onAppear {
                            print("🖼️ Original UIImage size: width=\(uiImage.size.width), height=\(uiImage.size.height)")
                            imageSize = calculateImageSize(for: uiImage)
                            print("📐 Calculated imageSize for display: width=\(imageSize.width), height=\(imageSize.height)")
                        }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: itemSize, height: itemSize)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        )
                        .overlay(
                            isSelected ?
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
                            : nil
                        )
                }
            }
            .scaleEffect(scale)
            .rotationEffect(Angle.degrees(rotation))
            .position(x: position.x + dragOffset.width, y: position.y + dragOffset.height)
            .onTapGesture {
                onSelected()
            }
            .onLongPressGesture {
                onLongPress()
            }
            .gesture(
                isSelected ? DragGesture()
                    .onChanged { value in
                        if dragOffset == .zero && value.translation != .zero {
                            onTransformStart()
                        }
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        let scaledItemSize = itemSize * scale
                        let newX = max(scaledItemSize/2, min(collageSize - scaledItemSize/2, position.x + value.translation.width))
                        let newY = max(scaledItemSize/2, min(collageSize - scaledItemSize/2, position.y + value.translation.height))
                        
                        let newPosition = CGPoint(x: newX, y: newY)
                        position = newPosition
                        dragOffset = .zero
                        
                        onPositionChanged(newPosition)
                        onTransformEnd()
                    } : nil
            )
            .gesture(
                isSelected ?
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if abs(value - 1.0) > 0.01 && abs(scale - baseScale) < 0.01 {
                                onTransformStart()
                            }
                            scale = max(0.5, min(3.0, baseScale * value))
                        }
                        .onEnded { value in
                            let finalScale = max(0.5, min(3.0, baseScale * value))
                            scale = finalScale
                            baseScale = finalScale
                            onScaleChanged(finalScale)
                            onTransformEnd()
                        },
                    RotationGesture()
                        .onChanged { value in
                            if abs(value.degrees) > 1.0 && abs(rotation - baseRotation) < 1.0 {
                                onTransformStart()
                            }
                            rotation = baseRotation + value.degrees
                        }
                        .onEnded { value in
                            let finalRotation = baseRotation + value.degrees
                            rotation = finalRotation
                            baseRotation = finalRotation
                            onRotationChanged(finalRotation)
                            onTransformEnd()
                        }
                ) : nil
            )
            
            // Delete button - positioned independently in absolute coordinates
            if isSelected {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .frame(width: deleteButtonSize, height: deleteButtonSize)
                        )
                        .font(.system(size: deleteButtonSize))
                }
                .frame(width: deleteButtonSize, height: deleteButtonSize)
                .position(deleteButtonPosition)
            }
        }
        .animation(.spring(), value: dragOffset)
    }
    
    private func calculateImageSize(for image: UIImage) -> CGSize {
        let aspectRatio = image.size.height / image.size.width
        let width = itemSize
        let height = width * aspectRatio
        return CGSize(width: width, height: height)
    }
}

// MARK: - Closet Item View
struct ClosetItemView: View {
    let item: Item
    let isOnCanvas: Bool
    let onTap: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        ZStack {
            Button(action: onTap) {
                if let primaryPhoto = (item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
                   let photoData = primaryPhoto.data,
                   let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(height: 100)
                        .clipped()
                        .cornerRadius(8)
                        .colorMultiply(isOnCanvas ? .gray : .white)
                        .opacity(isOnCanvas ? 0.8 : 1.0)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(height: 100)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        )
                        .opacity(isOnCanvas ? 0.8 : 1.0)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isOnCanvas)
            
            if isOnCanvas {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onRemove) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .background(Color.white)
                                .clipShape(Circle())
                                .font(.system(size: 20))
                        }
                        .padding(4)
                    }
                    Spacer()
                }
            }
        }
    }
}


*/
