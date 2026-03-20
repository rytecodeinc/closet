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

// MARK: - Category Size Weight
/// Determines relative visual weight of a clothing item on the canvas.
enum CategorySizeWeight: CGFloat {
    case large  = 1.00   // dresses, coats, outerwear, suits, jumpsuits
    case medium = 0.72   // tops, bottoms, activewear, swimwear
    case small  = 0.46   // shoes, bags, accessories, jewelry, hats, belts
}

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

// MARK: - Adaptive Layout Engine

/// Computes positions and sizes for all items on the canvas so they
/// fill the available space intelligently based on count and category.
struct AdaptiveLayoutEngine {

    struct LayoutResult {
        let frame: CGRect   // position + size in canvas coordinates
        let zIndex: Int
    }

    /// Returns a layout result for every item in `items`, ordered to match.
    static func layout(items: [OutfitItem], canvasSize: CGFloat) -> [UUID: LayoutResult] {
        guard !items.isEmpty else { return [:] }

        let count = items.count

        // Build raw weight for each item based on category
        let weights = items.map { sizeWeight(for: $0.item).rawValue }
        let totalWeight = weights.reduce(0, +)

        // Choose a layout strategy
        switch count {
        case 1:
            return singleItemLayout(items: items, canvasSize: canvasSize)
        case 2:
            return twoItemLayout(items: items, weights: weights, canvasSize: canvasSize)
        case 3:
            return threeItemLayout(items: items, weights: weights, canvasSize: canvasSize)
        case 4:
            return fourItemLayout(items: items, weights: weights, canvasSize: canvasSize)
        default:
            return gridLayout(items: items, weights: weights, canvasSize: canvasSize)
        }
    }

    // MARK: Layout Strategies

    private static func singleItemLayout(items: [OutfitItem], canvasSize: CGFloat) -> [UUID: LayoutResult] {
        let item = items[0]
        let weight = sizeWeight(for: item.item).rawValue
        // Fill most of the canvas
        let maxDim = canvasSize * 0.82 * weight
        let size = CGSize(width: maxDim, height: maxDim)
        let origin = CGPoint(x: (canvasSize - size.width) / 2,
                             y: (canvasSize - size.height) / 2)
        return [item.id: LayoutResult(frame: CGRect(origin: origin, size: size), zIndex: 0)]
    }

    private static func twoItemLayout(items: [OutfitItem], weights: [CGFloat], canvasSize: CGFloat) -> [UUID: LayoutResult] {
        let padding: CGFloat = 8
        let totalWeight = weights[0] + weights[1]

        // Determine if they should be side-by-side (both horizontal) or stacked
        // Prefer stacked (top/bottom) for outfit flow; side-by-side for accessories
        let bothSmall = weights.allSatisfy { $0 <= CategorySizeWeight.small.rawValue }
        let isHorizontal = bothSmall

        var result: [UUID: LayoutResult] = [:]

        if isHorizontal {
            let availW = (canvasSize - padding * 3) / 2
            let availH = canvasSize - padding * 2
            for (i, item) in items.enumerated() {
                let size = fitSize(weight: weights[i], availableSize: CGSize(width: availW, height: availH))
                let x = padding + CGFloat(i) * (availW + padding) + (availW - size.width) / 2
                let y = (canvasSize - size.height) / 2
                result[item.id] = LayoutResult(frame: CGRect(x: x, y: y, width: size.width, height: size.height), zIndex: i)
            }
        } else {
            // Stack vertically proportional to weight
            let availH = canvasSize - padding * 3
            let availW = canvasSize - padding * 2
            var yOffset = padding
            for (i, item) in items.enumerated() {
                let proportion = weights[i] / totalWeight
                let cellH = availH * proportion
                let size = fitSize(weight: weights[i], availableSize: CGSize(width: availW, height: cellH))
                let x = (canvasSize - size.width) / 2
                let y = yOffset + (cellH - size.height) / 2
                result[item.id] = LayoutResult(frame: CGRect(x: x, y: y, width: size.width, height: size.height), zIndex: i)
                yOffset += cellH + padding
            }
        }
        return result
    }

