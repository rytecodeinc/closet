//
//  PairItemSelectionView.swift
//  closet
//
//  Created by Dan Warner on 12/19/25.
//

import SwiftUI
import CoreData

struct PairItemSelectionView: View {
    @ObservedObject var item: Item
    @Binding var pairSourceSegment: PairSourceSegment
    var dismissesSheetOnSuccess: Bool = true
    var onUnpairComplete: (() -> Void)? = nil
    var onPairSuccess: (() -> Void)? = nil
    var onShowPairedItems: (() -> Void)? = nil
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSession

    @StateObject private var filterModel = ItemFilterModel()
    @StateObject private var tabBarHideState = TabBarHideState()
    @State private var pairableItems: [Item] = []
    @State private var selectedWardrobe: Wardrobe?
    @State private var showPairConfirmation = false
    @State private var itemToPair: Item?
    @State private var showFilter = false
    @State private var showWardrobeSelection = false
    @State private var isSearchActive = false
    @FocusState private var isSearchFocused: Bool
    @State private var searchDebounceTask: Task<Void, Never>?

    enum PairSourceSegment: String, CaseIterable {
        case closet = "Closet"
        case wishlist = "Wishlist"
    }

    private static let searchDebounceNanos: UInt64 = 250_000_000

    private let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var isWishlistItem: Bool {
        (item.wardrobes as? Set<Wardrobe>)?.contains { $0.type?.lowercased() == "wishlist" } ?? false
    }

    private var targetWardrobeType: String {
        if isWishlistItem {
            return pairSourceSegment == .wishlist ? "wishlist" : "closet"
        }
        return "closet"
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
        key += filterModel.sortOrder.sortAscending ? "sortAsc" : "sortDesc"
        key += selectedWardrobe?.objectID.uriRepresentation().absoluteString ?? ""
        return key
    }

    private var emptyStateTitle: String {
        if hasActiveItemFilters {
            return "No matching items"
        }
        if currentSegmentPairedCount > 0 && pairableItems.isEmpty {
            return "No more items to pair"
        }
        if currentSegmentPairedCount == 0 {
            return targetWardrobeType == "wishlist" ? "No wishlist pairs yet" : "No closet pairs yet"
        }
        return targetWardrobeType == "wishlist" ? "No wishlist items yet" : "No closet items yet"
    }

    private var emptyStateMessage: String {
        if hasActiveItemFilters {
            return "Try adjusting your filters or search."
        }
        if currentSegmentPairedCount > 0 && pairableItems.isEmpty {
            return "View paired items to manage existing pairs."
        }
        if currentSegmentPairedCount == 0 {
            return targetWardrobeType == "wishlist"
                ? "This item doesn't have any wishlist pairs yet."
                : "This item doesn't have any closet pairs yet."
        }
        return targetWardrobeType == "wishlist"
            ? "Add items to your wishlist to pair them."
            : "Add items to your closet to pair them."
    }

    private var hasActiveItemFilters: Bool {
        if !filterModel.trimmedSearchQuery.isEmpty { return true }
        return filterModel.selectedCategoryName != nil
            || filterModel.selectedSubcategoryName != nil
            || filterModel.selectedBrandName != nil
            || filterModel.selectedSizeValue != nil
            || !filterModel.selectedColors.isEmpty
            || !filterModel.selectedSeasons.isEmpty
            || filterModel.selectedLocation != nil
            || filterModel.filterLocationNotSet
            || filterModel.minPrice != nil
            || filterModel.maxPrice != nil
            || !filterModel.selectedTags.isEmpty
            || filterModel.filterTagsNotSet
            || filterModel.filterByWeight
            || filterModel.favoritesOnly
            || !filterModel.selectedWardrobes.isEmpty
    }

    private var currentSegmentPairedCount: Int {
        guard let pairedItemsSet = item.pairedItems as? Set<Item> else { return 0 }
        return pairedItemsSet.filter { paired in
            paired.isSoftDeleted != true && pairedItemMatchesTargetWardrobe(paired)
        }.count
    }

    private var visiblePairedItemCount: Int {
        guard let pairedItemsSet = item.pairedItems as? Set<Item> else { return 0 }
        return pairedItemsSet.filter { $0.isSoftDeleted != true }.count
    }

    private var pairedItemObjectIDs: Set<NSManagedObjectID> {
        guard let pairedItemsSet = item.pairedItems as? Set<Item> else { return [] }
        return Set(
            pairedItemsSet
                .filter { $0.isSoftDeleted != true }
                .map(\.objectID)
        )
    }

