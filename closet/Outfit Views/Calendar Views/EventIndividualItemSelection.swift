//
//  EventIndividualItemSelection.swift
//  closet
//
//  Created by Dan Warner on 10/8/25.
//

import SwiftUI
import CoreData

enum EventContentSegment: String, CaseIterable {
    case items = "Items"
    case outfits = "Outfits"
}

struct EventIndividualItemSelection: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSession

    @ObservedObject var event: Event
    /// When nil, the user's primary closet wardrobe is used.
    let initialWardrobe: Wardrobe?

    @FetchRequest(
        entity: Wardrobe.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.name, ascending: true)]
    ) private var allWardrobes: FetchedResults<Wardrobe>

    @StateObject private var filterModel = ItemFilterModel()
    @StateObject private var outfitFilterModel = OutfitFilterModel()
    @StateObject private var tabBarHideState = TabBarHideState()

    @State private var selectedWardrobe: Wardrobe?
    @State private var contentSegment: EventContentSegment = .items
    @State private var closetItems: [Item] = []
    @State private var outfits: [Outfit] = []
    /// Ordered item IDs so selection order is preserved across wardrobe switches.
    @State private var selectedItemIDs: [UUID] = []
    @State private var selectedItemsById: [UUID: Item] = [:]
    @State private var selectedOutfitsById: [UUID: Outfit] = [:]
    @State private var showWardrobeSelection = false
    @State private var showItemFilter = false
    @State private var showOutfitFilter = false
    @State private var isSearchActive = false
    @FocusState private var isSearchFocused: Bool
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var didInitialize = false

    private static let searchDebounceNanos: UInt64 = 250_000_000

    private let itemGridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private let outfitGridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var itemSquareSize: CGFloat { UIScreen.main.bounds.width / 3.05 }
    private var outfitSquareSize: CGFloat { UIScreen.main.bounds.width / 3.05 }

    private var currentUserId: String? { authSession.userId?.uuidString }

    private var closetWardrobes: [Wardrobe] {
        allWardrobes.filter {
            ($0.type ?? "").lowercased() == "closet" &&
            $0.isSoftDeleted != true &&
            (currentUserId == nil || $0.userId == currentUserId)
        }
    }

    private var wardrobeTitle: String {
        selectedWardrobe?.name ?? "Select Closet"
    }

    private var itemFilterKey: String {
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
        return key
    }

    private var outfitFilterKey: String {
        var key = ""
        key += outfitFilterModel.selectedCategory?.name ?? ""
        key += outfitFilterModel.selectedTags.map { $0.objectID.uriRepresentation().absoluteString }.sorted().joined(separator: ",")
        key += outfitFilterModel.filterTagsNotSet ? "tagsNotSet" : ""
        key += outfitFilterModel.favoritesOnly ? "favoritesOnly" : ""
        key += outfitFilterModel.sortOrder.sortAscending ? "sortAsc" : "sortDesc"
        return key
    }

    init(event: Event, selectedWardrobe: Wardrobe? = nil) {
        self.event = event
        self.initialWardrobe = selectedWardrobe
    }

    var body: some View {
        VStack(spacing: 0) {
            wardrobeHeader
            segmentPickerRow
            actionsBar

            TabView(selection: $contentSegment) {
                itemsContent
                    .tag(EventContentSegment.items)
                outfitsContent
                    .tag(EventContentSegment.outfits)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showWardrobeSelection) {
            SingleWardrobeSelectionView(
                selectedWardrobe: $selectedWardrobe,
                wardrobeType: "closet"
            )
        }
        .navigationDestination(isPresented: $showItemFilter) {
            ItemFilterView(
                filterModel: filterModel,
                tabBarHideState: tabBarHideState,
                wardrobeType: "closet",
                selectedWardrobe: selectedWardrobe
            )
        }
        .navigationDestination(isPresented: $showOutfitFilter) {
            OutfitFilterView(
                filterModel: outfitFilterModel,
                wardrobeType: "closet",
                selectedWardrobe: selectedWardrobe
            )
        }
        .onAppear {
            guard !didInitialize else { return }
            didInitialize = true
            bootstrapWardrobeIfNeeded()
            preselectExistingContent()
            refreshContent()
        }
        .onChange(of: selectedWardrobe) { _, wardrobe in
            if wardrobe?.isDefault != true {
                filterModel.selectedWardrobes.removeAll()
            }
            refreshContent()
        }
        .onChange(of: showItemFilter) { _, isShowing in
            if !isShowing { fetchClosetItems() }
        }
        .onChange(of: showOutfitFilter) { _, isShowing in
            if !isShowing { fetchOutfits() }
        }
        .onChange(of: itemFilterKey) { _, _ in
            fetchClosetItems()
        }
        .onChange(of: outfitFilterKey) { _, _ in
            fetchOutfits()
        }
        .onChange(of: filterModel.searchQuery) { _, _ in
            scheduleDebouncedFetch { fetchClosetItems() }
        }
        .onChange(of: outfitFilterModel.searchQuery) { _, _ in
            scheduleDebouncedFetch { fetchOutfits() }
        }
        .onChange(of: authSession.userId) { _, _ in
            bootstrapWardrobeIfNeeded()
            refreshContent()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Header

    private var wardrobeHeader: some View {
        SelectionHeader(
            title: wardrobeTitle,
            onTitleTap: { showWardrobeSelection = true }
        )
        .overlay {
            HStack {
                Button("Back") {
                    dismiss()
                }
                Spacer()
                Button("Done") {
                    saveSelection()
                    dismiss()
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var segmentPickerRow: some View {
        Picker("", selection: $contentSegment) {
            Text("Items (\(closetItems.count))")
                .tag(EventContentSegment.items)
            Text("Outfits (\(outfits.count))")
                .tag(EventContentSegment.outfits)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground))
    }

    @ViewBuilder
    private var actionsBar: some View {
        if contentSegment == .items {
            ItemFilterSortSearchBar(
                sortOrder: $filterModel.sortOrder,
                searchQuery: $filterModel.searchQuery,
                isSearchActive: $isSearchActive,
                isSearchFocused: $isSearchFocused,
                onFilter: { showItemFilter = true },
                onDismissSearch: { dismissSearch(clearQueries: true) },
                activeFilterCount: filterModel.activeFilterCount
            )
        } else {
            ItemFilterSortSearchBar(
                sortOrder: $outfitFilterModel.sortOrder,
                searchQuery: $outfitFilterModel.searchQuery,
                isSearchActive: $isSearchActive,
                isSearchFocused: $isSearchFocused,
                onFilter: { showOutfitFilter = true },
                onDismissSearch: { dismissSearch(clearQueries: true) },
                activeFilterCount: outfitFilterModel.activeFilterCount,
                searchPlaceholder: "Name, category, tag"
            )
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private var itemsContent: some View {
        if selectedWardrobe == nil {
            emptyState(
                icon: "cabinet",
                title: "Select a wardrobe",
                message: "Choose a closet to browse items."
            )
        } else if closetItems.isEmpty {
            emptyState(
                icon: "tshirt",
                title: "No items",
                message: "Add items to this wardrobe or adjust your filters."
            )
        } else {
            ScrollView {
                LazyVGrid(columns: itemGridColumns, spacing: 2) {
                    ForEach(closetItems, id: \.objectID) { item in
                        ZStack(alignment: .topTrailing) {
                            Button {
                                toggleItemSelection(item)
                            } label: {
                                ItemView(item: item)
                                    .frame(width: itemSquareSize, height: itemSquareSize)
                                    .border(isItemSelected(item) ? Color.blue : Color.clear, width: 2)
                            }
                            .buttonStyle(.plain)

                            if isItemSelected(item) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 20))
                                    .padding(4)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var outfitsContent: some View {
        if selectedWardrobe == nil {
            emptyState(
                icon: "cabinet",
                title: "Select a wardrobe",
                message: "Choose a closet to browse outfits."
            )
        } else if outfits.isEmpty {
            emptyState(
                icon: "tshirt",
                title: "No outfits",
                message: "Create an outfit in this wardrobe or adjust your filters."
            )
        } else {
            ScrollView {
                LazyVGrid(columns: outfitGridColumns, spacing: 2) {
                    ForEach(outfits, id: \.objectID) { outfit in
                        ZStack(alignment: .topTrailing) {
                            Button {
                                toggleOutfitSelection(outfit)
                            } label: {
                                outfitThumbnail(outfit)
                                    .frame(width: outfitSquareSize, height: outfitSquareSize)
                                    .clipped()
                                    .border(isOutfitSelected(outfit) ? Color.blue : Color.clear, width: 2)
                            }
                            .buttonStyle(.plain)

                            if isOutfitSelected(outfit) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 20))
                                    .padding(6)
                            }
                        }
                    }
                }
            }
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func outfitThumbnail(_ outfit: Outfit) -> some View {
        if let imageData = outfit.image,
           let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(1, contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                )
        }
    }

    // MARK: - Selection

    private func isItemSelected(_ item: Item) -> Bool {
        guard let id = item.id else { return false }
        return selectedItemsById[id] != nil
    }

    private func isOutfitSelected(_ outfit: Outfit) -> Bool {
        guard let id = outfit.id else { return false }
        return selectedOutfitsById[id] != nil
    }

    private func toggleItemSelection(_ item: Item) {
        guard let id = item.id else { return }
        if selectedItemsById[id] != nil {
            selectedItemsById.removeValue(forKey: id)
            selectedItemIDs.removeAll { $0 == id }
        } else {
            selectedItemsById[id] = item
            selectedItemIDs.append(id)
        }
    }

    private func toggleOutfitSelection(_ outfit: Outfit) {
        guard let id = outfit.id else { return }
        if selectedOutfitsById[id] != nil {
            selectedOutfitsById.removeValue(forKey: id)
        } else {
            selectedOutfitsById[id] = outfit
        }
    }

    // MARK: - Search helpers

    private func scheduleDebouncedFetch(_ fetch: @escaping () -> Void) {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: Self.searchDebounceNanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                fetch()
            }
        }
    }

    private func dismissSearch(clearQueries: Bool) {
        searchDebounceTask?.cancel()
        if clearQueries {
            filterModel.searchQuery = ""
            outfitFilterModel.searchQuery = ""
            refreshContent()
        }
        isSearchActive = false
        isSearchFocused = false
    }

    // MARK: - Bootstrap / fetch

    private func bootstrapWardrobeIfNeeded() {
        guard let userId = currentUserId, !userId.isEmpty else {
            selectedWardrobe = nil
            return
        }

        if let selected = selectedWardrobe,
           selected.userId == userId,
           (selected.type ?? "").lowercased() == "closet",
           selected.isSoftDeleted != true {
            return
        }

        if let initial = initialWardrobe,
           initial.userId == userId,
           (initial.type ?? "").lowercased() == "closet",
           initial.isSoftDeleted != true {
            selectedWardrobe = initial
            return
        }

        selectedWardrobe = WardrobeBootstrap.primaryWardrobe(in: closetWardrobes)
            ?? (try? WardrobeBootstrap.fetchPrimaryWardrobe(
                forType: "closet",
                userIdString: userId,
                in: viewContext
            ))
    }

    private func refreshContent() {
        fetchClosetItems()
        fetchOutfits()
    }

    private func fetchClosetItems() {
        guard let userId = currentUserId, !userId.isEmpty,
              let wardrobe = selectedWardrobe else {
            closetItems = []
            return
        }

        let request: NSFetchRequest<Item> = Item.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.createdAt, ascending: filterModel.sortOrder.sortAscending)]

        var subpredicates: [NSPredicate] = [
            NSPredicate(format: "userId == %@", userId),
            ItemFilterModel.wardrobeMembershipPredicate(
                viewingWardrobe: wardrobe,
                wardrobeType: "closet",
                filterModel: filterModel
            ),
            NSPredicate(format: "isDraft != YES"),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        ]

        if let filter = makePredicate(for: filterModel, context: viewContext) {
            subpredicates.append(filter)
        }

        if let searchPredicate = ItemFilterModel.itemSearchPredicate(query: filterModel.searchQuery) {
            subpredicates.append(searchPredicate)
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)

        do {
            closetItems = try viewContext.fetch(request)
        } catch {
            print("Failed to fetch closet items: \(error)")
            closetItems = []
        }
    }

    private func fetchOutfits() {
        guard let userId = currentUserId, !userId.isEmpty,
              let wardrobe = selectedWardrobe else {
            outfits = []
            return
        }

        let request = NSFetchRequest<Outfit>(entityName: "Outfit")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Outfit.createdAt, ascending: outfitFilterModel.sortOrder.sortAscending)]

        var subpredicates: [NSPredicate] = [
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "isDraft != YES"),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        ]

        if let filter = makeOutfitPredicate(for: outfitFilterModel) {
            subpredicates.append(filter)
        }

        if let searchPredicate = OutfitFilterModel.outfitSearchPredicate(query: outfitFilterModel.searchQuery) {
            subpredicates.append(searchPredicate)
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)

        do {
            let results = try viewContext.fetch(request)
            outfits = results.filter { $0.isVisible(in: wardrobe) }
        } catch {
            print("Failed to fetch outfits: \(error)")
            outfits = []
        }
    }

    private func preselectExistingContent() {
        if let existingItems = event.items as? NSOrderedSet {
            var items: [UUID: Item] = [:]
            var orderedIDs: [UUID] = []
            for case let item as Item in existingItems.array {
                if let id = item.id {
                    items[id] = item
                    orderedIDs.append(id)
                }
            }
            selectedItemsById = items
            selectedItemIDs = orderedIDs
        }

        if let existingOutfits = event.outfits as? Set<Outfit> {
            var outfitsMap: [UUID: Outfit] = [:]
            for outfit in existingOutfits {
                if let id = outfit.id {
                    outfitsMap[id] = outfit
                }
            }
            selectedOutfitsById = outfitsMap
        }
    }

    // MARK: - Save

    private func saveSelection() {
        if let existingItems = event.items as? NSOrderedSet {
            event.removeFromItems(existingItems)
        }
        for id in selectedItemIDs {
            if let item = selectedItemsById[id] {
                event.addToItems(item)
            }
        }

        if let existingOutfits = event.outfits as? Set<Outfit> {
            for outfit in existingOutfits {
                event.removeFromOutfits(outfit)
            }
        }
        for outfit in selectedOutfitsById.values {
            event.addToOutfits(outfit)
        }

        syncEventUserIdFromLinkedEntities(event)

        if !event.objectID.isTemporaryID {
            do {
                try viewContext.save()
            } catch {
                print("Failed to save event selection: \(error)")
            }
        }
    }
}
