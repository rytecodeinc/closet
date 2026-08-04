//
//  RemoteProfileWardrobeGridView.swift
//  closet
//
//  Read-only Items / Outfits grid for another user's public wardrobe (Supabase RPCs).
//

import SwiftUI

struct RemoteProfileWardrobeGridView: View {
    let ownerUserId: UUID
    let wardrobe: VisibleWardrobe
    var ownerProfile: PublicUserProfile? = nil
    var refreshToken: UUID = UUID()
    @Binding var preferredTab: String
    var tabBarHideState: TabBarHideState? = nil
    private let profileCollapsingHeader: AnyView
    private let profileStickyPrefix: AnyView

    @EnvironmentObject private var supabaseService: SupabaseService

    @StateObject private var itemFilterModel = ItemFilterModel()
    @StateObject private var outfitFilterModel = OutfitFilterModel()
    @StateObject private var ownedTabBarHideState = TabBarHideState()

    @State private var items: [VisibleWardrobeItem] = []
    @State private var outfits: [VisibleWardrobeOutfit] = []
    @State private var isLoadingItems = false
    @State private var isLoadingOutfits = false
    @State private var loadError: String?
    @State private var selectedItem: VisibleWardrobeItem?
    @State private var selectedOutfit: VisibleWardrobeOutfit?
    @State private var isActionBarSearchActive = false
    @FocusState private var isActionBarSearchFocused: Bool
    @State private var showItemFilter = false
    @State private var showOutfitFilter = false

    private static let pagedTabMinHeight: CGFloat = 280
    private static let tabActionsBarHeight: CGFloat = 44

    private let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    private var filterTabBarHideState: TabBarHideState {
        tabBarHideState ?? ownedTabBarHideState
    }

    private var wardrobeType: String {
        wardrobe.wardrobeType.lowercased()
    }

    private var displayedItems: [VisibleWardrobeItem] {
        Self.filteredAndSortedItems(items, filter: itemFilterModel)
    }

    private var displayedOutfits: [VisibleWardrobeOutfit] {
        Self.filteredAndSortedOutfits(outfits, filter: outfitFilterModel)
    }

    init(
        ownerUserId: UUID,
        wardrobe: VisibleWardrobe,
        ownerProfile: PublicUserProfile? = nil,
        refreshToken: UUID = UUID(),
        preferredTab: Binding<String>,
        tabBarHideState: TabBarHideState? = nil,
        @ViewBuilder profileCollapsingHeader: () -> some View = { EmptyView() },
        @ViewBuilder profileStickyPrefix: () -> some View = { EmptyView() }
    ) {
        self.ownerUserId = ownerUserId
        self.wardrobe = wardrobe
        self.ownerProfile = ownerProfile
        self.refreshToken = refreshToken
        self._preferredTab = preferredTab
        self.tabBarHideState = tabBarHideState
        self.profileCollapsingHeader = AnyView(profileCollapsingHeader())
        self.profileStickyPrefix = AnyView(profileStickyPrefix())
    }