    private static func threeItemLayout(items: [OutfitItem], weights: [CGFloat], canvasSize: CGFloat) -> [UUID: LayoutResult] {
        let padding: CGFloat = 8
        // Sort items: large/medium go top, small go bottom row
        let sorted = items.enumerated().sorted { sizeWeight(for: $0.element.item).rawValue > sizeWeight(for: $1.element.item).rawValue }
        let top2 = sorted.prefix(2).map { items[$0.offset] }
        let bottom1 = sorted.dropFirst(2).map { items[$0.offset] }

        var result: [UUID: LayoutResult] = [:]

        // Top row: 2 items side-by-side
        let topH = canvasSize * 0.58
        let colW = (canvasSize - padding * 3) / 2
        for (i, item) in top2.enumerated() {
            let w = weights[items.firstIndex(where: { $0.id == item.id })!]
            let size = fitSize(weight: w, availableSize: CGSize(width: colW, height: topH - padding * 2))
            let x = padding + CGFloat(i) * (colW + padding) + (colW - size.width) / 2
            let y = padding + (topH - padding * 2 - size.height) / 2
            result[item.id] = LayoutResult(frame: CGRect(x: x, y: y, width: size.width, height: size.height), zIndex: i)
        }

        // Bottom row: 1 item centered
        let bottomStartY = topH
        let bottomH = canvasSize - topH - padding
        for item in bottom1 {
            let w = weights[items.firstIndex(where: { $0.id == item.id })!]
            let size = fitSize(weight: w, availableSize: CGSize(width: canvasSize - padding * 2, height: bottomH - padding))
            let x = (canvasSize - size.width) / 2
            let y = bottomStartY + (bottomH - size.height) / 2
            result[item.id] = LayoutResult(frame: CGRect(x: x, y: y, width: size.width, height: size.height), zIndex: 2)
        }
        return result
    }

    private static func fourItemLayout(items: [OutfitItem], weights: [CGFloat], canvasSize: CGFloat) -> [UUID: LayoutResult] {
        let padding: CGFloat = 8
        let cols = 2
        let rows = 2
        let cellW = (canvasSize - padding * CGFloat(cols + 1)) / CGFloat(cols)
        let cellH = (canvasSize - padding * CGFloat(rows + 1)) / CGFloat(rows)

        var result: [UUID: LayoutResult] = [:]
        for (i, item) in items.enumerated() {
            let col = CGFloat(i % cols)
            let row = CGFloat(i / cols)
            let size = fitSize(weight: weights[i], availableSize: CGSize(width: cellW, height: cellH))
            let x = padding + col * (cellW + padding) + (cellW - size.width) / 2
            let y = padding + row * (cellH + padding) + (cellH - size.height) / 2
            result[item.id] = LayoutResult(frame: CGRect(x: x, y: y, width: size.width, height: size.height), zIndex: i)
        }
        return result
    }

    private static func gridLayout(items: [OutfitItem], weights: [CGFloat], canvasSize: CGFloat) -> [UUID: LayoutResult] {
        let padding: CGFloat = 6
        let cols = items.count <= 6 ? 3 : 4
        let rows = Int(ceil(Double(items.count) / Double(cols)))
        let cellW = (canvasSize - padding * CGFloat(cols + 1)) / CGFloat(cols)
        let cellH = (canvasSize - padding * CGFloat(rows + 1)) / CGFloat(rows)

        var result: [UUID: LayoutResult] = [:]
        for (i, item) in items.enumerated() {
            let col = CGFloat(i % cols)
            let row = CGFloat(i / cols)
            let size = fitSize(weight: weights[i], availableSize: CGSize(width: cellW, height: cellH))
            let x = padding + col * (cellW + padding) + (cellW - size.width) / 2
            let y = padding + row * (cellH + padding) + (cellH - size.height) / 2
            result[item.id] = LayoutResult(frame: CGRect(x: x, y: y, width: size.width, height: size.height), zIndex: i)
        }
        return result
    }

