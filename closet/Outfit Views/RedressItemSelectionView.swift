//
//  RedressItemSelectionView.swift
//  closet
//
//  Remote item picker for Redress mode (recipient wardrobes via Supabase RPCs).
//

import SwiftUI

struct RedressCanvasItem: Identifiable {
    let id: UUID
    let item: VisibleWardrobeItem
    let sourceWardrobeType: String
    let sourceWardrobeId: UUID?
    let sourceWardrobeName: String?
    var position: CGPoint
    let displaySize: CGSize
    var scale: CGFloat
    var rotation: Double
    var zIndex: Int

    init(
        id: UUID = UUID(),
        item: VisibleWardrobeItem,
        sourceWardrobeType: String,
        sourceWardrobeId: UUID? = nil,
        sourceWardrobeName: String? = nil,
        position: CGPoint,
        displaySize: CGSize,
        scale: CGFloat,
        rotation: Double,
        zIndex: Int
    ) {
        self.id = id
        self.item = item
        self.sourceWardrobeType = sourceWardrobeType.lowercased() == "wishlist" ? "wishlist" : "closet"
        self.sourceWardrobeId = sourceWardrobeId
        self.sourceWardrobeName = sourceWardrobeName
        self.position = position
        self.displaySize = displaySize
        self.scale = scale
        self.rotation = rotation
        self.zIndex = zIndex
    }

    static func defaultDisplaySize(canvasSize: CGFloat) -> CGSize {
        let side = canvasSize * 0.45
        return CGSize(width: side, height: side)
    }

    var displayWardrobeName: String {
        if let sourceWardrobeName, !sourceWardrobeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sourceWardrobeName
        }
        return sourceWardrobeType == "wishlist" ? "Wishlist" : "Closet"
    }
}

/// ITEMS subsection for Redress when canvas spans Closet + Wishlist wardrobes.
struct RedressWardrobeItemsSection: Identifiable {
    let id: UUID
    let name: String
    let wardrobeType: String
    let items: [VisibleWardrobeItem]
}

struct RedressItemSelectionView: View {
    let recipientUserId: UUID
    /// When set, prefer this wardrobe (must match current Closet/Wishlist segment).
    var initialWardrobeId: UUID? = nil
    @Binding var itemTypeSegment: OutfitItemTypeSegment
    let isOnCanvas: (VisibleWardrobeItem) -> Bool
    let canvasItemCount: Int
    let onAddItem: (VisibleWardrobeItem, VisibleWardrobe) -> Void

    @EnvironmentObject private var supabaseService: SupabaseService

    @State private var wardrobes: [VisibleWardrobe] = []
    @State private var selectedWardrobe: VisibleWardrobe?
    @State private var items: [VisibleWardrobeItem] = []
    @State private var isLoadingWardrobes = false
    @State private var isLoadingItems = false
    @State private var loadError: String?
    @State private var showFilter = false
    @State private var showWardrobeSelection = false
    @State private var isSearchActive = false
    @State private var didInitializeSession = false
    @State private var didApplyInitialWardrobePreference = false
    @StateObject private var filterModel = ItemFilterModel()
    @FocusState private var isSearchFocused: Bool

    private var filteredWardrobes: [VisibleWardrobe] {
        let targetType = itemTypeSegment == .wishlist ? "wishlist" : "closet"
        return wardrobes.filter { wardrobe in
            guard wardrobe.wardrobeType == targetType else { return false }
            // Match get_redress_wardrobes: never offer private; friends-only only when API returned it.
            switch wardrobe.wardrobeVisibility {
            case .public, .friends:
                return true
            case .private:
                return false
            }
        }
    }

    private var wardrobeTitle: String {
        selectedWardrobe?.name ?? (itemTypeSegment == .wishlist ? "Select Wishlist" : "Select Closet")
    }

