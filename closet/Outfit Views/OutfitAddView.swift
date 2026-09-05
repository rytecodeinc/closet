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

    /// When set (non-default edit context), Save prompts to add canvas items missing from this wardrobe.
    let wardrobeMembershipOnSave: Wardrobe?

    /// If provided, this item will be resolved and placed on the canvas on first appear.
    let preselectedItemURI: String?

    /// When set with `redressRecipient`, places this remote item on the Redress canvas on first appear.
    let preselectedRedressItem: VisibleWardrobeItem?
    /// Wardrobe type for `preselectedRedressItem` (`closet` / `wishlist`).
    let preselectedRedressWardrobeType: String
    /// Specific recipient wardrobe the user was browsing — Redress items sheet opens here.
    let preselectedRedressWardrobeId: UUID?

    /// When set, composes an outfit suggestion for another user (Redress mode).
    let redressRecipient: PublicUserProfile?
    /// When set with `redressRecipient`, Redress submit updates this pending suggestion.
    let editingSuggestionId: UUID?
    /// Wardrobe used to load suggestion detail thumbs while editing a pending Redress.
    let editingSuggestionWardrobeId: UUID?
    /// Seeded from pending detail so Edit can push without waiting on network.
    let editingProposedName: String?
    let editingProposedNotes: String?
    let editingItemThumbnails: [VisibleOutfitItemThumb]
    var onRedressSent: (() -> Void)? = nil

    /// When set (Closet/Wishlist tab path), “View Existing” duplicate appends `.outfitDetail` instead of nested `item:`.
    var navigationPath: Binding<NavigationPath>? = nil

    /// Forces a unique view identity per creation session (prevents @State reuse).
    let sessionID: UUID

    private var isRedressMode: Bool { redressRecipient != nil }
    private static let canvasScrollID = "outfitCanvas"

    private var redressRecipientUsernameCaption: String {
        let raw = redressRecipient?.username
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return "@user" }
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
    @State private var itemsSheetDetent: PresentationDetent = .medium
    @State private var showViewAllOutfitItemsSheet = false
    @State private var viewAllOutfitItemsInitialSegment: PairItemSelectionView.PairSourceSegment = .closet
    @State private var viewAllOutfitItemsSheetDetent: PresentationDetent = .medium
    @State private var outfitItems: [OutfitItem] = []
    @State private var redressCanvasItems: [RedressCanvasItem] = []
    @State private var collageSize: CGFloat = 0
    @State private var draggedItem: OutfitItem?
    @State private var showingSaveAlert = false
    @State private var showingDraftSaveAlert = false
    @State private var showingSaveDraftConfirmation = false
    @State private var showingDiscardChangesConfirmation = false
    @State private var selectedItemID: UUID?
    /// Lock list scroll only after scrolling canvas into view on select.
    @State private var canvasScrollLocked = false

    // Drafts folder — sheet-based to avoid navigation conflict
    @State private var showingDraftsSheet = false
    @State private var selectedDraftToEdit: Outfit? = nil
    @State private var showingDraftEditor = false

    // Manual override positions — when user drags, their position takes priority
    @State private var manualOverrides: [UUID: CGPoint] = [:]

    // Undo/Redo state
    @State private var undoStack: [CanvasState] = []
    @State private var redoStack: [CanvasState] = []
    @State private var redressUndoStack: [RedressCanvasState] = []
    @State private var redressRedoStack: [RedressCanvasState] = []
    @State private var transformInProgress = false
    @State private var canvasPinchBaseScale: CGFloat = 1.0
    @State private var canvasRotateBaseRotation: Double = 0.0

    @State private var didApplyPreselectedItem = false
    @State private var didLoadEditingSuggestion = false

    @State private var attributeOutfitDraft: Outfit?
    @State private var attributesSheet: OutfitAttributesSectionView.Sheet?
    @State private var isItemsSectionExpanded = false
    @State private var isAttributesSectionExpanded = true
    @State private var isSendingRedress = false
    @State private var showingRedressSentAlert = false
    @State private var showingClearRedressConfirm = false
    @State private var showingSendRedressConfirm = false
    @State private var redressSendError: String?
    @State private var duplicateOutfitConflict: RecipientDuplicateOutfit?
    @State private var localDuplicateOutfit: Outfit?
    @State private var existingDuplicateOutfitURI: String?
    @State private var showWardrobeMembershipAlert = false
    @State private var pendingMembershipAddCount = 0

    init(
        outfitToEdit: Outfit? = nil,
        wardrobeType: String = "closet",
        initialWardrobe: Wardrobe? = nil,
        lockWardrobeSource: Bool = false,
        wardrobeMembershipOnSave: Wardrobe? = nil,
        sessionID: UUID = UUID(),
        navigationPath: Binding<NavigationPath>? = nil
    ) {
        self.outfitToEdit = outfitToEdit
        self.wardrobeType = wardrobeType
        self.lockWardrobeSource = lockWardrobeSource
        self.wardrobeMembershipOnSave = wardrobeMembershipOnSave
        self.redressRecipient = nil
        self.editingSuggestionId = nil
        self.editingSuggestionWardrobeId = nil
        self.editingProposedName = nil
        self.editingProposedNotes = nil
        self.editingItemThumbnails = []
        _selectedWardrobe = State(initialValue: initialWardrobe)
        self.preselectedItemURI = nil
        self.preselectedRedressItem = nil
        self.preselectedRedressWardrobeType = "closet"
        self.preselectedRedressWardrobeId = nil
        self.sessionID = sessionID
        self.navigationPath = navigationPath
    }
    
    init(
        outfitToEdit: Outfit? = nil,
        wardrobeType: String = "closet",
        initialWardrobe: Wardrobe? = nil,
        lockWardrobeSource: Bool = false,
        wardrobeMembershipOnSave: Wardrobe? = nil,
        preselectedItemURI: String?,
        sessionID: UUID = UUID(),
        navigationPath: Binding<NavigationPath>? = nil
    ) {
        self.outfitToEdit = outfitToEdit
        self.wardrobeType = wardrobeType
        self.lockWardrobeSource = lockWardrobeSource
        self.wardrobeMembershipOnSave = wardrobeMembershipOnSave
        self.redressRecipient = nil
        self.editingSuggestionId = nil
        self.editingSuggestionWardrobeId = nil
        self.editingProposedName = nil
        self.editingProposedNotes = nil
        self.editingItemThumbnails = []
        _selectedWardrobe = State(initialValue: initialWardrobe)
        self.preselectedItemURI = preselectedItemURI
        self.preselectedRedressItem = nil
        self.preselectedRedressWardrobeType = "closet"
        self.preselectedRedressWardrobeId = nil
        self.sessionID = sessionID
        self.navigationPath = navigationPath
    }

    init(
        redressRecipient: PublicUserProfile,
        preselectedItem: VisibleWardrobeItem? = nil,
        preselectedWardrobeType: String = "closet",
        preselectedWardrobeId: UUID? = nil,
        editingSuggestionId: UUID? = nil,
        editingSuggestionWardrobeId: UUID? = nil,
        editingProposedName: String? = nil,
        editingProposedNotes: String? = nil,
        editingItemThumbnails: [VisibleOutfitItemThumb] = [],
        sessionID: UUID = UUID(),
        onRedressSent: (() -> Void)? = nil,
        navigationPath: Binding<NavigationPath>? = nil
    ) {
        self.outfitToEdit = nil
        self.wardrobeType = "closet"
        self.lockWardrobeSource = true
        self.wardrobeMembershipOnSave = nil
        self.redressRecipient = redressRecipient
        self.editingSuggestionId = editingSuggestionId
        self.editingSuggestionWardrobeId = editingSuggestionWardrobeId
        self.editingProposedName = editingProposedName
        self.editingProposedNotes = editingProposedNotes
        self.editingItemThumbnails = editingItemThumbnails
        self.onRedressSent = onRedressSent
        _selectedWardrobe = State(initialValue: nil)
        self.preselectedItemURI = nil
        self.preselectedRedressItem = preselectedItem
        self.preselectedRedressWardrobeType = preselectedWardrobeType.lowercased() == "wishlist" ? "wishlist" : "closet"
        self.preselectedRedressWardrobeId = preselectedWardrobeId ?? editingSuggestionWardrobeId
        self.sessionID = sessionID
        self.navigationPath = navigationPath
        _itemsSheetItemTypeSegment = State(
            initialValue: self.preselectedRedressWardrobeType == "wishlist" ? .wishlist : .closet
        )
    }

    private var squareSize: CGFloat {
        UIScreen.main.bounds.width
    }

    private func openItemsSheet() {
        itemsSheetSessionID = UUID()
        if isRedressMode {
            itemsSheetItemTypeSegment = preselectedRedressWardrobeType == "wishlist" ? .wishlist : .closet
        } else {
            itemsSheetItemTypeSegment = wardrobeType == "wishlist" ? .wishlist : .closet
        }
        itemsSheetDetent = .medium
        isItemsSheetPresented = true
    }

    private var outfitCanvasItemSelection: some View {
        Group {
            if isRedressMode, let recipient = redressRecipient {
                RedressItemSelectionView(
                    recipientUserId: recipient.userId,
                    initialWardrobeId: preselectedRedressWardrobeId,
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
                    // Defer Core Data / network work until after the navigation push finishes.
                    Task { @MainActor in
                        if editingSuggestionId != nil, !didLoadEditingSuggestion {
                            didLoadEditingSuggestion = true
                            applyEditingSuggestionSeed()
                            await refineEditingSuggestionTransforms()
                        } else if !didApplyPreselectedItem, let item = preselectedRedressItem {
                            ensureAttributeOutfitDraft()
                            isItemsSectionExpanded = false
                            didApplyPreselectedItem = true
                            itemsSheetItemTypeSegment = preselectedRedressWardrobeType == "wishlist" ? .wishlist : .closet
                            addPreselectedRedressItemToCanvas(item)
                        } else {
                            ensureAttributeOutfitDraft()
                            isItemsSectionExpanded = false
                        }
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
                            lockWardrobeSource: lockWardrobeSource,
                            wardrobeMembershipOnSave: wardrobeMembershipOnSave
                        )
                    }
                }
            }
            .sheet(isPresented: $isItemsSheetPresented) {
                NavigationStack {
                    outfitCanvasItemSelection
                }
                .presentationDetents([.medium, .large], selection: $itemsSheetDetent)
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
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
                .presentationDetents([.medium, .large], selection: $viewAllOutfitItemsSheetDetent)
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
            }
            .sheet(item: $attributesSheet) { sheet in
                if let outfit = activeOutfitForAttributes {
                    sheet.destination(for: outfit)
                }
            }
    }

    private var alertsContent: some View {
        outfitAddWithAlertsAndSheets
    }

    private var outfitAddMainColumn: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    outfitCollageArea
                        .frame(width: squareSize, height: squareSize)
                        .frame(maxWidth: .infinity)
                        .id(Self.canvasScrollID)
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color(.systemGray6))
                .listSectionSpacing(0)

                Section {
                    draftAndClearButtons
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color(.systemBackground))
                .listSectionSpacing(0)

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
                        attributesSectionBottomPad
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
            .scrollDisabled(canvasScrollLocked)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .onChange(of: selectedItemID) { _, newValue in
                handleCanvasSelectionScroll(newValue, proxy: proxy)
            }
        }
    }

    private func handleCanvasSelectionScroll(
        _ newValue: UUID?,
        proxy: ScrollViewProxy
    ) {
        if newValue != nil {
            // Keep scrolling enabled briefly so scrollTo can run, then lock.
            canvasScrollLocked = false
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                proxy.scrollTo(Self.canvasScrollID, anchor: .top)
            }
            DispatchQueue.main.async {
                if selectedItemID != nil {
                    canvasScrollLocked = true
                }
            }
        } else {
            canvasScrollLocked = false
        }
    }

    /// Matches ItemDetailView history section bottom pad.
    private var attributesSectionBottomPad: some View {
        Color.clear
            .frame(height: 4)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .environment(\.defaultMinListRowHeight, 1)
    }

    private var outfitAddWithNavigationChrome: some View {
        outfitAddMainColumn
            .navigationTitle(isRedressMode ? "" : "Outfit")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    leadingToolbarBackButton
                }
                if isRedressMode {
                    ToolbarItem(placement: .principal) {
                        redressPrincipalTitle
                    }
                    if !redressCanvasItems.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            sendRedressToolbarButton
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        outfitSaveToolbarButtons
                    }
                }
            }
            .overlay {
                if isSendingRedress {
                    redressSendingOverlay
                }
            }
    }

    private var redressPrincipalTitle: some View {
        VStack(spacing: 1) {
            Text("Redress")
                .font(.headline)
            Text(redressRecipientUsernameCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var outfitSaveToolbarButtons: some View {
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

    private var redressSendingOverlay: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            ProgressView("Sending…")
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var outfitAddWithAlertsAndSheets: some View {
        withDuplicateOutfitDestination(outfitAddWithDraftAndDiscardAlerts)
            .alert("Duplicate Outfit", isPresented: localDuplicateAlertPresented) {
                Button("View Existing") {
                    if let outfit = localDuplicateOutfit {
                        openExistingDuplicateOutfit(outfit)
                    }
                    localDuplicateOutfit = nil
                }
                Button("OK", role: .cancel) {
                    localDuplicateOutfit = nil
                }
            } message: {
                Text("You already have an outfit with this combination of items.")
            }
    }

    /// Closet/Wishlist pass `navigationPath` and append `.outfitDetail`; other hosts keep nested `item:`.
    @ViewBuilder
    private func withDuplicateOutfitDestination<Content: View>(_ content: Content) -> some View {
        if navigationPath != nil {
            content
        } else {
            content
                .navigationDestination(item: $existingDuplicateOutfitURI) { uriString in
                    duplicateOutfitDestination(uriString: uriString)
                }
        }
    }

    private func openExistingDuplicateOutfit(_ outfit: Outfit) {
        let uri = outfit.objectID.uriRepresentation().absoluteString
        if let navigationPath {
            navigationPath.wrappedValue.append(ItemGridFilterRoute.outfitDetail(uri: uri))
        } else {
            existingDuplicateOutfitURI = uri
        }
    }

    private var outfitAddWithRedressAlerts: some View {
        outfitAddWithNavigationChrome
            .alert("Clear Canvas?", isPresented: $showingClearRedressConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    clearRedressItems()
                }
            } message: {
                Text("Remove all items from this Redress?")
            }
            .alert("Send Redress?", isPresented: $showingSendRedressConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Send") {
                    submitRedressSuggestion()
                }
            } message: {
                Text(sendRedressConfirmMessage)
            }
        .alert("Redress Sent", isPresented: $showingRedressSentAlert) {
            Button("OK") {
                onRedressSent?()
                discardAttributeOutfitDraftIfNeeded()
                dismiss()
            }
        } message: {
            Text(
                editingSuggestionId == nil
                    ? "Your Redress was sent to \(redressRecipient?.username ?? redressRecipient?.displayName ?? "this user")."
                    : "Your Redress was updated for \(redressRecipient?.username ?? redressRecipient?.displayName ?? "this user")."
            )
        }
            .alert("Couldn't Send Redress", isPresented: redressSendErrorPresented) {
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
    }

    private var outfitAddWithDraftAndDiscardAlerts: some View {
        outfitAddWithRedressAlerts
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
                        clearRedressItems(recordHistory: false)
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
            .alert("Add Items to Wardrobe?", isPresented: $showWardrobeMembershipAlert) {
                Button("Add & Save") {
                    addPendingItemsToMembershipWardrobeAndSave()
                }
                Button("Cancel", role: .cancel) {
                    pendingMembershipAddCount = 0
                }
            } message: {
                Text(wardrobeMembershipAlertMessage)
            }
    }

    private var wardrobeMembershipAlertMessage: String {
        let count = pendingMembershipAddCount
        let rawName = wardrobeMembershipOnSave?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let wardrobeLabel = rawName.isEmpty ? "the current wardrobe" : "“\(rawName)”"
        let itemWord = count == 1 ? "item is" : "items are"
        let pronoun = count == 1 ? "it" : "them"
        return "\(count) \(itemWord) not in \(wardrobeLabel). Add \(pronoun) to save this outfit?"
    }

    @ViewBuilder
    private func duplicateOutfitDestination(uriString: String) -> some View {
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

    private var localDuplicateAlertPresented: Binding<Bool> {
        Binding(
            get: { localDuplicateOutfit != nil },
            set: { if !$0 { localDuplicateOutfit = nil } }
        )
    }

    // MARK: - Toolbar Items
    private var leadingToolbarBackButton: some View {
        Button {
            handleLeadingToolbarBack()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text(outfitToEdit != nil ? "Cancel" : "Back")
            }
        }
        .accessibilityLabel(outfitToEdit != nil ? "Cancel" : "Back")
    }

    private func handleLeadingToolbarBack() {
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

    private var collageEmptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            (
                Text("Tap ")
                    + Text("ITEMS").fontWeight(.bold)
                    + Text(" + to add items to canvas")
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            openItemsSheet()
        }
        .accessibilityLabel("Add items")
        .accessibilityAddTraits(.isButton)
    }

    private var collageBackground: some View {
        RoundedRectangle(cornerRadius: 0)
            .fill(Color(.systemBackground))
            .frame(width: squareSize, height: squareSize)
            .onTapGesture {
                handleBlankCanvasTap()
            }
    }

    private var isCanvasEmpty: Bool {
        isRedressMode ? redressCanvasItems.isEmpty : outfitItems.isEmpty
    }

    private func handleBlankCanvasTap() {
        if selectedItemID != nil {
            selectedItemID = nil
            return
        }
        if isCanvasEmpty {
            openItemsSheet()
        }
    }

    @ViewBuilder
    private var redressCollageArea: some View {
        // Layout size is locked to the square; sticker content is clipped so
        // selected overhang never expands the List row.
        let canvas = Color.clear
            .frame(width: squareSize, height: squareSize)
            .overlay {
                redressCanvasStack
            }
            .clipped()
            .contentShape(Rectangle())
            .overlay(alignment: .trailing) {
                if selectedItemID != nil {
                    VStack(spacing: 0) {
                        redressCanvasSelectionMenu
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 10)
                    .padding(.trailing, 10)
                }
            }

        if selectedItemID != nil {
            canvas
                .simultaneousGesture(canvasTransformGesture)
        } else {
            canvas
        }
    }

    private var redressCanvasSelectionMenu: some View {
        VStack(spacing: 4) {
            canvasMenuButton(
                systemName: "square.filled.on.square",
                accessibilityLabel: "Bring to front"
            ) {
                guard let item = selectedRedressCanvasItem else { return }
                bringRedressItemToFront(item)
            }
            canvasMenuButton(
                systemName: "square.on.square",
                accessibilityLabel: "Push to back"
            ) {
                guard let item = selectedRedressCanvasItem else { return }
                pushRedressItemToBack(item)
            }
            canvasMenuButton(
                systemName: "plus.magnifyingglass",
                accessibilityLabel: "Scale larger"
            ) {
                guard let item = selectedRedressCanvasItem else { return }
                scaleRedressItem(item, by: 1.15)
            }
            canvasMenuButton(
                systemName: "minus.magnifyingglass",
                accessibilityLabel: "Scale smaller"
            ) {
                guard let item = selectedRedressCanvasItem else { return }
                scaleRedressItem(item, by: 1 / 1.15)
            }
            canvasMenuButton(
                systemName: "trash",
                accessibilityLabel: "Remove from canvas",
                tint: .red
            ) {
                guard let item = selectedRedressCanvasItem else { return }
                removeRedressItem(item)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var selectedRedressCanvasItem: RedressCanvasItem? {
        guard let selectedItemID else { return nil }
        return redressCanvasItems.first(where: { $0.id == selectedItemID })
    }

    private func canvasMenuButton(
        systemName: String,
        accessibilityLabel: String,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.medium))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
    }

    private var redressCanvasStack: some View {
        ZStack {
            collageBackground
            if redressCanvasItems.isEmpty {
                collageEmptyPlaceholder
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
                    onDelete: { removeRedressItem(canvasItem) }
                )
            }
        }
        .frame(width: squareSize, height: squareSize)
        .clipped()
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var standardOutfitCollageArea: some View {
        // Layout size is locked to the square; sticker content is clipped so
        // drag overhang never expands the List row.
        let canvas = Color.clear
            .frame(width: squareSize, height: squareSize)
            .overlay {
                standardOutfitCanvasStack
            }
            .clipped()
            .contentShape(Rectangle())
            .overlay(alignment: .trailing) {
                if selectedItemID != nil {
                    VStack(spacing: 0) {
                        outfitCanvasSelectionMenu
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 10)
                    .padding(.trailing, 10)
                }
            }

        if selectedItemID != nil {
            canvas
                .simultaneousGesture(canvasTransformGesture)
        } else {
            canvas
        }
    }

    private var outfitCanvasSelectionMenu: some View {
        VStack(spacing: 4) {
            canvasMenuButton(
                systemName: "square.filled.on.square",
                accessibilityLabel: "Bring to front"
            ) {
                guard let item = selectedOutfitCanvasItem else { return }
                bringToFront(item)
            }
            canvasMenuButton(
                systemName: "square.on.square",
                accessibilityLabel: "Push to back"
            ) {
                guard let item = selectedOutfitCanvasItem else { return }
                pushOutfitItemToBack(item)
            }
            canvasMenuButton(
                systemName: "plus.magnifyingglass",
                accessibilityLabel: "Scale larger"
            ) {
                guard let item = selectedOutfitCanvasItem else { return }
                scaleOutfitItem(item, by: 1.15)
            }
            canvasMenuButton(
                systemName: "minus.magnifyingglass",
                accessibilityLabel: "Scale smaller"
            ) {
                guard let item = selectedOutfitCanvasItem else { return }
                scaleOutfitItem(item, by: 1 / 1.15)
            }
            canvasMenuButton(
                systemName: "trash",
                accessibilityLabel: "Remove from canvas",
                tint: .red
            ) {
                guard let item = selectedOutfitCanvasItem else { return }
                removeItem(item)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var selectedOutfitCanvasItem: OutfitItem? {
        guard let selectedItemID else { return nil }
        return outfitItems.first(where: { $0.id == selectedItemID })
    }

    private var standardOutfitCanvasStack: some View {
        ZStack {
            collageBackground
            if outfitItems.isEmpty {
                collageEmptyPlaceholder
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
        .clipped()
        .contentShape(Rectangle())
    }

    // MARK: - Canvas Controls Bar
    private var draftAndClearButtons: some View {
        VStack(spacing: 0) {
            Divider()
            Group {
                if isRedressMode {
                    redressCanvasControls
                } else {
                    standardCanvasControls
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical)
        }
    }

    private var redressCanvasControls: some View {
        ZStack {
            HStack(spacing: 16) {
                autoGridControl
                Spacer()
                undoRedoButtons
            }
            redressClearControl
        }
        .frame(height: 15)
    }

    private var standardCanvasControls: some View {
        ZStack {
            HStack(spacing: 16) {
                autoGridControl
                Spacer()
                undoRedoButtons
            }

            clearOutfitItemsControl
        }
        .frame(height: 15)
    }

    private var isAutoGridDisabled: Bool {
        isRedressMode ? redressCanvasItems.isEmpty : outfitItems.isEmpty
    }

    /// Tap controls (not `Button`) avoid SwiftUI List/toolbar action mix-ups.
    private var autoGridControl: some View {
        Image(systemName: "square.grid.2x2")
            .foregroundStyle(isAutoGridDisabled ? Color.secondary : Color.accentColor)
            .opacity(isAutoGridDisabled ? 0.45 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isAutoGridDisabled else { return }
                if isRedressMode {
                    autoGridRedressLayout()
                } else {
                    autoGridLayout()
                }
            }
            .accessibilityLabel("Auto-Grid")
            .accessibilityAddTraits(.isButton)
            .disabled(isAutoGridDisabled)
    }

    private var redressClearControl: some View {
        Text("Clear")
            .foregroundStyle(redressCanvasItems.isEmpty || isSendingRedress ? Color.secondary : Color.red)
            .opacity(redressCanvasItems.isEmpty || isSendingRedress ? 0.45 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !redressCanvasItems.isEmpty, !isSendingRedress else { return }
                showingClearRedressConfirm = true
            }
            .accessibilityLabel("Clear")
            .accessibilityAddTraits(.isButton)
    }

    private var sendRedressConfirmMessage: String {
        let name = redressRecipient?.username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        let display = name.isEmpty
            ? (redressRecipient?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "this user")
            : name
        if editingSuggestionId == nil {
            return "Send this Redress to \(display)?"
        }
        return "Update your pending Redress for \(display)?"
    }

    private var sendRedressToolbarButton: some View {
        Button("Send") {
            showingSendRedressConfirm = true
        }
        .disabled(redressCanvasItems.isEmpty || isSendingRedress)
        .opacity(redressCanvasItems.isEmpty || isSendingRedress ? 0.5 : 1)
        .accessibilityLabel("Send Redress")
    }

    private var canUndoCanvas: Bool {
        isRedressMode ? !redressUndoStack.isEmpty : !undoStack.isEmpty
    }

    private var canRedoCanvas: Bool {
        isRedressMode ? !redressRedoStack.isEmpty : !redoStack.isEmpty
    }

    private var undoRedoButtons: some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.uturn.backward")
                .foregroundColor(canUndoCanvas ? .primary : .gray)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard canUndoCanvas else { return }
                    undo()
                }
                .accessibilityLabel("Undo")
                .accessibilityAddTraits(.isButton)

            Image(systemName: "arrow.uturn.forward")
                .foregroundColor(canRedoCanvas ? .primary : .gray)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard canRedoCanvas else { return }
                    redo()
                }
                .accessibilityLabel("Redo")
                .accessibilityAddTraits(.isButton)
        }
    }

    private var clearOutfitItemsControl: some View {
        Text("Clear")
            .foregroundColor(outfitItems.isEmpty ? .secondary : .red)
            .opacity(outfitItems.isEmpty ? 0.45 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !outfitItems.isEmpty else { return }
                clearAllItems()
            }
            .accessibilityLabel("Clear")
            .accessibilityAddTraits(.isButton)
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
        viewAllOutfitItemsSheetDetent = .medium
        showViewAllOutfitItemsSheet = true
    }

    private func selectItemOnCanvas(_ item: Item) {
        if let outfitItem = outfitItems.first(where: { $0.item.objectID == item.objectID }) {
            selectItem(outfitItem)
        }
    }

    @ViewBuilder
    private var redressFeaturedItemsSectionContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !redressCanvasItemsOrdered.isEmpty {
                RedressFeaturedItemsSubsectionRow(
                    pairedItems: redressCanvasItemsOrdered,
                    wardrobeSections: redressNamedWardrobeSections,
                    showsWardrobeLabels: shouldSplitRedressCanvasByWardrobe,
                    onSelectItem: { selectRedressItemOnCanvas($0) },
                    onViewAll: { openItemsSheet() }
                )
            }
        }
        .listRowInsets(EdgeInsets(.zero))
    }

    private var redressCanvasItemsOrdered: [VisibleWardrobeItem] {
        // Insertion order — independent of canvas z-order (bring front / send back).
        redressCanvasItems.map(\.item)
    }

    /// Split ITEMS when canvas items come from more than one wardrobe.
    private var shouldSplitRedressCanvasByWardrobe: Bool {
        redressNamedWardrobeSections.count >= 2
    }

    /// Named wardrobe groups; source wardrobe first, then any other wardrobes underneath.
    private var redressNamedWardrobeSections: [RedressWardrobeItemsSection] {
        let sourceId = preselectedRedressWardrobeId

        struct Acc {
            var name: String
            var type: String
            var items: [VisibleWardrobeItem]
        }
        var grouped: [UUID: Acc] = [:]
        var orderKeys: [UUID] = []

        for canvasItem in redressCanvasItems {
            let key = canvasItem.sourceWardrobeId
                ?? (canvasItem.sourceWardrobeType == "wishlist"
                    ? UUID(uuidString: "00000000-0000-0000-0000-00000000FFFF")!
                    : UUID(uuidString: "00000000-0000-0000-0000-00000000FFFE")!)
            if grouped[key] == nil {
                grouped[key] = Acc(
                    name: canvasItem.displayWardrobeName,
                    type: canvasItem.sourceWardrobeType,
                    items: []
                )
                orderKeys.append(key)
            }
            grouped[key]?.items.append(canvasItem.item)
        }

        let sections = orderKeys.compactMap { key -> RedressWardrobeItemsSection? in
            guard let acc = grouped[key], !acc.items.isEmpty else { return nil }
            return RedressWardrobeItemsSection(
                id: key,
                name: acc.name,
                wardrobeType: acc.type,
                items: acc.items
            )
        }

        guard sections.count >= 2 else { return sections }

        return sections.sorted { a, b in
            // Source wardrobe first when present.
            if let sourceId {
                if a.id == sourceId && b.id != sourceId { return true }
                if b.id == sourceId && a.id != sourceId { return false }
            }
            // Prefer matching source type next, then name.
            let sourceType = preselectedRedressWardrobeType
            let ra = a.wardrobeType == sourceType ? 0 : 1
            let rb = b.wardrobeType == sourceType ? 0 : 1
            if ra != rb { return ra < rb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
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
        if isRedressMode {
            saveRedressState()
            return
        }
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

    private func saveRedressState() {
        let snapshots = redressCanvasItems.map { canvasItem -> RedressCanvasStateSnapshot in
            RedressCanvasStateSnapshot(
                canvasItemID: canvasItem.id,
                itemID: canvasItem.item.id,
                sourceWardrobeType: canvasItem.sourceWardrobeType,
                sourceWardrobeId: canvasItem.sourceWardrobeId,
                sourceWardrobeName: canvasItem.sourceWardrobeName,
                name: canvasItem.item.name,
                thumbnailUrl: canvasItem.item.thumbnailUrl,
                imageUrl: canvasItem.item.imageUrl,
                positionX: canvasItem.position.x,
                positionY: canvasItem.position.y,
                displayWidth: canvasItem.displaySize.width,
                displayHeight: canvasItem.displaySize.height,
                scale: canvasItem.scale,
                rotation: canvasItem.rotation,
                zIndex: canvasItem.zIndex
            )
        }
        redressUndoStack.append(RedressCanvasState(snapshots: snapshots))
        redressRedoStack.removeAll()
    }

    private func currentRedressSnapshots() -> [RedressCanvasStateSnapshot] {
        redressCanvasItems.map { canvasItem in
            RedressCanvasStateSnapshot(
                canvasItemID: canvasItem.id,
                itemID: canvasItem.item.id,
                sourceWardrobeType: canvasItem.sourceWardrobeType,
                sourceWardrobeId: canvasItem.sourceWardrobeId,
                sourceWardrobeName: canvasItem.sourceWardrobeName,
                name: canvasItem.item.name,
                thumbnailUrl: canvasItem.item.thumbnailUrl,
                imageUrl: canvasItem.item.imageUrl,
                positionX: canvasItem.position.x,
                positionY: canvasItem.position.y,
                displayWidth: canvasItem.displaySize.width,
                displayHeight: canvasItem.displaySize.height,
                scale: canvasItem.scale,
                rotation: canvasItem.rotation,
                zIndex: canvasItem.zIndex
            )
        }
    }

    private func undo() {
        if isRedressMode {
            undoRedress()
            return
        }
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

    private func undoRedress() {
        guard !redressUndoStack.isEmpty else { return }
        redressRedoStack.append(RedressCanvasState(snapshots: currentRedressSnapshots()))
        let previousState = redressUndoStack.removeLast()
        restoreRedressState(previousState)
    }

    private func redo() {
        if isRedressMode {
            redoRedress()
            return
        }
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

    private func redoRedress() {
        guard !redressRedoStack.isEmpty else { return }
        redressUndoStack.append(RedressCanvasState(snapshots: currentRedressSnapshots()))
        let nextState = redressRedoStack.removeLast()
        restoreRedressState(nextState)
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

    private func restoreRedressState(_ state: RedressCanvasState) {
        let previousSelection = selectedItemID
        let existingByCanvasID = Dictionary(
            uniqueKeysWithValues: redressCanvasItems.map { ($0.id, $0) }
        )
        let existingByItemID = Dictionary(
            uniqueKeysWithValues: redressCanvasItems.map { ($0.item.id, $0) }
        )

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            redressCanvasItems = state.snapshots.map { snapshot in
                let reused = existingByCanvasID[snapshot.canvasItemID]
                    ?? existingByItemID[snapshot.itemID]
                return RedressCanvasItem(
                    id: snapshot.canvasItemID,
                    item: reused?.item ?? VisibleWardrobeItem(
                        id: snapshot.itemID,
                        name: snapshot.name,
                        thumbnailUrl: snapshot.thumbnailUrl,
                        imageUrl: snapshot.imageUrl
                    ),
                    sourceWardrobeType: snapshot.sourceWardrobeType,
                    sourceWardrobeId: snapshot.sourceWardrobeId ?? reused?.sourceWardrobeId,
                    sourceWardrobeName: snapshot.sourceWardrobeName ?? reused?.sourceWardrobeName,
                    position: CGPoint(x: snapshot.positionX, y: snapshot.positionY),
                    displaySize: reused.map(\.displaySize)
                        ?? CGSize(width: snapshot.displayWidth, height: snapshot.displayHeight),
                    scale: snapshot.scale,
                    rotation: snapshot.rotation,
                    zIndex: snapshot.zIndex
                )
            }

            if let previousSelection,
               redressCanvasItems.contains(where: { $0.id == previousSelection }) {
                selectedItemID = previousSelection
            } else {
                selectedItemID = nil
            }
            isItemsSectionExpanded = !redressCanvasItems.isEmpty
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

    /// Places seeded pending-detail thumbs on the canvas immediately (no network).
    @MainActor
    private func applyEditingSuggestionSeed() {
        ensureAttributeOutfitDraft()
        if let name = editingProposedName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            attributeOutfitDraft?.name = name
        }
        if let notes = editingProposedNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            attributeOutfitDraft?.notes = notes
        }

        guard redressCanvasItems.isEmpty else {
            isItemsSectionExpanded = !redressCanvasItems.isEmpty
            return
        }

        let center = CGPoint(x: squareSize / 2, y: squareSize / 2)
        let thumbs = editingItemThumbnails
        if thumbs.isEmpty {
            isItemsSectionExpanded = false
            return
        }

        let seedType = preselectedRedressWardrobeType
        let seedWardrobeId = preselectedRedressWardrobeId ?? editingSuggestionWardrobeId
        redressCanvasItems = thumbs.enumerated().map { index, thumb in
            RedressCanvasItem(
                item: VisibleWardrobeItem(
                    id: thumb.id,
                    name: thumb.name,
                    thumbnailUrl: thumb.thumbnailUrl,
                    imageUrl: thumb.thumbnailUrl
                ),
                sourceWardrobeType: seedType,
                sourceWardrobeId: seedWardrobeId,
                sourceWardrobeName: nil,
                position: center,
                displaySize: RedressCanvasItem.defaultDisplaySize(canvasSize: squareSize),
                scale: 1,
                rotation: 0,
                zIndex: index
            )
        }
        isItemsSectionExpanded = true
    }

    /// Applies saved canvas transforms after seed is visible.
    private func refineEditingSuggestionTransforms() async {
        guard let suggestionId = editingSuggestionId else { return }

        do {
            let record = try await supabaseService.fetchOutfitSuggestionForMaterialization(
                suggestionId: suggestionId
            )
            var transformsByItemId: [UUID: SavedOutfitItem] = [:]
            for saved in record.transformationSavedItems() {
                guard let id = UUID(uuidString: saved.itemID) else { continue }
                transformsByItemId[id] = saved
            }
            guard !transformsByItemId.isEmpty else { return }

            await MainActor.run {
                let center = CGPoint(x: squareSize / 2, y: squareSize / 2)
                // Apply transforms + wardrobe metadata onto seeded canvas items.
                for index in redressCanvasItems.indices {
                    let itemId = redressCanvasItems[index].item.id
                    guard let saved = transformsByItemId[itemId] else { continue }
                    let existing = redressCanvasItems[index]
                    let type: String = {
                        if let raw = saved.sourceWardrobeType?.lowercased() {
                            return raw == "wishlist" ? "wishlist" : "closet"
                        }
                        return existing.sourceWardrobeType
                    }()
                    redressCanvasItems[index] = RedressCanvasItem(
                        id: existing.id,
                        item: existing.item,
                        sourceWardrobeType: type,
                        sourceWardrobeId: saved.sourceWardrobeId.flatMap(UUID.init(uuidString:)) ?? existing.sourceWardrobeId,
                        sourceWardrobeName: saved.sourceWardrobeName ?? existing.sourceWardrobeName,
                        position: CGPoint(x: saved.positionX, y: saved.positionY),
                        displaySize: existing.displaySize,
                        scale: saved.scale,
                        rotation: saved.rotation,
                        zIndex: saved.zIndex
                    )
                }

                // If seed was empty, build from transforms + record item ids.
                if redressCanvasItems.isEmpty {
                    let fromTransforms = record.transformationSavedItems().compactMap { UUID(uuidString: $0.itemID) }
                    let orderedIds = fromTransforms.isEmpty ? record.itemIds : fromTransforms
                    redressCanvasItems = orderedIds.enumerated().map { index, itemId in
                        let saved = transformsByItemId[itemId]
                        let savedType = saved?.sourceWardrobeType?.lowercased() == "wishlist" ? "wishlist" : "closet"
                        return RedressCanvasItem(
                            item: VisibleWardrobeItem(
                                id: itemId,
                                name: nil,
                                thumbnailUrl: nil,
                                imageUrl: nil
                            ),
                            sourceWardrobeType: saved?.sourceWardrobeType != nil ? savedType : (preselectedRedressWardrobeType),
                            sourceWardrobeId: saved?.sourceWardrobeId.flatMap(UUID.init(uuidString:))
                                ?? preselectedRedressWardrobeId
                                ?? editingSuggestionWardrobeId,
                            sourceWardrobeName: saved?.sourceWardrobeName,
                            position: CGPoint(
                                x: saved?.positionX ?? center.x,
                                y: saved?.positionY ?? center.y
                            ),
                            displaySize: RedressCanvasItem.defaultDisplaySize(canvasSize: squareSize),
                            scale: saved?.scale ?? 1,
                            rotation: saved?.rotation ?? 0,
                            zIndex: saved?.zIndex ?? index
                        )
                    }
                    isItemsSectionExpanded = !redressCanvasItems.isEmpty
                }
            }
        } catch {
            print("❌ [OutfitAddView] Failed to refine edit transforms: \(error.localizedDescription)")
        }
    }

    private func addPreselectedRedressItemToCanvas(_ item: VisibleWardrobeItem) {
        guard isRedressMode else { return }
        guard !redressCanvasItems.contains(where: { $0.item.id == item.id }) else { return }
        saveState()

        let center = CGPoint(x: squareSize / 2, y: squareSize / 2)
        let canvasItem = RedressCanvasItem(
            item: item,
            sourceWardrobeType: preselectedRedressWardrobeType,
            sourceWardrobeId: preselectedRedressWardrobeId,
            sourceWardrobeName: nil,
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

    private func addRedressItemToCanvas(_ item: VisibleWardrobeItem, wardrobe: VisibleWardrobe) {
        guard isRedressMode else { return }
        guard !redressCanvasItems.contains(where: { $0.item.id == item.id }) else { return }
        saveState()

        let center = CGPoint(x: squareSize / 2, y: squareSize / 2)
        let sourceType = wardrobe.wardrobeType == "wishlist" ? "wishlist" : "closet"
        let canvasItem = RedressCanvasItem(
            item: item,
            sourceWardrobeType: sourceType,
            sourceWardrobeId: wardrobe.id,
            sourceWardrobeName: wardrobe.name,
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
        updateRedressCanvasWithoutAnimation {
            var item = redressCanvasItems[index]
            item.scale = scale
            redressCanvasItems[index] = item
        }
    }

    private func applyRedressRotation(_ rotation: Double, at index: Int) {
        updateRedressCanvasWithoutAnimation {
            var item = redressCanvasItems[index]
            item.rotation = rotation
            redressCanvasItems[index] = item
        }
    }

    private func updateRedressItemPosition(_ canvasItem: RedressCanvasItem, _ newPosition: CGPoint) {
        updateRedressCanvasWithoutAnimation {
            if let index = redressCanvasItems.firstIndex(where: { $0.id == canvasItem.id }) {
                redressCanvasItems[index].position = newPosition
            }
        }
    }

    private func updateRedressItemScale(_ canvasItem: RedressCanvasItem, _ newScale: CGFloat) {
        updateRedressCanvasWithoutAnimation {
            if let index = redressCanvasItems.firstIndex(where: { $0.id == canvasItem.id }) {
                redressCanvasItems[index].scale = newScale
            }
        }
    }

    private func updateRedressItemRotation(_ canvasItem: RedressCanvasItem, _ newRotation: Double) {
        updateRedressCanvasWithoutAnimation {
            if let index = redressCanvasItems.firstIndex(where: { $0.id == canvasItem.id }) {
                redressCanvasItems[index].rotation = newRotation
            }
        }
    }

    /// Gesture-driven canvas edits should snap immediately; spring is reserved for undo/redo.
    private func updateRedressCanvasWithoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    }

    private func bringRedressItemToFront(_ canvasItem: RedressCanvasItem) {
        saveState()
        let maxZIndex = redressCanvasItems.map(\.zIndex).max() ?? 0
        if let index = redressCanvasItems.firstIndex(where: { $0.id == canvasItem.id }) {
            redressCanvasItems[index].zIndex = maxZIndex + 1
        }
        selectedItemID = canvasItem.id
    }

    private func pushRedressItemToBack(_ canvasItem: RedressCanvasItem) {
        saveState()
        let minZIndex = redressCanvasItems.map(\.zIndex).min() ?? 0
        if let index = redressCanvasItems.firstIndex(where: { $0.id == canvasItem.id }) {
            redressCanvasItems[index].zIndex = minZIndex - 1
        }
        selectedItemID = canvasItem.id
    }

    private func scaleRedressItem(_ canvasItem: RedressCanvasItem, by factor: CGFloat) {
        guard let index = redressCanvasItems.firstIndex(where: { $0.id == canvasItem.id }) else { return }
        let next = max(0.3, min(4.0, redressCanvasItems[index].scale * factor))
        guard abs(next - redressCanvasItems[index].scale) > 0.0001 else { return }
        saveState()
        updateRedressCanvasWithoutAnimation {
            redressCanvasItems[index].scale = next
        }
        selectedItemID = canvasItem.id
    }

    private func removeRedressItem(_ canvasItem: RedressCanvasItem) {
        saveState()
        redressCanvasItems.removeAll { $0.id == canvasItem.id }
        if selectedItemID == canvasItem.id {
            selectedItemID = nil
        }
    }

    private func clearRedressItems(recordHistory: Bool = true) {
        if recordHistory {
            saveState()
        }
        selectedItemID = nil
        withAnimation(.spring()) {
            redressCanvasItems.removeAll()
        }
    }

    private func autoGridRedressLayout() {
        guard !redressCanvasItems.isEmpty else { return }
        saveState()
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
        let maxZIndex = outfitItems.map { $0.zIndex }.max() ?? 0
        if let index = outfitItems.firstIndex(where: { $0.id == outfitItem.id }) {
            outfitItems[index].zIndex = maxZIndex + 1
        }
        selectedItemID = outfitItem.id
    }

    private func pushOutfitItemToBack(_ outfitItem: OutfitItem) {
        saveState()
        let minZIndex = outfitItems.map(\.zIndex).min() ?? 0
        if let index = outfitItems.firstIndex(where: { $0.id == outfitItem.id }) {
            outfitItems[index].zIndex = minZIndex - 1
        }
        selectedItemID = outfitItem.id
    }

    private func scaleOutfitItem(_ outfitItem: OutfitItem, by factor: CGFloat) {
        guard let index = outfitItems.firstIndex(where: { $0.id == outfitItem.id }) else { return }
        let next = max(0.3, min(4.0, outfitItems[index].scale * factor))
        guard abs(next - outfitItems[index].scale) > 0.0001 else { return }
        saveState()
        updateItemScale(outfitItem, next)
        selectedItemID = outfitItem.id
    }

    private func removeItem(_ outfitItem: OutfitItem) {
        saveState()
        outfitItems.removeAll { $0.id == outfitItem.id }
        if selectedItemID == outfitItem.id {
            selectedItemID = nil
        }
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
        guard captureCollageAsImage() != nil else {
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

        let missing = itemsMissingFromMembershipWardrobe()
        if !missing.isEmpty {
            pendingMembershipAddCount = missing.count
            showWardrobeMembershipAlert = true
            return
        }

        performSaveOutfit()
    }

    private func itemsMissingFromMembershipWardrobe() -> [Item] {
        guard let wardrobe = wardrobeMembershipOnSave else { return [] }
        let wardrobeID = wardrobe.objectID
        var seen = Set<NSManagedObjectID>()
        var missing: [Item] = []
        for outfitItem in outfitItems {
            let item = outfitItem.item
            guard seen.insert(item.objectID).inserted else { continue }
            let wardrobes = item.wardrobes as? Set<Wardrobe> ?? []
            if !wardrobes.contains(where: { $0.objectID == wardrobeID }) {
                missing.append(item)
            }
        }
        return missing
    }

    private func addPendingItemsToMembershipWardrobeAndSave() {
        guard let wardrobe = wardrobeMembershipOnSave else {
            pendingMembershipAddCount = 0
            performSaveOutfit()
            return
        }
        let missing = itemsMissingFromMembershipWardrobe()
        for item in missing {
            wardrobe.addToItems(item)
            setUpdatedAt(item)
        }
        pendingMembershipAddCount = 0
        performSaveOutfit()
        for item in missing {
            SyncService.shared.syncItemIfNeeded(item)
        }
    }

    private func performSaveOutfit() {
        guard let collageImage = captureCollageAsImage() else {
            print("Failed to capture collage image")
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
                        zIndex: canvasItem.zIndex,
                        sourceWardrobeId: canvasItem.sourceWardrobeId?.uuidString,
                        sourceWardrobeName: canvasItem.sourceWardrobeName,
                        sourceWardrobeType: canvasItem.sourceWardrobeType
                    )
                }
                let transformationJSON = String(data: try JSONEncoder().encode(savedItems), encoding: .utf8) ?? "[]"
                let suggestionId = editingSuggestionId ?? UUID()
                let isEditingExisting = editingSuggestionId != nil

                let imageURL = try await supabaseService.uploadOutfitSuggestionImage(
                    imageData: imageData,
                    suggestionId: suggestionId,
                    userId: suggesterId
                )

                let payload = SupabaseService.CreateOutfitSuggestionPayload(
                    suggestionId: suggestionId,
                    recipientId: recipient.userId,
                    proposedName: proposedName?.isEmpty == true ? nil : proposedName,
                    proposedNotes: proposedNotes?.isEmpty == true ? nil : proposedNotes,
                    imageURL: imageURL,
                    transformationJSON: transformationJSON,
                    itemIds: itemIds
                )
                if isEditingExisting {
                    _ = try await supabaseService.updatePendingOutfitSuggestion(payload)
                } else {
                    _ = try await supabaseService.createOutfitSuggestion(payload)
                }

                await MainActor.run {
                    clearRedressItems(recordHistory: false)
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
    /// Wardrobe the item was picked from when composing Redress (optional for older payloads).
    let sourceWardrobeId: String?
    let sourceWardrobeName: String?
    let sourceWardrobeType: String?

    init(
        itemID: String,
        positionX: CGFloat,
        positionY: CGFloat,
        scale: CGFloat,
        rotation: Double,
        zIndex: Int,
        sourceWardrobeId: String? = nil,
        sourceWardrobeName: String? = nil,
        sourceWardrobeType: String? = nil
    ) {
        self.itemID = itemID
        self.positionX = positionX
        self.positionY = positionY
        self.scale = scale
        self.rotation = rotation
        self.zIndex = zIndex
        self.sourceWardrobeId = sourceWardrobeId
        self.sourceWardrobeName = sourceWardrobeName
        self.sourceWardrobeType = sourceWardrobeType
    }

    enum CodingKeys: String, CodingKey {
        case itemID, positionX, positionY, scale, rotation, zIndex
        case sourceWardrobeId, sourceWardrobeName, sourceWardrobeType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemID = try c.decode(String.self, forKey: .itemID)
        positionX = try c.decode(CGFloat.self, forKey: .positionX)
        positionY = try c.decode(CGFloat.self, forKey: .positionY)
        scale = try c.decode(CGFloat.self, forKey: .scale)
        rotation = try c.decode(Double.self, forKey: .rotation)
        zIndex = try c.decode(Int.self, forKey: .zIndex)
        sourceWardrobeId = try c.decodeIfPresent(String.self, forKey: .sourceWardrobeId)
        sourceWardrobeName = try c.decodeIfPresent(String.self, forKey: .sourceWardrobeName)
        sourceWardrobeType = try c.decodeIfPresent(String.self, forKey: .sourceWardrobeType)
    }
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

// MARK: - Redress Canvas State Snapshot (for undo/redo)
struct RedressCanvasStateSnapshot {
    let canvasItemID: UUID
    let itemID: UUID
    let sourceWardrobeType: String
    let sourceWardrobeId: UUID?
    let sourceWardrobeName: String?
    let name: String?
    let thumbnailUrl: String?
    let imageUrl: String?
    let positionX: CGFloat
    let positionY: CGFloat
    let displayWidth: CGFloat
    let displayHeight: CGFloat
    let scale: CGFloat
    let rotation: Double
    let zIndex: Int
}

struct RedressCanvasState {
    let snapshots: [RedressCanvasStateSnapshot]
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
    /// While true, ignore the delete control so a long-press release cannot hit it.
    @State private var isLongPressing = false

    private let deleteButtonSize: CGFloat = 24
    private let deleteHitTargetSize: CGFloat = 44

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
                .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 10, pressing: { pressing in
                    isLongPressing = pressing
                }, perform: {
                    onLongPress()
                })
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
                        .frame(width: deleteHitTargetSize, height: deleteHitTargetSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: deleteHitTargetSize, height: deleteHitTargetSize)
                .position(deleteButtonPosition)
                .allowsHitTesting(!isLongPressing)
            }
        }
        // Lock layout to the canvas square; parent/stack clipping handles sticker overhang.
        .frame(width: canvasSize, height: canvasSize)
        .clipped()
        .allowsHitTesting(true)
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