    // MARK: Helpers

    /// Fit a square item into available space, scaled by weight
    private static func fitSize(weight: CGFloat, availableSize: CGSize) -> CGSize {
        let maxDim = min(availableSize.width, availableSize.height) * weight
        // Clamp so items don't overflow their cell
        let dim = min(maxDim, min(availableSize.width, availableSize.height) * 0.95)
        return CGSize(width: dim, height: dim)
    }

    static func sizeWeight(for item: Item) -> CategorySizeWeight {
        let categoryName = item.category?.name?.lowercased() ?? ""
        let subcategoryName = item.subcategory?.name?.lowercased() ?? ""

        switch subcategoryName {
        case "hats": return .small
        case "bags": return .small
        case "belts", "scarves": return .small
        case "jewelry": return .small
        case "heels", "flats", "sneakers", "boots", "sandals": return .small
        case "jackets", "coats", "blazers": return .large
        case "t-shirts", "blouses", "sweaters", "tanks", "tops", "sports bras": return .medium
        case "jeans", "trousers", "skirts", "shorts", "leggings": return .medium
        case "mini", "midi", "maxi", "one-piece": return .large
        case "skirt suits", "pant suits": return .large
        case "bikini", "cover-ups": return .medium
        default: break
        }

        switch categoryName {
        case "tops", "bottoms", "activewear", "shoes", "swimwear": return .medium
        case "outerwear", "dresses", "suits": return .large
        case "accessories": return .small
        default: return .medium
        }
    }
}

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

    // Current user's id — used to filter wardrobe lists throughout this view
    private var currentUserId: String? { SupabaseService.shared.currentUser?.id.uuidString }

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
        return key
    }

    // Fetch items filtered by selected wardrobe
    private func fetchClosetItems() {
        let targetWardrobeType: String
        if wardrobeType == "wishlist" {
            targetWardrobeType = itemTypeSegment == .wishlist ? "wishlist" : "closet"
        } else {
            targetWardrobeType = "closet"
        }

        let targetWardrobes = allWardrobes.filter {
            $0.type == targetWardrobeType &&
            $0.isSoftDeleted != true &&
            (currentUserId == nil || $0.userId == currentUserId)
        }

        guard !targetWardrobes.isEmpty else {
            closetItems = []
            return
        }

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

        let request: NSFetchRequest<Item> = Item.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.createdAt, ascending: sortAscending)]

        let filterPredicate = makePredicate(for: filterModel, context: viewContext)
        let wardrobePredicate = NSPredicate(format: "ANY wardrobes == %@", wardrobe)
        let softDeleteFilter = NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")

        let finalPredicate: NSPredicate
        if let filter = filterPredicate {
            finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [filter, wardrobePredicate, softDeleteFilter])
        } else {
            finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [wardrobePredicate, softDeleteFilter])
        }

        request.predicate = finalPredicate
        request.fetchBatchSize = 0

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

    init(outfitToEdit: Outfit? = nil, wardrobeType: String = "closet", initialWardrobe: Wardrobe? = nil) {
        self.outfitToEdit = outfitToEdit
        self.wardrobeType = wardrobeType
        _selectedWardrobe = State(initialValue: initialWardrobe)
    }

    private var squareSize: CGFloat {
        UIScreen.main.bounds.width
    }

    // MARK: - Adaptive Layout

    /// Compute the current adaptive layout for all items.
    private var adaptiveLayout: [UUID: AdaptiveLayoutEngine.LayoutResult] {
        AdaptiveLayoutEngine.layout(items: outfitItems, canvasSize: squareSize)
    }

    var body: some View {
        sheetsContent
            .onAppear {
                if selectedWardrobe == nil {
                    if wardrobeType == "wishlist" {
                        selectedWardrobe = allWardrobes.first(where: { $0.type == "wishlist" })
                    } else {
                        selectedWardrobe = wardrobes.first
                    }
                }
                loadOutfitIfEditing()
                fetchClosetItems()
            }
            .onChange(of: selectedWardrobe) { _ in fetchClosetItems() }
            .onChange(of: wardrobes) { newWardrobes in
                if let current = selectedWardrobe, !newWardrobes.contains(current) {
                    selectedWardrobe = newWardrobes.first
                }
            }
            .onChange(of: filterKey) { _ in fetchClosetItems() }
            .onChange(of: itemTypeSegment) { _ in
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

    // MARK: - Body Sub-expressions
    // Split to keep the type-checker happy (too many chained modifiers in one expression).

    private var sheetsContent: some View {
        alertsContent
            .sheet(isPresented: $isWardrobeSelectionPresented) {
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
                        OutfitAddView(outfitToEdit: draft, wardrobeType: wardrobeType)
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
        .toolbar(.hidden, for: .tabBar)
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
        .alert("Save as draft?", isPresented: $showingSaveDraftConfirmation) {
            Button("Yes") { saveDraft() }
            Button("No", role: .cancel) { dismiss() }
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
    private var outfitCollageArea: some View {
        ZStack {
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

            // Render items using adaptive layout
            ForEach(outfitItems.sorted(by: { $0.zIndex < $1.zIndex })) { outfitItem in
                if let layoutResult = adaptiveLayout[outfitItem.id] {
                    AdaptiveOutfitItemView(
                        outfitItem: outfitItem,
                        layoutFrame: layoutResult.frame,
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
        }
        // Animate when items count changes — smoothly reflow
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: outfitItems.count)
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
                OutfitItem(item: item, position: CGPoint(x: squareSize / 2, y: squareSize / 2),
                           scale: 1.0, rotation: 0.0, zIndex: i)
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
            return OutfitItem(
                item: item,
                position: CGPoint(x: savedItem.positionX, y: savedItem.positionY),
                scale: savedItem.scale,
                rotation: savedItem.rotation,
                zIndex: savedItem.zIndex
            )
        }
        print("🔍 Loaded \(outfitItems.count) outfitItems onto canvas")
    }

    // MARK: - Undo/Redo Functions
    /// Snapshots the current canvas state into the undo stack.
    /// Resolves any nil (auto-layout) positions to their actual frame centers
    /// so undo restores items to where they were visually displayed.
    private func saveState() {
        let snapshotLayout = AdaptiveLayoutEngine.layout(items: outfitItems, canvasSize: squareSize)
        let snapshots = outfitItems.map { outfitItem -> CanvasStateSnapshot in
            let frame = snapshotLayout[outfitItem.id]?.frame
            let pos = outfitItem.position ?? frame.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: squareSize / 2, y: squareSize / 2)
            return CanvasStateSnapshot(
                itemID: outfitItem.item.objectID.uriRepresentation().absoluteString,
                outfitItemID: outfitItem.id,
                positionX: pos.x,
                positionY: pos.y,
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
        let undoLayout = AdaptiveLayoutEngine.layout(items: outfitItems, canvasSize: squareSize)
        let currentSnapshots = outfitItems.map { outfitItem -> CanvasStateSnapshot in
            let frame = undoLayout[outfitItem.id]?.frame
            let pos = outfitItem.position ?? frame.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: squareSize / 2, y: squareSize / 2)
            return CanvasStateSnapshot(
                itemID: outfitItem.item.objectID.uriRepresentation().absoluteString,
                outfitItemID: outfitItem.id,
                positionX: pos.x,
                positionY: pos.y,
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
        let redoLayout = AdaptiveLayoutEngine.layout(items: outfitItems, canvasSize: squareSize)
        let currentSnapshots = outfitItems.map { outfitItem -> CanvasStateSnapshot in
            let frame = redoLayout[outfitItem.id]?.frame
            let pos = outfitItem.position ?? frame.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: squareSize / 2, y: squareSize / 2)
            return CanvasStateSnapshot(
                itemID: outfitItem.item.objectID.uriRepresentation().absoluteString,
                outfitItemID: outfitItem.id,
                positionX: pos.x,
                positionY: pos.y,
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
        guard !outfitItems.contains(where: { $0.item.objectID == item.objectID }) else { return }
        saveState()

        // position is nil — AdaptiveLayoutEngine will place it on first render
        let outfitItem = OutfitItem(
            item: item,
            position: nil,
            scale: 1.0,
            rotation: 0.0,
            zIndex: outfitItems.count
        )

        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
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
            outfit.userId = SupabaseService.shared.currentUser?.id.uuidString
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

        let saveLayout = AdaptiveLayoutEngine.layout(items: outfitItems, canvasSize: squareSize)
        let savedItems = outfitItems.map { outfitItem -> SavedOutfitItem in
            let frame = saveLayout[outfitItem.id]?.frame
            let resolvedPos = outfitItem.position ?? frame.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: squareSize / 2, y: squareSize / 2)
            return SavedOutfitItem(
                itemID: outfitItem.item.id?.uuidString ?? "",
                positionX: resolvedPos.x,
                positionY: resolvedPos.y,
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
        draft.userId = SupabaseService.shared.currentUser?.id.uuidString
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

        let draftLayout = AdaptiveLayoutEngine.layout(items: outfitItems, canvasSize: squareSize)
        let savedItems = outfitItems.map { outfitItem -> SavedOutfitItem in
            let frame = draftLayout[outfitItem.id]?.frame
            let resolvedPos = outfitItem.position ?? frame.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: squareSize / 2, y: squareSize / 2)
            return SavedOutfitItem(
                itemID: outfitItem.item.id?.uuidString ?? "",
                positionX: resolvedPos.x,
                positionY: resolvedPos.y,
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
        let layout = AdaptiveLayoutEngine.layout(items: outfitItems, canvasSize: squareSize)
        let size = squareSize

        // Build a capture-only view that mirrors the canvas exactly.
        // IMPORTANT: No .ignoresSafeArea() — ImageRenderer has no window/safe-area context.
        // Using Canvas rather than SwiftUI .position() avoids coordinate space
        // discrepancies that occur when UIHostingController hosts views with .position().
        let captureView = Canvas { ctx, _ in
            for outfitItem in outfitItems.sorted(by: { $0.zIndex < $1.zIndex }) {
                guard let layoutResult = layout[outfitItem.id] else { continue }

                // Resolve the photo image
                guard let primaryPhoto = (outfitItem.item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
                      let photoData = primaryPhoto.data,
                      let uiImage = UIImage(data: photoData) else { continue }

                let frame = layoutResult.frame
                // Use the manual position if the user moved the item; otherwise use auto-layout center
                let center = outfitItem.position ?? CGPoint(x: frame.midX, y: frame.midY)
                // Apply user scale on top of auto-layout frame dimensions
                let scaledW = frame.width  * outfitItem.scale
                let scaledH = frame.height * outfitItem.scale

                ctx.translateBy(x: center.x, y: center.y)
                ctx.rotate(by: Angle.degrees(outfitItem.rotation))

                // Draw image scaled to fit the (possibly user-scaled) frame, preserving aspect ratio
                let imgAspect = uiImage.size.height / uiImage.size.width
                let drawW = scaledW
                let drawH = drawW * imgAspect
                let drawRect = CGRect(x: -drawW / 2, y: -drawH / 2, width: drawW, height: drawH)

                ctx.draw(Image(uiImage: uiImage).resizable(), in: drawRect)

                // Reset transform for next item
                ctx.rotate(by: Angle.degrees(-outfitItem.rotation))
                ctx.translateBy(x: -center.x, y: -center.y)
            }
        }
        .background(Color(red: 247/255, green: 247/255, blue: 247/255))
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
    /// nil  = item hasn't been manually placed yet → use auto-layout position
    /// non-nil = user dragged it, or position was restored from saved data
    var position: CGPoint?
    var scale: CGFloat
    var rotation: Double
    var zIndex: Int
}

// MARK: - Adaptive Outfit Item View
/// Renders an outfit item using a layout frame provided by AdaptiveLayoutEngine.
/// On first render the item snaps to the computed frame; after the user drags it,
/// the position is tracked as a manual override but layout sizing still applies.
struct AdaptiveOutfitItemView: View {
    let outfitItem: OutfitItem
    let layoutFrame: CGRect      // computed by AdaptiveLayoutEngine
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
    @State private var manualCenter: CGPoint? = nil  // nil = use layoutFrame center
    @State private var rotation: Double
    @State private var baseRotation: Double
    @State private var scaleMultiplier: CGFloat = 1.0  // on top of layout size
    @State private var baseScaleMultiplier: CGFloat = 1.0

    private let deleteButtonSize: CGFloat = 24

    init(outfitItem: OutfitItem, layoutFrame: CGRect, canvasSize: CGFloat, isSelected: Bool,
         onPositionChanged: @escaping (CGPoint) -> Void,
         onScaleChanged: @escaping (CGFloat) -> Void,
         onRotationChanged: @escaping (Double) -> Void,
         onTransformStart: @escaping () -> Void,
         onTransformEnd: @escaping () -> Void,
         onSelected: @escaping () -> Void,
         onLongPress: @escaping () -> Void,
         onDelete: @escaping () -> Void) {
        self.outfitItem = outfitItem
        self.layoutFrame = layoutFrame
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
        // Restore manual position and scale so editing displays the saved canvas state
        _manualCenter = State(initialValue: outfitItem.position)
        _scaleMultiplier = State(initialValue: outfitItem.scale)
        _baseScaleMultiplier = State(initialValue: outfitItem.scale)
    }

    private var effectiveCenter: CGPoint {
        let base = manualCenter ?? CGPoint(x: layoutFrame.midX, y: layoutFrame.midY)
        return CGPoint(x: base.x + dragOffset.width, y: base.y + dragOffset.height)
    }

    private var itemSize: CGSize { layoutFrame.size }

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
                .gesture(transformGesture)
                .onChange(of: layoutFrame) { _ in }

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
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: layoutFrame.origin)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: layoutFrame.size)
    }

    @ViewBuilder
    private var itemImage: some View {
        let selectionOverlay = RoundedRectangle(cornerRadius: 8)
            .stroke(Color.gray.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
        if let primaryPhoto = (outfitItem.item.photos as? Set<Photo>)?.first(where: { $0.isPrimary }),
           let photoData = primaryPhoto.data,
           let uiImage = UIImage(data: photoData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: itemSize.width, height: itemSize.height)
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
                let base = manualCenter ?? CGPoint(x: layoutFrame.midX, y: layoutFrame.midY)
                let halfW = (itemSize.width * scaleMultiplier) / 2
                let halfH = (itemSize.height * scaleMultiplier) / 2
                let newX = max(halfW, min(canvasSize - halfW, base.x + value.translation.width))
                let newY = max(halfH, min(canvasSize - halfH, base.y + value.translation.height))
                manualCenter = CGPoint(x: newX, y: newY)
                dragOffset = .zero
                onPositionChanged(manualCenter!)
                onTransformEnd()
            }
    }

    private var transformGesture: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    guard isSelected else { return }
                    scaleMultiplier = max(0.3, min(4.0, baseScaleMultiplier * value))
                }
                .onEnded { value in
                    guard isSelected else { return }
                    let final = max(0.3, min(4.0, baseScaleMultiplier * value))
                    scaleMultiplier = final
                    baseScaleMultiplier = final
                    onScaleChanged(final)
                    onTransformEnd()
                },
            RotationGesture()
                .onChanged { value in
                    guard isSelected else { return }
                    rotation = baseRotation + value.degrees
                }
                .onEnded { value in
                    guard isSelected else { return }
                    let final = baseRotation + value.degrees
                    rotation = final
                    baseRotation = final
                    onRotationChanged(final)
                    onTransformEnd()
                }
        )
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