    private func pairedItemMatchesTargetWardrobe(_ pairedItem: Item) -> Bool {
        let isWishlist = (pairedItem.wardrobes as? Set<Wardrobe>)?
            .contains { $0.type?.lowercased() == "wishlist" } ?? false
        return targetWardrobeType == "wishlist" ? isWishlist : !isWishlist
    }

    var body: some View {
        Group {
            if dismissesSheetOnSuccess {
                NavigationStack {
                    pairSelectionContent
                }
            } else {
                pairSelectionContent
            }
        }
        .onAppear {
            resetFiltersForNewSession()
            fetchPairableItems()
        }
        .onChange(of: pairSourceSegment) { _, _ in
            selectedWardrobe = nil
            fetchPairableItems()
        }
        .onChange(of: filterKey) { _, _ in
            fetchPairableItems()
        }
        .onChange(of: filterModel.sortOrder) { _, _ in
            fetchPairableItems()
        }
        .onChange(of: filterModel.searchQuery) { _, _ in
            scheduleDebouncedFetch()
        }
        .onChange(of: selectedWardrobe) { _, _ in
            fetchPairableItems()
        }
        .onChange(of: visiblePairedItemCount) { _, _ in
            fetchPairableItems()
        }
        .modifier(PairItemSelectionPresentationModifier(appliesDetents: dismissesSheetOnSuccess))
        .alert("Pair Item", isPresented: $showPairConfirmation) {
            Button("Cancel", role: .cancel) {
                itemToPair = nil
            }
            Button("Pair") {
                if let itemToPair {
                    confirmPair(with: itemToPair)
                }
            }
        } message: {
            if let itemToPair {
                Text(pairConfirmationMessage(with: itemToPair))
            }
        }
    }

