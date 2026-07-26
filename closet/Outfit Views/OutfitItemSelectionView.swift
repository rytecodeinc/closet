import SwiftUI
import CoreData

enum OutfitItemTypeSegment: String, CaseIterable {
    case wishlist = "Wishlist"
    case closet = "Closet"

    init(pairSourceSegment: PairItemSelectionView.PairSourceSegment) {
        self = pairSourceSegment == .wishlist ? .wishlist : .closet
    }
}

struct OutfitItemSelectionView: View {
    let wardrobeType: String
    let lockWardrobeSource: Bool
    var initialWardrobe: Wardrobe?
    @Binding var itemTypeSegment: OutfitItemTypeSegment
    let isOnCanvas: (Item) -> Bool
    var canvasItemCount: Int = 0
    let onAddItem: (Item) -> Void
    let onRemoveFromCanvas: (Item) -> Void
    var onShowAddedItems: (() -> Void)? = nil

    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var authSession: AuthSession

    @FetchRequest(
        entity: Wardrobe.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.name, ascending: true)]
    ) private var allWardrobes: FetchedResults<Wardrobe>

    @StateObject private var filterModel = ItemFilterModel()
    @StateObject private var tabBarHideState = TabBarHideState()
    @State private var selectedWardrobe: Wardrobe?
    @State private var closetItems: [Item] = []
    @State private var showWardrobeSelection = false
    @State private var showFilter = false
    @State private var isSearchActive = false
    @State private var didInitializeSession = false
    @FocusState private var isSearchFocused: Bool
    @State private var searchDebounceTask: Task<Void, Never>?

    private static let searchDebounceNanos: UInt64 = 250_000_000

    private var currentUserId: String? { authSession.userId?.uuidString }

    private var wardrobes: [Wardrobe] {
        allWardrobes.filter {
            $0.type == wardrobeType &&
            $0.isSoftDeleted != true &&
            (currentUserId == nil || $0.userId == currentUserId)
        }
    }

    private var itemsSheetWardrobeType: String {
        wardrobeType == "wishlist" && itemTypeSegment == .closet ? "closet" : wardrobeType
    }

    private var filterKey: String {
        var key = ""
        key += filterModel.selectedColors.sorted().joined(separator: ",")
        key += filterModel.selectedSeasons.sorted().joined(separator: ",")
        key += filterModel.selectedBrandName ?? ""
        key += filterModel.selectedTags.map { $0.objectID.uriRepresentation().absoluteString }.sorted().joined(separator: ",")
        key += filterModel.minPrice?.description ?? ""
        key += filterModel.maxPrice?.description ?? ""
        key += filterModel.selectedCategoryName ?? ""
        key += filterModel.selectedSubcategoryName ?? ""
        key += filterModel.selectedSizeValue ?? ""
        key += filterModel.selectedLocation?.objectID.uriRepresentation().absoluteString ?? ""
        key += filterModel.filterLocationNotSet ? "locationNotSet" : ""
        key += filterModel.filterTagsNotSet ? "tagsNotSet" : ""
        key += filterModel.selectedWardrobes.map { $0.objectID.uriRepresentation().absoluteString }.sorted().joined(separator: ",")
        key += filterModel.favoritesOnly ? "favoritesOnly" : ""
        key += filterModel.filterByWeight ? "filterByWeight" : ""
        key += filterModel.sortOrder.sortAscending ? "sortAsc" : "sortDesc"
        key += selectedWardrobe?.objectID.uriRepresentation().absoluteString ?? ""
        return key
    }

    private var wardrobeTitle: String {
        selectedWardrobe?.name ?? (wardrobeType == "wishlist" ? "Select Wishlist" : "Select Closet")
    }

    private var wardrobeTitleTap: (() -> Void)? {
        lockWardrobeSource ? nil : { showWardrobeSelection = true }
    }

    var body: some View {
        VStack(spacing: 0) {
            selectionHeader
            selectionActionsBar

            ScrollView {
                if selectedWardrobe == nil {
                    Text("Please select a wardrobe")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
                        ForEach(closetItems, id: \.objectID) { item in
                            Button {
                                onAddItem(item)
                            } label: {
                                ItemView(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            guard !didInitializeSession else { return }
            didInitializeSession = true
            resetFiltersForNewSession()
            bootstrapWardrobeIfNeeded()
            fetchClosetItems()
        }
        .onChange(of: showFilter) { _, isShowing in
            if !isShowing {
                fetchClosetItems()
            }
        }
        .onChange(of: selectedWardrobe) { _, wardrobe in
            if wardrobe?.isDefault != true {
                filterModel.selectedWardrobes.removeAll()
            }
            fetchClosetItems()
        }
        .onChange(of: filterKey) { _, _ in
            fetchClosetItems()
        }
        .onChange(of: filterModel.sortOrder) { _, _ in
            fetchClosetItems()
        }
        .onChange(of: filterModel.searchQuery) { _, _ in
            scheduleDebouncedFetch()
        }
        .onChange(of: itemTypeSegment) { _, _ in
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
        .onChange(of: canvasItemCount) { _, _ in
            fetchClosetItems()
        }
        .navigationDestination(isPresented: $showFilter) {
            ItemFilterView(
                filterModel: filterModel,
                tabBarHideState: tabBarHideState,
                wardrobeType: itemsSheetWardrobeType,
                selectedWardrobe: selectedWardrobe
            )
        }
        .navigationDestination(isPresented: $showWardrobeSelection) {
            SingleWardrobeSelectionView(
                selectedWardrobe: $selectedWardrobe,
                wardrobeType: itemsSheetWardrobeType
            )
        }
    }

    @ViewBuilder
    private var selectionHeader: some View {
        if wardrobeType == "wishlist" {
            outfitItemsPanel(showsSegmentPicker: true)
        } else {
            outfitItemsPanel(showsSegmentPicker: false)
        }
    }

    @ViewBuilder
    private func outfitItemsPanel(showsSegmentPicker: Bool) -> some View {
        if onShowAddedItems != nil {
            if showsSegmentPicker {
                SelectionPanelHeader(
                    title: wardrobeTitle,
                    onTitleTap: wardrobeTitleTap,
                    actionPlacement: .barAboveTitle,
                    leading: { EmptyView() },
                    trailing: { selectionHeaderTrailing },
                    picker: { itemTypeSegmentPicker }
                )
            } else {
                SelectionPanelHeader(
                    title: wardrobeTitle,
                    onTitleTap: wardrobeTitleTap,
                    actionPlacement: .barAboveTitle,
                    leading: { EmptyView() },
                    trailing: { selectionHeaderTrailing }
                )
            }
        } else if showsSegmentPicker {
            SelectionPanelHeader(
                title: wardrobeTitle,
                onTitleTap: wardrobeTitleTap,
                picker: { itemTypeSegmentPicker }
            )
        } else {
            SelectionPanelHeader(
                title: wardrobeTitle,
                onTitleTap: wardrobeTitleTap
            )
        }
    }

    private var itemTypeSegmentPicker: some View {
        Picker("Item Type", selection: $itemTypeSegment) {
            Text(OutfitItemTypeSegment.closet.rawValue)
                .tag(OutfitItemTypeSegment.closet)
            Text(OutfitItemTypeSegment.wishlist.rawValue)
                .tag(OutfitItemTypeSegment.wishlist)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var selectionHeaderTrailing: some View {
        if let onShowAddedItems {
            Button(action: onShowAddedItems) {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                    Text("View Items")
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View items")
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
            backgroundColor: Color(UIColor.secondarySystemBackground)
        )
    }

    private func bootstrapWardrobeIfNeeded() {
        if selectedWardrobe == nil, let initialWardrobe {
            selectedWardrobe = initialWardrobe
        }
        guard selectedWardrobe == nil else { return }

        guard let userId = currentUserId else { return }

        if wardrobeType == "wishlist" {
            let wish = allWardrobes.filter {
                $0.type == "wishlist" &&
                $0.isSoftDeleted != true &&
                $0.userId == userId
            }
            selectedWardrobe = WardrobeBootstrap.primaryWardrobe(in: wish)
        } else {
            selectedWardrobe = WardrobeBootstrap.primaryWardrobe(in: wardrobes)
        }
    }

    private func resetFiltersForNewSession() {
        searchDebounceTask?.cancel()
        filterModel.clearAll()
        isSearchActive = false
        isSearchFocused = false
    }

    private func scheduleDebouncedFetch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: Self.searchDebounceNanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                fetchClosetItems()
            }
        }
    }

    private func dismissSearch(clearQueries: Bool) {
        searchDebounceTask?.cancel()
        if clearQueries {
            filterModel.searchQuery = ""
            fetchClosetItems()
        }
        isSearchActive = false
        isSearchFocused = false
    }

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
            selectedWardrobe = primary
        } else {
            closetItems = []
            return
        }

        let request: NSFetchRequest<Item> = Item.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.createdAt, ascending: filterModel.sortOrder.sortAscending)]
        request.fetchBatchSize = 0

        var subpredicates: [NSPredicate] = [
            NSPredicate(format: "userId == %@", userId),
            ItemFilterModel.wardrobeMembershipPredicate(
                viewingWardrobe: wardrobe,
                wardrobeType: targetWardrobeType,
                filterModel: filterModel
            ),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil"),
            NSPredicate(format: "isDraft != YES"),
        ]

        if let filter = makePredicate(for: filterModel, context: viewContext) {
            subpredicates.append(filter)
        }

        if let searchPredicate = ItemFilterModel.itemSearchPredicate(query: filterModel.searchQuery) {
            subpredicates.append(searchPredicate)
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)

        do {
            let results = try viewContext.fetch(request)
            closetItems = results.filter { !isOnCanvas($0) }
        } catch {
            print("❌ Failed to fetch items: \(error)")
            closetItems = []
        }
    }
}
