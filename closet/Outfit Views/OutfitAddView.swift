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

    /// When set with `redressRecipient`, places this remote item on the Redress canvas on first appear.
    let preselectedRedressItem: VisibleWardrobeItem?
    /// Wardrobe type for `preselectedRedressItem` (`closet` / `wishlist`).
    let preselectedRedressWardrobeType: String

    /// When set, composes an outfit suggestion for another user (Redress mode).
    let redressRecipient: PublicUserProfile?
    var onRedressSent: (() -> Void)? = nil

    /// Forces a unique view identity per creation session (prevents @State reuse).
    let sessionID: UUID

    private var isRedressMode: Bool { redressRecipient != nil }

    private var redressRecipientUsernameCaption: String {
        let raw = (redressRecipient?.username ?? redressRecipient?.displayName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "user" }
        return raw.hasPrefix("@") ? raw : "@\(raw)"
    }

    @EnvironmentObject private var supabaseService: SupabaseService

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

    // Selected wardrobe for outfit context (drafts / initial selection)
    @State private var selectedWardrobe: Wardrobe?

    @State private var isItemsSheetPresented = false
    @State private var itemsSheetSessionID = UUID()
    @State private var itemsSheetItemTypeSegment: OutfitItemTypeSegment = .closet
    @State private var showViewAllOutfitItemsSheet = false
    @State private var viewAllOutfitItemsInitialSegment: PairItemSelectionView.PairSourceSegment = .closet
    @State private var outfitItems: [OutfitItem] = []
    @State private var redressCanvasItems: [RedressCanvasItem] = []
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

    @State private var attributeOutfitDraft: Outfit?
    @State private var attributesSheet: OutfitAttributesSectionView.Sheet?
    @State private var isItemsSectionExpanded = false
    @State private var isAttributesSectionExpanded = true
    @State private var isSendingRedress = false
    @State private var showingRedressSentAlert = false
    @State private var redressSendError: String?
    @State private var duplicateOutfitConflict: RecipientDuplicateOutfit?
    @State private var localDuplicateOutfit: Outfit?
    @State private var existingDuplicateOutfitURI: String?

    init(
        outfitToEdit: Outfit? = nil,
        wardrobeType: String = "closet",
        initialWardrobe: Wardrobe? = nil,
        lockWardrobeSource: Bool = false,
        sessionID: UUID = UUID()
    ) {
        self.outfitToEdit = outfitToEdit
        self.wardrobeType = wardrobeType
        self.lockWardrobeSource = lockWardrobeSource
        self.redressRecipient = nil
        _selectedWardrobe = State(initialValue: initialWardrobe)
        self.preselectedItemURI = nil
        self.preselectedRedressItem = nil
        self.preselectedRedressWardrobeType = "closet"
        self.sessionID = sessionID
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
        self.redressRecipient = nil
        _selectedWardrobe = State(initialValue: initialWardrobe)
        self.preselectedItemURI = preselectedItemURI
        self.preselectedRedressItem = nil
        self.preselectedRedressWardrobeType = "closet"
        self.sessionID = sessionID
    }

    init(
        redressRecipient: PublicUserProfile,
        preselectedItem: VisibleWardrobeItem? = nil,
        preselectedWardrobeType: String = "closet",
        sessionID: UUID = UUID(),
        onRedressSent: (() -> Void)? = nil
    ) {
        self.outfitToEdit = nil
        self.wardrobeType = "closet"
        self.lockWardrobeSource = true
        self.redressRecipient = redressRecipient
        self.onRedressSent = onRedressSent
        _selectedWardrobe = State(initialValue: nil)
        self.preselectedItemURI = nil
        self.preselectedRedressItem = preselectedItem
        self.preselectedRedressWardrobeType = preselectedWardrobeType.lowercased() == "wishlist" ? "wishlist" : "closet"
        self.sessionID = sessionID
    }

    private var squareSize: CGFloat {
        UIScreen.main.bounds.width
    }

    private func openItemsSheet() {
        itemsSheetSessionID = UUID()
        itemsSheetItemTypeSegment = wardrobeType == "wishlist" ? .wishlist : .closet
        isItemsSheetPresented = true
    }

    private var outfitCanvasItemSelection: some View {
        Group {
            if isRedressMode, let recipient = redressRecipient {
                RedressItemSelectionView(
                    recipientUserId: recipient.userId,
                    itemTypeSegment: $itemsSheetItemTypeSegment,
                    isOnCanvas: { item in
                        redressCanvasItems.contains(where: { $0.item.id == item.id })
                    },
                    canvasItemCount: redressCanvasItems.count,
                    onAddItem: addRedressItemToCanvas
                )
            } else {
                OutfitItemSelectionView(
                    wardrobeType: wardrobeType,
                    lockWardrobeSource: lockWardrobeSource,
                    initialWardrobe: selectedWardrobe,
                    itemTypeSegment: $itemsSheetItemTypeSegment,
                    isOnCanvas: { item in
                        outfitItems.contains(where: { $0.item.objectID == item.objectID })
                    },
                    canvasItemCount: outfitItems.count,
                    onAddItem: addItemToOutfit,
                    onRemoveFromCanvas: removeItemFromCanvas
                )
            }
        }
        .id(itemsSheetSessionID)
    }

    var body: some View {
        sheetsContent
            .onAppear {
                print("👗 [OutfitAddView] onAppear. sessionID=\(sessionID.uuidString) outfitToEdit=\(outfitToEdit != nil) wardrobeType=\(wardrobeType) preselectedItemURI=\(preselectedItemURI ?? "nil") redress=\(isRedressMode)")

                guard !isRedressMode else {
                    ensureAttributeOutfitDraft()
                    isItemsSectionExpanded = false
                    if !didApplyPreselectedItem, let item = preselectedRedressItem {
                        didApplyPreselectedItem = true
                        itemsSheetItemTypeSegment = preselectedRedressWardrobeType == "wishlist" ? .wishlist : .closet
                        addRedressItemToCanvas(item)
                    }
                    return
                }

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
                ensureAttributeOutfitDraft()
                if outfitItems.isEmpty {
                    isItemsSectionExpanded = false
                } else {
                    isItemsSectionExpanded = true
                }
                print("👗 [OutfitAddView] Finished onAppear work. outfitItemsCount=\(outfitItems.count)")
            }
            .onChange(of: outfitItems.count) { oldCount, newCount in
                guard !isRedressMode else { return }
                if newCount == 0 {
                    isItemsSectionExpanded = false
                } else if oldCount == 0 && newCount > 0 {
                    isItemsSectionExpanded = true
                }
            }
            .onChange(of: redressCanvasItems.count) { oldCount, newCount in
                guard isRedressMode else { return }
                if newCount == 0 {
                    isItemsSectionExpanded = false
                } else if oldCount == 0 && newCount > 0 {
                    isItemsSectionExpanded = true
                }
            }
            .onChange(of: wardrobes) { newWardrobes in
                guard !lockWardrobeSource else { return }
                if let current = selectedWardrobe, !newWardrobes.contains(current) {
                    selectedWardrobe = WardrobeBootstrap.primaryWardrobe(in: newWardrobes)
                }
            }
    }

    // MARK: - Body Sub-expressions
    // Split to keep the type-checker happy (too many chained modifiers in one expression).

    private var sheetsContent: some View {
        alertsContent
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
            .sheet(isPresented: $isItemsSheetPresented) {
                NavigationStack {
                    outfitCanvasItemSelection
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showViewAllOutfitItemsSheet) {
                OutfitCanvasItemsViewAllSheet(
                    items: canvasItemsOrdered,
                    showsWardrobePicker: shouldSplitCanvasItemsByWardrobeType,
                    initialSegment: viewAllOutfitItemsInitialSegment,
                    wardrobeType: wardrobeType,
                    lockWardrobeSource: lockWardrobeSource,
                    initialWardrobe: selectedWardrobe,
                    isOnCanvas: { item in
                        outfitItems.contains(where: { $0.item.objectID == item.objectID })
                    },
                    onSelect: { item in
                        selectItemOnCanvas(item)
                        showViewAllOutfitItemsSheet = false
                    },
                    onRemove: { item in
                        removeItemFromCanvas(item)
                    },
                    onAddItem: addItemToOutfit,
                    onRemoveFromCanvas: removeItemFromCanvas
                )
                .id(viewAllOutfitItemsInitialSegment)
                .presentationDetents(outfitItems.count > 6 ? [.medium, .large] : [.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $attributesSheet) { sheet in
                if let outfit = activeOutfitForAttributes {
                    sheet.destination(for: outfit)
                }
            }
    }

    private var alertsContent: some View {
        VStack(spacing: 0) {
            outfitCollageArea
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
            draftAndClearButtons
                .background(Color(.systemGray6))
            outfitDetailsList
        }
        .background(Color(.systemGray6))
        .navigationTitle(isRedressMode ? "" : "Outfit")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                leadingToolbarItems
            }
            if isRedressMode {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Redress")
                            .font(.headline)
                        Text(redressRecipientUsernameCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if !isRedressMode {
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
            } else {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        submitRedressSuggestion()
                    }
                    .disabled(redressCanvasItems.isEmpty || isSendingRedress)
                }
            }
        }
        .overlay {
            if isSendingRedress {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Sending…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .alert("Redress Sent", isPresented: $showingRedressSentAlert) {
            Button("OK") {
                onRedressSent?()
                discardAttributeOutfitDraftIfNeeded()
                dismiss()
            }
        } message: {
            Text("Your outfit suggestion was sent to \(redressRecipient?.username ?? redressRecipient?.displayName ?? "this user").")
        }
        .alert("Couldn't Send Suggestion", isPresented: redressSendErrorPresented) {
            Button("OK", role: .cancel) { redressSendError = nil }
        } message: {
            Text(redressSendError ?? "")
        }
        .sheet(item: $duplicateOutfitConflict) { duplicate in
            if let recipient = redressRecipient {
                RedressDuplicateOutfitSheet(
                    recipient: recipient,
                    duplicate: duplicate,
                    onDismiss: { duplicateOutfitConflict = nil }
                )
                .environmentObject(supabaseService)
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
            Button("No", role: .cancel) {
                discardAttributeOutfitDraftIfNeeded()
                dismiss()
            }
        } message: {
            Text("Saving this outfit to drafts will allow you to finish editing it later.")
        }
        .alert("Discard Changes?", isPresented: $showingDiscardChangesConfirmation) {
            Button("Discard", role: .destructive) {
                if isRedressMode {
                    clearRedressItems()
                    discardAttributeOutfitDraftIfNeeded()
                    dismiss()
                } else {
                    discardAttributeOutfitDraftIfNeeded()
                    dismiss()
                }
            }
            Button("Keep Editing", role: .cancel) { }
        } message: {
            Text("Your changes to this outfit will not be saved.")
        }
        .alert("Duplicate Outfit", isPresented: localDuplicateAlertPresented) {
            Button("View Existing") {
                if let outfit = localDuplicateOutfit {
                    existingDuplicateOutfitURI = outfit.objectID.uriRepresentation().absoluteString
                }
                localDuplicateOutfit = nil
            }
            Button("OK", role: .cancel) {
                localDuplicateOutfit = nil
            }
        } message: {
            Text("You already have an outfit with this combination of items.")
        }
        .navigationDestination(item: $existingDuplicateOutfitURI) { uriString in
            Group {
                if let url = URL(string: uriString),
                   let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
                   let outfit = try? viewContext.existingObject(with: objectID) as? Outfit {
                    OutfitDetailView(outfit: outfit)
                        .onAppear { existingDuplicateOutfitURI = nil }
                } else {
                    EmptyView()
                        .onAppear { existingDuplicateOutfitURI = nil }
                }
            }
        }
    }

    private var localDuplicateAlertPresented: Binding<Bool> {
        Binding(
            get: { localDuplicateOutfit != nil },
            set: { if !$0 { localDuplicateOutfit = nil } }
        )
    }

    // MARK: - Toolbar Items
    @ViewBuilder
    private var leadingToolbarItems: some View {
        Button {
            if isRedressMode {
                if !redressCanvasItems.isEmpty {
                    showingDiscardChangesConfirmation = true
                } else {
                    discardAttributeOutfitDraftIfNeeded()
                    dismiss()
                }
            } else if outfitToEdit != nil && !undoStack.isEmpty {
                showingDiscardChangesConfirmation = true
            } else if !outfitItems.isEmpty && outfitToEdit == nil {
                showingSaveDraftConfirmation = true
            } else {
                discardAttributeOutfitDraftIfNeeded()
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
        guard !isRedressMode, let selectedItemID else { return nil }
        return outfitItems.firstIndex(where: { $0.id == selectedItemID })
    }

    private var selectedRedressItemIndex: Int? {
        guard isRedressMode, let selectedItemID else { return nil }
        return redressCanvasItems.firstIndex(where: { $0.id == selectedItemID })
    }

    private var canvasTransformGesture: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    if isRedressMode {
                        guard let index = selectedRedressItemIndex else { return }
                        if !transformInProgress {
                            canvasPinchBaseScale = redressCanvasItems[index].scale
                            canvasRotateBaseRotation = redressCanvasItems[index].rotation
                            onTransformStart()
                        }
                        applyRedressScale(max(0.3, min(4.0, canvasPinchBaseScale * value)), at: index)
                    } else {
                        guard let index = selectedOutfitItemIndex else { return }
                        if !transformInProgress {
                            canvasPinchBaseScale = outfitItems[index].scale
                            canvasRotateBaseRotation = outfitItems[index].rotation
                            onTransformStart()
                        }
                        applyScale(max(0.3, min(4.0, canvasPinchBaseScale * value)), at: index)
                    }
                }
                .onEnded { value in
                    if isRedressMode {
                        guard let index = selectedRedressItemIndex else { return }
                        applyRedressScale(max(0.3, min(4.0, canvasPinchBaseScale * value)), at: index)
                    } else {
                        guard let index = selectedOutfitItemIndex else { return }
                        applyScale(max(0.3, min(4.0, canvasPinchBaseScale * value)), at: index)
                    }
                    onTransformEnd()
                },
            RotationGesture()
                .onChanged { value in
                    if isRedressMode {
                        guard let index = selectedRedressItemIndex else { return }
                        if !transformInProgress {
                            canvasPinchBaseScale = redressCanvasItems[index].scale
                            canvasRotateBaseRotation = redressCanvasItems[index].rotation
                            onTransformStart()
                        }
                        applyRedressRotation(canvasRotateBaseRotation + value.degrees, at: index)
                    } else {
                        guard let index = selectedOutfitItemIndex else { return }
                        if !transformInProgress {
                            canvasPinchBaseScale = outfitItems[index].scale
                            canvasRotateBaseRotation = outfitItems[index].rotation
                            onTransformStart()
                        }
                        applyRotation(canvasRotateBaseRotation + value.degrees, at: index)
                    }
                }
                .onEnded { value in
                    if isRedressMode {
                        guard let index = selectedRedressItemIndex else { return }
                        applyRedressRotation(canvasRotateBaseRotation + value.degrees, at: index)
                    } else {
                        guard let index = selectedOutfitItemIndex else { return }
                        applyRotation(canvasRotateBaseRotation + value.degrees, at: index)
                    }
                    onTransformEnd()
                }
        )
    }

    @ViewBuilder
    private var outfitCollageArea: some View {
        if isRedressMode {
            redressCollageArea
        } else {
            standardOutfitCollageArea
        }
    }

    @ViewBuilder
    private var redressCollageArea: some View {
        let canvas = ZStack {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color(.systemBackground))
                .frame(width: squareSize, height: squareSize)
                .onTapGesture { selectedItemID = nil }

            if redressCanvasItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.dashed")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Tap Items below to add to your outfit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            ForEach(redressCanvasItems.sorted(by: { $0.zIndex < $1.zIndex })) { canvasItem in
                AdaptiveRedressCanvasItemView(
                    canvasItem: canvasItem,
                    canvasSize: squareSize,
                    isSelected: selectedItemID == canvasItem.id,
                    onPositionChanged: { newPosition in
                        updateRedressItemPosition(canvasItem, newPosition)
                    },
                    onScaleChanged: { newScale in
                        updateRedressItemScale(canvasItem, newScale)
                    },
                    onRotationChanged: { newRotation in
                        updateRedressItemRotation(canvasItem, newRotation)
                    },
                    onTransformStart: { onTransformStart() },
                    onTransformEnd: { onTransformEnd() },
                    onSelected: { selectedItemID = canvasItem.id },
                    onLongPress: { bringRedressItemToFront(canvasItem) },
                    onDelete: { removeRedressItem(canvasItem) }
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

    @ViewBuilder
    private var standardOutfitCollageArea: some View {
        let canvas = ZStack {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color(.systemBackground))
                .frame(width: squareSize, height: squareSize)
                .onTapGesture { selectedItemID = nil }

            if outfitItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.dashed")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Tap Items below to add to your outfit")
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

    // MARK: - Canvas Controls Bar
    private var draftAndClearButtons: some View {
        ZStack {
            HStack(spacing: 16) {
                Button {
                    if isRedressMode {
                        autoGridRedressLayout()
                    } else {
                        autoGridLayout()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2")
                        Text("Auto-Grid")
                    }
                }
                .disabled(isRedressMode ? redressCanvasItems.isEmpty : outfitItems.isEmpty)

                Spacer()

                if !isRedressMode {
                    HStack(spacing: 16) {
                        Button {
                            undo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .foregroundColor(undoStack.isEmpty ? .gray : .primary)
                        }
                        .disabled(undoStack.isEmpty)

                        Button {
                            redo()
                        } label: {
                            Image(systemName: "arrow.uturn.forward")
                                .foregroundColor(redoStack.isEmpty ? .gray : .primary)
                        }
                        .disabled(redoStack.isEmpty)
                    }
                }
            }

            Button {
                if isRedressMode {
                    clearRedressItems()
                } else {
                    clearAllItems()
                }
            } label: {
                Text("Clear")
                    .foregroundColor(.red)
            }
            .disabled(isRedressMode ? redressCanvasItems.isEmpty : outfitItems.isEmpty)
        }
        .padding(.horizontal, 16)
        .frame(height: 15)
        .padding(.vertical)
    }

    private var activeOutfitForAttributes: Outfit? {
        outfitToEdit ?? attributeOutfitDraft
    }

    private var redressSendErrorPresented: Binding<Bool> {
        Binding(
            get: { redressSendError != nil },
            set: { if !$0 { redressSendError = nil } }
        )
    }

    private var canvasItemsOrdered: [Item] {
        outfitItems.sorted(by: { $0.zIndex < $1.zIndex }).map(\.item)
    }

    private func itemIsWishlistMember(_ item: Item) -> Bool {
        (item.wardrobes as? Set<Wardrobe>)?.contains { $0.type?.lowercased() == "wishlist" } ?? false
    }

    private var canvasWishlistItems: [Item] {
        canvasItemsOrdered.filter { itemIsWishlistMember($0) }
    }

    private var canvasClosetItems: [Item] {
        canvasItemsOrdered.filter { !itemIsWishlistMember($0) }
    }

    private var shouldSplitCanvasItemsByWardrobeType: Bool {
        !canvasWishlistItems.isEmpty && !canvasClosetItems.isEmpty
    }

    private var itemsSectionHeaderIconName: String {
        isItemsSectionExpanded ? "minus" : "plus"
    }

    private func handleItemsSectionHeaderTap() {
        if isRedressMode {
            if redressCanvasItems.isEmpty {
                openItemsSheet()
            } else {
                withAnimation {
                    isItemsSectionExpanded.toggle()
                }
            }
            return
        }
        if outfitItems.isEmpty {
            openItemsSheet()
            return
        }
        withAnimation {
            isItemsSectionExpanded.toggle()
        }
    }

    private func presentViewAllOutfitItemsSheet(segment: PairItemSelectionView.PairSourceSegment = .closet) {
        viewAllOutfitItemsInitialSegment = segment
        showViewAllOutfitItemsSheet = true
    }

    private func selectItemOnCanvas(_ item: Item) {
        if let outfitItem = outfitItems.first(where: { $0.item.objectID == item.objectID }) {
            selectItem(outfitItem)
        }
    }

    private var outfitDetailsList: some View {
        List {
            Section {
                if isItemsSectionExpanded {
                    if isRedressMode {
                        redressFeaturedItemsSectionContent
                            .transition(.opacity.combined(with: .slide))
                    } else {
                        featuredItemsSectionContent
                            .transition(.opacity.combined(with: .slide))
                    }
                }
            } header: {
                HStack {
                    Text("ITEMS")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: itemsSectionHeaderIconName)
                        .foregroundColor(.gray)
                        .font(.caption)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    handleItemsSectionHeaderTap()
                }
            }
            .listRowInsets(EdgeInsets(.zero))
            .listSectionSpacing(0)
            .padding(.horizontal)

            if let outfit = activeOutfitForAttributes {
                Section {
                    if isAttributesSectionExpanded {
                        OutfitAttributesSectionView(
                            outfit: outfit,
                            activeSheet: $attributesSheet,
                            redressSuggestionMode: isRedressMode
                        )
                            .transition(.opacity.combined(with: .slide))
                            .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                    }
                } header: {
                    HStack {
                        Text("ATTRIBUTES")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: isAttributesSectionExpanded ? "minus" : "plus")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            isAttributesSectionExpanded.toggle()
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var redressFeaturedItemsSectionContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !redressCanvasItemsOrdered.isEmpty {
                RedressFeaturedItemsSubsectionRow(
                    pairedItems: redressCanvasItemsOrdered,
                    wishlistItems: redressWishlistCanvasItems,
                    closetItems: redressClosetCanvasItems,
                    showsWardrobeLabels: shouldSplitRedressCanvasByWardrobeType,
                    onSelectItem: { selectRedressItemOnCanvas($0) },
                    onViewAll: { openItemsSheet() }
                )
            }
        }
        .listRowInsets(EdgeInsets(.zero))
    }

    private var redressCanvasItemsOrdered: [VisibleWardrobeItem] {
        redressCanvasItems
            .sorted { $0.zIndex < $1.zIndex }
            .map(\.item)
    }

    private var redressWishlistCanvasItems: [VisibleWardrobeItem] {
        redressCanvasItems
            .filter { $0.sourceWardrobeType == "wishlist" }
            .sorted { $0.zIndex < $1.zIndex }
            .map(\.item)
    }

    private var redressClosetCanvasItems: [VisibleWardrobeItem] {
        redressCanvasItems
            .filter { $0.sourceWardrobeType != "wishlist" }
            .sorted { $0.zIndex < $1.zIndex }
            .map(\.item)
    }

    private var shouldSplitRedressCanvasByWardrobeType: Bool {
        !redressWishlistCanvasItems.isEmpty && !redressClosetCanvasItems.isEmpty
    }

    private func selectRedressItemOnCanvas(_ item: VisibleWardrobeItem) {
        if let canvasItem = redressCanvasItems.first(where: { $0.item.id == item.id }) {
            selectedItemID = canvasItem.id
        }
    }

    @ViewBuilder
    private var featuredItemsSectionContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !canvasItemsOrdered.isEmpty {
                FeaturedItemsSubsectionRow(
                    pairedItems: canvasItemsOrdered,
                    wishlistItems: canvasWishlistItems,
                    closetItems: canvasClosetItems,
                    showsWardrobeLabels: shouldSplitCanvasItemsByWardrobeType,
                    onSelectPairedItem: { selectItemOnCanvas($0) },
                    onViewAll: { presentViewAllOutfitItemsSheet(segment: .closet) }
                )
            }
        }
        .listRowInsets(EdgeInsets(.zero))
    }

    private func ensureAttributeOutfitDraft() {
        guard outfitToEdit == nil, attributeOutfitDraft == nil else { return }
        let outfit = Outfit(context: viewContext)
        outfit.id = UUID()
        outfit.userId = authSession.userId?.uuidString
        outfit.isDraft = true
        let now = Date()
        outfit.timestamp = now
        attributeOutfitDraft = outfit
    }

    private func discardAttributeOutfitDraftIfNeeded() {
        guard outfitToEdit == nil, let draft = attributeOutfitDraft else { return }
        viewContext.delete(draft)
        attributeOutfitDraft = nil
        try? viewContext.save()
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
        guard !isRedressMode else { return }
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
        if !isItemsSectionExpanded {
            withAnimation {
                isItemsSectionExpanded = true
            }
        }
    }

    // MARK: - Redress canvas

    private func addRedressItemToCanvas(_ item: VisibleWardrobeItem) {
        guard isRedressMode else { return }
        guard !redressCanvasItems.contains(where: { $0.item.id == item.id }) else { return }

        let center = CGPoint(x: squareSize / 2, y: squareSize / 2)
        let sourceType = itemsSheetItemTypeSegment == .wishlist ? "wishlist" : "closet"
        let canvasItem = RedressCanvasItem(
            item: item,
            sourceWardrobeType: sourceType,
            position: center,
            displaySize: RedressCanvasItem.defaultDisplaySize(canvasSize: squareSize),
            scale: 1.0,
            rotation: 0.0,
            zIndex: redressCanvasItems.count
        )
        redressCanvasItems.append(canvasItem)
        selectedItemID = canvasItem.id
        if !isItemsSectionExpanded {
            withAnimation {
                isItemsSectionExpanded = true
            }
        }
    }

    private func applyRedressScale(_ scale: CGFloat, at index: Int) {
        var item = redressCanvasItems[index]
        item.scale = scale
        redressCanvasItems[index] = item
    }

    private func applyRedressRotation(_ rotation: Double, at index: Int) {
        var item = redressCanvasItems[index]
        item.rotation = rotation
        redressCanvasItems[index] = item
    }

    private func updateRedressItemPosition(_ canvasItem: RedressCanvasItem, _ newPosition: CGPoint) {
        if let index = redressCanvasItems.firstIndex(where: { $0.id == canvasItem.id }) {
            redressCanvasItems[index].position = newPosition
        }
    }

    private func updateRedressItemScale(_ canvasItem: RedressCanvasItem, _ newScale: CGFloat) {
        if let index = redressCanvasItems.firstIndex(where: { $0.id == canvasItem.id }) {
            redressCanvasItems[index].scale = newScale
        }
    }

    private func updateRedressItemRotation(_ canvasItem: RedressCanvasItem, _ newRotation: Double) {
        if let index = redressCanvasItems.firstIndex(where: { $0.id == canvasItem.id }) {
            redressCanvasItems[index].rotation = newRotation
        }
    }

    private func bringRedressItemToFront(_ canvasItem: RedressCanvasItem) {
        selectedItemID = nil
        let maxZIndex = redressCanvasItems.map(\.zIndex).max() ?? 0
        if let index = redressCanvasItems.firstIndex(where: { $0.id == canvasItem.id }) {
            redressCanvasItems[index].zIndex = maxZIndex + 1
        }
        selectedItemID = canvasItem.id
    }

    private func removeRedressItem(_ canvasItem: RedressCanvasItem) {
        redressCanvasItems.removeAll { $0.id == canvasItem.id }
        if selectedItemID == canvasItem.id {
            selectedItemID = nil
        }
    }

    private func clearRedressItems() {
        selectedItemID = nil
        withAnimation(.spring()) {
            redressCanvasItems.removeAll()
        }
    }

    private func autoGridRedressLayout() {
        guard !redressCanvasItems.isEmpty else { return }
        selectedItemID = nil

        let count = redressCanvasItems.count
        let columns: Int
        let rows: Int
        switch count {
        case 1: columns = 1; rows = 1
        case 2: columns = 2; rows = 1
        case 3, 4: columns = 2; rows = 2
        case 5, 6: columns = 3; rows = 2
        default: columns = 3; rows = Int(ceil(Double(count) / 3.0))
        }

        let cellWidth = squareSize / CGFloat(columns)
        let cellHeight = squareSize / CGFloat(rows)
        let sortedIndices = redressCanvasItems.indices.sorted {
            redressCanvasItems[$0].zIndex < redressCanvasItems[$1].zIndex
        }

        for (gridIndex, itemIndex) in sortedIndices.enumerated() {
            let col = gridIndex % columns
            let row = gridIndex / columns
            let center = CGPoint(
                x: cellWidth * (CGFloat(col) + 0.5),
                y: cellHeight * (CGFloat(row) + 0.5)
            )
            let fitScale = min(
                cellWidth * 0.85 / redressCanvasItems[itemIndex].displaySize.width,
                cellHeight * 0.85 / redressCanvasItems[itemIndex].displaySize.height
            )
            redressCanvasItems[itemIndex].position = center
            redressCanvasItems[itemIndex].scale = fitScale
            redressCanvasItems[itemIndex].rotation = 0
            redressCanvasItems[itemIndex].zIndex = gridIndex
        }
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

    private func autoGridLayout() {
        guard !outfitItems.isEmpty else { return }
        saveState()
        selectedItemID = nil

        let count = outfitItems.count
        let columns: Int
        let rows: Int
        switch count {
        case 1:
            columns = 1
            rows = 1
        case 2:
            columns = 2
            rows = 1
        case 3, 4:
            columns = 2
            rows = 2
        default:
            columns = Int(ceil(sqrt(Double(count))))
            rows = Int(ceil(Double(count) / Double(columns)))
        }

        let gap: CGFloat = 8
        let cellWidth = (squareSize - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let cellHeight = (squareSize - gap * CGFloat(rows - 1)) / CGFloat(rows)
        let padding: CGFloat = 0.88

        let sortedIndices = outfitItems.indices.sorted {
            outfitItems[$0].zIndex < outfitItems[$1].zIndex
        }

        withAnimation(.spring()) {
            for (layoutIndex, itemIndex) in sortedIndices.enumerated() {
                let column = layoutIndex % columns
                let row = layoutIndex / columns
                let centerX = CGFloat(column) * (cellWidth + gap) + cellWidth / 2
                let centerY = CGFloat(row) * (cellHeight + gap) + cellHeight / 2

                var item = outfitItems[itemIndex]
                item.position = CGPoint(x: centerX, y: centerY)
                item.rotation = 0
                item.zIndex = layoutIndex

                let fitScale = min(
                    cellWidth * padding / max(item.displaySize.width, 1),
                    cellHeight * padding / max(item.displaySize.height, 1)
                )
                item.scale = max(0.3, min(4.0, fitScale))
                outfitItems[itemIndex] = item
            }
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

        let canvasItemIds = outfitItems.compactMap { $0.item.id }
        if let userId = authSession.userId?.uuidString,
           let duplicate = findDuplicateOutfit(
               matchingItemIds: canvasItemIds,
               userId: userId,
               excluding: [outfitToEdit, attributeOutfitDraft].compactMap { $0 },
               in: viewContext
           ) {
            localDuplicateOutfit = duplicate
            return
        }

        ensureAttributeOutfitDraft()
        guard let outfit = outfitToEdit ?? attributeOutfitDraft else { return }

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
        if outfitToEdit == nil || outfit.createdAt == nil {
            outfit.createdAt = Date()
        }
        setUpdatedAt(outfit)
        attributeOutfitDraft = nil

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

        ensureAttributeOutfitDraft()
        let draft = attributeOutfitDraft ?? Outfit(context: viewContext)
        if attributeOutfitDraft == nil {
            draft.id = UUID()
            draft.userId = authSession.userId?.uuidString
            draft.timestamp = Date()
        }
        draft.isDraft = true

        if let imageData = collageImage.processForStorage() {
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
            attributeOutfitDraft = nil
            showingDraftSaveAlert = true
        } catch {
            print("Error saving draft: \(error)")
        }
    }

    private func submitRedressSuggestion() {
        guard let recipient = redressRecipient,
              let suggesterId = authSession.userId else { return }
        guard !redressCanvasItems.isEmpty else { return }

        selectedItemID = nil
        isSendingRedress = true

        Task {
            defer { Task { @MainActor in isSendingRedress = false } }
            do {
                let itemIds = redressCanvasItems.map(\.item.id)

                if let duplicate = try await supabaseService.findRecipientDuplicateOutfit(
                    recipientId: recipient.userId,
                    itemIds: itemIds
                ) {
                    await MainActor.run {
                        duplicateOutfitConflict = duplicate
                    }
                    return
                }

                guard let collageImage = await captureRedressCollageAsImage(),
                      let imageData = collageImage.processForStorage() else {
                    throw NSError(domain: "OutfitAddView", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to capture outfit collage"])
                }

                await MainActor.run { ensureAttributeOutfitDraft() }
                let draft = await MainActor.run { attributeOutfitDraft }
                let proposedName = draft?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let proposedNotes = draft?.notes?.trimmingCharacters(in: .whitespacesAndNewlines)

                let savedItems = redressCanvasItems.map { canvasItem in
                    SavedOutfitItem(
                        itemID: canvasItem.item.id.uuidString,
                        positionX: canvasItem.position.x,
                        positionY: canvasItem.position.y,
                        scale: canvasItem.scale,
                        rotation: canvasItem.rotation,
                        zIndex: canvasItem.zIndex
                    )
                }
                let transformationJSON = String(data: try JSONEncoder().encode(savedItems), encoding: .utf8) ?? "[]"
                let suggestionId = UUID()

                let imageURL = try await supabaseService.uploadOutfitSuggestionImage(
                    imageData: imageData,
                    suggestionId: suggestionId,
                    userId: suggesterId
                )

                _ = try await supabaseService.createOutfitSuggestion(
                    SupabaseService.CreateOutfitSuggestionPayload(
                        suggestionId: suggestionId,
                        recipientId: recipient.userId,
                        proposedName: proposedName?.isEmpty == true ? nil : proposedName,
                        proposedNotes: proposedNotes?.isEmpty == true ? nil : proposedNotes,
                        imageURL: imageURL,
                        transformationJSON: transformationJSON,
                        itemIds: itemIds
                    )
                )

                await MainActor.run {
                    clearRedressItems()
                    showingRedressSentAlert = true
                }
            } catch {
                let message = error.localizedDescription
                if message.localizedCaseInsensitiveContains("already has an outfit with these items"),
                   let duplicate = try? await supabaseService.findRecipientDuplicateOutfit(
                    recipientId: recipient.userId,
                    itemIds: redressCanvasItems.map(\.item.id)
                   ) {
                    await MainActor.run {
                        duplicateOutfitConflict = duplicate
                    }
                    return
                }
                await MainActor.run {
                    redressSendError = message
                }
            }
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

                ctx.rotate(by: Angle.degrees(-outfitItem.rotation))
                ctx.translateBy(x: -center.x, y: -center.y)
            }
        }
        .background(Color(.systemBackground))
        .frame(width: size, height: size)

        let renderer = ImageRenderer(content: captureView)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }

    private func captureRedressCollageAsImage() async -> UIImage? {
        let size = squareSize
        var imageByItemId: [UUID: UIImage] = [:]

        for canvasItem in redressCanvasItems {
            guard let url = canvasItem.item.displayImageURL else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      let image = UIImage(data: data) else { continue }
                imageByItemId[canvasItem.item.id] = image
            } catch {
                continue
            }
        }

        let sortedItems = redressCanvasItems.sorted { $0.zIndex < $1.zIndex }
        let captureView = Canvas { ctx, _ in
            for canvasItem in sortedItems {
                guard let uiImage = imageByItemId[canvasItem.item.id] else { continue }
                let center = canvasItem.position
                let scaledW = canvasItem.displaySize.width * canvasItem.scale
                let scaledH = canvasItem.displaySize.height * canvasItem.scale

                ctx.translateBy(x: center.x, y: center.y)
                ctx.rotate(by: Angle.degrees(canvasItem.rotation))

                let drawRect = CGRect(x: -scaledW / 2, y: -scaledH / 2, width: scaledW, height: scaledH)
                ctx.draw(Image(uiImage: uiImage).resizable(), in: drawRect)

                ctx.rotate(by: Angle.degrees(-canvasItem.rotation))
                ctx.translateBy(x: -center.x, y: -center.y)
            }
        }
        .background(Color(.systemBackground))
        .frame(width: size, height: size)

        let renderer = ImageRenderer(content: captureView)
        renderer.scale = UIScreen.main.scale
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
                        GridItemRemoveButton(
                            accessibilityLabel: "Remove item from outfit"
                        ) {
                            onRemove()
                        }
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

// MARK: - Redress duplicate outfit

private struct RedressDuplicateOutfitSheet: View {
    let recipient: PublicUserProfile
    let duplicate: RecipientDuplicateOutfit
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedOutfitNavigation: RedressDuplicateOutfitNavigation?

    private struct RedressDuplicateOutfitNavigation: Hashable {
        let outfit: VisibleWardrobeOutfit
        let wardrobeId: UUID
    }

    private var recipientUsername: String {
        let username = recipient.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !username.isEmpty { return username }
        let displayName = recipient.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !displayName.isEmpty { return displayName }
        return "This user"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("\(recipientUsername) already has an outfit with these items")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if duplicate.canNavigateToDetail, let wardrobeId = duplicate.wardrobeId {
                    Button {
                        selectedOutfitNavigation = RedressDuplicateOutfitNavigation(
                            outfit: VisibleWardrobeOutfit(
                                id: duplicate.outfitId,
                                name: duplicate.name,
                                imageUrl: duplicate.imageUrl,
                                wornImageUrl: nil
                            ),
                            wardrobeId: wardrobeId
                        )
                    } label: {
                        RedressDuplicateOutfitThumbnail(url: duplicate.collageImageURL)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View existing outfit")
                } else {
                    RedressDuplicateOutfitThumbnail(url: duplicate.collageImageURL)
                }

                Button("OK") {
                    onDismiss()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Duplicate Outfit")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedOutfitNavigation) { navigation in
                ReadOnlyOutfitDetailView(
                    ownerUserId: recipient.userId,
                    wardrobeId: navigation.wardrobeId,
                    outfitSummary: navigation.outfit,
                    redressRecipientUserId: recipient.userId
                )
            }
        }
        .presentationDetents([.medium])
    }
}

private struct RedressDuplicateOutfitThumbnail: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(.systemGray5)
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }
}
