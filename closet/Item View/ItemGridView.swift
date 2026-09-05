//
//  ItemGridView.swift
//  closet
//
//  Created by Dan Warner on 7/15/25.
//


import SwiftUI
import UIKit
import CoreData
import Combine

private enum PackingNavigation: Hashable {
    case packing
}

/// Own-profile read-only item tap → same destination as other-user profile grid.
/// Owned by `ProfileView`'s `NavigationStack` path; keep set until pop.
struct ProfileReadOnlyItemDestination: Hashable {
    let ownerUserId: UUID
    let wardrobeId: UUID
    let item: VisibleWardrobeItem
    let wardrobeType: String
    var ownerProfile: PublicUserProfile? = nil
}

struct ItemGridView: View {
    @ObservedObject var filterModel: ItemFilterModel
    @ObservedObject var outfitFilterModel: OutfitFilterModel
    var wardrobeType: String
    var selectedWardrobe: Wardrobe
    var isReadOnly: Bool = false
    /// When true (Profile), shows a Redress toggle on the Outfits action bar to filter accepted Redress outfits.
    var showsProfilePendingRedressSuggestions: Bool = false
    /// Profile avatar/stats header that scrolls away above the sticky chrome.
    private let profileCollapsingHeader: AnyView
    /// Profile rows pinned with the picker (e.g. wardrobe bar).
    private let profileStickyPrefix: AnyView
    /// When set (Profile), parent owns filter-bar visibility.
    private let externalTabActionsBarVisible: Binding<Bool>?
    
    // Binding to communicate selection state to parent
    @Binding var isInSelectionMode: Bool
    /// Closet/Wishlist hide the wardrobe picker while Items selection shows Manage.
    @Binding var isReplacingNavigationTitle: Bool
    /// ProfileView sets this so its tab-bar visibility stays in sync with pushed detail screens.
    @Binding var isDetailNavigationActive: Bool
    /// Parent owns `NavigationPath` + Filter destinations — grid only requests a push (avoids AttributeGraph cycle).
    var onOpenItemFilter: () -> Void
    var onOpenOutfitFilter: () -> Void
    /// Closet/Wishlist append `ItemGridFilterRoute.addItem` / `.addItemQueued` on the tab path.
    var onOpenAddItem: ((Bool) -> Void)?
    /// Closet/Wishlist append `ItemGridFilterRoute.addOutfit(sessionID:)` on the tab path.
    var onOpenAddOutfit: ((UUID) -> Void)?
    /// Closet/Wishlist append `ItemGridFilterRoute.itemDetail(uri:)` on the tab path.
    var onOpenItemDetail: ((String) -> Void)?
    /// Closet/Wishlist append `ItemGridFilterRoute.outfitDetail(uri:)` on the tab path.
    var onOpenOutfitDetail: ((String) -> Void)?
    /// Closet append `ItemGridFilterRoute.packing` on the tab path.
    var onOpenPacking: (() -> Void)?
    /// Profile append `ProfileRoute.pendingRedress` on the tab path.
    var onOpenPendingRedress: ((PendingRedressNavigationDestination) -> Void)?
    /// Profile tab owns `ProfileRoute.readOnlyItem` — grid only requests a path append.
    var onOpenProfileReadOnlyItem: ((ProfileReadOnlyItemDestination) -> Void)?
    /// Tab-bar hide flag shared with `ItemFilterView` (destination is on the parent stack).
    @ObservedObject var tabBarHideState: TabBarHideState

    init(
        filterModel: ItemFilterModel,
        outfitFilterModel: OutfitFilterModel,
        wardrobeType: String,
        selectedWardrobe: Wardrobe,
        isReadOnly: Bool = false,
        showsProfilePendingRedressSuggestions: Bool = false,
        isInSelectionMode: Binding<Bool>,
        isReplacingNavigationTitle: Binding<Bool> = .constant(false),
        isDetailNavigationActive: Binding<Bool> = .constant(false),
        isTabActionsBarVisible: Binding<Bool>? = nil,
        onOpenItemFilter: @escaping () -> Void,
        onOpenOutfitFilter: @escaping () -> Void,
        onOpenAddItem: ((Bool) -> Void)? = nil,
        onOpenAddOutfit: ((UUID) -> Void)? = nil,
        onOpenItemDetail: ((String) -> Void)? = nil,
        onOpenOutfitDetail: ((String) -> Void)? = nil,
        onOpenPacking: (() -> Void)? = nil,
        onOpenPendingRedress: ((PendingRedressNavigationDestination) -> Void)? = nil,
        onOpenProfileReadOnlyItem: ((ProfileReadOnlyItemDestination) -> Void)? = nil,
        tabBarHideState: TabBarHideState,
        queueCoordinator: ImageQueueCoordinator,
        @ViewBuilder profileCollapsingHeader: () -> some View = { EmptyView() },
        @ViewBuilder profileStickyPrefix: () -> some View = { EmptyView() }
    ) {
        self.filterModel = filterModel
        self.outfitFilterModel = outfitFilterModel
        self.wardrobeType = wardrobeType
        self.selectedWardrobe = selectedWardrobe
        self.isReadOnly = isReadOnly
        self.showsProfilePendingRedressSuggestions = showsProfilePendingRedressSuggestions
        self._isInSelectionMode = isInSelectionMode
        self._isReplacingNavigationTitle = isReplacingNavigationTitle
        self._isDetailNavigationActive = isDetailNavigationActive
        self.onOpenItemFilter = onOpenItemFilter
        self.onOpenOutfitFilter = onOpenOutfitFilter
        self.onOpenAddItem = onOpenAddItem
        self.onOpenAddOutfit = onOpenAddOutfit
        self.onOpenItemDetail = onOpenItemDetail
        self.onOpenOutfitDetail = onOpenOutfitDetail
        self.onOpenPacking = onOpenPacking
        self.onOpenPendingRedress = onOpenPendingRedress
        self.onOpenProfileReadOnlyItem = onOpenProfileReadOnlyItem
        self._queueCoordinator = ObservedObject(wrappedValue: queueCoordinator)
        self._tabBarHideState = ObservedObject(wrappedValue: tabBarHideState)
        self.externalTabActionsBarVisible = isTabActionsBarVisible
        self.profileCollapsingHeader = AnyView(profileCollapsingHeader())
        self.profileStickyPrefix = AnyView(profileStickyPrefix())
        self._internalTabActionsBarVisible = State(
            initialValue: isTabActionsBarVisible?.wrappedValue ?? true
        )
    }
    
    @State private var packingNavigation: PackingNavigation?

