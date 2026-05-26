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

// MARK: - Smart Positioning System

enum ClothingZone {
    case headwear      // top center
    case jewelry       // top right
    case outerwear     // center right
    case top           // top left
    case bottom        // center left
    case shoes         // bottom center
    case accessories   // bottom right
    case bag           // middle right

    func basePosition(canvasSize: CGFloat) -> CGPoint {
        let third = canvasSize / 3
        let half = canvasSize / 2

        switch self {
        case .headwear:    return CGPoint(x: half,          y: third * 0.5)
        case .jewelry:     return CGPoint(x: third * 2.5,   y: third * 0.7)
        case .outerwear:   return CGPoint(x: third * 2.3,   y: half)
        case .top:         return CGPoint(x: third * 0.7,   y: third * 0.8)
        case .bottom:      return CGPoint(x: third * 0.7,   y: third * 1.8)
        case .shoes:       return CGPoint(x: half,          y: third * 2.5)
        case .accessories: return CGPoint(x: third * 2.3,   y: third * 2.3)
        case .bag:         return CGPoint(x: third * 2.5,   y: third * 1.5)
        }
    }
}

struct OutfitAddView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSession

    // Optional outfit for editing
    let outfitToEdit: Outfit?

    // Wardrobe type to filter by (closet or wishlist)
    let wardrobeType: String

    /// When true, item source wardrobe is fixed (non-default closet context); no wardrobe picker sheet.
    let lockWardrobeSource: Bool

    /// If provided, this item will be resolved and placed on the canvas on first appear.
    let preselectedItemURI: String?
    
    /// Forces a unique view identity per creation session (prevents @State reuse).
    let sessionID: UUID

    // Fetch all wardrobes (we'll filter by type)
    @FetchRequest(
        entity: Wardrobe.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.name, ascending: true)]
    ) private var allWardrobes: FetchedResults<Wardrobe>

    // Current user's id — used to filter wardrobe lists throughout this view
    private var currentUserId: String? { authSession.userId?.uuidString }

    // Filter wardrobes by type, excluding soft-deleted and unowned wardrobes
    private var wardrobes: [Wardrobe] {
        allWardrobes.filter {
            $0.type == wardrobeType &&
            $0.isSoftDeleted != true &&
            (currentUserId == nil || $0.userId == currentUserId)
        }
    }

    // Get wardrobes for the currently selected segment (when in wishlist mode)
    private var currentSegmentWardrobes: [Wardrobe] {
        if wardrobeType == "wishlist" {
            let segmentType = itemTypeSegment == .wishlist ? "wishlist" : "closet"
            return allWardrobes.filter {
                $0.type == segmentType &&
                $0.isSoftDeleted != true &&
                (currentUserId == nil || $0.userId == currentUserId)
            }
        } else {
            return wardrobes
        }
    }

    // Selected wardrobe for filtering items
    @State private var selectedWardrobe: Wardrobe?
    @State private var isWardrobeSelectionPresented = false
    @State private var closetItems: [Item] = []
    @StateObject private var filterModel = ItemFilterModel()
    @State private var sortAscending: Bool = false

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
        key += filterModel.selectedWardrobes.map { $0.objectID.uriRepresentation().absoluteString }.sorted().joined(separator: ",")
        key += selectedWardrobe?.objectID.uriRepresentation().absoluteString ?? ""
        return key
    }

    // Fetch items filtered by selected wardrobe
    private func fetchClosetItems() {
        guard let userId = currentUserId, !userId.isEmpty else {
            closetItems = []
            return
        }

        let targetWardrobeType: String
        if wardrobeType == "wishlist" {
            targetWardrobeType = itemTypeSegment == .wishlist ? "wishlist" : "closet"
        } else {
            targetWardrobeType = "closet"
        }

        let targetWardrobes = allWardrobes.filter {
            $0.type == targetWardrobeType &&
            $0.isSoftDeleted != true &&
            $0.userId == userId
        }

        guard !targetWardrobes.isEmpty else {
            closetItems = []
            return
        }

        let wardrobe: Wardrobe
        if let selected = selectedWardrobe,
           targetWardrobes.contains(where: { $0.objectID == selected.objectID }) {
            wardrobe = selected
        } else if let primary = WardrobeBootstrap.primaryWardrobe(in: targetWardrobes) {
            wardrobe = primary
        } else {
            closetItems = []
            return
        }

        let request: NSFetchRequest<Item> = Item.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.createdAt, ascending: sortAscending)]
        request.fetchBatchSize = 0

        var subpredicates: [NSPredicate] = [
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "ANY wardrobes == %@", wardrobe),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil"),
            NSPredicate(format: "isDraft != YES"),
        ]

        let filteredWardrobes = filterModel.selectedWardrobes.filter {
            $0.type == targetWardrobeType && $0.userId == userId
        }
        if !filteredWardrobes.isEmpty {
            subpredicates.append(NSPredicate(format: "ANY wardrobes IN %@", Array(filteredWardrobes)))
        }

        if let filter = makePredicate(for: filterModel, context: viewContext) {
            subpredicates.append(filter)
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)

        do {
            let results = try viewContext.fetch(request)
            let wardrobeID = wardrobe.objectID
            closetItems = results.filter { item in
                guard let wardrobes = item.wardrobes as? Set<Wardrobe> else { return false }
                return wardrobes.contains { $0.objectID == wardrobeID }
            }
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
    @State private var showingDiscardChangesConfirmation = false
    @State private var selectedItemID: UUID?

    // Drafts folder — sheet-based to avoid navigation conflict
    @State private var showingDraftsSheet = false
    @State private var selectedDraftToEdit: Outfit? = nil
    @State private var showingDraftEditor = false

    // Manual override positions — when user drags, their position takes priority
    @State private var manualOverrides: [UUID: CGPoint] = [:]

    // Undo/Redo state
    @State private var undoStack: [CanvasState] = []
    @State private var redoStack: [CanvasState] = []
    @State private var transformInProgress = false
    @State private var canvasPinchBaseScale: CGFloat = 1.0
    @State private var canvasRotateBaseRotation: Double = 0.0

    @State private var didApplyPreselectedItem = false

    init(
        outfitToEdit: Outfit? = nil,
        wardrobeType: String = "closet",
        initialWardrobe: Wardrobe? = nil,
        lockWardrobeSource: Bool = false
    ) {
        self.outfitToEdit = outfitToEdit
        self.wardrobeType = wardrobeType
        self.lockWardrobeSource = lockWardrobeSource
        _selectedWardrobe = State(initialValue: initialWardrobe)
        self.preselectedItemURI = nil
        self.sessionID = UUID()
    }
    
    init(
        outfitToEdit: Outfit? = nil,
        wardrobeType: String = "closet",
        initialWardrobe: Wardrobe? = nil,
        lockWardrobeSource: Bool = false,
        preselectedItemURI: String?,
        sessionID: UUID = UUID()
    ) {
        self.outfitToEdit = outfitToEdit
        self.wardrobeType = wardrobeType
        self.lockWardrobeSource = lockWardrobeSource
        _selectedWardrobe = State(initialValue: initialWardrobe)
        self.preselectedItemURI = preselectedItemURI
        self.sessionID = sessionID
    }

    private var squareSize: CGFloat {
        UIScreen.main.bounds.width
    }

    private var wardrobeSelectionSheetPresented: Binding<Bool> {
        Binding(
            get: { !lockWardrobeSource && isWardrobeSelectionPresented },
            set: { isWardrobeSelectionPresented = $0 }
        )
    }

    var body: some View {
        sheetsContent
            .onAppear {
                print("👗 [OutfitAddView] onAppear. sessionID=\(sessionID.uuidString) outfitToEdit=\(outfitToEdit != nil) wardrobeType=\(wardrobeType) preselectedItemURI=\(preselectedItemURI ?? "nil")")
                
                if selectedWardrobe == nil {
                    if wardrobeType == "wishlist" {
                        let wish = allWardrobes.filter {
                            $0.type == "wishlist" &&
                            $0.isSoftDeleted != true &&
                            (currentUserId == nil || $0.userId == currentUserId)
                        }
                        selectedWardrobe = WardrobeBootstrap.primaryWardrobe(in: wish)
                    } else {
                        selectedWardrobe = WardrobeBootstrap.primaryWardrobe(in: wardrobes)
                    }
                }
                
                if !didApplyPreselectedItem, let uriString = preselectedItemURI {
                    didApplyPreselectedItem = true
                    print("👗 [OutfitAddView] Attempting to resolve preselected item. uri=\(uriString)")
                    if let url = URL(string: uriString),
                       let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url) {
                        do {
                            if let resolvedItem = try viewContext.existingObject(with: objectID) as? Item {
                                print("👗 [OutfitAddView] Resolved preselected item. objectID=\(objectID) itemID=\(resolvedItem.id?.uuidString ?? "nil")")
                                addItemToOutfit(resolvedItem)
                                print("👗 [OutfitAddView] Added preselected item to canvas. outfitItemsCount=\(outfitItems.count)")
                            } else {
                                print("❌ [OutfitAddView] Resolved object was not an Item. objectID=\(objectID)")
                            }
                        } catch {
                            print("❌ [OutfitAddView] Failed to resolve preselected item via existingObject. error=\(error)")
                        }
                    } else {
                        print("❌ [OutfitAddView] Invalid preselected item URI or could not create objectID. uri=\(uriString)")
                    }
                }
                
                loadOutfitIfEditing()
                fetchClosetItems()
                print("👗 [OutfitAddView] Finished onAppear work. closetItemsCount=\(closetItems.count) outfitItemsCount=\(outfitItems.count)")
            }
            .onChange(of: selectedWardrobe) { _ in fetchClosetItems() }
            .onChange(of: wardrobes) { newWardrobes in
                guard !lockWardrobeSource else { return }
                if let current = selectedWardrobe, !newWardrobes.contains(current) {
                    selectedWardrobe = WardrobeBootstrap.primaryWardrobe(in: newWardrobes)
                }
            }
            .onChange(of: filterKey) { _ in fetchClosetItems() }
            .onChange(of: itemTypeSegment) { _ in
                if wardrobeType == "wishlist", !lockWardrobeSource {
                    let targetType = itemTypeSegment == .wishlist ? "wishlist" : "closet"
                    let targetWardrobes = allWardrobes.filter {
                        $0.type == targetType &&
                        $0.isSoftDeleted != true &&
                        (currentUserId == nil || $0.userId == currentUserId)
                    }
                    selectedWardrobe = WardrobeBootstrap.primaryWardrobe(in: targetWardrobes)
                }
                fetchClosetItems()
            }
    }

    // MARK: - Body Sub-expressions
    // Split to keep the type-checker happy (too many chained modifiers in one expression).

    private var sheetsContent: some View {
        alertsContent
            .sheet(isPresented: wardrobeSelectionSheetPresented) {
                NavigationView {
                    SingleWardrobeSelectionView(
                        selectedWardrobe: $selectedWardrobe,
                        wardrobeType: wardrobeType == "wishlist" && itemTypeSegment == .closet ? "closet" : wardrobeType
                    )
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingDraftsSheet) {
                NavigationView {
                    OutfitDraftsView(
                        wardrobeType: wardrobeType,
                        selectedWardrobe: selectedWardrobe,
                        onSelectDraft: { draft in
                            showingDraftsSheet = false
                            selectedDraftToEdit = draft
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                showingDraftEditor = true
                            }
                        }
                    )
                }
            }
            .sheet(isPresented: $showingDraftEditor, onDismiss: { selectedDraftToEdit = nil }) {
                if let draft = selectedDraftToEdit {
                    NavigationView {
                        OutfitAddView(
                            outfitToEdit: draft,
                            wardrobeType: wardrobeType,
                            initialWardrobe: selectedWardrobe,
                            lockWardrobeSource: lockWardrobeSource
                        )
                    }
                }
            }
    }

    private var alertsContent: some View {
        VStack(spacing: 0) {
            outfitCollageArea
            draftAndClearButtons
            Divider()
            closetItemsGrid
            Spacer()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                wardrobeSelectionButton
            }
            ToolbarItemGroup(placement: .navigationBarLeading) {
                leadingToolbarItems
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if outfitToEdit == nil {
                        Button {
                            showingDraftsSheet = true
                        } label: {
                            Image(systemName: "folder")
                        }
                    }
                    Button("Save") {
                        saveOutfit()
                    }
                    .disabled(outfitItems.isEmpty)
                }
            }
        }
        .alert("Outfit Saved", isPresented: $showingSaveAlert) {
            Button("OK") { dismiss() }
        }
        .alert("Draft Saved", isPresented: $showingDraftSaveAlert) {
            Button("OK") { dismiss() }
        }
        .alert("Save draft?", isPresented: $showingSaveDraftConfirmation) {
            Button("Yes") { saveDraft() }
            Button("No", role: .cancel) { dismiss() }
        } message: {
            Text("Saving this outfit to drafts will allow you to finish editing it later.")
        }
        .alert("Discard Changes?", isPresented: $showingDiscardChangesConfirmation) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) { }
        } message: {
            Text("Your changes to this outfit will not be saved.")
        }
    }

    // MARK: - Toolbar Items
    @ViewBuilder
    private var leadingToolbarItems: some View {
        Button {
            if outfitToEdit != nil && !undoStack.isEmpty {
                // Editing with unsaved changes — confirm discard
                showingDiscardChangesConfirmation = true
            } else if !outfitItems.isEmpty && outfitToEdit == nil {
                // Creating with items on canvas — offer draft save
                showingSaveDraftConfirmation = true
            } else {
                dismiss()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text(outfitToEdit != nil ? "Cancel" : "Back")
            }
        }
    }

    // MARK: - Outfit Collage Area

    private var selectedOutfitItemIndex: Int? {
        guard let selectedItemID else { return nil }
        return outfitItems.firstIndex(where: { $0.id == selectedItemID })
    }

    private var canvasTransformGesture: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    guard let index = selectedOutfitItemIndex else { return }
                    if !transformInProgress {
                        canvasPinchBaseScale = outfitItems[index].scale
                        canvasRotateBaseRotation = outfitItems[index].rotation
                        onTransformStart()
                    }
                    applyScale(max(0.3, min(4.0, canvasPinchBaseScale * value)), at: index)
                }
                .onEnded { value in
                    guard let index = selectedOutfitItemIndex else { return }
                    applyScale(max(0.3, min(4.0, canvasPinchBaseScale * value)), at: index)
                    onTransformEnd()
                },
            RotationGesture()
                .onChanged { value in
                    guard let index = selectedOutfitItemIndex else { return }
                    if !transformInProgress {
                        canvasPinchBaseScale = outfitItems[index].scale
                        canvasRotateBaseRotation = outfitItems[index].rotation
                        onTransformStart()
                    }
                    applyRotation(canvasRotateBaseRotation + value.degrees, at: index)
                }
                .onEnded { value in
                    guard let index = selectedOutfitItemIndex else { return }
                    applyRotation(canvasRotateBaseRotation + value.degrees, at: index)
                    onTransformEnd()
                }
        )
    }

    @ViewBuilder
    private var outfitCollageArea: some View {
        let canvas = ZStack {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color(.systemGray6))
                .frame(width: squareSize, height: squareSize)
                .onTapGesture { selectedItemID = nil }

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

            ForEach(outfitItems.sorted(by: { $0.zIndex < $1.zIndex })) { outfitItem in
                AdaptiveOutfitItemView(
                    outfitItem: outfitItem,
                    canvasSize: squareSize,
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
                    onTransformStart: { onTransformStart() },
                    onTransformEnd: { onTransformEnd() },
                    onSelected: { selectItem(outfitItem) },
                    onLongPress: { bringToFront(outfitItem) },
                    onDelete: { removeItem(outfitItem) }
                )
            }
        }
        .frame(width: squareSize, height: squareSize)

        if selectedItemID != nil {
            canvas.simultaneousGesture(canvasTransformGesture)
        } else {
            canvas
        }
    }

    // MARK: - Draft and Clear Buttons
    private var draftAndClearButtons: some View {
        VStack(spacing: 0) {
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
                        if !sortAscending {
                            Label("Newest First", systemImage: "checkmark")
                        } else {
                            Text("Newest First")
                        }
                    }
                    Button {
                        sortAscending = true
                        fetchClosetItems()
                    } label: {
                        if sortAscending {
                            Label("Oldest First", systemImage: "checkmark")
                        } else {
                            Text("Oldest First")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundColor(.primary)
                        .frame(maxWidth: 50)
                }

                Divider()

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
                    Button {
                        undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .foregroundColor(undoStack.isEmpty ? .gray : .primary)
                            .frame(maxWidth: 50)
                    }
                    .disabled(undoStack.isEmpty)

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
    @ViewBuilder
    private var wardrobeSelectionButton: some View {
        if lockWardrobeSource {
            Text(selectedWardrobe?.name ?? "Wardrobe")
                .font(.headline)
        } else {
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
    }

    // MARK: - Closet Items Grid
    private var closetItemsGrid: some View {
        VStack(spacing: 0) {
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
                                onTap: { addItemToOutfit(item) },
                                onRemove: { removeItemFromCanvas(item) }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Load Outfit for Editing
    private func loadOutfitIfEditing() {
        print("🔍 loadOutfitIfEditing called")
        
        guard let outfit = outfitToEdit else {
            print("🔍 No outfit to edit — skipping load")
            return
        }
        print("🔍 outfitToEdit id=\(outfit.id?.uuidString ?? "nil"), items count=\((outfit.items?.count ?? 0))")
        
        guard let transformationData = outfit.transformationData else {
            print("🔍 No transformationData — will load items without position data")
            // Fallback: load items at default positions so the canvas isn't empty
            let items = outfit.items as? Set<Item> ?? []
            print("🔍 Fallback: loading \(items.count) items without transformation data")
            outfitItems = items.enumerated().map { i, item in
                let center = CGPoint(x: squareSize / 2, y: squareSize / 2)
                let bounds = PhotoContentBounds.contentBounds(for: item)
                return OutfitItem(
                    item: item,
                    position: center,
                    displaySize: OutfitItem.defaultDisplaySize(canvasSize: squareSize, contentAspect: bounds.aspectRatio),
                    scale: 1.0,
                    rotation: 0.0,
                    zIndex: i,
                    contentBounds: bounds
                )
            }
            return
        }
        
        print("🔍 transformationData size=\(transformationData.count) bytes")
        
        let decoder = JSONDecoder()
        guard let savedItems = try? decoder.decode([SavedOutfitItem].self, from: transformationData) else {
            print("❌ Failed to decode transformationData")
            if let raw = String(data: transformationData, encoding: .utf8) {
                print("❌ Raw transformationData: \(raw)")
            }
            return
        }
        print("🔍 Decoded \(savedItems.count) saved items")
        
        let items = outfit.items as? Set<Item> ?? []
        print("🔍 Outfit has \(items.count) items in Core Data")
        
        outfitItems = savedItems.compactMap { savedItem in
            print("🔍   Looking for itemID=\(savedItem.itemID)")
            guard let item = items.first(where: {
                $0.id?.uuidString == savedItem.itemID ||
                $0.objectID.uriRepresentation().absoluteString == savedItem.itemID
            }) else {
                print("⚠️   No matching item found for itemID=\(savedItem.itemID)")
                return nil
            }
            print("🔍   Matched item: \(item.id?.uuidString ?? "no-uuid")")
            let bounds = PhotoContentBounds.contentBounds(for: item)
            return OutfitItem(
                item: item,
                position: CGPoint(x: savedItem.positionX, y: savedItem.positionY),
                displaySize: OutfitItem.defaultDisplaySize(canvasSize: squareSize, contentAspect: bounds.aspectRatio),
                scale: savedItem.scale,
                rotation: savedItem.rotation,
                zIndex: savedItem.zIndex,
                contentBounds: bounds
            )
        }
        print("🔍 Loaded \(outfitItems.count) outfitItems onto canvas")
    }

    // MARK: - Undo/Redo Functions
    private func saveState() {
        let snapshots = outfitItems.map { outfitItem -> CanvasStateSnapshot in
            return CanvasStateSnapshot(
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
        redoStack.removeAll()
    }

    private func undo() {
        guard !undoStack.isEmpty else { return }
        let currentSnapshots = outfitItems.map { outfitItem -> CanvasStateSnapshot in
            return CanvasStateSnapshot(
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
        let previousState = undoStack.removeLast()
        restoreState(previousState)
    }

    private func redo() {
        guard !redoStack.isEmpty else { return }
        let currentSnapshots = outfitItems.map { outfitItem -> CanvasStateSnapshot in
            return CanvasStateSnapshot(
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
        let nextState = redoStack.removeLast()
        restoreState(nextState)
    }

    private func restoreState(_ state: CanvasState) {
        outfitItems = state.snapshots.compactMap { snapshot in
            guard let url = URL(string: snapshot.itemID),
                  let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
                  let item = try? viewContext.existingObject(with: objectID) as? Item else { return nil }

            let bounds = PhotoContentBounds.contentBounds(for: item)
            return OutfitItem(
                item: item,
                position: CGPoint(x: snapshot.positionX, y: snapshot.positionY),
                displaySize: OutfitItem.defaultDisplaySize(canvasSize: squareSize, contentAspect: bounds.aspectRatio),
                scale: snapshot.scale,
                rotation: snapshot.rotation,
                zIndex: snapshot.zIndex,
                contentBounds: bounds
            )
        }
    }

    // MARK: - Helper Functions
    private func addItemToOutfit(_ item: Item) {
        guard !outfitItems.contains(where: { $0.item.objectID == item.objectID }) else { return }
        saveState()

        let center = CGPoint(x: squareSize / 2, y: squareSize / 2)
        let bounds = PhotoContentBounds.contentBounds(for: item)
        let outfitItem = OutfitItem(
            item: item,
            position: center,
            displaySize: OutfitItem.defaultDisplaySize(canvasSize: squareSize, contentAspect: bounds.aspectRatio),
            scale: 1.0,
            rotation: 0.0,
            zIndex: outfitItems.count,
            contentBounds: bounds
        )

        outfitItems.append(outfitItem)
        selectedItemID = outfitItem.id
    }

    private func applyScale(_ scale: CGFloat, at index: Int) {
        var item = outfitItems[index]
        item.scale = scale
        outfitItems[index] = item
    }

    private func applyRotation(_ rotation: Double, at index: Int) {
        var item = outfitItems[index]
        item.rotation = rotation
        outfitItems[index] = item
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

    private func onTransformStart() {
        if !transformInProgress {
            transformInProgress = true
            saveState()
        }
    }

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

        let outfit = outfitToEdit ?? Outfit(context: viewContext)

        if outfitToEdit == nil {
            outfit.id = UUID()
            outfit.userId = authSession.userId?.uuidString
            let now = Date()
            outfit.timestamp = now
            outfit.createdAt = now
        }

        if let imageData = collageImage.processForStorage() {
            outfit.image = imageData
        }

        if outfitToEdit != nil {
            outfit.removeFromItems(outfit.items ?? NSSet())
        }

        for outfitItem in outfitItems {
            outfit.addToItems(outfitItem.item)
        }

        let savedItems = outfitItems.map { outfitItem -> SavedOutfitItem in
            return SavedOutfitItem(
                itemID: outfitItem.item.id?.uuidString ?? "",
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

        outfit.isDraft = false
        setUpdatedAt(outfit)

        do {
            try viewContext.save()
            SyncService.shared.syncOutfitIfNeeded(outfit)
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

        let draft = Outfit(context: viewContext)
        draft.id = UUID()
        draft.userId = authSession.userId?.uuidString
        let now = Date()
        draft.timestamp = now
        draft.createdAt = now
        draft.isDraft = true

        if let imageData = collageImage.pngData() {
            draft.image = imageData
        }

        for outfitItem in outfitItems {
            draft.addToItems(outfitItem.item)
        }

        let savedItems = outfitItems.map { outfitItem -> SavedOutfitItem in
            return SavedOutfitItem(
                itemID: outfitItem.item.id?.uuidString ?? "",
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
            SyncService.shared.syncOutfitIfNeeded(draft)
            showingDraftSaveAlert = true
        } catch {
            print("Error saving draft: \(error)")
        }
    }

    private func captureCollageAsImage() -> UIImage? {
        let size = squareSize

        let captureView = Canvas { ctx, _ in
            for outfitItem in outfitItems.sorted(by: { $0.zIndex < $1.zIndex }) {
                guard let primaryPhoto = (outfitItem.item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
                      let photoData = primaryPhoto.data,
                      let uiImage = UIImage(data: photoData) else { continue }

                let center = outfitItem.position
                let scaledW = outfitItem.displaySize.width * outfitItem.scale
                let scaledH = outfitItem.displaySize.height * outfitItem.scale

                ctx.translateBy(x: center.x, y: center.y)
                ctx.rotate(by: Angle.degrees(outfitItem.rotation))

                let drawImage = uiImage.cropped(toNormalizedBounds: outfitItem.contentBounds) ?? uiImage
                let drawRect = CGRect(x: -scaledW / 2, y: -scaledH / 2, width: scaledW, height: scaledH)
                ctx.draw(Image(uiImage: drawImage).resizable(), in: drawRect)

                // Reset transform for next item
                ctx.rotate(by: Angle.degrees(-outfitItem.rotation))
                ctx.translateBy(x: -center.x, y: -center.y)
            }
        }
       // .background(Color(red: 247/255, green: 247/255, blue: 247/255))
        .frame(width: size, height: size)

        let renderer = ImageRenderer(content: captureView)
        renderer.scale = UIScreen.main.scale  // render at full device resolution
        return renderer.uiImage
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
    /// Tight cutout size at scale 1.0; position is the center point on canvas.
    let displaySize: CGSize
    var scale: CGFloat
    var rotation: Double
    var zIndex: Int
    let contentBounds: NormalizedContentBounds
    var contentAspect: CGFloat { contentBounds.aspectRatio }

    init(
        item: Item,
        position: CGPoint,
        displaySize: CGSize,
        scale: CGFloat,
        rotation: Double,
        zIndex: Int,
        contentBounds: NormalizedContentBounds? = nil
    ) {
        self.item = item
        self.position = position
        self.displaySize = displaySize
        self.scale = scale
        self.rotation = rotation
        self.zIndex = zIndex
        self.contentBounds = contentBounds ?? PhotoContentBounds.contentBounds(for: item)
    }

    /// Default on-canvas size for a new item (~45% of canvas long edge, tight to content aspect).
    static func defaultDisplaySize(canvasSize: CGFloat, contentAspect: CGFloat) -> CGSize {
        let maxSide = canvasSize * 0.45
        let aspect = max(contentAspect, 0.01)
        if aspect >= 1 {
            return CGSize(width: maxSide, height: maxSide / aspect)
        }
        return CGSize(width: maxSide * aspect, height: maxSide)
    }
}

// MARK: - Canvas item view
struct AdaptiveOutfitItemView: View {
    let outfitItem: OutfitItem
    let canvasSize: CGFloat
    let isSelected: Bool
    let onPositionChanged: (CGPoint) -> Void
    let onScaleChanged: (CGFloat) -> Void
    let onRotationChanged: (Double) -> Void
    let onTransformStart: () -> Void
    let onTransformEnd: () -> Void
    let onSelected: () -> Void
    let onLongPress: () -> Void
    let onDelete: () -> Void

    // Local gesture state
    @State private var dragOffset: CGSize = .zero
    @State private var dragCenter: CGPoint
    @State private var rotation: Double
    @State private var baseRotation: Double
    @State private var scaleMultiplier: CGFloat = 1.0  // on top of layout size
    @State private var baseScaleMultiplier: CGFloat = 1.0

    private let deleteButtonSize: CGFloat = 24

    init(outfitItem: OutfitItem, canvasSize: CGFloat, isSelected: Bool,
         onPositionChanged: @escaping (CGPoint) -> Void,
         onScaleChanged: @escaping (CGFloat) -> Void,
         onRotationChanged: @escaping (Double) -> Void,
         onTransformStart: @escaping () -> Void,
         onTransformEnd: @escaping () -> Void,
         onSelected: @escaping () -> Void,
         onLongPress: @escaping () -> Void,
         onDelete: @escaping () -> Void) {
        self.outfitItem = outfitItem
        self.canvasSize = canvasSize
        self.isSelected = isSelected
        self.onPositionChanged = onPositionChanged
        self.onScaleChanged = onScaleChanged
        self.onRotationChanged = onRotationChanged
        self.onTransformStart = onTransformStart
        self.onTransformEnd = onTransformEnd
        self.onSelected = onSelected
        self.onLongPress = onLongPress
        self.onDelete = onDelete
        _rotation = State(initialValue: outfitItem.rotation)
        _baseRotation = State(initialValue: outfitItem.rotation)
        _dragCenter = State(initialValue: outfitItem.position)
        _scaleMultiplier = State(initialValue: outfitItem.scale)
        _baseScaleMultiplier = State(initialValue: outfitItem.scale)
    }

    private var effectiveCenter: CGPoint {
        CGPoint(x: dragCenter.x + dragOffset.width, y: dragCenter.y + dragOffset.height)
    }

    private var itemSize: CGSize { outfitItem.displaySize }

    private var deleteButtonPosition: CGPoint {
        let halfW = (itemSize.width * scaleMultiplier) / 2
        let halfH = (itemSize.height * scaleMultiplier) / 2
        let rad = rotation * .pi / 180.0
        let x = halfW * cos(rad) - (-halfH) * sin(rad)
        let y = halfW * sin(rad) + (-halfH) * cos(rad)
        return CGPoint(x: effectiveCenter.x + x, y: effectiveCenter.y + y)
    }

    var body: some View {
        ZStack {
            itemImage
                .scaleEffect(scaleMultiplier)
                .rotationEffect(Angle.degrees(rotation))
                .position(effectiveCenter)
                .onTapGesture { onSelected() }
                .onLongPressGesture { onLongPress() }
                .gesture(dragGesture)
                .onChange(of: outfitItem.position) { newValue in
                    dragCenter = newValue
                }
                .onChange(of: outfitItem.scale) { newValue in
                    scaleMultiplier = newValue
                    baseScaleMultiplier = newValue
                }
                .onChange(of: outfitItem.rotation) { newValue in
                    rotation = newValue
                    baseRotation = newValue
                }

            if isSelected {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .background(Circle().fill(Color.white).frame(width: deleteButtonSize, height: deleteButtonSize))
                        .font(.system(size: deleteButtonSize))
                }
                .frame(width: deleteButtonSize, height: deleteButtonSize)
                .position(deleteButtonPosition)
            }
        }
    }

    @ViewBuilder
    private var itemImage: some View {
        let selectionOverlay = RoundedRectangle(cornerRadius: 8)
            .stroke(Color.gray.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
        if let primaryPhoto = (outfitItem.item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
           let photoData = primaryPhoto.data,
           let uiImage = UIImage(data: photoData) {
            OutfitTightContentImage(
                uiImage: uiImage,
                contentBounds: outfitItem.contentBounds,
                frameSize: itemSize
            )
            .overlay { if isSelected { selectionOverlay } }
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .frame(width: itemSize.width, height: itemSize.height)
                .overlay { Image(systemName: "photo").foregroundColor(.secondary) }
                .overlay { if isSelected { selectionOverlay } }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard isSelected else { return }
                if dragOffset == .zero && value.translation != .zero {
                    onTransformStart()
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard isSelected else { return }
                let halfW = (itemSize.width * scaleMultiplier) / 2
                let halfH = (itemSize.height * scaleMultiplier) / 2
                let newX = max(halfW, min(canvasSize - halfW, dragCenter.x + value.translation.width))
                let newY = max(halfH, min(canvasSize - halfH, dragCenter.y + value.translation.height))
                dragCenter = CGPoint(x: newX, y: newY)
                dragOffset = .zero
                onPositionChanged(dragCenter)
                onTransformEnd()
            }
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
                        .overlay(Image(systemName: "photo").foregroundColor(.secondary))
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

// MARK: - Tight content image (crop to stored bounds, no letterboxing)

/// Maps the normalized opaque region of the photo to exactly `frameSize` (layout tight box).
struct OutfitTightContentImage: View {
    let uiImage: UIImage
    let contentBounds: NormalizedContentBounds
    let frameSize: CGSize

    var body: some View {
        let bw = max(contentBounds.width, 0.001)
        let bh = max(contentBounds.height, 0.001)
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFill()
            .frame(width: frameSize.width / bw, height: frameSize.height / bh)
            .offset(
                x: frameSize.width * (0.5 - contentBounds.midX) / bw,
                y: frameSize.height * (0.5 - contentBounds.midY) / bh
            )
            .frame(width: frameSize.width, height: frameSize.height)
            .clipped()
    }
}