    var body: some View {
        // Match own Profile: UIKit nested scroll (collapsing header, sticky chrome,
        // paged Items/Outfits with independent scroll + UIRefreshControl).
        ProfileNestedScrollContainer(
            selectedTab: $preferredTab,
            header: profileCollapsingHeader,
            sticky: stickyChrome,
            itemsPage: itemsTab,
            outfitsPage: outfitsTab,
            onRefresh: {
                await loadGridData(forceRefresh: true)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(wardrobe.id.uuidString)-\(refreshToken.uuidString)") {
            await loadGridData(forceRefresh: true)
        }
        .onAppear {
            tabBarHideState?.shouldHideTabBar = true
            hydrateGridFromCacheIfNeeded()
        }
        .onChange(of: preferredTab) { _, _ in
            dismissActionBarSearch(clearQueries: false)
        }
        .navigationDestination(item: $selectedItem) { item in
            ReadOnlyItemDetailView(
                ownerUserId: ownerUserId,
                wardrobeId: wardrobe.id,
                itemSummary: item,
                wardrobeType: wardrobeType,
                ownerProfile: ownerProfile,
                tabBarHideState: tabBarHideState
            )
        }
        .navigationDestination(item: $selectedOutfit) { outfit in
            if outfit.isPendingSuggestion {
                PendingOutfitDetailView(
                    recipientUserId: ownerUserId,
                    wardrobeId: wardrobe.id,
                    suggestionSummary: outfit,
                    viewerRole: .submitter
                )
            } else {
                ReadOnlyOutfitDetailView(
                    ownerUserId: ownerUserId,
                    wardrobeId: wardrobe.id,
                    outfitSummary: outfit,
                    tabBarHideState: tabBarHideState
                )
            }
        }
        .navigationDestination(isPresented: $showItemFilter) {
            ItemFilterView(
                filterModel: itemFilterModel,
                tabBarHideState: filterTabBarHideState,
                attributesReadOnly: true,
                remoteProfileMode: true,
                selectedWardrobe: nil
            )
        }
        .navigationDestination(isPresented: $showOutfitFilter) {
            OutfitFilterView(
                filterModel: outfitFilterModel,
                wardrobeType: wardrobeType,
                attributesReadOnly: true,
                remoteProfileMode: true,
                selectedWardrobe: nil
            )
        }
    }

    @ViewBuilder
    private var stickyChrome: some View {
        VStack(spacing: 0) {
            profileStickyPrefix
            tabPicker
            tabActionsBar
        }
        .background(Color(.systemBackground))
    }

    private var tabPicker: some View {
        Picker("", selection: $preferredTab) {
            Text("Items (\(displayedItems.count))").tag("Items")
            Text("Outfits (\(displayedOutfits.count))").tag("Outfits")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var tabActionsBar: some View {
        if preferredTab == "Items" {
            ItemFilterSortSearchBar(
                sortOrder: $itemFilterModel.sortOrder,
                searchQuery: $itemFilterModel.searchQuery,
                isSearchActive: $isActionBarSearchActive,
                isSearchFocused: $isActionBarSearchFocused,
                onFilter: {
                    filterTabBarHideState.shouldHideTabBar = true
                    showItemFilter = true
                },
                onDismissSearch: { dismissActionBarSearch(clearQueries: true) },
                activeFilterCount: remoteItemActiveFilterCount,
                barHeight: Self.tabActionsBarHeight
            )
        } else {
            ItemFilterSortSearchBar(
                sortOrder: $outfitFilterModel.sortOrder,
                searchQuery: $outfitFilterModel.searchQuery,
                isSearchActive: $isActionBarSearchActive,
                isSearchFocused: $isActionBarSearchFocused,
                onFilter: {
                    filterTabBarHideState.shouldHideTabBar = true
                    showOutfitFilter = true
                },
                onDismissSearch: { dismissActionBarSearch(clearQueries: true) },
                activeFilterCount: remoteOutfitActiveFilterCount,
                searchPlaceholder: "Name, category",
                barHeight: Self.tabActionsBarHeight
            )
        }
    }

    private var remoteItemActiveFilterCount: Int {
        var count = 0
        if itemFilterModel.selectedCategoryName != nil { count += 1 }
        if itemFilterModel.selectedBrandName != nil { count += 1 }
        if let size = itemFilterModel.selectedSizeValue, !size.isEmpty { count += 1 }
        return count
    }

    private var remoteOutfitActiveFilterCount: Int {
        outfitFilterModel.selectedCategory != nil ? 1 : 0
    }

    private func dismissActionBarSearch(clearQueries: Bool) {
        isActionBarSearchActive = false
        isActionBarSearchFocused = false
        if clearQueries {
            itemFilterModel.searchQuery = ""
            outfitFilterModel.searchQuery = ""
        }
    }

    private var itemsTab: some View {
        ScrollView(showsIndicators: false) {
            itemsContent
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var outfitsTab: some View {
        ScrollView(showsIndicators: false) {
            outfitsContent
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var itemsContent: some View {
        if isLoadingItems && items.isEmpty {
            ProgressView("Loading items…")
                .frame(maxWidth: .infinity)
                .frame(minHeight: Self.pagedTabMinHeight)
        } else if let loadError, items.isEmpty {
            Text(loadError)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity)
                .frame(minHeight: Self.pagedTabMinHeight)
        } else if items.isEmpty {
            Text("No items in this wardrobe")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Self.pagedTabMinHeight)
        } else if displayedItems.isEmpty {
            Text("No matching items")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Self.pagedTabMinHeight)
        } else {
            LazyVGrid(columns: gridColumns, spacing: 2) {
                ForEach(displayedItems) { item in
                    RemoteProfileItemCell(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedItem = item
                        }
                }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var outfitsContent: some View {
        if isLoadingOutfits && outfits.isEmpty {
            ProgressView("Loading outfits…")
                .frame(maxWidth: .infinity)
                .frame(minHeight: Self.pagedTabMinHeight)
        } else if let loadError, outfits.isEmpty {
            Text(loadError)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity)
                .frame(minHeight: Self.pagedTabMinHeight)
        } else if outfits.isEmpty {
            Text("No outfits in this wardrobe")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Self.pagedTabMinHeight)
        } else if displayedOutfits.isEmpty {
            Text("No matching outfits")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Self.pagedTabMinHeight)
        } else {
            LazyVGrid(columns: gridColumns, spacing: 2) {
                ForEach(displayedOutfits) { outfit in
                    RemoteProfileOutfitCell(outfit: outfit)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedOutfit = outfit
                        }
                }
            }
            .padding(.top, 2)
        }
    }

    private func hydrateGridFromCacheIfNeeded() {
        guard items.isEmpty, outfits.isEmpty else { return }
        if let cachedItems = supabaseService.cachedWardrobeGridItems(
            userId: ownerUserId,
            wardrobeId: wardrobe.id
        ) {
            items = cachedItems
        }
        if let cachedOutfits = supabaseService.cachedWardrobeGridOutfits(
            userId: ownerUserId,
            wardrobeId: wardrobe.id
        ) {
            outfits = cachedOutfits
        }
    }

    private func loadGridData(forceRefresh: Bool) async {
        let hasCachedGrid = !forceRefresh && supabaseService.hasCachedWardrobeGrid(
            userId: ownerUserId,
            wardrobeId: wardrobe.id
        )
        if !hasCachedGrid {
            loadError = nil
            isLoadingItems = true
            isLoadingOutfits = true
        }
        defer {
            isLoadingItems = false
            isLoadingOutfits = false
        }

        async let itemsTask = supabaseService.fetchVisibleWardrobeItems(
            userId: ownerUserId,
            wardrobeId: wardrobe.id,
            forceRefresh: forceRefresh
        )
        async let outfitsTask = supabaseService.fetchVisibleWardrobeOutfits(
            userId: ownerUserId,
            wardrobeId: wardrobe.id,
            forceRefresh: forceRefresh
        )

        do {
            let (fetchedItems, fetchedOutfits) = try await (itemsTask, outfitsTask)
            if Task.isCancelled { return }
            items = fetchedItems
            outfits = fetchedOutfits
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            if Self.isCancellationError(error) { return }
            if items.isEmpty && outfits.isEmpty {
                loadError = error.localizedDescription
            }
            print("⚠️ Failed to load remote wardrobe grid: \(error.localizedDescription)")
        }
    }

    private static func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    // MARK: - Client-side filter / sort (visible wardrobe RPC fields)

    private static func filteredAndSortedItems(
        _ items: [VisibleWardrobeItem],
        filter: ItemFilterModel
    ) -> [VisibleWardrobeItem] {
        var result = items.filter { item in
            matchesRemoteItem(item, filter: filter)
        }
        result.sort { lhs, rhs in
            compareRemoteDates(
                lhs.createdAt,
                rhs.createdAt,
                lhsName: lhs.name,
                rhsName: rhs.name,
                ascending: filter.sortOrder.sortAscending
            )
        }
        return result
    }

    private static func filteredAndSortedOutfits(
        _ outfits: [VisibleWardrobeOutfit],
        filter: OutfitFilterModel
    ) -> [VisibleWardrobeOutfit] {
        var result = outfits.filter { outfit in
            matchesRemoteOutfit(outfit, filter: filter)
        }
        result.sort { lhs, rhs in
            compareRemoteDates(
                lhs.createdAt,
                rhs.createdAt,
                lhsName: lhs.name,
                rhsName: rhs.name,
                ascending: filter.sortOrder.sortAscending
            )
        }
        return result
    }

    private static func matchesRemoteItem(_ item: VisibleWardrobeItem, filter: ItemFilterModel) -> Bool {
        let query = filter.trimmedSearchQuery
        if !query.isEmpty {
            let haystacks = [
                item.name,
                item.brandName,
                item.categoryName,
                item.subcategoryName,
                item.sizeValue
            ]
            let matchesQuery = haystacks.contains { value in
                (value ?? "").localizedCaseInsensitiveContains(query)
            }
            if !matchesQuery { return false }
        }

        if let selected = filter.selectedCategoryName {
            if selected == ItemFilterModel.categoryNotSetFilterValue {
                if !(item.categoryName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                    return false
                }
            } else {
                let cat = item.categoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard cat.caseInsensitiveCompare(selected) == .orderedSame else { return false }
                if let sub = filter.selectedSubcategoryName?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !sub.isEmpty {
                    let itemSub = item.subcategoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard itemSub.caseInsensitiveCompare(sub) == .orderedSame else { return false }
                }
            }
        }

        if let selected = filter.selectedBrandName {
            if selected == ItemFilterModel.brandNotSetFilterValue {
                if !(item.brandName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                    return false
                }
            } else {
                let brand = item.brandName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard brand.caseInsensitiveCompare(selected) == .orderedSame else { return false }
            }
        }

        if let selected = filter.selectedSizeValue, !selected.isEmpty {
            if selected == ItemFilterModel.sizeNotSetFilterValue {
                if !(item.sizeValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                    return false
                }
            } else {
                let size = item.sizeValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard size.caseInsensitiveCompare(selected) == .orderedSame else { return false }
            }
        }

        return true
    }

    private static func matchesRemoteOutfit(_ outfit: VisibleWardrobeOutfit, filter: OutfitFilterModel) -> Bool {
        let query = filter.trimmedSearchQuery
        if !query.isEmpty {
            let haystacks = [outfit.name, outfit.categoryName]
            let matchesQuery = haystacks.contains { value in
                (value ?? "").localizedCaseInsensitiveContains(query)
            }
            if !matchesQuery { return false }
        }

        if let selectedName = filter.selectedCategory?.name?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !selectedName.isEmpty {
            let cat = outfit.categoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard cat.caseInsensitiveCompare(selectedName) == .orderedSame else { return false }
        }

        return true
    }

    private static func compareRemoteDates(
        _ lhs: Date?,
        _ rhs: Date?,
        lhsName: String?,
        rhsName: String?,
        ascending: Bool
    ) -> Bool {
        switch (lhs, rhs) {
        case let (l?, r?):
            if l != r { return ascending ? l < r : l > r }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }
        let left = (lhsName ?? "").lowercased()
        let right = (rhsName ?? "").lowercased()
        return ascending ? left < right : left > right
    }
}

private struct RemoteProfileItemCell: View {
    let item: VisibleWardrobeItem

    var body: some View {
        GeometryReader { geo in
            RemoteURLImage(
                url: item.displayImageURL,
                failureSystemImage: "tshirt"
            )
            .frame(width: geo.size.width, height: geo.size.width)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct RemoteProfileOutfitCell: View {
    let outfit: VisibleWardrobeOutfit

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                RemoteURLImage(
                    url: outfit.collageImageURL,
                    failureSystemImage: "photo"
                )

                if let profile = outfit.suggesterProfile {
                    RedressSuggesterAvatarBadge(
                        profile: profile,
                        size: geo.size.width * 0.28
                    )
                    .padding(6)
                }
            }
            .frame(width: geo.size.width, height: geo.size.width)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