    @EnvironmentObject var supabaseService: SupabaseService
    @EnvironmentObject var authSession: AuthSession
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appCapabilities) private var appCapabilities
    @State private var closetItems: [Item] = []
    @State private var hasCompletedInitialItemsFetch = false
    @State private var hasCompletedInitialOutfitsFetch = false
    @State private var hasCompletedInitialRedressFetch = false
    @State private var isLoadingRedressSuggestions = false
    @State private var isImagePickerPresented = false
    @State private var pickedImage: UIImage? = nil
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedTab: String = "Items"
    
    @State private var outfits: [Outfit] = []
    @State private var pendingRedressOutfitIds: Set<UUID> = []
    @State private var profilePendingSuggestions: [VisibleOutfitSuggestion] = []
    @State private var isRedressFilterActive = false
    @State private var selectedPendingRedress: PendingRedressNavigationDestination?
    
    // Selection mode state
    @State private var selectedItemURIForNavigation: String?
    @State private var selectedItems: Set<Item> = []
    @State private var selectedItemStripIDs: [NSManagedObjectID] = []
    @State private var selectedOutfitURIForNavigation: String?
    @State private var selectedOutfits: Set<Outfit> = []
    @State private var selectedOutfitStripIDs: [NSManagedObjectID] = []
    @State private var showWardrobeSelectionSheet = false
    @State private var showWardrobeSelectionConfirmAlert = false
    @State private var pendingWardrobeSelectionTarget: Wardrobe?
    @State private var pendingWardrobeSelectionWillRemove = false
    @State private var showDeleteConfirmation = false
    @State private var showOutfitDeleteConfirmation = false
    @State private var showTagSelectionSheet = false
    @State private var tagSelectionSearchText = ""
    @State private var showColorSelectionSheet = false
    @State private var showCategorySelectionSheet = false
    @State private var bulkSetCategoryExpanded: Set<NSManagedObjectID> = []
    @State private var showCategorySelectionConfirmAlert = false
    @State private var pendingBulkCategory: Category?
    @State private var pendingBulkSubcategory: Subcategory?
    @State private var showDeletionToast = false
    @State private var deletionToastMessage: String = ""
    @State private var showTagSelectionConfirmAlert = false
    @State private var pendingTagSelectionTarget: Tag?
    @State private var pendingTagSelectionWillRemove = false
    @State private var showOutfitCategorySelectionSheet = false
    @State private var showOutfitCategorySelectionConfirmAlert = false
    @State private var wardrobeVisibilityRevision = 0
    @State private var pendingOutfitCategoryTarget: OutfitCategory?
    @State private var pendingOutfitCategoryWillRemove = false
    @State private var showColorSelectionConfirmAlert = false
    @State private var pendingColorSelectionTarget: AppColor?
    @State private var pendingColorSelectionWillRemove = false
    @State private var showFavoriteSelectionConfirmAlert = false
    @State private var pendingFavoriteSelectionWillUnfavorite = false
    /// Bumps when favorites change so the bottom bar heart reflects Core Data without relying on selection set identity.
    @State private var favoriteToolbarTick = 0
    @State private var showAddFromClosetSheet = false
    
    // Multi-image picker state
    @ObservedObject var queueCoordinator: ImageQueueCoordinator
    @State private var showMultiImagePicker = false
    @State private var showCropperForQueue = false
    @State private var isItemAddOnPath = false
    @State private var isOutfitAddOnPath = false
    @State private var isPackingOnPath = false
    @State private var queuedImages: [UIImage] = []
    @State private var showCropperCancelConfirmation = false

    private static let tabActionsBarHeight: CGFloat = 44
    private static let searchDebounceNanos: UInt64 = 250_000_000
    /// Coalesce Core Data save storms (sync merges, bulk edits) into one grid reload.
    private static let contextSaveDebounceNanos: UInt64 = 400_000_000

    @Environment(\.scenePhase) private var scenePhase

    @State private var internalTabActionsBarVisible = true
    @State private var isActionBarSearchActive = false
    @FocusState private var isActionBarSearchFocused: Bool
    @State private var itemSearchDebounceTask: Task<Void, Never>?
    @State private var outfitSearchDebounceTask: Task<Void, Never>?
    @State private var contextSaveDebounceTask: Task<Void, Never>?
    @State private var itemFetchTask: Task<Void, Never>?
    @State private var outfitRefreshTask: Task<Void, Never>?
    @State private var itemFetchGeneration = 0
    @State private var outfitRefreshGeneration = 0
    @State private var needsItemFetchRetry = false
    @State private var needsOutfitFetchRetry = false

    private var isTabActionsBarVisible: Bool {
        get { externalTabActionsBarVisible?.wrappedValue ?? internalTabActionsBarVisible }
        nonmutating set {
            if let externalTabActionsBarVisible {
                externalTabActionsBarVisible.wrappedValue = newValue
            } else {
                internalTabActionsBarVisible = newValue
            }
        }
    }

    let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    // Computed property to track filter changes
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
        key += filterModel.favoritesOnly ? "favoritesOnly" : "allItems"
        if filterModel.filterByWeight {
            // Include user weight in key so it refreshes when user updates their weight
            let repository = UserProfileRepository(context: viewContext)
            let userWeightKg = repository.getWeightKg()
            key += "weight:\(userWeightKg)"
        }
        key += filterModel.sortOrder.sortAscending ? "sortAsc" : "sortDesc"
        key += filterModel.selectedWardrobes.map { $0.objectID.uriRepresentation().absoluteString }.sorted().joined(separator: ",")
        key += filterModel.trimmedSearchQuery
        return key
    }
    
    // Computed property to track outfit filter changes
    private var outfitFilterKey: String {
        var key = ""
        key += outfitFilterModel.selectedCategory?.name ?? ""
        key += outfitFilterModel.selectedTags.map { $0.objectID.uriRepresentation().absoluteString }.sorted().joined(separator: ",")
        key += outfitFilterModel.filterTagsNotSet ? "tagsNotSet" : ""
        key += outfitFilterModel.favoritesOnly ? "favoritesOnly" : "allOutfits"
        key += outfitFilterModel.sortOrder.sortAscending ? "sortAsc" : "sortDesc"
        key += outfitFilterModel.trimmedSearchQuery
        return key
    }

    private var isItemsTabLoading: Bool {
        guard authSession.userId != nil else { return true }
        if !hasCompletedInitialItemsFetch { return true }
        return false
    }

    private var displayedOutfitCount: Int {
        if isRedressFilterActive {
            return displayedPendingRedressSuggestions.count + outfits.count
        }
        return outfits.count
    }

    private var isOutfitsTabLoading: Bool {
        guard authSession.userId != nil else { return true }
        if !hasCompletedInitialOutfitsFetch { return true }
        return false
    }

    private var isRedressLoading: Bool {
        guard showsProfilePendingRedressSuggestions else { return false }
        if isLoadingRedressSuggestions { return true }
        if !hasCompletedInitialRedressFetch { return true }
        return false
    }

    private var showsTabActionsBar: Bool {
        // Closet / Wishlist / Profile: keep Filter/Sort/Search visible (disabled in selection mode).
        true
    }

    private var shouldHideTabBar: Bool {
        isInSelectionMode
            || isShowingDetailNavigation
            || isItemAddOnPath
            || isOutfitAddOnPath
            || isPackingOnPath
    }

    private var isShowingDetailNavigation: Bool {
        selectedItemURIForNavigation != nil
            || selectedOutfitURIForNavigation != nil
            || selectedPendingRedress != nil
    }

    /// Skip expensive grid refetches while a pushed screen is open (avoids navigation re-render loops).
    private var isPushNavigationActive: Bool {
        isShowingDetailNavigation
            || isItemAddOnPath
            || isOutfitAddOnPath
            || isPackingOnPath
            || packingNavigation != nil
    }

    var body: some View {
        withGridOwnedDetailDestinations(
            withGridOwnedPackingAndRedressDestinations(itemGridChrome)
        )
    }

    private var itemGridChrome: some View {
        itemGridWithAlerts
            .overlay(alignment: .top) {
                if showDeletionToast {
                    Text(deletionToastMessage)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.8))
                        .clipShape(Capsule())
                        .padding(.top, 10)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onChange(of: isShowingDetailNavigation) { _, isActive in
                isDetailNavigationActive = isActive
            }
            .onChange(of: queueCoordinator.addViewDismissTick) { _, _ in
                isItemAddOnPath = false
                handleItemAddViewDismiss()
            }
            .onChange(of: tabBarHideState.outfitAddDismissTick) { _, _ in
                isOutfitAddOnPath = false
            }
            .onChange(of: tabBarHideState.packingDismissTick) { _, _ in
                isPackingOnPath = false
            }
    }

    /// Closet owns packing on `NavigationPath`; Profile owns pending Redress on `ProfileRoute`.
    @ViewBuilder
    private func withGridOwnedPackingAndRedressDestinations<Content: View>(_ content: Content) -> some View {
        if onOpenPacking != nil, onOpenPendingRedress != nil {
            content
        } else if onOpenPacking != nil {
            content
                .navigationDestination(item: $selectedPendingRedress) { destination in
                    pendingRedressDestination(destination)
                }
        } else if onOpenPendingRedress != nil {
            content
                .navigationDestination(item: $packingNavigation) { _ in
                    localPackingDestination
                }
        } else {
            content
                .navigationDestination(item: $selectedPendingRedress) { destination in
                    pendingRedressDestination(destination)
                }
                .navigationDestination(item: $packingNavigation) { _ in
                    localPackingDestination
                }
        }
    }

    private var localPackingDestination: some View {
        ItemPackView(
            selectedWardrobe: selectedWardrobe,
            wardrobeType: wardrobeType,
            tabBarHideState: tabBarHideState
        )
        .onAppear { packingNavigation = nil }
    }

    private func pendingRedressDestination(_ destination: PendingRedressNavigationDestination) -> some View {
        PendingOutfitDetailView(
            recipientUserId: destination.recipientUserId,
            wardrobeId: destination.wardrobeId,
            suggestionSummary: destination.suggestionSummary,
            viewerRole: destination.viewerRole,
            onSuggestionResolved: {
                scheduleOutfitsRefresh(forceRedressRefresh: true)
            },
            backButtonTitle: showsProfilePendingRedressSuggestions
                ? (supabaseService.cachedUsername ?? "Profile")
                : nil
        )
    }

    /// Closet/Wishlist own item/outfit detail on `NavigationPath`. Profile still uses local `item:` + clear-on-appear.
    @ViewBuilder
    private func withGridOwnedDetailDestinations<Content: View>(_ content: Content) -> some View {
        if onOpenItemDetail != nil, onOpenOutfitDetail != nil {
            content
        } else {
            content
                .navigationDestination(item: $selectedItemURIForNavigation) { uriString in
                    Group {
                        if let item = managedItem(forURI: uriString) {
                            ItemDetailView(item: item, isReadOnly: false)
                                .id(item.objectID)
                                .onAppear { selectedItemURIForNavigation = nil }
                        } else {
                            EmptyView()
                                .onAppear { selectedItemURIForNavigation = nil }
                        }
                    }
                }
                .navigationDestination(item: $selectedOutfitURIForNavigation) { uriString in
                    Group {
                        if let outfit = managedOutfit(forURI: uriString) {
                            OutfitDetailView(
                                outfit: outfit,
                                isReadOnly: isReadOnly,
                                initialWardrobe: selectedWardrobe,
                                lockWardrobeSource: selectedWardrobe.isDefault != true
                            )
                                .id(outfit.objectID)
                                .onAppear { selectedOutfitURIForNavigation = nil }
                        } else {
                            EmptyView()
                                .onAppear { selectedOutfitURIForNavigation = nil }
                        }
                    }
                }
        }
    }

    private var usesProfileUnifiedScroll: Bool {
        showsProfilePendingRedressSuggestions
    }

    private var itemGridMainContent: some View {
        Group {
            if usesProfileUnifiedScroll {
                profileUnifiedScrollContent
            } else {
                closetWishlistMainContent
            }
        }
    }

    /// Closet / Wishlist: fixed chrome + page TabView with per-tab ScrollViews.
    private var closetWishlistMainContent: some View {
        VStack(spacing: 0) {
            profileOrStandardTabPickerRow
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
                .disabled(isInSelectionMode)

            if showsTabActionsBar {
                tabActionsBar
                    .disabled(isInSelectionMode)
            }

            TabView(selection: $selectedTab) {
                itemsTab.tag("Items")
                outfitsTab.tag("Outfits")
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    /// Profile: UIKit nested scroll — collapsing header, sticky chrome, paged tabs with
    /// independent UIScrollViews (Instagram-style coordination).
    private var profileUnifiedScrollContent: some View {
        ProfileNestedScrollContainer(
            selectedTab: $selectedTab,
            header: profileCollapsingHeader,
            sticky: profileStickyChrome,
            itemsPage: itemsTab,
            outfitsPage: outfitsTab,
            onRefresh: {
                await refreshProfileItemsAndOutfits()
            },
            snapsHeaderCollapse: true
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Pull-to-refresh: sync from cloud (when enabled), then reload local items/outfits (+ Redress).
    private func refreshProfileItemsAndOutfits() async {
        if appCapabilities.enablesCloudSync {
            try? await SyncService.shared.syncAllItems()
        }
        await MainActor.run {
            viewContext.refreshAllObjects()
            scheduleItemsFetch()
            scheduleOutfitsRefresh(forceRedressRefresh: true)
        }
        // Wait for scheduled reloads (outfits includes pending Redress) to finish.
        await itemFetchTask?.value
        await outfitRefreshTask?.value
    }

    @ViewBuilder
    private func closetPullToRefreshIfNeeded<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if usesProfileUnifiedScroll {
            // Profile nested scroll owns pull-to-refresh via `onRefresh`.
            content()
        } else {
            content()
                .refreshable {
                    await refreshProfileItemsAndOutfits()
                }
        }
    }

    @ViewBuilder
    private var profileStickyChrome: some View {
        VStack(spacing: 0) {
            profileStickyPrefix

            profileOrStandardTabPickerRow
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
                .disabled(isInSelectionMode)

            if showsTabActionsBar {
                tabActionsBar
                    .disabled(isInSelectionMode)
            }
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var profileOrStandardTabPickerRow: some View {
        profileOrStandardTabPicker
    }

    /// Profile and Closet/Wishlist: text Items / Outfits (with counts).
    @ViewBuilder
    private var profileOrStandardTabPicker: some View {
        Picker("", selection: $selectedTab) {
            Text("Items (\(closetItems.count))")
                .tag("Items")
            Text("Outfits (\(displayedOutfitCount))")
                .tag("Outfits")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var itemGridWithObservers: some View {
        Group {
            if showsProfilePendingRedressSuggestions {
                // Profile owns the nav toolbar + tab bar. Any `.toolbar` here (even
                // tabBar-only) competes with ProfileView and can wipe gear/edit/users.
                if isInSelectionMode {
                    itemGridObservedContent
                        .toolbar {
                            if isInSelectionMode && selectedTab == "Items" {
                                ToolbarItem(placement: .principal) {
                                    selectionModePrincipalToolbar
                                }
                            }
                        }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            selectionModeBottomChrome
                        }
                } else {
                    itemGridObservedContent
                }
            } else {
                itemGridObservedContent
                    .toolbar {
                        ToolbarItemGroup(placement: .navigationBarLeading) {
                            leadingToolbarContent()
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            trailingToolbarContent()
                        }
                        if isInSelectionMode && selectedTab == "Items" {
                            ToolbarItem(placement: .principal) {
                                selectionModePrincipalToolbar
                            }
                        }
                    }
                    .toolbar(tabBarHideState.shouldHideTabBar ? .hidden : .automatic, for: .tabBar)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if isInSelectionMode {
                            selectionModeBottomChrome
                        }
                    }
            }
        }
    }

    /// Lifecycle observers without navigation toolbar (Profile supplies nav bar items on `ProfileView`).
    private var itemGridObservedContent: some View {
        Group {
            if showsProfilePendingRedressSuggestions {
                itemGridMainContent
            } else {
                itemGridMainContent
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
            .onChange(of: shouldHideTabBar) { _, hide in
                tabBarHideState.shouldHideTabBar = hide
            }
            .onAppear {
                tabBarHideState.shouldHideTabBar = shouldHideTabBar
            }
            .onChange(of: selectedTab) { oldValue, newValue in
                if oldValue != newValue && isInSelectionMode {
                    isInSelectionMode = false
                    clearItemSelection()
                    clearOutfitSelection()
                }
                syncNavigationTitleReplacement()
                if oldValue != newValue {
                    isTabActionsBarVisible = true
                    if newValue != "Outfits", isRedressFilterActive {
                        isRedressFilterActive = false
                        scheduleOutfitsRefresh()
                    }
                    if isActionBarSearchActive {
                        isActionBarSearchFocused = true
                    }
                }
            }
            .onChange(of: showsTabActionsBar) { _, shows in
                if !shows {
                    dismissActionBarSearch(clearQueries: false)
                }
            }
            .onChange(of: isInSelectionMode) { _, enteringSelection in
                syncNavigationTitleReplacement()
                if enteringSelection {
                    dismissActionBarSearch(clearQueries: false)
                } else {
                    isTabActionsBarVisible = true
                }
            }
            .onChange(of: isActionBarSearchActive) { _, active in
                if active {
                    isTabActionsBarVisible = true
                }
            }
            .onChange(of: filterModel.searchQuery) { _, _ in
                scheduleDebouncedItemFetch()
            }
            .onChange(of: outfitFilterModel.searchQuery) { _, _ in
                scheduleDebouncedOutfitFetch()
            }
            .onAppear {
                syncNavigationTitleReplacement()
                scheduleItemsFetch()
                scheduleOutfitsRefresh()
            }
            .onChange(of: authSession.userId) { _, newUserId in
                guard newUserId != nil else { return }
                hasCompletedInitialItemsFetch = false
                hasCompletedInitialOutfitsFetch = false
                hasCompletedInitialRedressFetch = false
                scheduleItemsFetch()
                scheduleOutfitsRefresh()
            }
            .onChange(of: filterKey) {
                scheduleItemsFetch()
            }
            .onChange(of: filterModel.filterByWeight) {
                scheduleItemsFetch()
            }
            .onChange(of: outfitFilterKey) {
                scheduleOutfitsRefresh()
            }
            .onChange(of: selectedWardrobe.objectID) {
                dismissActionBarSearch(clearQueries: false)
                filterModel.clearAll()
                outfitFilterModel.clearAll()
                hasCompletedInitialRedressFetch = false
                profilePendingSuggestions = []
                pendingRedressOutfitIds = []
                isRedressFilterActive = false
                scheduleItemsFetch()
                scheduleOutfitsRefresh()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                if needsItemFetchRetry {
                    scheduleItemsFetch()
                }
                if needsOutfitFetchRetry {
                    scheduleOutfitsRefresh()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { notification in
                guard !isPushNavigationActive else { return }
                if let context = notification.object as? NSManagedObjectContext,
                   context === viewContext || context.parent === viewContext {
                    scheduleDebouncedContextSaveRefresh()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("Closet.ItemDeletionToast"))) { notification in
                if let message = notification.userInfo?["message"] as? String {
                    showToast(message)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("Closet.PendingRedressResolved"))) { _ in
                scheduleOutfitsRefresh(forceRedressRefresh: true)
            }
    }

    private var selectionModeBottomChrome: some View {
        VStack(spacing: 0) {
            if selectedTab == "Items" {
                selectionThumbnailsStrip(
                    selectedCount: selectedItems.count,
                    stripIDs: selectedItemStripIDs,
                    onDeselectAll: { clearItemSelection() }
                ) {
                    ForEach(selectedItemsForStrip, id: \.objectID) { item in
                        selectionThumbnailCell(item)
                            .id(item.objectID)
                            .zIndex(1)
                    }
                }
            } else if selectedTab == "Outfits" {
                selectionThumbnailsStrip(
                    selectedCount: selectedOutfits.count,
                    stripIDs: selectedOutfitStripIDs,
                    onDeselectAll: { clearOutfitSelection() }
                ) {
                    ForEach(selectedOutfitsForStrip, id: \.objectID) { outfit in
                        selectionOutfitThumbnailCell(outfit)
                            .id(outfit.objectID)
                            .zIndex(1)
                    }
                }
            }
            selectionModeBottomBar
        }
    }

    private var selectedItemsForStrip: [Item] {
        selectedItemStripIDs.compactMap { objectID in
            selectedItems.first { $0.objectID == objectID }
        }
    }

    private var selectedOutfitsForStrip: [Outfit] {
        selectedOutfitStripIDs.compactMap { objectID in
            selectedOutfits.first { $0.objectID == objectID }
        }
    }

    private func selectionThumbnailsStrip<ID: Hashable, Cells: View>(
        selectedCount: Int,
        stripIDs: [ID],
        onDeselectAll: @escaping () -> Void,
        @ViewBuilder cells: () -> Cells
    ) -> some View {
        let cellViews = cells()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(selectedCount) Selected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Button("Deselect All") {
                    onDeselectAll()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .disabled(selectedCount == 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .zIndex(0)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        cellViews
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
                .zIndex(1)
                .onChange(of: stripIDs) { _, ids in
                    guard let lastID = ids.last else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .trailing)
                    }
                }
            }
        }
        .background(.bar)
    }

    private func selectionThumbnailCell(_ item: Item) -> some View {
        ZStack(alignment: .topTrailing) {
            ItemView(
                item: item,
                usesFlexibleSizing: true,
                showsFavoriteOverlay: false,
                usesGridThumbnailOnly: true
            )
            .frame(width: 68, height: 68)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                deselectItemFromStrip(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.6))
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
            .zIndex(2)
            .accessibilityLabel("Deselect item")
        }
    }

    private func selectionOutfitThumbnailCell(_ outfit: Outfit) -> some View {
        ZStack(alignment: .topTrailing) {
            OutfitView(
                outfit: outfit,
                usesFlexibleSizing: true,
                showsFavoriteOverlay: false,
                showsRedressSuggesterAvatar: false
            )
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                removeOutfitFromSelection(outfit)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.6))
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
            .zIndex(2)
            .accessibilityLabel("Deselect outfit")
        }
    }

    private func deselectItemFromStrip(_ item: Item) {
        removeItemFromSelection(item)
    }

    private func addItemToSelection(_ item: Item) {
        guard !selectedItems.contains(item) else { return }
        selectedItems.insert(item)
        selectedItemStripIDs.append(item.objectID)
    }

    private func removeItemFromSelection(_ item: Item) {
        selectedItems.remove(item)
        selectedItemStripIDs.removeAll { $0 == item.objectID }
    }

    private func clearItemSelection() {
        selectedItems.removeAll()
        selectedItemStripIDs.removeAll()
    }

    private func setItemSelection(to items: [Item]) {
        selectedItems = Set(items)
        selectedItemStripIDs = items.map(\.objectID)
    }

    private func addOutfitToSelection(_ outfit: Outfit) {
        guard !selectedOutfits.contains(outfit) else { return }
        selectedOutfits.insert(outfit)
        selectedOutfitStripIDs.append(outfit.objectID)
    }

    private func removeOutfitFromSelection(_ outfit: Outfit) {
        selectedOutfits.remove(outfit)
        selectedOutfitStripIDs.removeAll { $0 == outfit.objectID }
    }

    private func clearOutfitSelection() {
        selectedOutfits.removeAll()
        selectedOutfitStripIDs.removeAll()
    }

    private func setOutfitSelection(to outfits: [Outfit]) {
        selectedOutfits = Set(outfits)
        selectedOutfitStripIDs = outfits.map(\.objectID)
    }

    private var selectionModeBottomBar: some View {
        HStack(spacing: 0) {
            if selectedTab == "Items" {
                selectionBottomBarButton(
                    title: "Category",
                    systemImage: "tshirt",
                    disabled: selectedItems.isEmpty
                ) {
                    showCategorySelectionSheet = true
                }
                selectionBottomBarButton(
                    title: "Color",
                    systemImage: "paintpalette",
                    disabled: selectedItems.isEmpty
                ) {
                    showColorSelectionSheet = true
                }
                selectionBottomBarButton(
                    title: "Tag",
                    systemImage: "tag",
                    disabled: selectedItems.isEmpty
                ) {
                    showTagSelectionSheet = true
                }
                selectionBottomBarButton(
                    title: "Favorite",
                    systemImage: selectedItemsFavoriteToolbarIcon,
                    disabled: selectedItems.isEmpty
                ) {
                    pendingFavoriteSelectionWillUnfavorite = selectedItemsAllFavorited
                    showFavoriteSelectionConfirmAlert = true
                }
            } else if selectedTab == "Outfits" {
                selectionBottomBarButton(
                    title: "Tag",
                    systemImage: "tag",
                    disabled: selectedOutfits.isEmpty
                ) {
                    showTagSelectionSheet = true
                }
                selectionBottomBarButton(
                    title: "Category",
                    systemImage: "tshirt",
                    disabled: selectedOutfits.isEmpty
                ) {
                    showOutfitCategorySelectionSheet = true
                }
                selectionBottomBarButton(
                    title: "Favorite",
                    systemImage: selectedOutfitsFavoriteToolbarIcon,
                    disabled: selectedOutfits.isEmpty
                ) {
                    pendingFavoriteSelectionWillUnfavorite = selectedOutfitsAllFavorited
                    showFavoriteSelectionConfirmAlert = true
                }
            }

            selectionBottomBarButton(
                title: "Delete",
                systemImage: "trash",
                disabled: isSelectionDeleteDisabled,
                tint: selectionDeleteColor
            ) {
                if selectedTab == "Items" {
                    showDeleteConfirmation = true
                } else {
                    showOutfitDeleteConfirmation = true
                }
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func selectionBottomBarButton(
        title: String,
        systemImage: String,
        disabled: Bool,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack {
                Image(systemName: systemImage)
                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(tint ?? Color.accentColor)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .frame(maxWidth: .infinity)
    }

    private func syncNavigationTitleReplacement() {
        isReplacingNavigationTitle = isInSelectionMode && selectedTab == "Items"
    }

    @ViewBuilder
    private var selectionModePrincipalToolbar: some View {
        Button {
            showWardrobeSelectionSheet = true
        } label: {
            HStack(spacing: 4) {
                Text("Manage")
                    .font(.headline)
                Image(systemName: "plus.rectangle.on.folder")
                    .font(.caption)
            }
        }
    }

    private var itemGridWithSheets: some View {
        itemGridWithObservers
            .sheet(isPresented: $isImagePickerPresented) {
                ImagePicker(
                    image: $pickedImage,
                    sourceType: $imagePickerSource,
                    allowsEditing: true
                ) { image in
                    if let image = image {
                        createNewItem(with: image, in: selectedWardrobe)
                    }
                    isImagePickerPresented = false
                }
            }
            .sheet(isPresented: $showMultiImagePicker) {
                MultiImagePicker(selectedImages: $queuedImages) {
                    showMultiImagePicker = false

                    if !queuedImages.isEmpty {
                        queueCoordinator.loadQueue(queuedImages)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showCropperForQueue = true
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showCropperForQueue) {
                if let imageToCrop = queueCoordinator.currentImage {
                    NavigationView {
                        ImageCropperView(
                            originalImage: imageToCrop,
                            onCrop: { croppedImage in
                                queueCoordinator.storeCroppedImage(croppedImage)
                                showCropperForQueue = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    openAddItem(queued: true)
                                }
                            },
                            isEditing: false,
                            onCancel: {
                                if queueCoordinator.isQueueActive {
                                    showCropperCancelConfirmation = true
                                } else {
                                    showCropperForQueue = false
                                }
                            }
                        )
                        .navigationBarTitleDisplayMode(.inline)
                    }
                    .alert("Discard this item?", isPresented: $showCropperCancelConfirmation) {
                        Button("Discard", role: .destructive) {
                            handleCropperCancel()
                        }
                        Button("Keep", role: .cancel) {}
                    } message: {
                        if queueCoordinator.hasMore {
                            Text("This image will be skipped and you'll move to the next image in the queue.")
                        } else {
                            Text("This image will be discarded.")
                        }
                    }
                }
            }
            .sheet(isPresented: $showWardrobeSelectionSheet) {
                wardrobeSelectionSheet()
            }
            .sheet(isPresented: $showTagSelectionSheet, onDismiss: {
                tagSelectionSearchText = ""
            }) {
                tagSelectionSheet()
            }
            .sheet(isPresented: $showOutfitCategorySelectionSheet) {
                outfitCategorySelectionSheet()
            }
            .sheet(isPresented: $showColorSelectionSheet) {
                colorSelectionSheet()
            }
            .sheet(isPresented: $showAddFromClosetSheet) {
                AddItemsFromDefaultWardrobeView(
                    wardrobe: selectedWardrobe,
                    onCompleted: { addedCount in
                        let dest = selectedWardrobe.name ?? "this wardrobe"
                        let sourceLabel = (selectedWardrobe.type ?? "closet").lowercased() == "wishlist" ? "wishlist" : "closet"
                        showToast("Added \(addedCount) item\(addedCount == 1 ? "" : "s") from your \(sourceLabel) to \"\(dest)\".")
                    }
                )
            }
            .sheet(isPresented: $showCategorySelectionSheet) {
                categorySelectionSheet()
            }
    }

    private var itemGridWithAlerts: some View {
        itemGridWithSheets
            .alert(pendingFavoriteSelectionWillUnfavorite ? "Remove from Favorites?" : "Add to Favorites?", isPresented: $showFavoriteSelectionConfirmAlert) {
                Button(pendingFavoriteSelectionWillUnfavorite ? "Remove" : "Add", role: pendingFavoriteSelectionWillUnfavorite ? .destructive : nil) {
                    let favorite = !pendingFavoriteSelectionWillUnfavorite
                    let message: String?
                    if selectedTab == "Items" {
                        message = applyFavoriteToSelectedItems(favorite: favorite)
                    } else {
                        message = applyFavoriteToSelectedOutfits(favorite: favorite)
                    }
                    if let message {
                        completeBulkSelectionAction(toast: message)
                    }
                    pendingFavoriteSelectionWillUnfavorite = false
                }
                Button("Cancel", role: .cancel) {
                    pendingFavoriteSelectionWillUnfavorite = false
                }
            } message: {
                if selectedTab == "Items" {
                    let count = selectedItems.count
                    let itemPhrase = "\(count) selected item\(count == 1 ? "" : "s")"
                    Text(pendingFavoriteSelectionWillUnfavorite
                         ? "Remove \(itemPhrase) from favorites?"
                         : "Add \(itemPhrase) to favorites?")
                } else {
                    let count = selectedOutfits.count
                    let outfitPhrase = "\(count) outfit\(count == 1 ? "" : "s")"
                    Text(pendingFavoriteSelectionWillUnfavorite
                         ? "Remove \(outfitPhrase) from favorites?"
                         : "Add \(outfitPhrase) to favorites?")
                }
            }
            .alert("Delete Items", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteSelectedItems()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteSelectedItemsAlertMessage)
            }
            .alert("Delete Outfits", isPresented: $showOutfitDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteSelectedOutfits()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete \(selectedOutfits.count) outfit\(selectedOutfits.count == 1 ? "" : "s")? This action cannot be undone.")
            }
            .alert(pendingOutfitCategoryWillRemove ? "Remove Category?" : "Add Category?", isPresented: $showOutfitCategorySelectionConfirmAlert) {
                Button(pendingOutfitCategoryWillRemove ? "Remove" : "Apply", role: pendingOutfitCategoryWillRemove ? .destructive : nil) {
                    let category = pendingOutfitCategoryWillRemove ? nil : pendingOutfitCategoryTarget
                    if let message = applyCategoryToSelectedOutfits(category: category) {
                        completeBulkSelectionAction(toast: message)
                    }
                    pendingOutfitCategoryTarget = nil
                    pendingOutfitCategoryWillRemove = false
                }
                Button("Cancel", role: .cancel) {
                    pendingOutfitCategoryTarget = nil
                    pendingOutfitCategoryWillRemove = false
                }
            } message: {
                let name = pendingOutfitCategoryTarget?.name ?? "category"
                Text(pendingOutfitCategoryWillRemove
                     ? "Remove category “\(name)” from \(selectedOutfits.count) selected outfit(s)?"
                     : "Set category “\(name)” on \(selectedOutfits.count) selected outfit(s)?")
            }
            .alert(pendingWardrobeSelectionWillRemove ? "Remove from Wardrobe?" : "Add to Wardrobe?", isPresented: $showWardrobeSelectionConfirmAlert) {
                Button(pendingWardrobeSelectionWillRemove ? "Remove" : "Add", role: pendingWardrobeSelectionWillRemove ? .destructive : nil) {
                    guard let wardrobe = pendingWardrobeSelectionTarget else { return }
                    let message: String?
                    if pendingWardrobeSelectionWillRemove {
                        message = removeSelectedItemsFromWardrobe(wardrobe)
                    } else {
                        message = addSelectedItemsToWardrobe(wardrobe)
                    }
                    showWardrobeSelectionSheet = false
                    pendingWardrobeSelectionTarget = nil
                    pendingWardrobeSelectionWillRemove = false
                    if let message {
                        showToast(message)
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingWardrobeSelectionTarget = nil
                    pendingWardrobeSelectionWillRemove = false
                }
            } message: {
                let name = pendingWardrobeSelectionTarget?.name ?? "this wardrobe"
                Text(pendingWardrobeSelectionWillRemove
                     ? "Remove \(selectedItems.count) selected item\(selectedItems.count == 1 ? "" : "s") from “\(name)”?"
                     : "Add \(selectedItems.count) selected item\(selectedItems.count == 1 ? "" : "s") to “\(name)”?")
            }
    }

    // MARK: - Core Data fetch

    /// One in-flight items fetch; bumps generation so stale results are dropped.
    private func scheduleItemsFetch() {
        itemFetchGeneration += 1
        let generation = itemFetchGeneration
        itemFetchTask?.cancel()
        itemFetchTask = Task { @MainActor in
            guard !Task.isCancelled, generation == itemFetchGeneration else { return }
            fetchItems(generation: generation)
        }
    }

    /// One in-flight outfits refresh (local fetch + pending Redress).
    private func scheduleOutfitsRefresh(forceRedressRefresh: Bool = false) {
        outfitRefreshGeneration += 1
        let generation = outfitRefreshGeneration
        outfitRefreshTask?.cancel()
        outfitRefreshTask = Task { @MainActor in
            guard !Task.isCancelled, generation == outfitRefreshGeneration else { return }
            await performOutfitsRefresh(
                generation: generation,
                forceRedressRefresh: forceRedressRefresh
            )
        }
    }

    /// Coalesce rapid viewContext saves into a single items+outfits reload.
    private func scheduleDebouncedContextSaveRefresh() {
        contextSaveDebounceTask?.cancel()
        contextSaveDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.contextSaveDebounceNanos)
            guard !Task.isCancelled else { return }
            scheduleItemsFetch()
            scheduleOutfitsRefresh()
        }
    }

    private func scheduleDebouncedItemFetch() {
        itemSearchDebounceTask?.cancel()
        itemSearchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.searchDebounceNanos)
            guard !Task.isCancelled else { return }
            scheduleItemsFetch()
        }
    }

    private func scheduleDebouncedOutfitFetch() {
        outfitSearchDebounceTask?.cancel()
        outfitSearchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.searchDebounceNanos)
            guard !Task.isCancelled else { return }
            scheduleOutfitsRefresh()
        }
    }

    @MainActor
    private func performOutfitsRefresh(generation: Int, forceRedressRefresh: Bool) async {
        async let redressLoad: Void = loadPendingRedressSuggestionsIfNeeded(
            forceRefresh: forceRedressRefresh,
            applyFetchGeneration: generation
        )
        fetchOutfits(generation: generation)
        await redressLoad
        guard generation == outfitRefreshGeneration else { return }
        await hydrateAcceptedRedressSuggesterProfilesIfNeeded()
    }

    func fetchItems(generation: Int? = nil) {
        // Require authentication - get userId
        guard let userId = authSession.userId?.uuidString else {
            needsItemFetchRetry = true
            return
        }
        
        let request = NSFetchRequest<Item>(entityName: "Item")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Item.createdAt, ascending: filterModel.sortOrder.sortAscending)]
        
        // Build predicate from filterModel, but exclude wardrobe filter since we handle it separately below
        var subpredicates: [NSPredicate] = []
        
        // Add userId filter (CRITICAL: only show current user's items)
        let userIdPredicate = NSPredicate(format: "userId == %@", userId)
        subpredicates.append(userIdPredicate)

        if let filter = makePredicate(for: filterModel, context: viewContext) {
            subpredicates.append(filter)
        }
        
        subpredicates.append(wardrobeScopePredicate())

        if let searchPredicate = ItemFilterModel.itemSearchPredicate(query: filterModel.searchQuery) {
            subpredicates.append(searchPredicate)
        }
        
        // Exclude drafts from item listings
        let draftPredicate = NSPredicate(format: "isDraft != YES")
        subpredicates.append(draftPredicate)
        
        // Exclude soft-deleted items
        let softDeleteFilter = NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        subpredicates.append(softDeleteFilter)
        
        // Combine all predicates
        let finalPredicate: NSPredicate
        if subpredicates.count == 1 {
            finalPredicate = subpredicates.first!
        } else {
            finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        }
        request.predicate = finalPredicate
        
        // Debug: Log predicate if weight filter is active
        if filterModel.filterByWeight {
            print("🔍 Final predicate: \(finalPredicate)")
        }
        
        do {
            let results = try viewContext.fetch(request)
            
            // Debug: Log results if weight filter is active
            if filterModel.filterByWeight {
                let repository = UserProfileRepository(context: viewContext)
                let userWeightKg = repository.getWeightKg()
                print("🔍 Fetched \(results.count) items with weight filter")
                // Sample a few items to check their weights
                for (index, item) in results.prefix(5).enumerated() {
                    if let weight = item.primitiveValue(forKey: "weight") as? Double {
                        print("🔍 Item \(index + 1): weight = \(String(format: "%.2f", weight)) kg (>= \(String(format: "%.2f", userWeightKg))? \(weight >= userWeightKg))")
                    } else {
                        print("🔍 Item \(index + 1): weight = nil (no limit)")
                    }
                }
            }

            if let generation, generation != itemFetchGeneration { return }
            closetItems = results
            hasCompletedInitialItemsFetch = true
            needsItemFetchRetry = false
        } catch {
            print("❌ Failed to fetch items: \(error)")
            if let nsError = error as NSError? {
                print("❌ Error details: \(nsError.userInfo)")
            }
            if let generation, generation != itemFetchGeneration { return }
            // Keep prior results; retry when the scene becomes active.
            needsItemFetchRetry = true
        }
    }

    private func wardrobeScopePredicate() -> NSPredicate {
        ItemFilterModel.wardrobeMembershipPredicate(
            viewingWardrobe: selectedWardrobe,
            wardrobeType: wardrobeType,
            filterModel: filterModel
        )
    }

    @MainActor
    private func hydrateAcceptedRedressSuggesterProfilesIfNeeded() async {
        guard appCapabilities.enablesFriendsAndSharing else { return }
        let needsHydration: [Outfit] = outfits.compactMap { outfit -> Outfit? in
            guard outfit.isRedressOutfit, outfit.id != nil else { return nil }
            let missingUserId = outfit.redressSuggesterUserId == nil
            let missingAvatar = (outfit.redressSuggesterAvatarUrl ?? "").isEmpty
            let missingUsername = (outfit.redressSuggesterUsername ?? "").isEmpty
            return (missingUserId || missingAvatar || missingUsername) ? outfit : nil
        }
        guard !needsHydration.isEmpty else { return }

        var changed = false
        for outfit in needsHydration.prefix(25) {
            guard let outfitId = outfit.id,
                  let context = await supabaseService.fetchOutfitRedressSuggestionContext(suggestionId: outfitId)
            else { continue }
            if outfit.persistRedressHistoryIfNeeded(from: context) {
                changed = true
            }
        }
        if changed {
            try? viewContext.save()
        }
    }

    @MainActor
    private func loadPendingRedressSuggestionsIfNeeded(
        forceRefresh: Bool = false,
        applyFetchGeneration: Int? = nil
    ) async {
        guard appCapabilities.enablesFriendsAndSharing,
              let wardrobeId = selectedWardrobe.id else {
            pendingRedressOutfitIds = []
            profilePendingSuggestions = []
            hasCompletedInitialRedressFetch = true
            isLoadingRedressSuggestions = false
            return
        }

        // Avoid stacking duplicate in-flight loads unless a refresh was requested.
        if isLoadingRedressSuggestions, !forceRefresh { return }

        isLoadingRedressSuggestions = true
        defer { isLoadingRedressSuggestions = false }

        do {
            let suggestions = try await supabaseService.fetchRecipientOutfitSuggestions(
                wardrobeId: wardrobeId,
                forceRefresh: forceRefresh
            )
            // Pending suggestion IDs match materialized outfit IDs when previewed.
            pendingRedressOutfitIds = Set(suggestions.map(\.id))
            profilePendingSuggestions = showsProfilePendingRedressSuggestions ? suggestions : []
            hasCompletedInitialRedressFetch = true
            fetchOutfits(generation: applyFetchGeneration)
        } catch {
            print("⚠️ Failed to load pending Redress suggestions: \(error.localizedDescription)")
            // Keep prior pending IDs / suggestions; still refresh local outfits for this generation.
            hasCompletedInitialRedressFetch = true
            fetchOutfits(generation: applyFetchGeneration)
        }
    }

    /// Pending Redress suggestions for the active filter, respecting search / attribute filters / sort.
    private var displayedPendingRedressSuggestions: [VisibleOutfitSuggestion] {
        guard isRedressFilterActive, showsProfilePendingRedressSuggestions else { return [] }
        // Attribute filters only apply to saved outfits; pending suggestions have no category/tags.
        if outfitFilterModel.selectedCategory != nil
            || !outfitFilterModel.selectedTags.isEmpty
            || outfitFilterModel.filterTagsNotSet
            || outfitFilterModel.favoritesOnly {
            return []
        }
        var list = profilePendingSuggestions
        let query = outfitFilterModel.trimmedSearchQuery
        if !query.isEmpty {
            list = list.filter { suggestion in
                (suggestion.name ?? "").localizedCaseInsensitiveContains(query)
                    || (suggestion.suggesterUsername ?? "").localizedCaseInsensitiveContains(query)
                    || (suggestion.suggesterDisplayName ?? "").localizedCaseInsensitiveContains(query)
            }
        }
        // RPC returns newest-first; reverse for oldest-first.
        if outfitFilterModel.sortOrder == .oldestFirst {
            list.reverse()
        }
        return list
    }

    func fetchOutfits(generation: Int? = nil) {
        // Require authentication - get userId
        guard let userId = authSession.userId?.uuidString else {
            needsOutfitFetchRetry = true
            return
        }
        
        let request = NSFetchRequest<Outfit>(entityName: "Outfit")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Outfit.createdAt, ascending: outfitFilterModel.sortOrder.sortAscending)]
        
        // Build predicate from outfit filter model
        let filterPredicate = makeOutfitPredicate(for: outfitFilterModel)
        
        // Base predicate: exclude drafts and soft-deleted items, filter by userId
        let draftPredicate = NSPredicate(format: "isDraft != YES")
        let softDeleteFilter = NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        let userIdPredicate = NSPredicate(format: "userId == %@", userId)
        
        // Combine predicates
        var outfitSubpredicates = [draftPredicate, softDeleteFilter, userIdPredicate]
        if let filter = filterPredicate {
            outfitSubpredicates.append(filter)
        }
        if let searchPredicate = OutfitFilterModel.outfitSearchPredicate(query: outfitFilterModel.searchQuery) {
            outfitSubpredicates.append(searchPredicate)
        }
        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: outfitSubpredicates)
        
        request.predicate = finalPredicate

        do {
            let allOutfits = try viewContext.fetch(request)
            let filtered = allOutfits.filter { outfit in
                guard outfit.isVisible(in: selectedWardrobe) else { return false }
                if isRedressFilterActive {
                    // Accepted Redress only (pending shown separately from remote suggestions).
                    guard outfit.isRedressOutfit else { return false }
                    if let outfitId = outfit.id, pendingRedressOutfitIds.contains(outfitId) {
                        return false
                    }
                    return true
                }
                // Default grid: own outfits + accepted Redress; hide still-pending suggestions.
                if let outfitId = outfit.id, pendingRedressOutfitIds.contains(outfitId) {
                    return false
                }
                return true
            }
            if let generation, generation != outfitRefreshGeneration { return }
            outfits = filtered
            hasCompletedInitialOutfitsFetch = true
            needsOutfitFetchRetry = false
        } catch {
            print("Failed to fetch outfits: \(error)")
            if let generation, generation != outfitRefreshGeneration { return }
            // Keep prior results; retry when the scene becomes active.
            needsOutfitFetchRetry = true
        }
    }


    // MARK: - Create New Item
    private func createNewItem(with image: UIImage, in wardrobe: Wardrobe) {
        let item = Item(context: viewContext)
        item.id = UUID()
        let now = Date()
        item.timestamp = now
        item.createdAt = now
        item.updatedAt = now // Set updatedAt for sync tracking
        
        // Process and compress image
        if let imageData = image.processForStorage() {
            let photo = Photo(context: viewContext)
            PhotoContentBounds.assignImage(UIImage(data: imageData) ?? image, to: photo, data: imageData)
            photo.thumbnailData = image.generateThumbnail()
            photo.isPrimary = true
            photo.id = UUID()
            photo.type = "front"
            photo.item = item
        }

        wardrobe.addToItems(item)   // <-- attach to the correct wardrobe
        ItemLifecycleDates.applyOnSave(for: item, at: now)

        do {
            try viewContext.save()
            print("✅ New item saved in \(wardrobe.name ?? "unknown wardrobe")")
            // Refresh items after adding new one
            scheduleItemsFetch()
            
            // Trigger automatic sync for the new item
            SyncService.shared.syncItemIfNeeded(item)
        } catch {
            print("❌ Failed to save new item: \(error.localizedDescription)")
        }
    }
    
    private var closetContentLoadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: usesProfileUnifiedScroll ? 240 : 0)
    }

    private var itemsTab: some View {
        closetPullToRefreshIfNeeded {
            ScrollView(showsIndicators: false) {
                if isItemsTabLoading {
                    closetContentLoadingView
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 240)
                } else if closetItems.isEmpty {
                    Group {
                        if hasActiveItemFiltersOrSearch {
                            EmptyOutfitStateView(
                                title: "No matching items",
                                message: "Try adjusting your filters or search.",
                                systemImage: "line.3.horizontal.decrease.circle"
                            )
                        } else {
                            EmptyItemStateView(wardrobe: selectedWardrobe)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 240)
                } else {
                    itemsLazyGrid
                }
            }
        }
    }

    private var hasActiveItemFiltersOrSearch: Bool {
        filterModel.activeFilterCount > 0 || !filterModel.trimmedSearchQuery.isEmpty
    }

    private var itemsLazyGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 2) {
            ForEach(closetItems, id: \.objectID) { item in
                ItemView(item: item, showsFavoriteOverlay: !isReadOnly, usesGridThumbnailOnly: true)
                    .overlay(
                        Group {
                            if isInSelectionMode && selectedItems.contains(item) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.35))
                            }
                        }
                    )
                    .overlay(
                        Group {
                            if isInSelectionMode && selectedItems.contains(item) {
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Image(systemName: "checkmark.circle")
                                            .foregroundColor(.white)
                                            .background(
                                                Circle()
                                                    .fill(Color.blue)
                                                    .padding(2)
                                            )
                                            .font(.system(size: 22))
                                            .shadow(radius: 1)
                                            .padding(8)
                                    }
                                }
                            }
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        print("📱 Tap gesture detected on item: \(item.id?.uuidString ?? "no-id")")
                        handleTap(for: item)
                    }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        handleLongPress(for: item)
                    }
            }
        }
        .padding(.top, 2)
    }
    
    // MARK: - Gesture Handlers
    
    private func handleTap(for item: Item) {
        print("📱 handleTap called for item: \(item.id?.uuidString ?? "no-id"), isInSelectionMode: \(isInSelectionMode)")
        
        if isInSelectionMode {
            // Toggle selection
            if selectedItems.contains(item) {
                removeItemFromSelection(item)
                print("📱 Item deselected. Total selected: \(selectedItems.count)")
            } else {
                addItemToSelection(item)
                print("📱 Item selected. Total selected: \(selectedItems.count)")
            }
        } else {
            // Navigate to detail view
            if isReadOnly {
                openProfileReadOnlyItemDetail(item)
            } else {
                print("📱 Navigating to ItemDetailView for item: \(item.id?.uuidString ?? "no-id")")
                let uri = item.objectID.uriRepresentation().absoluteString
                if let onOpenItemDetail {
                    onOpenItemDetail(uri)
                } else {
                    selectedItemURIForNavigation = uri
                }
            }
        }
    }
    
    private func handleLongPress(for item: Item) {
        guard !isReadOnly else { return }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Enter selection mode and select this item
        if !isInSelectionMode {
            isInSelectionMode = true
        }
        
        addItemToSelection(item)
    }
    
    // MARK: - Outfit Gesture Handlers

    private func managedItem(forURI uriString: String) -> Item? {
        guard let url = URL(string: uriString),
              let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
              let item = try? viewContext.existingObject(with: objectID) as? Item,
              item.isSoftDeleted != true else {
            return nil
        }
        return item
    }

    private func managedOutfit(forURI uriString: String) -> Outfit? {
        guard let url = URL(string: uriString),
              let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
              let outfit = try? viewContext.existingObject(with: objectID) as? Outfit,
              outfit.isSoftDeleted != true else {
            return nil
        }
        return outfit
    }

    private func openProfileReadOnlyItemDetail(_ item: Item) {
        guard let ownerUserId = authSession.userId,
              let wardrobeId = selectedWardrobe.id,
              let itemId = item.id else { return }
        let photos = Array((item.photos as? Set<Photo>) ?? [])
        // Prefer typed front (same as ItemDetailView.getImage), then legacy primary, then any.
        let frontPhoto =
            photos.first(where: { ($0.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "front" })
            ?? photos.first(where: {
                $0.isPrimary && ($0.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
            ?? photos.first(where: { $0.isPrimary })
            ?? photos.first
        let type = wardrobeType.lowercased() == "wishlist" ? "wishlist" : "closet"
        tabBarHideState.shouldHideTabBar = true
        onOpenProfileReadOnlyItem?(
            ProfileReadOnlyItemDestination(
                ownerUserId: ownerUserId,
                wardrobeId: wardrobeId,
                item: VisibleWardrobeItem(
                    id: itemId,
                    name: item.name,
                    thumbnailUrl: frontPhoto?.thumbnailUrl ?? frontPhoto?.imageUrl,
                    imageUrl: frontPhoto?.imageUrl,
                    createdAt: item.createdAt ?? item.timestamp ?? item.purchasedAt ?? item.wishedAt
                ),
                wardrobeType: type
            )
        )
    }

    private func handleOutfitTap(for outfit: Outfit) {
        if isInSelectionMode {
            if selectedOutfits.contains(outfit) {
                removeOutfitFromSelection(outfit)
            } else {
                addOutfitToSelection(outfit)
            }
        } else {
            if isReadOnly {
                tabBarHideState.shouldHideTabBar = true
            }
            let uri = outfit.objectID.uriRepresentation().absoluteString
            if let onOpenOutfitDetail {
                onOpenOutfitDetail(uri)
            } else {
                selectedOutfitURIForNavigation = uri
            }
        }
    }
    
    private func handleOutfitLongPress(for outfit: Outfit) {
        guard !isReadOnly else { return }
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Enter selection mode and select this outfit
        if !isInSelectionMode {
            isInSelectionMode = true
        }
        
        addOutfitToSelection(outfit)
    }
    
    @ViewBuilder
    private var tabActionsBar: some View {
        if selectedTab == "Items" {
            ItemFilterSortSearchBar(
                sortOrder: $filterModel.sortOrder,
                searchQuery: $filterModel.searchQuery,
                isSearchActive: $isActionBarSearchActive,
                isSearchFocused: $isActionBarSearchFocused,
                onFilter: { onOpenItemFilter() },
                onDismissSearch: { dismissActionBarSearch(clearQueries: true) },
                onPack: showsPackAction ? {
                    openPacking()
                } : nil,
                activeFilterCount: filterModel.activeFilterCount,
                barHeight: Self.tabActionsBarHeight
            )
        } else if selectedTab == "Outfits" {
            ItemFilterSortSearchBar(
                sortOrder: $outfitFilterModel.sortOrder,
                searchQuery: $outfitFilterModel.searchQuery,
                isSearchActive: $isActionBarSearchActive,
                isSearchFocused: $isActionBarSearchFocused,
                onFilter: { onOpenOutfitFilter() },
                onDismissSearch: { dismissActionBarSearch(clearQueries: true) },
                onRedress: showsRedressFilterAction
                    ? {
                        isRedressFilterActive.toggle()
                        scheduleOutfitsRefresh(forceRedressRefresh: isRedressFilterActive)
                    }
                    : nil,
                isRedressFilterActive: isRedressFilterActive,
                activeFilterCount: outfitFilterModel.activeFilterCount,
                searchPlaceholder: "Name, category, tag",
                barHeight: Self.tabActionsBarHeight
            )
        }
    }

    private var showsPackAction: Bool {
        !isReadOnly && wardrobeType.lowercased() != "wishlist"
    }

    /// Closet + Profile Closet outfits: Redress filter chip (not Wishlist).
    /// Shown even when the outfits list is empty; Profile’s grid is read-only but still includes Redress.
    private var showsRedressFilterAction: Bool {
        guard appCapabilities.enablesFriendsAndSharing else { return false }
        guard wardrobeType.lowercased() != "wishlist" else { return false }
        if showsProfilePendingRedressSuggestions { return true }
        return !isReadOnly
    }

    private func dismissActionBarSearch(clearQueries: Bool) {
        itemSearchDebounceTask?.cancel()
        outfitSearchDebounceTask?.cancel()
        if clearQueries {
            filterModel.searchQuery = ""
            outfitFilterModel.searchQuery = ""
        }
        isActionBarSearchActive = false
        isActionBarSearchFocused = false
    }

    // MARK: - Toolbar Content
    
    @ViewBuilder
    private func leadingToolbarContent() -> some View {
        if isInSelectionMode {
            if selectedTab == "Items" {
                itemsSelectionModeLeadingToolbar()
            } else if selectedTab == "Outfits" {
                outfitsSelectionModeLeadingToolbar()
            }
        } else {
            nonSelectionModeLeadingToolbar()
        }
    }
    
    @ViewBuilder
    private func itemsSelectionModeLeadingToolbar() -> some View {
        // Select all button
        let allSelected = !closetItems.isEmpty && selectedItems.count == closetItems.count
        Button {
            if allSelected {
                clearItemSelection()
            } else {
                setItemSelection(to: closetItems)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                Text("All")
            }
        }
    }
    
    @ViewBuilder
    private func outfitsSelectionModeLeadingToolbar() -> some View {
        // Select all button
        let allSelected = !outfits.isEmpty && selectedOutfits.count == outfits.count
        Button {
            if allSelected {
                clearOutfitSelection()
            } else {
                setOutfitSelection(to: outfits)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                Text("All")
            }
        }
    }
    
    @ViewBuilder
    private func nonSelectionModeLeadingToolbar() -> some View {
        if !isReadOnly {
            if appCapabilities.enablesCloudSync {
                wardrobeVisibilityToolbarMenu
            }
        }
    }
    
    @ViewBuilder
    private func trailingToolbarContent() -> some View {
        if isInSelectionMode {
            selectionModeTrailingToolbar()
        } else {
            nonSelectionModeTrailingToolbar()
        }
    }
    
    @ViewBuilder
    private func selectionModeTrailingToolbar() -> some View {
        let hasSelection =
            (selectedTab == "Items" && !selectedItems.isEmpty)
            || (selectedTab == "Outfits" && !selectedOutfits.isEmpty)
        Button(hasSelection ? "Done" : "Cancel") {
            isInSelectionMode = false
            if selectedTab == "Items" {
                clearItemSelection()
            } else {
                clearOutfitSelection()
            }
        }
    }
    
    @ViewBuilder
    private func nonSelectionModeTrailingToolbar() -> some View {
        if isReadOnly {
            EmptyView()
        } else {
            nonSelectionModeAddToolbarButton
        }
    }

    private var wardrobeVisibilityToolbarMenu: some View {
        Menu {
            ForEach(WardrobeVisibility.allCases) { option in
                Button {
                    updateSelectedWardrobeVisibility(option)
                } label: {
                    Label(option.menuLabel, systemImage: option.iconName)
                }
            }
        } label: {
            Image(systemName: selectedWardrobe.wardrobeVisibility.iconName)
        }
        .id(wardrobeVisibilityRevision)
        .accessibilityLabel("Wardrobe visibility")
    }

    private func updateSelectedWardrobeVisibility(_ visibility: WardrobeVisibility) {
        WardrobeVisibilityPersistence.apply(
            visibility,
            to: selectedWardrobe,
            userId: authSession.userId?.uuidString
        )
        WardrobeVisibilityPersistence.saveAndSync(selectedWardrobe, in: viewContext)
        wardrobeVisibilityRevision += 1
    }

    @ViewBuilder
    private var nonSelectionModeAddToolbarButton: some View {
        if selectedTab == "Items" {
                if selectedWardrobe.isDefault == true {
                    Button {
                        openAddItem(queued: false)
                    } label: {
                        Image(systemName: "plus")
                    }
                } else {
                    Menu {
                        Button {
                            showAddFromClosetSheet = true
                        } label: {
                            let isWishlist = wardrobeType.lowercased() == "wishlist"
                            Label(
                                isWishlist ? "Add from Wishlist" : "Add from Closet",
                                systemImage: isWishlist ? "heart" : "hanger"
                            )
                        }
                        Button {
                            openAddItem(queued: false)
                        } label: {
                            Label("Add Item", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            } else {
                Button {
                    openAddOutfit()
                } label: {
                    Image(systemName: "plus")
                }
            }
    }
    
    // MARK: - Cropper Cancel Handler
    
    private func handleCropperCancel() {
        // Skip current image and move to next if available
        if queueCoordinator.isQueueActive {
            if queueCoordinator.hasMore {
                print("📸 Skipping current image, moving to next in queue")
                queueCoordinator.moveToNext()
                
                // Show cropper for next image
                if let nextImage = queueCoordinator.currentImage {
                    showCropperForQueue = false
                    // Small delay to ensure clean transition
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showCropperForQueue = true
                    }
                } else {
                    // No more images after skipping
                    print("📸 No more images after skipping, clearing queue")
                    queueCoordinator.clear()
                    showCropperForQueue = false
                }
            } else {
                // This was the last image, just clear and dismiss
                print("📸 Last image discarded, clearing queue")
                queueCoordinator.clear()
                showCropperForQueue = false
            }
        } else {
            // Queue not active, just dismiss
            showCropperForQueue = false
        }
    }
    
    private func openAddItem(queued: Bool) {
        tabBarHideState.shouldHideTabBar = true
        isItemAddOnPath = true
        onOpenAddItem?(queued)
    }

    private func openAddOutfit() {
        tabBarHideState.shouldHideTabBar = true
        isOutfitAddOnPath = true
        onOpenAddOutfit?(UUID())
    }

    // MARK: - ItemAddView Dismiss Handler
    
    private func handleItemAddViewDismiss() {
        // Check if there's a current image available
        if queueCoordinator.isQueueActive {
            // If hasMore is false AND we have a cropped image, we just processed the last image
            // (currentCroppedImage is set when we crop, and cleared when we moveToNext)
            if !queueCoordinator.hasMore && queueCoordinator.currentCroppedImage != nil {
                print("📸 ItemAddView dismissed, last image processed (hasMore=false, croppedImage exists), clearing queue")
                queuedImages.removeAll()
                queueCoordinator.clear()
                return
            }
            
            // If hasMore is true, we moved to the next image, so show cropper for it
            // OR if hasMore is false but no croppedImage, we're on the last image that hasn't been cropped yet
            if let currentImage = queueCoordinator.currentImage {
                print("📸 ItemAddView dismissed, showing cropper for image at index \(queueCoordinator.currentIndex), hasMore: \(queueCoordinator.hasMore)")
                
                // Small delay to ensure clean transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // Double-check that we still have a current image (queue might have been cleared)
                    if queueCoordinator.isQueueActive, let _ = queueCoordinator.currentImage {
                        showCropperForQueue = true
                    }
                }
            } else {
                // No current image available - we've processed all images, clean up
                print("📸 ItemAddView dismissed, no current image available, clearing queue")
                queuedImages.removeAll()
                queueCoordinator.clear()
            }
        } else {
            // Queue not active, clean up
            print("📸 ItemAddView dismissed, queue not active")
            queuedImages.removeAll()
        }
    }
    
    // MARK: - Wardrobe Selection Sheet
    
    @ViewBuilder
    private func wardrobeSelectionSheet() -> some View {
        let wardrobes = fetchAllWardrobes()
        
        return NavigationView {
            List {
                ForEach(wardrobes, id: \.self) { wardrobe in
                    let allItemsInWardrobe = areAllSelectedItemsInWardrobe(wardrobe)
                    let isDefaultRow = wardrobe.isDefault == true
                    
                    Button {
                        pendingWardrobeSelectionTarget = wardrobe
                        pendingWardrobeSelectionWillRemove = allItemsInWardrobe && !isDefaultRow
                        showWardrobeSelectionConfirmAlert = true
                    } label: {
                        HStack {
                            Text(wardrobe.name ?? "Untitled")
                            
                            if isDefaultRow {
                                Text("Default")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color(UIColor.secondarySystemBackground))
                                    )
                            }
                            
                            Spacer()
                            
                            Image(systemName: allItemsInWardrobe ? "checkmark" : "plus")
                                .foregroundColor(.blue)
                                .font(.system(size: 16, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDefaultRow && allItemsInWardrobe)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Add to Wardrobe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
    }
    
    private func areAllSelectedItemsInWardrobe(_ wardrobe: Wardrobe) -> Bool {
        guard !selectedItems.isEmpty else { return false }
        
        let itemsInWardrobe = (wardrobe.items as? Set<Item>) ?? []
        
        // Check if all selected items are already in this wardrobe
        return selectedItems.allSatisfy { itemsInWardrobe.contains($0) }
    }
    
    private func fetchAllWardrobes() -> [Wardrobe] {
        guard let userId = authSession.userId?.uuidString, !userId.isEmpty else { return [] }

        let request: NSFetchRequest<Wardrobe> = Wardrobe.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "type == %@", wardrobeType),
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        ])
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Wardrobe.createdAt, ascending: true)
        ]

        do {
            let results = try viewContext.fetch(request)
            let filteredWardrobes = filterModel.selectedWardrobes.filter {
                $0.type == wardrobeType && $0.userId == userId
            }
            if filteredWardrobes.isEmpty {
                return results
            }
            let allowedIDs = Set(filteredWardrobes.map(\.objectID))
            return results.filter { allowedIDs.contains($0.objectID) }
        } catch {
            print("❌ Failed to fetch wardrobes: \(error.localizedDescription)")
            return []
        }
    }
    
    @discardableResult
    private func addSelectedItemsToWardrobe(_ wardrobe: Wardrobe) -> String? {
        guard !selectedItems.isEmpty else { return nil }

        let wardrobeName = wardrobe.name ?? "this wardrobe"
        let itemsInWardrobe = (wardrobe.items as? Set<Item>) ?? []
        var addedCount = 0
        for item in selectedItems where !itemsInWardrobe.contains(item) {
            wardrobe.addToItems(item)
            addedCount += 1
        }

        guard addedCount > 0 else {
            return "Selected items are already in “\(wardrobeName)”."
        }

        do {
            try viewContext.save()
            print("✅ Added \(addedCount) items to wardrobe '\(wardrobeName)'")
            isInSelectionMode = false
            clearItemSelection()
            scheduleItemsFetch()
            return "Added \(addedCount) item\(addedCount == 1 ? "" : "s") to “\(wardrobeName)”."
        } catch {
            print("❌ Failed to add items to wardrobe: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    private func removeSelectedItemsFromWardrobe(_ wardrobe: Wardrobe) -> String? {
        guard !selectedItems.isEmpty else { return nil }
        guard wardrobe.isDefault != true else { return nil }

        let wardrobeName = wardrobe.name ?? "this wardrobe"
        let itemsInWardrobe = (wardrobe.items as? Set<Item>) ?? []
        var removedCount = 0
        for item in selectedItems where itemsInWardrobe.contains(item) {
            wardrobe.removeFromItems(item)
            removedCount += 1
        }

        guard removedCount > 0 else {
            return "Selected items aren’t in “\(wardrobeName)”."
        }

        do {
            try viewContext.save()
            print("✅ Removed \(removedCount) items from wardrobe '\(wardrobeName)'")
            isInSelectionMode = false
            clearItemSelection()
            scheduleItemsFetch()
            return "Removed \(removedCount) item\(removedCount == 1 ? "" : "s") from “\(wardrobeName)”."
        } catch {
            print("❌ Failed to remove items from wardrobe: \(error.localizedDescription)")
            return nil
        }
    }
    
    private var isSelectionDeleteDisabled: Bool {
        selectedTab == "Items" ? selectedItems.isEmpty : selectedOutfits.isEmpty
    }

    private var selectionDeleteColor: Color {
        isSelectionDeleteDisabled ? .gray : .red
    }

    private var selectedItemsAllFavorited: Bool {
        _ = favoriteToolbarTick
        guard !selectedItems.isEmpty else { return false }
        return selectedItems.allSatisfy(\.isFavorite)
    }

    private var selectedItemsFavoriteToolbarIcon: String {
        _ = favoriteToolbarTick
        guard !selectedItems.isEmpty else { return "heart" }
        return selectedItemsAllFavorited ? "heart.fill" : "heart"
    }

    private var selectedOutfitsAllFavorited: Bool {
        _ = favoriteToolbarTick
        guard !selectedOutfits.isEmpty else { return false }
        return selectedOutfits.allSatisfy(\.isFavorite)
    }

    private var selectedOutfitsFavoriteToolbarIcon: String {
        _ = favoriteToolbarTick
        guard !selectedOutfits.isEmpty else { return "heart" }
        return selectedOutfitsAllFavorited ? "heart.fill" : "heart"
    }

    @discardableResult
    private func applyFavoriteToSelectedItems(favorite: Bool) -> String? {
        guard !selectedItems.isEmpty else { return nil }
        let selectionCount = selectedItems.count
        var itemsUpdated = 0
        for item in selectedItems where item.isFavorite != favorite {
            item.isFavorite = favorite
            setUpdatedAt(item)
            itemsUpdated += 1
        }
        do {
            try viewContext.save()
            for item in selectedItems {
                SyncService.shared.syncItemIfNeeded(item)
            }
            favoriteToolbarTick += 1
            print("✅ \(favorite ? "Favorited" : "Unfavorited") \(itemsUpdated) items")
            if favorite {
                return "Added \(selectionCount) item\(selectionCount == 1 ? "" : "s") to favorites."
            }
            return "Removed \(selectionCount) item\(selectionCount == 1 ? "" : "s") from favorites."
        } catch {
            print("❌ Failed to update favorites: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    private func applyFavoriteToSelectedOutfits(favorite: Bool) -> String? {
        guard !selectedOutfits.isEmpty else { return nil }
        let selectionCount = selectedOutfits.count
        var outfitsUpdated = 0
        for outfit in selectedOutfits where outfit.isFavorite != favorite {
            outfit.isFavorite = favorite
            setUpdatedAt(outfit)
            outfitsUpdated += 1
        }
        do {
            try viewContext.save()
            for outfit in selectedOutfits {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }
            favoriteToolbarTick += 1
            print("✅ \(favorite ? "Favorited" : "Unfavorited") \(outfitsUpdated) outfits")
            if favorite {
                return "Added \(selectionCount) outfit\(selectionCount == 1 ? "" : "s") to favorites."
            }
            return "Removed \(selectionCount) outfit\(selectionCount == 1 ? "" : "s") from favorites."
        } catch {
            print("❌ Failed to update outfit favorites: \(error.localizedDescription)")
            return nil
        }
    }

    /// Removes deleted items from other items' `pairedItems` and clears deleted items' own pairs.
    /// Returns the set of non-deleted items that were modified and should be synced.
    private func sanitizePairsAfterDeleting(deletedItems: Set<Item>) -> Set<Item> {
        guard !deletedItems.isEmpty else { return [] }

        var modifiedPairedItems: Set<Item> = []

        for deleted in deletedItems {
            let paired = (deleted.pairedItems as? Set<Item>) ?? []

            // Remove the deleted item from any still-active paired items.
            for other in paired where !deletedItems.contains(other) {
                var othersPairs = (other.pairedItems as? Set<Item>) ?? []
                if othersPairs.remove(deleted) != nil {
                    other.pairedItems = othersPairs as NSSet
                    setUpdatedAt(other)
                    modifiedPairedItems.insert(other)
                }
            }

            // Clear pairs on the deleted item itself to prevent "ghost" pairs in UI.
            if !paired.isEmpty {
                deleted.pairedItems = NSSet()
                setUpdatedAt(deleted)
            }
        }

        return modifiedPairedItems
    }

    private func deleteSelectedItems() {
        guard !selectedItems.isEmpty else { return }

        let itemCount = selectedItems.count
        let outfitsToDelete = outfitsContainingSelectedItems()
        let deletedOutfitsCount = outfitsToDelete.count

        for outfit in outfitsToDelete {
            softDelete(outfit)
        }

        // Store brands before deletion to check if cleanup is needed
        var brandsToCheck: Set<Brand> = []
        for item in selectedItems {
            if let brand = item.brand {
                brandsToCheck.insert(brand)
            }
        }

        // Sanitize pairs before soft-delete (soft delete won't trigger Core Data delete rules).
        let modifiedPairedItems = sanitizePairsAfterDeleting(deletedItems: selectedItems)
        
        // Soft delete all selected items (for sync)
        for item in selectedItems {
            softDelete(item)
        }
        
        do {
            try viewContext.save()
            print("✅ Deleted \(itemCount) items and \(deletedOutfitsCount) outfits")
            
            // Trigger sync for all soft-deleted items
            for item in selectedItems {
                SyncService.shared.syncItemIfNeeded(item)
            }

            // Also sync any items whose pair relationships were updated
            for item in modifiedPairedItems {
                SyncService.shared.syncItemIfNeeded(item)
            }

            for outfit in outfitsToDelete {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }

            let toastMessage: String
            if deletedOutfitsCount == 0 {
                toastMessage = "Deleted \(itemCount) item\(itemCount == 1 ? "" : "s")."
            } else {
                toastMessage = "Deleted \(itemCount) item\(itemCount == 1 ? "" : "s") and \(deletedOutfitsCount) outfit\(deletedOutfitsCount == 1 ? "" : "s")."
            }
            NotificationCenter.default.post(
                name: Notification.Name("Closet.ItemDeletionToast"),
                object: nil,
                userInfo: ["message": toastMessage]
            )
            
            // Cleanup orphaned brands
            for brand in brandsToCheck {
                cleanupBrandIfOrphaned(brand)
            }
            
            // Exit selection mode and refresh after deletion
            isInSelectionMode = false
            clearItemSelection()
            scheduleItemsFetch()
            scheduleOutfitsRefresh()
        } catch {
            print("❌ Failed to delete items: \(error.localizedDescription)")
        }
    }

    /// Outfits that include any of the currently selected items (non–soft-deleted).
    private func outfitsContainingSelectedItems() -> [Outfit] {
        guard !selectedItems.isEmpty else { return [] }
        guard let userId = authSession.userId?.uuidString, !userId.isEmpty else { return [] }

        let request: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "ANY items IN %@", selectedItems),
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil"),
        ])

        do {
            return try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch outfits containing selected items: \(error.localizedDescription)")
            return []
        }
    }

    private var deleteSelectedItemsAlertMessage: String {
        let itemCount = selectedItems.count
        let itemPhrase = "\(itemCount) item\(itemCount == 1 ? "" : "s")"
        let outfitCount = outfitsContainingSelectedItems().count
        if outfitCount == 0 {
            return "Are you sure you want to delete \(itemPhrase)? This action cannot be undone."
        }
        let outfitPhrase = "\(outfitCount) outfit\(outfitCount == 1 ? "" : "s")"
        let containingPhrase = itemCount == 1 ? "that item" : "those items"
        return "Are you sure you want to delete \(itemPhrase)? This will also delete \(outfitPhrase) containing \(containingPhrase). This action cannot be undone."
    }

    private func showToast(_ message: String) {
        deletionToastMessage = message
        withAnimation(.easeInOut(duration: 0.18)) {
            showDeletionToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeInOut(duration: 0.22)) {
                showDeletionToast = false
            }
        }
    }

    private func completeBulkSelectionAction(toast message: String) {
        showTagSelectionSheet = false
        showColorSelectionSheet = false
        showCategorySelectionSheet = false
        showOutfitCategorySelectionSheet = false
        showToast(message)
    }

    // Outfit sanitation is handled by `OutfitSanitizer` at delete-time.
    
    private func deleteSelectedOutfits() {
        guard !selectedOutfits.isEmpty else { return }
        
        let outfitsToDelete = Array(selectedOutfits)
        for outfit in outfitsToDelete {
            softDelete(outfit)
        }
        
        do {
            try viewContext.save()
            print("✅ Deleted \(outfitsToDelete.count) outfits")
            
            for outfit in outfitsToDelete {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }
            
            // Exit selection mode and refresh outfits after deletion
            isInSelectionMode = false
            clearOutfitSelection()
            scheduleOutfitsRefresh()
        } catch {
            print("❌ Failed to delete outfits: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Cleanup Orphaned Brand
    private func cleanupBrandIfOrphaned(_ brand: Brand) {
        // Refresh the brand to get current item count
        viewContext.refresh(brand, mergeChanges: true)
        
        // Check if brand has any items
        if let items = brand.items as? Set<Item>, items.isEmpty {
            viewContext.delete(brand)
            do {
                try viewContext.save()
                print("✅ Cleaned up orphaned brand: \(brand.name ?? "unknown")")
            } catch {
                print("❌ Failed to cleanup orphaned brand: \(error)")
            }
        }
    }
    
    // MARK: - Tag Selection Sheet
    
    @ViewBuilder
    private func tagSelectionSheet() -> some View {
        let tagsForContext = selectedTab == "Outfits" ? fetchAllOutfitTags() : fetchAllTags()
        let filteredTags: [Tag] = {
            let trimmed = tagSelectionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return tagsForContext }
            let lower = trimmed.lowercased()
            return tagsForContext.filter { ($0.name ?? "").lowercased().contains(lower) }
        }()

        return NavigationView {
            VStack(spacing: 0) {
                HStack {
                    TextField("Add or select a tag", text: $tagSelectionSearchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textInputAutocapitalization(.words)

                    Button("Add") {
                        submitTagSelectionSearch(existingTags: tagsForContext)
                    }
                    .disabled(tagSelectionSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
                .padding(.top)
                .padding(.bottom, 12)

                List {
                    if tagsForContext.isEmpty {
                        Text(wardrobeType == "wishlist"
                            ? "Tags used on wishlist items will appear here."
                            : "Tags added to your closet will appear here.")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if filteredTags.isEmpty {
                        Text("No matching tags")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(filteredTags, id: \.self) { tag in
                            let allSelectedHaveTag = selectedTab == "Outfits"
                                ? doAllSelectedOutfitsHaveTag(tag)
                                : doAllSelectedItemsHaveTag(tag)

                            Button {
                                pendingTagSelectionTarget = tag
                                pendingTagSelectionWillRemove = allSelectedHaveTag
                                showTagSelectionConfirmAlert = true
                            } label: {
                                HStack {
                                    highlightedTagText(for: tag.name ?? "Untitled", matching: tagSelectionSearchText)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Image(systemName: allSelectedHaveTag ? "checkmark" : "plus")
                                        .foregroundColor(.blue)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Add Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .alert(pendingTagSelectionWillRemove ? "Remove Tag?" : "Add Tag?", isPresented: $showTagSelectionConfirmAlert) {
            Button(pendingTagSelectionWillRemove ? "Remove" : "Add", role: pendingTagSelectionWillRemove ? .destructive : nil) {
                guard let tag = pendingTagSelectionTarget else { return }
                let message: String?
                if pendingTagSelectionWillRemove {
                    message = selectedTab == "Outfits"
                        ? removeTagFromSelectedOutfits(tag)
                        : removeTagFromSelectedItems(tag)
                } else {
                    message = selectedTab == "Outfits"
                        ? addTagToSelectedOutfits(tag)
                        : addTagToSelectedItems(tag)
                }
                if let message {
                    completeBulkSelectionAction(toast: message)
                }
                pendingTagSelectionTarget = nil
                pendingTagSelectionWillRemove = false
            }
            Button("Cancel", role: .cancel) {
                pendingTagSelectionTarget = nil
                pendingTagSelectionWillRemove = false
            }
        } message: {
            let name = pendingTagSelectionTarget?.name ?? "this tag"
            if selectedTab == "Outfits" {
                Text(pendingTagSelectionWillRemove
                     ? "Remove tag “\(name)” from \(selectedOutfits.count) selected outfit(s)?"
                     : "Add tag “\(name)” to \(selectedOutfits.count) selected outfit(s)?")
            } else {
                Text(pendingTagSelectionWillRemove
                     ? "Remove tag “\(name)” from \(selectedItems.count) selected item(s)?"
                     : "Add tag “\(name)” to \(selectedItems.count) selected item(s)?")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func highlightedTagText(for tagName: String, matching input: String) -> Text {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerTag = tagName.lowercased()
        let lowerInput = trimmedInput.lowercased()

        guard !trimmedInput.isEmpty, let range = lowerTag.range(of: lowerInput) else {
            return Text(tagName)
        }

        let nsRange = NSRange(range, in: tagName)
        let start = tagName.startIndex
        let matchStart = tagName.index(start, offsetBy: nsRange.location)
        let matchEnd = tagName.index(matchStart, offsetBy: nsRange.length)

        let before = String(tagName[..<matchStart])
        let match = String(tagName[matchStart..<matchEnd])
        let after = String(tagName[matchEnd...])

        return Text(before) + Text(match).bold() + Text(after)
    }

    private func submitTagSelectionSearch(existingTags: [Tag]) {
        let trimmed = tagSelectionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let tag: Tag
        if let existing = existingTags.first(where: {
            ($0.name ?? "").localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            tag = existing
        } else {
            guard let userId = authSession.userId?.uuidString, !userId.isEmpty else { return }
            let newTag = Tag(context: viewContext)
            newTag.name = trimmed
            newTag.id = UUID()
            newTag.userId = userId
            do {
                try viewContext.save()
            } catch {
                print("❌ Failed to create tag: \(error.localizedDescription)")
                viewContext.rollback()
                return
            }
            tag = newTag
        }

        let allSelectedHaveTag = selectedTab == "Outfits"
            ? doAllSelectedOutfitsHaveTag(tag)
            : doAllSelectedItemsHaveTag(tag)
        pendingTagSelectionTarget = tag
        pendingTagSelectionWillRemove = allSelectedHaveTag
        showTagSelectionConfirmAlert = true
    }

    private func doAllSelectedOutfitsHaveTag(_ tag: Tag) -> Bool {
        guard !selectedOutfits.isEmpty else { return false }
        return selectedOutfits.allSatisfy { outfit in
            let tags = outfit.tags as? Set<Tag> ?? []
            return tags.contains(tag)
        }
    }

    private func fetchAllOutfitTags() -> [Tag] {
        guard let userId = authSession.userId?.uuidString, !userId.isEmpty else { return [] }
        let request: NSFetchRequest<Tag> = Tag.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]
        request.predicate = NSPredicate(
            format: "SUBQUERY(outfits, $o, $o.userId == %@ AND ($o.isSoftDeleted != YES OR $o.isSoftDeleted == nil)).@count > 0",
            userId
        )
        do {
            var tags = try viewContext.fetch(request)
            for outfit in selectedOutfits {
                let outfitTags = outfit.tags as? Set<Tag> ?? []
                for tag in outfitTags where !tags.contains(where: { $0.objectID == tag.objectID }) {
                    tags.append(tag)
                }
            }
            tags.sort { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
            return tags
        } catch {
            print("❌ Failed to fetch outfit tags: \(error.localizedDescription)")
            return []
        }
    }
    
    private func doAllSelectedItemsHaveTag(_ tag: Tag) -> Bool {
        guard !selectedItems.isEmpty else { return false }
        
        // Check if all selected items already have this tag
        return selectedItems.allSatisfy { item in
            if let tags = item.tags as? Set<Tag> {
                return tags.contains(tag)
            }
            return false
        }
    }
    
    private func fetchAllTags() -> [Tag] {
        guard let userId = authSession.userId?.uuidString, !userId.isEmpty else { return [] }

        let request: NSFetchRequest<Tag> = Tag.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]
        request.predicate = NSPredicate(
            format: "SUBQUERY(items, $i, $i.userId == %@ AND ($i.isSoftDeleted != YES OR $i.isSoftDeleted == nil) AND ANY $i.wardrobes == %@).@count > 0",
            userId,
            selectedWardrobe
        )

        do {
            var tags = try viewContext.fetch(request)
            for item in selectedItems {
                guard let itemTags = item.tags as? Set<Tag> else { continue }
                for tag in itemTags where !tags.contains(where: { $0.objectID == tag.objectID }) {
                    tags.append(tag)
                }
            }
            tags.sort { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
            return tags
        } catch {
            print("❌ Failed to fetch tags: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Outfit Category Selection Sheet

    @ViewBuilder
    private func outfitCategorySelectionSheet() -> some View {
        let categoriesForContext = fetchAllOutfitCategories()
        return NavigationView {
            List {
                if categoriesForContext.isEmpty {
                    Text("Categories added to your outfits will appear here.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(categoriesForContext, id: \.objectID) { category in
                        let allOutfitsHaveCategory = doAllSelectedOutfitsHaveCategory(category)
                        Button {
                            pendingOutfitCategoryTarget = category
                            pendingOutfitCategoryWillRemove = allOutfitsHaveCategory
                            showOutfitCategorySelectionConfirmAlert = true
                        } label: {
                            HStack {
                                Text(category.name ?? "")
                                Spacer()
                                Image(systemName: allOutfitsHaveCategory ? "checkmark" : "plus")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Add Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
    }

    private func doAllSelectedOutfitsHaveCategory(_ category: OutfitCategory) -> Bool {
        guard !selectedOutfits.isEmpty else { return false }
        return selectedOutfits.allSatisfy { $0.category?.objectID == category.objectID }
    }

    private func fetchAllOutfitCategories() -> [OutfitCategory] {
        guard let userId = authSession.userId?.uuidString, !userId.isEmpty else { return [] }
        do {
            var categories = try viewContext.fetchOutfitCategoriesForFilterList(
                userId: userId,
                wardrobe: selectedWardrobe
            )
            for outfit in selectedOutfits {
                if let category = outfit.category,
                   !categories.contains(where: { $0.objectID == category.objectID }) {
                    categories.append(category)
                }
            }
            categories.sort { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
            return categories
        } catch {
            print("❌ Failed to fetch outfit categories: \(error.localizedDescription)")
            return []
        }
    }

    @discardableResult
    private func applyCategoryToSelectedOutfits(category: OutfitCategory?) -> String? {
        guard !selectedOutfits.isEmpty else { return nil }
        let selectionCount = selectedOutfits.count

        var outfitsUpdated = 0
        var previousCategories: [OutfitCategory] = []
        for outfit in selectedOutfits {
            if outfit.category?.objectID != category?.objectID {
                if let old = outfit.category {
                    previousCategories.append(old)
                }
                outfit.category = category
                setUpdatedAt(outfit)
                outfitsUpdated += 1
            }
        }

        do {
            try viewContext.save()
            for outfit in selectedOutfits {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }
            for old in Set(previousCategories) {
                cleanupOutfitCategoryIfOrphaned(old)
            }
            let label = category?.name ?? "None"
            print("✅ Set category '\(label)' on \(outfitsUpdated) outfits")
            if let name = category?.name {
                return "Set category “\(name)” on \(selectionCount) outfit\(selectionCount == 1 ? "" : "s")."
            }
            return "Removed category from \(selectionCount) outfit\(selectionCount == 1 ? "" : "s")."
        } catch {
            print("❌ Failed to set category on outfits: \(error.localizedDescription)")
            return nil
        }
    }
    
    @discardableResult
    private func addTagToSelectedItems(_ tag: Tag) -> String? {
        guard !selectedItems.isEmpty else { return nil }

        let selectionCount = selectedItems.count
        var itemsAdded = 0
        for item in selectedItems {
            if let tags = item.tags as? Set<Tag>, !tags.contains(tag) {
                item.addToTags(tag)
                setUpdatedAt(item)
                itemsAdded += 1
            }
        }

        do {
            try viewContext.save()
            for item in selectedItems {
                SyncService.shared.syncItemIfNeeded(item)
            }
            print("✅ Added tag '\(tag.name ?? "unknown")' to \(itemsAdded) items")
            let name = tag.name ?? "tag"
            return "Added tag “\(name)” to \(selectionCount) item\(selectionCount == 1 ? "" : "s")."
        } catch {
            print("❌ Failed to add tag to items: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    private func removeTagFromSelectedItems(_ tag: Tag) -> String? {
        guard !selectedItems.isEmpty else { return nil }

        let selectionCount = selectedItems.count
        for item in selectedItems {
            if let tags = item.tags as? Set<Tag>, tags.contains(tag) {
                item.removeFromTags(tag)
                setUpdatedAt(item)
            }
        }

        do {
            try viewContext.save()
            for item in selectedItems {
                SyncService.shared.syncItemIfNeeded(item)
            }
            print("✅ Removed tag '\(tag.name ?? "unknown")' from \(selectionCount) items")
            let name = tag.name ?? "tag"
            return "Removed tag “\(name)” from \(selectionCount) item\(selectionCount == 1 ? "" : "s")."
        } catch {
            print("❌ Failed to remove tag from items: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    private func addTagToSelectedOutfits(_ tag: Tag) -> String? {
        guard !selectedOutfits.isEmpty else { return nil }
        let selectionCount = selectedOutfits.count
        var outfitsAdded = 0
        for outfit in selectedOutfits {
            let tags = outfit.tags as? Set<Tag> ?? []
            if !tags.contains(tag) {
                outfit.addToTags(tag)
                setUpdatedAt(outfit)
                outfitsAdded += 1
            }
        }
        do {
            try viewContext.save()
            for outfit in selectedOutfits {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }
            print("✅ Added tag '\(tag.name ?? "unknown")' to \(outfitsAdded) outfits")
            let name = tag.name ?? "tag"
            return "Added tag “\(name)” to \(selectionCount) outfit\(selectionCount == 1 ? "" : "s")."
        } catch {
            print("❌ Failed to add tag to outfits: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    private func removeTagFromSelectedOutfits(_ tag: Tag) -> String? {
        guard !selectedOutfits.isEmpty else { return nil }
        let selectionCount = selectedOutfits.count
        for outfit in selectedOutfits {
            let tags = outfit.tags as? Set<Tag> ?? []
            if tags.contains(tag) {
                outfit.removeFromTags(tag)
                setUpdatedAt(outfit)
            }
        }
        do {
            try viewContext.save()
            for outfit in selectedOutfits {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }
            print("✅ Removed tag '\(tag.name ?? "unknown")' from \(selectionCount) outfits")
            let name = tag.name ?? "tag"
            return "Removed tag “\(name)” from \(selectionCount) outfit\(selectionCount == 1 ? "" : "s")."
        } catch {
            print("❌ Failed to remove tag from outfits: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Color Selection Sheet

    @ViewBuilder
    private func colorSelectionSheet() -> some View {
        let colorsForContext = fetchAllColorsForBulkSet()
        return NavigationView {
            List {
                if colorsForContext.isEmpty {
                    Text("Colors added to your closet will appear here.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(colorsForContext, id: \.objectID) { color in
                        let allItemsHaveColor = doAllSelectedItemsHaveColor(color)
                        let name = color.name ?? ""

                        Button {
                            pendingColorSelectionTarget = color
                            pendingColorSelectionWillRemove = allItemsHaveColor
                            showColorSelectionConfirmAlert = true
                        } label: {
                            HStack {
                                Circle()
                                    .fill(colorFromName(name))
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))

                                Text(name)

                                Spacer()

                                Image(systemName: allItemsHaveColor ? "checkmark" : "plus")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Add Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .alert(pendingColorSelectionWillRemove ? "Remove Color?" : "Add Color?", isPresented: $showColorSelectionConfirmAlert) {
            Button(pendingColorSelectionWillRemove ? "Remove" : "Add", role: pendingColorSelectionWillRemove ? .destructive : nil) {
                guard let color = pendingColorSelectionTarget else { return }
                let message: String?
                if pendingColorSelectionWillRemove {
                    message = removeColorFromSelectedItems(color)
                } else {
                    message = addColorToSelectedItems(color)
                }
                if let message {
                    completeBulkSelectionAction(toast: message)
                }
                pendingColorSelectionTarget = nil
                pendingColorSelectionWillRemove = false
            }
            Button("Cancel", role: .cancel) {
                pendingColorSelectionTarget = nil
                pendingColorSelectionWillRemove = false
            }
        } message: {
            let name = pendingColorSelectionTarget?.name ?? "this color"
            Text(pendingColorSelectionWillRemove
                 ? "Remove color “\(name)” from \(selectedItems.count) selected item(s)?"
                 : "Add color “\(name)” to \(selectedItems.count) selected item(s)?")
        }
        .presentationDetents([.medium, .large])
    }

    private func doAllSelectedItemsHaveColor(_ color: AppColor) -> Bool {
        guard !selectedItems.isEmpty else { return false }
        return selectedItems.allSatisfy { item in
            (item.colors as? Set<AppColor>)?.contains(color) ?? false
        }
    }

    private func fetchAllColorsForBulkSet() -> [AppColor] {
        guard let userId = authSession.userId?.uuidString, !userId.isEmpty else { return [] }

        do {
            var colors = try viewContext.fetchColorsForFilterList(userId: userId, itemsOnly: false)
            for item in selectedItems {
                guard let itemColors = item.colors as? Set<AppColor> else { continue }
                for color in itemColors where !colors.contains(where: { $0.objectID == color.objectID }) {
                    colors.append(color)
                }
            }
            colors.sort { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
            return colors
        } catch {
            print("❌ Failed to fetch colors: \(error.localizedDescription)")
            return []
        }
    }

    @discardableResult
    private func addColorToSelectedItems(_ color: AppColor) -> String? {
        guard !selectedItems.isEmpty else { return nil }

        let selectionCount = selectedItems.count
        for item in selectedItems {
            if let colors = item.colors as? Set<AppColor>, !colors.contains(color) {
                item.addToColors(color)
                setUpdatedAt(item)
            }
        }

        do {
            try viewContext.save()
            for item in selectedItems {
                SyncService.shared.syncItemIfNeeded(item)
            }
            print("✅ Added color '\(color.name ?? "unknown")' to \(selectionCount) items")
            let name = color.name ?? "color"
            return "Added color “\(name)” to \(selectionCount) item\(selectionCount == 1 ? "" : "s")."
        } catch {
            print("❌ Failed to add color to items: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    private func removeColorFromSelectedItems(_ color: AppColor) -> String? {
        guard !selectedItems.isEmpty else { return nil }

        let selectionCount = selectedItems.count
        for item in selectedItems {
            if let colors = item.colors as? Set<AppColor>, colors.contains(color) {
                item.removeFromColors(color)
                setUpdatedAt(item)
            }
        }

        do {
            try viewContext.save()
            for item in selectedItems {
                SyncService.shared.syncItemIfNeeded(item)
            }
            print("✅ Removed color '\(color.name ?? "unknown")' from \(selectionCount) items")
            let name = color.name ?? "color"
            return "Removed color “\(name)” from \(selectionCount) item\(selectionCount == 1 ? "" : "s")."
        } catch {
            print("❌ Failed to remove color from items: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Category Selection Sheet

    @ViewBuilder
    private func categorySelectionSheet() -> some View {
        CategoryPickerList(
            title: "Add Category",
            userId: authSession.userId?.uuidString ?? "",
            expanded: $bulkSetCategoryExpanded,
            onCategoriesLoaded: expandBulkSetCategoryForCurrentSelection(categories:),
            showsCategoryCheckmark: { allSelectedItemsMatch(category: $0, subcategory: nil) },
            showsSubcategoryCheckmark: { category, sub in
                allSelectedItemsMatch(category: category, subcategory: sub)
            },
            onCategoryTap: { category in
                pendingBulkCategory = category
                pendingBulkSubcategory = nil
                showCategorySelectionConfirmAlert = true
            },
            onSubcategoryTap: { category, sub in
                pendingBulkCategory = category
                pendingBulkSubcategory = sub
                showCategorySelectionConfirmAlert = true
            }
        )
        .alert("Add Category?", isPresented: $showCategorySelectionConfirmAlert) {
            Button("Apply") {
                guard let category = pendingBulkCategory else { return }
                if let message = applyCategoryToSelectedItems(category: category, subcategory: pendingBulkSubcategory) {
                    completeBulkSelectionAction(toast: message)
                }
                pendingBulkCategory = nil
                pendingBulkSubcategory = nil
            }
            Button("Cancel", role: .cancel) {
                pendingBulkCategory = nil
                pendingBulkSubcategory = nil
            }
        } message: {
            Text(bulkCategorySelectionConfirmMessage)
        }
        .presentationDetents([.medium, .large])
    }

    private var bulkCategorySelectionConfirmMessage: String {
        let count = selectedItems.count
        let itemPhrase = "\(count) selected item\(count == 1 ? "" : "s")"
        if let sub = pendingBulkSubcategory {
            let cat = pendingBulkCategory?.name ?? ""
            let subName = sub.name ?? ""
            return "Set “\(cat) › \(subName)” on \(itemPhrase)?"
        }
        let name = pendingBulkCategory?.name ?? "category"
        return "Set category “\(name)” on \(itemPhrase)?"
    }

    private func expandBulkSetCategoryForCurrentSelection(categories: [Category]) {
        bulkSetCategoryExpanded = []
        guard !selectedItems.isEmpty,
              let first = selectedItems.first,
              let sharedCategory = first.category,
              selectedItems.allSatisfy({ pickerCategoriesMatch($0.category, sharedCategory) }),
              let listCategory = resolveCategoryInPickerList(sharedCategory, categories: categories)
        else { return }

        if let sharedSub = first.subcategory,
           subcategoryBelongsToPickerCategory(sharedSub, listCategory: sharedCategory),
           selectedItems.allSatisfy({ pickerSubcategoriesMatch($0.subcategory, sharedSub) }) {
            bulkSetCategoryExpanded.insert(listCategory.objectID)
        }
    }

    private func allSelectedItemsMatch(category: Category, subcategory: Subcategory?) -> Bool {
        guard !selectedItems.isEmpty else { return false }
        return selectedItems.allSatisfy { item in
            guard pickerCategoriesMatch(item.category, category) else { return false }
            if let subcategory {
                return pickerSubcategoriesMatch(item.subcategory, subcategory)
            }
            return item.subcategory == nil
        }
    }

    @discardableResult
    private func applyCategoryToSelectedItems(category: Category, subcategory: Subcategory?) -> String? {
        guard !selectedItems.isEmpty else { return nil }

        let userId = authSession.userId?.uuidString ?? ""
        let normalizedCategory = userId.isEmpty
            ? category
            : viewContext.canonicalCategoryForAttributePicker(category, userId: userId)
        let normalizedSubcategory: Subcategory?
        if let subcategory {
            normalizedSubcategory = userId.isEmpty
                ? subcategory
                : viewContext.canonicalSubcategoryForAttributePicker(subcategory, parent: normalizedCategory, userId: userId)
        } else {
            normalizedSubcategory = nil
        }

        let selectionCount = selectedItems.count
        for item in selectedItems {
            item.category = normalizedCategory
            item.subcategory = normalizedSubcategory
            setUpdatedAt(item)
        }

        let label: String
        if let subName = normalizedSubcategory?.name, !subName.isEmpty {
            let catName = normalizedCategory.name ?? "category"
            label = "\(catName) › \(subName)"
        } else {
            label = normalizedCategory.name ?? "category"
        }

        do {
            try viewContext.save()
            for item in selectedItems {
                SyncService.shared.syncItemIfNeeded(item)
            }
            print("✅ Set category '\(label)' on \(selectionCount) items")
            return "Set category “\(label)” on \(selectionCount) item\(selectionCount == 1 ? "" : "s")."
        } catch {
            print("❌ Failed to set category on items: \(error.localizedDescription)")
            return nil
        }
    }

    @ViewBuilder
    private var outfitsEmptyState: some View {
        if isRedressFilterActive {
            EmptyOutfitStateView(
                title: "No Redress outfits",
                message: "Nobody has redressed you yet! Connect with friends and invite them to redress you.",
                systemImage: "person.2"
            )
        } else if hasActiveOutfitFiltersOrSearch {
            EmptyOutfitStateView(
                title: "No matching outfits",
                message: "Try adjusting your filters or search.",
                systemImage: "line.3.horizontal.decrease.circle"
            )
        } else {
            EmptyOutfitStateView()
        }
    }

    private var hasActiveOutfitFiltersOrSearch: Bool {
        outfitFilterModel.activeFilterCount > 0 || !outfitFilterModel.trimmedSearchQuery.isEmpty
    }

    private var hasRedressFilterContent: Bool {
        !displayedPendingRedressSuggestions.isEmpty || !outfits.isEmpty
    }

    private var outfitsTab: some View {
        closetPullToRefreshIfNeeded {
            ScrollView(showsIndicators: false) {
                if isOutfitsTabLoading || (isRedressFilterActive && isRedressLoading && !hasRedressFilterContent) {
                    closetContentLoadingView
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 240)
                } else if isRedressFilterActive {
                    if !hasRedressFilterContent {
                        outfitsEmptyState
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 240)
                    } else {
                        redressFilterContent
                    }
                } else if outfits.isEmpty {
                    outfitsEmptyState
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 240)
                } else {
                    outfitsLazyGrid
                }
            }
        }
    }

    @ViewBuilder
    private var redressFilterContent: some View {
        let hasPending = !displayedPendingRedressSuggestions.isEmpty
        VStack(spacing: 0) {
            if hasPending {
                redressSectionHeader("PENDING")
                pendingRedressSuggestionsGrid
            }
            if !outfits.isEmpty {
                // PENDING/ACCEPTED headers only when there is at least one pending suggestion
                // (Profile). Closet Redress shows accepted only, with no section headers.
                if hasPending {
                    redressSectionHeader("ACCEPTED")
                }
                outfitsLazyGrid
            }
        }
    }

    private func redressSectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var pendingRedressSuggestionsGrid: some View {
        let suggestions = displayedPendingRedressSuggestions
        let rowCount = (suggestions.count + 2) / 3
        return VStack(spacing: 2) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        if index < suggestions.count {
                            let suggestion = suggestions[index]
                            ProfilePendingRedressOutfitCell(suggestion: suggestion)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    openProfilePendingSuggestion(suggestion)
                                }
                        } else {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
        .padding(.top, 2)
        .id(suggestions.map(\.id))
    }

    private func openPacking() {
        tabBarHideState.shouldHideTabBar = true
        if let onOpenPacking {
            isPackingOnPath = true
            onOpenPacking()
        } else {
            packingNavigation = .packing
        }
    }

    private func openProfilePendingSuggestion(_ suggestion: VisibleOutfitSuggestion) {
        guard let recipientUserId = authSession.userId,
              let wardrobeId = selectedWardrobe.id else { return }

        let destination = PendingRedressNavigationDestination(
            recipientUserId: recipientUserId,
            wardrobeId: wardrobeId,
            suggestionSummary: suggestion.asGridOutfit(),
            viewerRole: .recipient
        )
        if let onOpenPendingRedress {
            isDetailNavigationActive = true
            onOpenPendingRedress(destination)
        } else {
            selectedPendingRedress = destination
        }
    }

    private var outfitsLazyGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 2) {
            ForEach(outfits, id: \.objectID) { outfit in
                OutfitView(outfit: outfit, showsFavoriteOverlay: !isReadOnly)
                    .overlay(
                        Group {
                            if isInSelectionMode && selectedOutfits.contains(outfit) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.35))
                            }
                        }
                    )
                    .overlay(
                        Group {
                            if isInSelectionMode {
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Image(systemName: selectedOutfits.contains(outfit) ? "checkmark.circle" : "circle")
                                            .foregroundColor(.white)
                                            .background(
                                                Circle()
                                                    .fill(selectedOutfits.contains(outfit) ? Color.blue : Color.clear)
                                                    .padding(2)
                                            )
                                            .font(.system(size: 22))
                                            .shadow(radius: 1)
                                            .padding(8)
                                    }
                                }
                            }
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleOutfitTap(for: outfit)
                    }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        handleOutfitLongPress(for: outfit)
                    }
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Profile pending Redress outfit cell

private struct ProfilePendingRedressOutfitCell: View {
    let suggestion: VisibleOutfitSuggestion

    private var collageURL: URL? {
        guard let imageUrl = suggestion.imageUrl, let url = URL(string: imageUrl) else { return nil }
        return url
    }

    var body: some View {
        Color(red: 247 / 255, green: 247 / 255, blue: 247 / 255)
            .overlay {
                if let url = collageURL {
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
            }
            .overlay(alignment: .bottomTrailing) {
                if let profile = suggestion.suggesterProfile {
                    GeometryReader { geo in
                        RedressSuggesterAvatarBadge(
                            profile: profile,
                            size: max(22, geo.size.width * 0.28)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(6)
                    }
                }
            }
            .clipped()
            .aspectRatio(1, contentMode: .fit)
    }
}