    private var displayedItems: [VisibleWardrobeItem] {
        var result = items
        let query = filterModel.trimmedSearchQuery
        if !query.isEmpty {
            result = result.filter { ($0.name ?? "").localizedCaseInsensitiveContains(query) }
        }
        if filterModel.sortOrder == .oldestFirst {
            result.reverse()
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            SelectionPanelHeader(
                title: wardrobeTitle,
                onTitleTap: { showWardrobeSelection = true },
                actionPlacement: .barAboveTitle,
                leading: { itemTypeMenuPicker },
                trailing: { EmptyView() }
            )

            selectionActionsBar

            Group {
                if isLoadingWardrobes || isLoadingItems {
                    ProgressView("Loading items…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if selectedWardrobe == nil {
                    Text("Please select a wardrobe")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if displayedItems.isEmpty {
                    Text(items.isEmpty ? "No items in this wardrobe" : "No matching items")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3),
                            spacing: 1
                        ) {
                            ForEach(displayedItems) { item in
                                Button {
                                    guard let wardrobe = selectedWardrobe else { return }
                                    onAddItem(item, wardrobe)
                                } label: {
                                    RedressItemGridCell(item: item, isOnCanvas: isOnCanvas(item))
                                }
                                .buttonStyle(.plain)
                                .disabled(selectedWardrobe == nil)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: recipientUserId) {
            await loadWardrobes()
        }
        .onAppear {
            guard !didInitializeSession else { return }
            didInitializeSession = true
            resetFiltersForNewSession()
            bootstrapWardrobeIfNeeded()
        }
        .navigationDestination(isPresented: $showFilter) {
            RedressItemFilterView(filterModel: filterModel)
        }
        .onChange(of: itemTypeSegment) { _, _ in
            bootstrapWardrobeForCurrentSegment()
            Task { await loadItems() }
        }
        .onChange(of: selectedWardrobe?.id) { _, _ in
            Task { await loadItems() }
        }
        .onChange(of: canvasItemCount) { _, _ in
            // Refresh grid checkmarks when canvas changes.
        }
        // Same as OutfitItemSelectionView: sheet for wardrobe pick (not a nested nav push).
        // Pushing from this sheet cancels `.task` / re-applies source wardrobe and undoes the tap.
        .sheet(isPresented: $showWardrobeSelection) {
            NavigationStack {
                RedressWardrobeSelectionView(
                    wardrobes: filteredWardrobes,
                    selectedWardrobe: $selectedWardrobe
                )
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var selectionActionsBar: some View {
        ItemFilterSortSearchBar(
            sortOrder: $filterModel.sortOrder,
            searchQuery: $filterModel.searchQuery,
            isSearchActive: $isSearchActive,
            isSearchFocused: $isSearchFocused,
            onFilter: { showFilter = true },
            onDismissSearch: { dismissSearch(clearQueries: true) },
            activeFilterCount: filterModel.activeFilterCount,
            searchPlaceholder: "Name",
            backgroundColor: Color(UIColor.secondarySystemBackground)
        )
    }

    private var itemTypeMenuPicker: some View {
        Menu {
            Picker("Item Type", selection: $itemTypeSegment) {
                Text(OutfitItemTypeSegment.closet.rawValue).tag(OutfitItemTypeSegment.closet)
                Text(OutfitItemTypeSegment.wishlist.rawValue).tag(OutfitItemTypeSegment.wishlist)
            }
        } label: {
            HStack(spacing: 4) {
                Text(itemTypeSegment.rawValue)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Item type, \(itemTypeSegment.rawValue)")
    }

    private func resetFiltersForNewSession() {
        filterModel.clearAll()
        isSearchActive = false
        isSearchFocused = false
    }

    private func dismissSearch(clearQueries: Bool) {
        if clearQueries {
            filterModel.searchQuery = ""
        }
        isSearchActive = false
        isSearchFocused = false
    }

    private func loadWardrobes() async {
        await MainActor.run {
            isLoadingWardrobes = true
            loadError = nil
        }
        do {
            let fetched = try await supabaseService.fetchRedressWardrobes(forUserId: recipientUserId)
            await MainActor.run {
                wardrobes = fetched
                isLoadingWardrobes = false
                applyInitialWardrobePreference()
            }
            await loadItems()
        } catch {
            await MainActor.run {
                wardrobes = []
                selectedWardrobe = nil
                items = []
                loadError = error.localizedDescription
                isLoadingWardrobes = false
            }
        }
    }

    private func loadItems() async {
        guard let wardrobe = selectedWardrobe else {
            await MainActor.run { items = [] }
            return
        }
        await MainActor.run {
            isLoadingItems = true
            loadError = nil
        }
        do {
            let fetched = try await supabaseService.fetchRedressWardrobeItems(
                userId: recipientUserId,
                wardrobeId: wardrobe.id
            )
            await MainActor.run {
                items = fetched
                isLoadingItems = false
            }
        } catch {
            await MainActor.run {
                items = []
                loadError = error.localizedDescription
                isLoadingItems = false
            }
        }
    }

    private func bootstrapWardrobeIfNeeded() {
        guard selectedWardrobe == nil else { return }
        applyInitialWardrobePreference()
    }

    /// Prefer the browsing-source wardrobe when present; keep Closet/Wishlist segment in sync.
    private func applyInitialWardrobePreference() {
        // Only seed once — re-running after a user pick (e.g. `.task` restart) must not stomp selection.
        guard !didApplyInitialWardrobePreference else {
            if selectedWardrobe == nil {
                bootstrapWardrobeForCurrentSegment()
            }
            return
        }
        didApplyInitialWardrobePreference = true

        if let initialId = initialWardrobeId,
           let match = wardrobes.first(where: { $0.id == initialId }) {
            let matchSegment: OutfitItemTypeSegment = match.wardrobeType == "wishlist" ? .wishlist : .closet
            if itemTypeSegment != matchSegment {
                itemTypeSegment = matchSegment
            }
            selectedWardrobe = match
            return
        }
        bootstrapWardrobeForCurrentSegment()
    }

    private func bootstrapWardrobeForCurrentSegment() {
        let segmentWardrobes = filteredWardrobes
        // Keep a valid in-segment selection (user may have changed wardrobe in the picker).
        if let selected = selectedWardrobe,
           segmentWardrobes.contains(where: { $0.id == selected.id }) {
            return
        }
        // Only fall back to source wardrobe when nothing valid is selected for this segment.
        if let initialId = initialWardrobeId,
           let match = segmentWardrobes.first(where: { $0.id == initialId }) {
            selectedWardrobe = match
            return
        }
        selectedWardrobe = primaryWardrobe(in: segmentWardrobes)
    }

    private func primaryWardrobe(in wardrobes: [VisibleWardrobe]) -> VisibleWardrobe? {
        wardrobes.first(where: \.isDefault) ?? wardrobes.first
    }
}

private struct RedressItemFilterView: View {
    @ObservedObject var filterModel: ItemFilterModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Picker("Sort", selection: $filterModel.sortOrder) {
                ForEach(ItemSortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.menu)

            Section {
                Button("Reset All", role: .destructive) {
                    filterModel.clearAll()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle("Filter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply") {
                    dismiss()
                }
            }
        }
    }
}

private struct RedressWardrobeSelectionView: View {
    let wardrobes: [VisibleWardrobe]
    @Binding var selectedWardrobe: VisibleWardrobe?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if wardrobes.isEmpty {
                Text("No wardrobes available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(wardrobes) { wardrobe in
                    Button {
                        selectedWardrobe = wardrobe
                        dismiss()
                    } label: {
                        HStack {
                            Text(wardrobe.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedWardrobe?.id == wardrobe.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Select Wardrobe")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
        }
    }
}

private struct RedressItemGridCell: View {
    let item: VisibleWardrobeItem
    let isOnCanvas: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 247 / 255, green: 247 / 255, blue: 247 / 255)
                if let url = item.displayImageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Image(systemName: "photo").foregroundStyle(.secondary)
                        default:
                            ProgressView()
                        }
                    }
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }

                if isOnCanvas {
                    Color.black.opacity(0.25)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.width)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct AdaptiveRedressCanvasItemView: View {
    let canvasItem: RedressCanvasItem
    let canvasSize: CGFloat
    let isSelected: Bool
    let onPositionChanged: (CGPoint) -> Void
    let onScaleChanged: (CGFloat) -> Void
    let onRotationChanged: (Double) -> Void
    let onTransformStart: () -> Void
    let onTransformEnd: () -> Void
    let onSelected: () -> Void
    let onDelete: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var dragCenter: CGPoint
    @State private var isDragging = false

    private let deleteButtonSize: CGFloat = 24
    private let deleteHitTargetSize: CGFloat = 44

    init(
        canvasItem: RedressCanvasItem,
        canvasSize: CGFloat,
        isSelected: Bool,
        onPositionChanged: @escaping (CGPoint) -> Void,
        onScaleChanged: @escaping (CGFloat) -> Void,
        onRotationChanged: @escaping (Double) -> Void,
        onTransformStart: @escaping () -> Void,
        onTransformEnd: @escaping () -> Void,
        onSelected: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.canvasItem = canvasItem
        self.canvasSize = canvasSize
        self.isSelected = isSelected
        self.onPositionChanged = onPositionChanged
        self.onScaleChanged = onScaleChanged
        self.onRotationChanged = onRotationChanged
        self.onTransformStart = onTransformStart
        self.onTransformEnd = onTransformEnd
        self.onSelected = onSelected
        self.onDelete = onDelete
        _dragCenter = State(initialValue: canvasItem.position)
    }

    /// Prefer model position when idle so undo/redo animations apply to the view.
    private var effectiveCenter: CGPoint {
        if isDragging {
            return CGPoint(x: dragCenter.x + dragOffset.width, y: dragCenter.y + dragOffset.height)
        }
        return canvasItem.position
    }

    private var itemSize: CGSize { canvasItem.displaySize }

    private var deleteButtonPosition: CGPoint {
        let halfW = (itemSize.width * canvasItem.scale) / 2
        let halfH = (itemSize.height * canvasItem.scale) / 2
        let rad = canvasItem.rotation * .pi / 180.0
        let x = halfW * cos(rad) - (-halfH) * sin(rad)
        let y = halfW * sin(rad) + (-halfH) * cos(rad)
        return CGPoint(x: effectiveCenter.x + x, y: effectiveCenter.y + y)
    }

    var body: some View {
        ZStack {
            itemImage
                .scaleEffect(canvasItem.scale)
                .rotationEffect(Angle.degrees(canvasItem.rotation))
                .position(effectiveCenter)
                .onTapGesture { onSelected() }
                .gesture(dragGesture)

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
        if let url = canvasItem.item.displayImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: itemSize.width, height: itemSize.height)
                        .overlay { if isSelected { selectionOverlay } }
                case .failure:
                    placeholderImage(selectionOverlay: selectionOverlay)
                default:
                    ProgressView()
                        .frame(width: itemSize.width, height: itemSize.height)
                }
            }
        } else {
            placeholderImage(selectionOverlay: selectionOverlay)
        }
    }

    private func placeholderImage(selectionOverlay: some View) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemGray5))
            .frame(width: itemSize.width, height: itemSize.height)
            .overlay { Image(systemName: "photo").foregroundColor(.secondary) }
            .overlay { if isSelected { selectionOverlay } }
    }

    /// Keeps the item *center* on the canvas. Edges / selection chrome may overhang.
    private func clampCenter(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), canvasSize),
            y: min(max(point.y, 0), canvasSize)
        )
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard isSelected else { return }
                if !isDragging {
                    isDragging = true
                    dragCenter = canvasItem.position
                    dragOffset = .zero
                    onTransformStart()
                }
                let clamped = clampCenter(
                    CGPoint(
                        x: dragCenter.x + value.translation.width,
                        y: dragCenter.y + value.translation.height
                    )
                )
                dragOffset = CGSize(
                    width: clamped.x - dragCenter.x,
                    height: clamped.y - dragCenter.y
                )
            }
            .onEnded { value in
                guard isSelected else { return }
                let newCenter = clampCenter(
                    CGPoint(
                        x: dragCenter.x + value.translation.width,
                        y: dragCenter.y + value.translation.height
                    )
                )
                // Commit parent position before leaving live-drag mode so we don't
                // flash the pre-drag position (and so undo/redo spring isn't used here).
                onPositionChanged(newCenter)
                dragCenter = newCenter
                dragOffset = .zero
                isDragging = false
                onTransformEnd()
            }
    }
}