    private var pairSelectionContent: some View {
        VStack(spacing: 0) {
            pairSelectionHeader
            pairSelectionActionsBar

            if pairableItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tshirt")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(emptyStateTitle)
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(emptyStateMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(pairableItems, id: \.objectID) { candidate in
                            if candidate.objectID != item.objectID {
                                Button {
                                    itemToPair = candidate
                                    showPairConfirmation = true
                                } label: {
                                    ItemView(item: candidate)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .navigationDestination(isPresented: $showFilter) {
            ItemFilterView(
                filterModel: filterModel,
                tabBarHideState: tabBarHideState,
                wardrobeType: targetWardrobeType,
                selectedWardrobe: selectedWardrobe
            )
        }
        .navigationDestination(isPresented: $showWardrobeSelection) {
            SingleWardrobeSelectionView(
                selectedWardrobe: $selectedWardrobe,
                wardrobeType: targetWardrobeType
            )
        }
    }

    private var pairSheetWardrobeTitle: String {
        selectedWardrobe?.name ?? (targetWardrobeType == "wishlist" ? "Select Wishlist" : "Select Closet")
    }

    @ViewBuilder
    private var pairSelectionHeader: some View {
        if isWishlistItem {
            pairSelectionPanel(showsSegmentPicker: true)
        } else {
            pairSelectionPanel(showsSegmentPicker: false)
        }
    }

    @ViewBuilder
    private func pairSelectionPanel(showsSegmentPicker: Bool) -> some View {
        if onShowPairedItems != nil {
            if showsSegmentPicker {
                SelectionPanelHeader(
                    title: pairSheetWardrobeTitle,
                    onTitleTap: { showWardrobeSelection = true },
                    actionPlacement: .barAboveTitle,
                    leading: { EmptyView() },
                    trailing: { pairSelectionHeaderTrailing },
                    picker: { pairSourceSegmentPicker }
                )
            } else {
                SelectionPanelHeader(
                    title: pairSheetWardrobeTitle,
                    onTitleTap: { showWardrobeSelection = true },
                    actionPlacement: .barAboveTitle,
                    leading: { EmptyView() },
                    trailing: { pairSelectionHeaderTrailing }
                )
            }
        } else if showsSegmentPicker {
            SelectionPanelHeader(
                title: pairSheetWardrobeTitle,
                onTitleTap: { showWardrobeSelection = true },
                picker: { pairSourceSegmentPicker }
            )
        } else {
            SelectionPanelHeader(
                title: pairSheetWardrobeTitle,
                onTitleTap: { showWardrobeSelection = true }
            )
        }
    }

    private var pairSourceSegmentPicker: some View {
        Picker("Item Type", selection: $pairSourceSegment) {
            ForEach(PairSourceSegment.allCases, id: \.self) { segment in
                Text(segment.rawValue).tag(segment)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var pairSelectionHeaderTrailing: some View {
        if let onShowPairedItems {
            Button(action: onShowPairedItems) {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                    Text("View Pairs")
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View pairs")
        }
    }

    private var pairSelectionActionsBar: some View {
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

    private func scheduleDebouncedFetch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: Self.searchDebounceNanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                fetchPairableItems()
            }
        }
    }

    private func dismissSearch(clearQueries: Bool) {
        searchDebounceTask?.cancel()
        if clearQueries {
            filterModel.searchQuery = ""
            fetchPairableItems()
        }
        isSearchActive = false
        isSearchFocused = false
    }

    private func resetFiltersForNewSession() {
        searchDebounceTask?.cancel()
        filterModel.clearAll()
        isSearchActive = false
        isSearchFocused = false
    }

    private func trimmedItemName(_ item: Item) -> String {
        (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pairConfirmationMessage(with other: Item) -> String {
        let sourceName = trimmedItemName(item)
        let otherName = trimmedItemName(other)
        let sourceNamed = !sourceName.isEmpty
        let otherNamed = !otherName.isEmpty

        switch (sourceNamed, otherNamed) {
        case (false, false):
            return "Pair these items?"
        case (false, true):
            return "Pair this item with \(otherName)?"
        case (true, false):
            return "Pair this item with \(sourceName)?"
        case (true, true):
            return "Pair \"\(sourceName)\" with \"\(otherName)\"?"
        }
    }

    private func confirmPair(with pairedItem: Item) {
        var currentPairedItems = item.pairedItems as? Set<Item> ?? []
        currentPairedItems.insert(pairedItem)
        item.pairedItems = currentPairedItems as NSSet

        var pairedItemSet = pairedItem.pairedItems as? Set<Item> ?? []
        pairedItemSet.insert(item)
        pairedItem.pairedItems = pairedItemSet as NSSet

        do {
            setUpdatedAt(item)
            setUpdatedAt(pairedItem)

            try viewContext.save()

            SyncService.shared.syncItemIfNeeded(item)
            SyncService.shared.syncItemIfNeeded(pairedItem)

            itemToPair = nil
            onPairSuccess?()
            if dismissesSheetOnSuccess {
                dismiss()
            } else {
                fetchPairableItems()
            }
        } catch {
            print("❌ Failed to save paired item: \(error)")
        }
    }

    private func fetchPairableItems() {
        guard let userId = authSession.userId?.uuidString, !userId.isEmpty else {
            pairableItems = []
            selectedWardrobe = nil
            return
        }

        let wardrobeType = targetWardrobeType

        let wardrobe: Wardrobe?
        if let selected = selectedWardrobe,
           (selected.type ?? "").lowercased() == wardrobeType,
           selected.userId == userId,
           selected.isSoftDeleted != true {
            wardrobe = selected
        } else {
            let matchingWardrobes = (item.wardrobes as? Set<Wardrobe>)?
                .filter {
                    ($0.type ?? "").lowercased() == wardrobeType &&
                    $0.userId == userId &&
                    $0.isSoftDeleted != true
                } ?? []

            if !matchingWardrobes.isEmpty {
                wardrobe = WardrobeBootstrap.primaryWardrobe(in: matchingWardrobes) ?? matchingWardrobes.first
            } else {
                wardrobe = try? WardrobeBootstrap.fetchPrimaryWardrobe(
                    forType: wardrobeType,
                    userIdString: userId,
                    in: viewContext
                )
            }
            selectedWardrobe = wardrobe
        }

        guard let wardrobe else {
            pairableItems = []
            return
        }

        let request: NSFetchRequest<Item> = Item.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.createdAt, ascending: filterModel.sortOrder.sortAscending)]

        var subpredicates: [NSPredicate] = [
            NSPredicate(format: "userId == %@", userId),
            ItemFilterModel.wardrobeMembershipPredicate(
                viewingWardrobe: wardrobe,
                wardrobeType: wardrobeType,
                filterModel: filterModel
            ),
            NSPredicate(format: "isDraft != YES"),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil"),
            NSPredicate(format: "SELF != %@", item)
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
            let wardrobeID = wardrobe.objectID
            pairableItems = results.filter { candidate in
                guard let wardrobes = candidate.wardrobes as? Set<Wardrobe> else { return false }
                return wardrobes.contains { $0.objectID == wardrobeID }
                    && !pairedItemObjectIDs.contains(candidate.objectID)
            }
        } catch {
            print("❌ Failed to fetch pairable items: \(error)")
            pairableItems = []
        }
    }
}

private struct PairItemSelectionPresentationModifier: ViewModifier {
    let appliesDetents: Bool

    func body(content: Content) -> some View {
        Group {
            if appliesDetents {
                content
                    .presentationDetents([.medium, .large])
            } else {
                content
            }
        }
        .presentationDragIndicator(.visible)
    }
}
