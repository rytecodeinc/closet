//
//  ItemDetailView.swift
//  closet
//
//  Created by Dan Warner on 7/19/25.
//


import SwiftUI
import UIKit
import CoreData

struct ItemDetailView: View {
    @ObservedObject var item: Item
    var isReadOnly: Bool = false
    /// Closet/Wishlist tab path — nested Create Outfit / pair / outfit append routes (no nested `item:`).
    var navigationPath: Binding<NavigationPath>? = nil
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appCapabilities) private var appCapabilities
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession
    
    @State private var outfits: [Outfit] = []
    @State private var isEditingAttributes = false
    @State private var attributesSheet: AttributesSectionView.Sheet?
    @State private var isImageFullScreen = false
    @State private var isAttributesExpanded = true
    @State private var isSetsExpanded = false
    @State private var isOutfitsExpanded = false
    @State private var isLinksExpanded = false
    @State private var isHistoryExpanded = false
    
    private let currencySymbol = Locale.current.currencySymbol ?? "$"

    @State private var isImagePickerPresented = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedUIImage: UIImage?
    @State private var pendingImageType: ImageType? // Track which image type is being added/edited
    
    /// Sheet (not nested `item:` push) — Item Detail is already mid-stack on Closet/Wishlist path.
    @State private var isCropEditorPresented = false
    @State private var imageToEdit: UIImage?
    @State private var cropEditorSessionID = UUID()
    @State private var showShareSheet = false
    @State private var isPreparingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showShareSelectionSheet = false
    @State private var selectedShareAttributes: Set<ShareableAttribute> = []
    @State private var pendingShareText: String?
    @State private var pendingShareImage: UIImage?
    @State private var showShareFriendsSheet = false
    @State private var showWornStatsSheet = false
    @State private var selectedImageType: ImageType = .front
    /// Inline hero carousel: 0 = front, 1 = worn (fixed slots; fullscreen still skips empty slots).
    @State private var heroCarouselPage: Int = 0
    @State private var likeCount = 0
    @State private var isLikedByMe = false
    @State private var isLikeBusy = false
    @State private var showThumbnailActionSheet: Bool = false
    @State private var thumbnailActionSheetType: ImageType?
    @State private var showDeleteConfirmation = false
    @State private var showAddToClosetConfirmation = false
    @State private var showRemoveWornImageConfirmation = false
    /// Set when a worn photo is saved/replaced. Consumed after any front reset so Worn wins.
    @State private var pendingSelectWornHero = false
    @State private var showHeroDisplayOptionsDialog = false
    @State private var showPairItemSelection = false
    @State private var pairSelectionInitialSegment: PairItemSelectionView.PairSourceSegment = .closet
    @State private var showViewAllPairsSheet = false
    @State private var viewAllPairsInitialSegment: PairItemSelectionView.PairSourceSegment = .closet
    @State private var showViewAllOutfitsSheet = false
    @State private var pendingCreateOutfitAfterSheetDismiss = false
    @State private var selectedPairedItemForNavigation: Item?
    @State private var pendingPairedItemForNavigation: Item?
    @State private var selectedOutfitURIForNavigation: String?
    @State private var pendingOutfitForNavigation: Outfit?
    @State private var showAddToClosetToast = false
    @State private var addToClosetToastMessage = "Added to closet."
    
    private enum CreateOutfitNavigation: Hashable {
        case create
    }
    @State private var createOutfitNavigation: CreateOutfitNavigation?
    @State private var createOutfitSessionID: UUID = UUID()
    
    // Computed property to get paired items, sorted by date/time added (oldest first)
    // Note: We use updatedAt as a proxy for when pairs were added, since Core Data doesn't
    // track relationship creation timestamps. When a pair is added, both items get updatedAt set.
    // We use createdAt as a tiebreaker to ensure stable sorting.
    private var pairedItems: [Item] {
        if let pairedItemsSet = item.pairedItems as? Set<Item> {
            // Exclude soft-deleted items to avoid "ghost" pairs lingering in UI.
            let visiblePairedItems = pairedItemsSet.filter { ($0.isSoftDeleted == false) }
            return Array(visiblePairedItems).sorted { item1, item2 in
                // Primary sort: updatedAt ascending (oldest first)
                // If updatedAt is nil, treat as oldest (put at beginning)
                let date1 = item1.updatedAt ?? Date.distantPast
                let date2 = item2.updatedAt ?? Date.distantPast
                
                if date1 != date2 {
                    return date1 < date2
                }
                
                // Tiebreaker: createdAt ascending (older items first if updatedAt is the same)
                let created1 = item1.createdAt ?? Date.distantPast
                let created2 = item2.createdAt ?? Date.distantPast
                
                if created1 != created2 {
                    return created1 < created2
                }
                
                // Final tiebreaker: Use item ID for stable sorting
                let id1 = item1.id?.uuidString ?? ""
                let id2 = item2.id?.uuidString ?? ""
                return id1 < id2
            }
        }
        return []
    }

    private var preferredWardrobeForNewOutfit: Wardrobe? {
        guard let set = item.wardrobes as? Set<Wardrobe> else { return nil }
        let closets = set.filter { ($0.type ?? "").lowercased() == "closet" }
        return closets.first ?? set.first
    }
    
    enum ImageType: Hashable {
        case front
        case worn
    }

    private var pairsSectionHeaderIconName: String {
        isSetsExpanded ? "minus" : "plus"
    }

    private func handlePairsSectionHeaderTap() {
        if !isReadOnly && pairedItems.isEmpty {
            openPairItemSelection(segment: .closet)
            return
        }
        guard !pairedItems.isEmpty else { return }
        withAnimation {
            isSetsExpanded.toggle()
        }
    }

    private func openPairItemSelection(segment: PairItemSelectionView.PairSourceSegment = .closet) {
        pairSelectionInitialSegment = segment
        showPairItemSelection = true
    }

    private func presentViewAllPairsSheet(segment: PairItemSelectionView.PairSourceSegment) {
        viewAllPairsInitialSegment = segment
        showViewAllPairsSheet = true
    }

    private func handleViewAllPairsSheetDismissed() {
        guard let pending = pendingPairedItemForNavigation else { return }
        pendingPairedItemForNavigation = nil
        openPairedItem(pending)
    }

    @ViewBuilder
    private var pairsSectionContent: some View {
        if !pairedItems.isEmpty {
            FeaturedItemsSubsectionRow(
                pairedItems: pairedItems,
                wishlistItems: wishlistPairedItems,
                closetItems: closetPairedItems,
                showsWardrobeLabels: shouldShowPairsWardrobeLabels,
                isReadOnly: isReadOnly,
                onSelectPairedItem: { openPairedItem($0) },
                onViewAll: { presentViewAllPairsSheet(segment: .closet) }
            )
        }
    }

    private var isWishlistItem: Bool {
        (item.wardrobes as? Set<Wardrobe>)?.contains { $0.type?.lowercased() == "wishlist" } ?? false
    }

    private var itemPastWornEventCount: Int {
        pastWornEvents(for: item).count
    }

    private var showsCalendarActions: Bool {
        !isReadOnly && !isWishlistItem && itemPastWornEventCount > 0
    }

    private func pairedItemIsWishlistMember(_ pairedItem: Item) -> Bool {
        (pairedItem.wardrobes as? Set<Wardrobe>)?.contains { $0.type?.lowercased() == "wishlist" } ?? false
    }

    private var wishlistPairedItems: [Item] {
        pairedItems.filter { pairedItemIsWishlistMember($0) }
    }

    private var closetPairedItems: [Item] {
        pairedItems.filter { !pairedItemIsWishlistMember($0) }
    }

    private var shouldShowPairsWardrobeLabels: Bool {
        let hasWishlistPairs = !wishlistPairedItems.isEmpty
        let hasClosetPairs = !closetPairedItems.isEmpty
        return (hasWishlistPairs && hasClosetPairs)
            || (isWishlistItem && hasClosetPairs)
            || (!isWishlistItem && hasWishlistPairs)
    }

    private var outfitsSectionHeaderIconName: String {
        isOutfitsExpanded ? "minus" : "plus"
    }

    private func handleOutfitsSectionHeaderTap() {
        if !isReadOnly && outfits.isEmpty {
            openCreateOutfit()
            return
        }
        guard !outfits.isEmpty else { return }
        withAnimation {
            isOutfitsExpanded.toggle()
        }
    }

    private func handleViewAllOutfitsSheetDismissed() {
        if pendingCreateOutfitAfterSheetDismiss {
            pendingCreateOutfitAfterSheetDismiss = false
            openCreateOutfit()
            return
        }
        guard let pending = pendingOutfitForNavigation else { return }
        pendingOutfitForNavigation = nil
        openOutfit(pending)
    }

    private func openCreateOutfit() {
        let uri = item.objectID.uriRepresentation().absoluteString
        createOutfitSessionID = UUID()
        print("🧭 [ItemDetailView] Create Outfit tapped. itemURI=\(uri) sessionID=\(createOutfitSessionID.uuidString)")
        // Defer push so the List header tap is not held by the system gesture gate.
        DispatchQueue.main.async {
            if let navigationPath {
                navigationPath.wrappedValue.append(
                    ItemGridFilterRoute.createOutfitFromItem(itemURI: uri, sessionID: createOutfitSessionID)
                )
            } else {
                createOutfitNavigation = .create
            }
        }
    }

    private func openPairedItem(_ pairedItem: Item) {
        if let navigationPath {
            navigationPath.wrappedValue.append(
                ItemGridFilterRoute.itemDetail(uri: pairedItem.objectID.uriRepresentation().absoluteString)
            )
        } else {
            selectedPairedItemForNavigation = pairedItem
        }
    }

    private func openOutfit(_ outfit: Outfit) {
        let uri = outfit.objectID.uriRepresentation().absoluteString
        if let navigationPath {
            navigationPath.wrappedValue.append(ItemGridFilterRoute.outfitDetail(uri: uri))
        } else {
            selectedOutfitURIForNavigation = uri
        }
    }

    private var namedItemLinks: [Link] {
        ((item.links as? Set<Link>) ?? [])
            .filter { !($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private func namedItemLinks(for type: ItemLinkType) -> [Link] {
        namedItemLinks.filter { $0.itemLinkType == type }
    }

    private var itemLinkCount: Int { namedItemLinks.count }

    private var linksSectionHeaderIconName: String {
        isLinksExpanded ? "minus" : "plus"
    }

    private func handleLinksSectionHeaderTap() {
        if !isReadOnly && itemLinkCount == 0 {
            attributesSheet = .link
            return
        }
        withAnimation {
            isLinksExpanded.toggle()
        }
    }

    private let linksChevronColumnWidth: CGFloat = 20

    @ViewBuilder
    private var linksSectionContent: some View {
        HStack(alignment: .center, spacing: 2) {
            ItemLinkTypedSectionsView(
                linksForType: namedItemLinks(for:)
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isReadOnly {
                Button {
                    attributesSheet = .link
                } label: {
                    Color.clear
                        .overlay {
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: linksChevronColumnWidth)
                .frame(maxHeight: .infinity, alignment: .center)
                .accessibilityLabel("Edit links")
            }
        }
    }

    @ViewBuilder
    private var outfitsSectionContent: some View {
        if !outfits.isEmpty {
            OutfitsSubsectionRow(
                outfits: outfits,
                isReadOnly: isReadOnly,
                onSelectOutfit: { outfit in
                    openOutfit(outfit)
                },
                onViewAll: { showViewAllOutfitsSheet = true }
            )
        }
    }

    private var historySectionHeaderIconName: String {
        isHistoryExpanded ? "minus" : "plus"
    }

    private var historySectionBottomPad: some View {
        Color.clear
            .frame(height: 4)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .environment(\.defaultMinListRowHeight, 1)
    }

    private func initializeSelectedImageType() {
        selectedImageType = .front
        heroCarouselPage = 0
    }

    private func selectHeroImageSlot(_ type: ImageType) {
        switch type {
        case .front:
            selectedImageType = .front
            heroCarouselPage = 0
        case .worn:
            selectedImageType = .worn
            heroCarouselPage = 1
        }
    }

    private func syncHeroCarouselWithSelectedImageType() {
        heroCarouselPage = (selectedImageType == .worn) ? 1 : 0
    }

    var body: some View {
        withNestedItemPathDestinations(itemDetailWithAlerts)
            .toolbar(.hidden, for: .tabBar)
    }

    /// Closet/Wishlist pass `navigationPath` and register detail/create on the tab path.
    /// Other hosts keep nested `item:` destinations (Profile, Travel, etc.).
    @ViewBuilder
    private func withNestedItemPathDestinations<Content: View>(_ content: Content) -> some View {
        if navigationPath != nil {
            content
        } else {
            content
                .navigationDestination(item: $createOutfitNavigation) { _ in
                    let uri = item.objectID.uriRepresentation().absoluteString
                    let wardrobe = preferredWardrobeForNewOutfit
                    return OutfitAddView(
                        outfitToEdit: nil,
                        wardrobeType: wardrobe?.type ?? "closet",
                        initialWardrobe: wardrobe,
                        lockWardrobeSource: false,
                        wardrobeMembershipOnSave: (wardrobe?.isDefault != true) ? wardrobe : nil,
                        preselectedItemURI: uri,
                        sessionID: createOutfitSessionID
                    )
                    .id(createOutfitSessionID)
                    .onAppear {
                        print("🧭 [ItemDetailView] OutfitAddView appeared; resetting createOutfitNavigation to nil.")
                        createOutfitNavigation = nil
                    }
                }
                .navigationDestination(item: $selectedPairedItemForNavigation) { pairedItem in
                    ItemDetailView(item: pairedItem, isReadOnly: isReadOnly)
                        .onAppear {
                            let uri = pairedItem.objectID.uriRepresentation().absoluteString
                            print("🧭 [ItemDetailView] Paired ItemDetailView appeared; resetting selectedPairedItemForNavigation to nil. pairedItemURI=\(uri)")
                            selectedPairedItemForNavigation = nil
                        }
                }
                .navigationDestination(item: $selectedOutfitURIForNavigation) { uriString in
                    Group {
                        if let url = URL(string: uriString),
                           let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
                           let outfit = try? viewContext.existingObject(with: objectID) as? Outfit {
                            OutfitDetailView(
                                outfit: outfit,
                                isReadOnly: isReadOnly,
                                initialWardrobe: preferredWardrobeForNewOutfit,
                                lockWardrobeSource: preferredWardrobeForNewOutfit?.isDefault != true
                            )
                                .id(outfit.objectID)
                                .onAppear {
                                    print("🧭 [ItemDetailView] OutfitDetailView appeared; resetting selectedOutfitURIForNavigation to nil. outfitURI=\(uriString)")
                                    selectedOutfitURIForNavigation = nil
                                }
                        } else {
                            EmptyView()
                                .onAppear {
                                    print("❌ [ItemDetailView] Failed to resolve outfit for navigation. uri=\(uriString)")
                                    selectedOutfitURIForNavigation = nil
                                }
                        }
                    }
                }
        }
    }

    private var itemDetailMainContent: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                List {
                    // Image Gallery Section
                    Section {
                        // Large primary image display
                        itemImageDisplay()
                        
                        // Row of 3 square images
                        // imageThumbnailRow()

                        SocialEngagementActionsRow(
                            segmentSelection: Binding(
                                get: { heroCarouselPage == 0 ? .tshirt : .worn },
                                set: { segment in
                                    withAnimation {
                                        heroCarouselPage = segment == .tshirt ? 0 : 1
                                        selectedImageType = segment == .tshirt ? .front : .worn
                                    }
                                    _ = item.photos
                                }
                            ),
                            favoriteSelection: isViewingOwnContent ? item.isFavorite : isLikedByMe,
                            likeCount: isReadOnly ? likeCount : nil,
                            calendarCount: showsCalendarActions
                                ? itemPastWornEventCount
                                : nil,
                            showsLikeButton: true,
                            isLikeInteractive: isReadOnly ? canToggleSocialLike : true,
                            showsCalendarButton: showsCalendarActions,
                            showsShareButton: appCapabilities.enablesFriendsAndSharing,
                            showsMoveToClosetButton: !isReadOnly && appCapabilities.showsWishlistTab && isWishlistItem,
                            showsWornSegment: getImage(for: .worn) != nil || !isReadOnly,
                            onLike: {
                                if isReadOnly {
                                    toggleSocialLike()
                                } else {
                                    withAnimation {
                                        toggleFavorite()
                                    }
                                }
                            },
                            onCalendar: { showWornStatsSheet = true },
                            onShare: { showShareFriendsSheet = true },
                            onMoveToCloset: { showAddToClosetConfirmation = true }
                        )
                    }
                    .listRowInsets(EdgeInsets(.zero))
                    .listRowSeparator(.hidden)
                    .listSectionSpacing(0)
                    
                    
                    // ATTRIBUTES Section
                    if !isReadOnly || AttributesSectionView.hasReadOnlyVisibleContent(for: item) {
                        Section {
                            if isAttributesExpanded {
                                AttributesSectionView(
                                    item: item,
                                    activeSheet: $attributesSheet,
                                    isReadOnly: isReadOnly,
                                    includeLinks: false
                                )
                                    .transition(.opacity.combined(with: .slide))
                                    .listRowInsets(EdgeInsets(top: 05, leading: 20, bottom: 05, trailing: 20))
                            }
                        } header: {
                            HStack {
                                Text("ATTRIBUTES")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: isAttributesExpanded ? "minus" : "plus")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation {
                                    isAttributesExpanded.toggle()
                                }
                            }
                        }
                        .listSectionSpacing(4)
                    }
                    //  .listRowInsets(EdgeInsets(.zero))
                    
                    if !isReadOnly || !pairedItems.isEmpty {
                        Section {
                            if isSetsExpanded {
                                pairsSectionContent
                                    .transition(.opacity.combined(with: .slide))
                            }
                        } header: {
                        HStack {
                            Text("PAIRS")
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: pairsSectionHeaderIconName)
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handlePairsSectionHeaderTap()
                        }
                    }
                    .listRowInsets(EdgeInsets(.zero))
                    .listSectionSpacing(4)
                    .padding(.horizontal)
                    }

                    if !isReadOnly || !outfits.isEmpty {
                        Section {
                        if isOutfitsExpanded {
                            outfitsSectionContent
                                .transition(.opacity.combined(with: .slide))
                        }
                    } header: {
                        Button {
                            handleOutfitsSectionHeaderTap()
                        } label: {
                            HStack {
                                Text("OUTFITS")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: outfitsSectionHeaderIconName)
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowInsets(EdgeInsets(.zero))
                    .listSectionSpacing(4)
                    .padding(.horizontal)
                    }

                    if !isReadOnly || itemLinkCount > 0 {
                        Section {
                            if isLinksExpanded {
                                linksSectionContent
                                    .transition(.opacity.combined(with: .slide))
                            }
                        } header: {
                            Button {
                                handleLinksSectionHeaderTap()
                            } label: {
                                HStack {
                                    Text("LINKS")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: linksSectionHeaderIconName)
                                        .foregroundColor(.gray)
                                        .font(.caption)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowInsets(EdgeInsets(.zero))
                        .listSectionSpacing(4)
                        .padding(.horizontal)
                    }

                    if !isReadOnly || !itemHistoryEntries.isEmpty {
                        Section {
                        if isHistoryExpanded {
                            historyRows
                                .transition(.opacity.combined(with: .slide))
                        }
                        historySectionBottomPad
                    } header: {
                        HStack {
                            Text("HISTORY")
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: historySectionHeaderIconName)
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation {
                                isHistoryExpanded.toggle()
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(.zero))
                    .listSectionSpacing(4)
                    .padding(.horizontal)
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
            }
        }
        .sheet(item: $attributesSheet) { sheet in
            sheet.destination(for: item, isReadOnly: isReadOnly)
                .onDisappear {
                    if sheet == .link, itemLinkCount > 0 {
                        isLinksExpanded = true
                    }
                }
        }
        .onAppear {
            fetchOutfits()
            if !isReadOnly {
                viewContext.refresh(item, mergeChanges: true)
                purgeRetiredBackPhotosIfNeeded()
            }
            // Always land on front first; a pending worn selection re-applies after (and async).
            heroCarouselPage = 0
            selectedImageType = .front
            applyPendingWornHeroSelectionIfNeeded(clearAfterApplying: true)
            if isReadOnly {
                // Match ReadOnlyItemDetailView: attributes expanded; secondary sections collapsed.
                isSetsExpanded = false
                isOutfitsExpanded = false
                isLinksExpanded = false
                isHistoryExpanded = false
            } else {
                isSetsExpanded = !pairedItems.isEmpty
                if outfits.isEmpty {
                    isOutfitsExpanded = false
                }
                isLinksExpanded = itemLinkCount > 0
            }
        }
        .task(id: item.id) {
            guard isReadOnly, let itemId = item.id else { return }
            await refreshSocialLikeState(itemId: itemId)
        }
        .onDisappear {
            guard !isCoveringModalPresented else { return }
            // Attribute sheets save locally on dismiss; push once when leaving detail.
            syncPendingItemChangesIfNeeded()
            pendingSelectWornHero = false
            heroCarouselPage = 0
            selectedImageType = .front
        }
        .onChange(of: scenePhase) { _, phase in
            // Safety net if the app backgrounds before popping detail.
            guard phase == .background else { return }
            syncPendingItemChangesIfNeeded()
        }
        .onChange(of: authSession.userId) { _, _ in
            fetchOutfits()
        }
        .onChange(of: pairedItems.count) { oldCount, newCount in
            if newCount == 0 {
                isSetsExpanded = false
            } else if oldCount == 0 && newCount > 0 {
                isSetsExpanded = true
            }
        }
        .onChange(of: outfits.count) { oldCount, newCount in
            if newCount == 0 {
                isOutfitsExpanded = false
            } else if oldCount == 0 && newCount > 0 {
                isOutfitsExpanded = true
            }
        }
        .onChange(of: itemLinkCount) { oldCount, newCount in
            if newCount == 0 {
                isLinksExpanded = false
            } else if oldCount == 0 && newCount > 0 {
                isLinksExpanded = true
            }
        }
        .toolbar {
            if !isReadOnly {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if getImage(for: .front) != nil {
                        Button {
                            let available = getAvailableAttributes()
                            let defaults = DefaultShareAttributes.load().intersection(available)
                            selectedShareAttributes = defaults.isEmpty ? available : defaults
                            showShareSelectionSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share item")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .accessibilityLabel("Delete item")
                }
            }
        }
    }

    private var itemDetailWithSheets: some View {
        itemDetailMainContent
        .sheet(isPresented: $isImagePickerPresented, onDismiss: {
            applyPendingWornHeroSelectionIfNeeded(clearAfterApplying: false)
        }) {
            ImagePicker(
                image: $selectedUIImage,
                sourceType: $imagePickerSource,
                allowsEditing: true
            ) { image in
                if let newImage = image, let imageType = pendingImageType {
                    switch imageType {
                    case .front:
                        replaceFrontImage(with: newImage)
                    case .worn:
                        replaceWornImage(with: newImage)
                    }
                    pendingImageType = nil
                }
                isImagePickerPresented = false
            }
        }
        .sheet(isPresented: $isCropEditorPresented, onDismiss: {
            applyPendingWornHeroSelectionIfNeeded(clearAfterApplying: false)
            pendingImageType = nil
            imageToEdit = nil
        }) {
            itemImageCropperSheetContent
        }
        .sheet(isPresented: $showShareSelectionSheet, onDismiss: handleShareSelectionSheetDismissed) {
            shareSelectionSheetContent
        }
        .sheet(isPresented: $showWornStatsSheet) {
            ItemWearDetailsSheet(item: item)
        }
    }

    @ViewBuilder
    private var itemImageCropperSheetContent: some View {
        if let image = imageToEdit {
            NavigationView {
                ImageCropperView(
                    originalImage: image,
                    onCrop: { croppedImage in
                        switch pendingImageType {
                        case .front:
                            replaceFrontImage(with: croppedImage)
                        case .worn:
                            replaceWornImage(with: croppedImage)
                        case nil:
                            break
                        }
                        pendingImageType = nil
                        imageToEdit = nil
                        isCropEditorPresented = false
                    },
                    isEditing: true,
                    title: "Edit"
                )
                .id(cropEditorSessionID)
            }
        } else {
            Text("No image found to edit.")
                .padding()
        }
    }

    private var itemDetailWithPresentation: some View {
        itemDetailWithSheets
        .navigationTitle("Item Details")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isImageFullScreen) {
            fullScreenImageView()
        }
        .onChange(of: isImageFullScreen) { _, isOpen in
            if !isOpen {
                syncHeroCarouselWithSelectedImageType()
            }
        }
        .onChange(of: showShareSheet) { _, isShowing in
            if !isShowing {
                isPreparingShareSheet = false
            }
        }
    }

    private var itemDetailWithShareOverlays: some View {
        itemDetailWithPresentation
        .overlay {
            if showShareSheet {
                ActivityViewController(
                    activityItems: shareItems,
                    isPresented: $showShareSheet,
                    onShareSheetPresented: { isPreparingShareSheet = false }
                )
                    .frame(width: 0, height: 0)
            }
        }
        .overlay {
            if isPreparingShareSheet {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                    ProgressView()
                        .controlSize(.large)
                }
                .allowsHitTesting(true)
            }
        }
        .overlay(alignment: .top) {
            if showAddToClosetToast {
                Text(addToClosetToastMessage)
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
    }

    private var itemDetailWithAlerts: some View {
        itemDetailWithShareOverlays
        .alert("Delete Item", isPresented: $showDeleteConfirmation) {
            if outfitCountForItemActions > 0 {
                Button(deleteItemAndOutfitsButtonTitle, role: .destructive) {
                    deleteItemAndOutfits()
                }
            }
            Button(deleteItemOnlyButtonTitle, role: .destructive) {
                deleteItemOnly()
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Deleting this item removes it from all wardrobes. This action cannot be undone.")
        }
        .alert("Remove Photo", isPresented: $showRemoveWornImageConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                deleteImage(type: .worn)
            }
        } message: {
            Text("Remove this worn photo? This action cannot be undone.")
        }
        .alert("Add to Closet?", isPresented: $showAddToClosetConfirmation) {
            if outfitCountForItemActions > 0 {
                Button(addItemAndOutfitsButtonTitle) {
                    addItemAndOutfitsToCloset()
                }
                .keyboardShortcut(.defaultAction)
                Button(addItemOnlyButtonTitle) {
                    addItemOnlyToCloset()
                }
            } else {
                Button(addItemOnlyButtonTitle) {
                    addItemOnlyToCloset()
                }
                .keyboardShortcut(.defaultAction)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This item will be removed from your wishlist and added to your closet.")
        }
        .sheet(isPresented: $showPairItemSelection) {
            PairItemSelectionView(
                item: item,
                pairSourceSegment: $pairSelectionInitialSegment,
                onPairSuccess: { showPairItemSelection = false }
            )
            .id(item.objectID)
        }
        .sheet(isPresented: $showViewAllPairsSheet, onDismiss: handleViewAllPairsSheetDismissed) {
            PairsViewAllSheet(
                sourceItem: item,
                showsWardrobePicker: isWishlistItem,
                initialSegment: viewAllPairsInitialSegment,
                allowsUnpair: !isReadOnly,
                onSelect: { selected in
                    pendingPairedItemForNavigation = selected
                    showViewAllPairsSheet = false
                }
            )
            .id(viewAllPairsInitialSegment)
            .presentationDetents(pairedItems.count > 6 ? [.medium, .large] : [.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showViewAllOutfitsSheet, onDismiss: handleViewAllOutfitsSheetDismissed) {
            NavigationView {
                OutfitsViewAllSheet(
                    outfits: outfits,
                    onCreateOutfit: isReadOnly ? nil : {
                        pendingCreateOutfitAfterSheetDismiss = true
                        showViewAllOutfitsSheet = false
                    },
                    onSelect: { outfit in
                        pendingOutfitForNavigation = outfit
                        showViewAllOutfitsSheet = false
                    }
                )
            }
            .presentationDetents(outfits.count > 6 ? [.medium, .large] : [.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { appCapabilities.enablesFriendsAndSharing && showShareFriendsSheet },
            set: { showShareFriendsSheet = $0 }
        )) {
            if let itemId = item.id {
                ShareItemFriendsSheet(targetId: itemId)
                    .environmentObject(supabaseService)
            } else {
                Text("This item isn’t ready to share yet.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
    
    // MARK: - Edit Button (deprecated, using presentCropperForImage instead)


    // MARK: - Replace Image Functions

    private func configureReplacedPhoto(
        _ newPhoto: Photo,
        with image: UIImage,
        processedData: Data?,
        type: String,
        asPrimary: Bool
    ) {
        ItemPhotoSlot.configureReplacedPhoto(
            newPhoto,
            on: item,
            image: image,
            processedData: processedData,
            type: type,
            asPrimary: asPrimary
        )
    }

    private func replaceFrontImage(with image: UIImage) {
        ItemPhotoSlot.deleteMatching(in: item, slot: "front", context: viewContext)

        let processedData = image.processForStorage()
        let newPhoto = Photo(context: viewContext)
        configureReplacedPhoto(newPhoto, with: image, processedData: processedData, type: "front", asPrimary: true)

        setUpdatedAt(item)

        let outfitsToSync = OutfitSanitizer.regenerateCollagesForOutfitsContaining(item: item, in: viewContext)

        do {
            try viewContext.save()
            print("✅ Replaced front photo.")
            selectedImageType = .front
            heroCarouselPage = 0

            for outfit in outfitsToSync {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }
            SyncService.shared.syncItemPhotosIfNeeded(item)
        } catch {
            print("❌ Failed to save new photo: \(error.localizedDescription)")
        }
    }
    
    private func purgeRetiredBackPhotosIfNeeded() {
        guard ItemPhotoSlot.purgeRetiredBackPhotos(in: item, context: viewContext) else { return }
        setUpdatedAt(item)
        do {
            try viewContext.save()
            SyncService.shared.syncItemPhotosIfNeeded(item)
            print("🧹 Purged retired item back photo(s)")
        } catch {
            print("⚠️ Failed to purge retired back photos: \(error.localizedDescription)")
        }
    }

    private func replaceWornImage(with image: UIImage) {
        ItemPhotoSlot.deleteMatching(in: item, slot: "worn", context: viewContext)

        let processedData = image.processForStorage()
        let newPhoto = Photo(context: viewContext)
        configureReplacedPhoto(newPhoto, with: image, processedData: processedData, type: "worn", asPrimary: false)

        setUpdatedAt(item)

        do {
            try viewContext.save()
            print("✅ Replaced worn photo.")
            pendingSelectWornHero = true
            selectHeroImageSlot(.worn)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard pendingSelectWornHero else { return }
                selectHeroImageSlot(.worn)
                pendingSelectWornHero = false
            }
            SyncService.shared.syncItemPhotosIfNeeded(item)
        } catch {
            print("❌ Failed to save new photo: \(error.localizedDescription)")
        }
    }

    /// Re-selects Worn after a front reset when `pendingSelectWornHero` is set.
    /// - Parameter clearAfterApplying: When true (onAppear), clear the flag on the next turn
    ///   after re-asserting Worn so late resets still lose.
    private func applyPendingWornHeroSelectionIfNeeded(clearAfterApplying: Bool) {
        guard pendingSelectWornHero else { return }
        withAnimation {
            selectHeroImageSlot(.worn)
        }
        guard clearAfterApplying else { return }
        DispatchQueue.main.async {
            guard pendingSelectWornHero else { return }
            withAnimation {
                selectHeroImageSlot(.worn)
            }
            pendingSelectWornHero = false
        }
    }

    /// Sheets / covers that can re-fire `onAppear` without leaving the detail screen.
    private var isCoveringModalPresented: Bool {
        isImagePickerPresented
            || isCropEditorPresented
            || isImageFullScreen
            || showShareSelectionSheet
            || showWornStatsSheet
            || showPairItemSelection
            || showViewAllPairsSheet
            || showViewAllOutfitsSheet
            || attributesSheet != nil
    }

    /// Attribute edits persist locally on sheet dismiss; cloud sync is deferred here.
    private func syncPendingItemChangesIfNeeded() {
        guard !isReadOnly else { return }
        SyncService.shared.syncItemIfNeeded(item)
    }

    private func deleteImage(type: ImageType) {
        let slot: String
        switch type {
        case .front: slot = "front"
        case .worn: slot = "worn"
        }
        let before = (item.photos as? Set<Photo>) ?? []
        guard !ItemPhotoSlot.photosMatching(before, slot: slot).isEmpty else { return }

        ItemPhotoSlot.deleteMatching(in: item, slot: slot, context: viewContext)

        setUpdatedAt(item)

        let outfitsToSync = OutfitSanitizer.regenerateCollagesForOutfitsContaining(item: item, in: viewContext)

        do {
            try viewContext.save()
            print("✅ Deleted \(placeholderText(for: type)) photo.")
            if selectedImageType == type {
                selectedImageType = .front
                heroCarouselPage = 0
            }

            for outfit in outfitsToSync {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }
            SyncService.shared.syncItemPhotosIfNeeded(item)
        } catch {
            print("❌ Failed to delete photo: \(error.localizedDescription)")
        }
    }


    // MARK: - Image Display
    
    /// Order matches `ItemFullScreenView` pager: only slots that have an image.
    private func orderedAvailableImageTypes(front: UIImage?, worn: UIImage?) -> [ImageType] {
        var types: [ImageType] = []
        if front != nil { types.append(.front) }
        if worn != nil { types.append(.worn) }
        return types
    }
    
    private func fullscreenPageIndex(for imageType: ImageType, front: UIImage?, worn: UIImage?) -> Int {
        let order = orderedAvailableImageTypes(front: front, worn: worn)
        return order.firstIndex(of: imageType) ?? 0
    }
    
    private func imageType(forFullscreenPageIndex index: Int, front: UIImage?, worn: UIImage?) -> ImageType {
        let order = orderedAvailableImageTypes(front: front, worn: worn)
        guard !order.isEmpty else { return .front }
        let clamped = min(max(0, index), order.count - 1)
        return order[clamped]
    }
    
    private func fullscreenSelectedPageIndexBinding(frontImage: UIImage?, wornImage: UIImage?) -> Binding<Int> {
        Binding(
            get: { self.fullscreenPageIndex(for: self.selectedImageType, front: frontImage, worn: wornImage) },
            set: { newIndex in
                let newType = self.imageType(forFullscreenPageIndex: newIndex, front: frontImage, worn: wornImage)
                if self.selectedImageType != newType {
                    self.selectedImageType = newType
                    _ = self.item.photos
                }
            }
        )
    }
    
    private func fullScreenImageView() -> some View {
        let frontImage = getImage(for: .front)
        let wornImage = getImage(for: .worn)
        
        return ItemFullScreenView(
            frontImage: frontImage,
            wornImage: wornImage,
            selectedPageIndex: fullscreenSelectedPageIndexBinding(frontImage: frontImage, wornImage: wornImage),
            isPresented: $isImageFullScreen
        )
    }
    
    private var screenWidth: CGFloat { UIScreen.main.bounds.width }

    private func itemImageDisplay() -> some View {
        let frontImage = getImage(for: .front)
        let wornImage = getImage(for: .worn)
        let allowsHeroSwipe = !isReadOnly || wornImage != nil

        return ZStack(alignment: .topTrailing) {
            Group {
                if allowsHeroSwipe {
                    TabView(selection: $heroCarouselPage) {
                        Group {
                            if let uiImage = frontImage {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: screenWidth, height: screenWidth)
                                    .clipped()
                                    .onTapGesture { isImageFullScreen = true }
                            } else {
                                heroImagePlaceholder(for: .front)
                            }
                        }
                        .tag(0)

                        Group {
                            if let uiImage = wornImage {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: screenWidth, height: screenWidth)
                                    .clipped()
                                    .onTapGesture { isImageFullScreen = true }
                            } else {
                                heroImagePlaceholder(for: .worn)
                            }
                        }
                        .tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                } else {
                    Group {
                        if let uiImage = frontImage {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: screenWidth, height: screenWidth)
                                .clipped()
                                .onTapGesture { isImageFullScreen = true }
                        } else {
                            heroImagePlaceholder(for: .front)
                        }
                    }
                }
            }
            .frame(width: screenWidth, height: screenWidth)

            if heroCarouselPage == 0, frontImage != nil, !isReadOnly {
                heroDisplayAreaOptionsButton
            } else if heroCarouselPage == 1, wornImage != nil, !isReadOnly {
                heroDisplayAreaOptionsButton
            }
        }
        .frame(width: screenWidth, height: screenWidth)
        .onChange(of: heroCarouselPage) { _, newPage in
            selectedImageType = newPage == 0 ? .front : .worn
            _ = item.photos
        }
        .confirmationDialog("Photo", isPresented: $showHeroDisplayOptionsDialog, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Retake Photo") {
                    pendingImageType = selectedImageType
                    selectHeroImageSlot(selectedImageType)
                    imagePickerSource = .camera
                    isImagePickerPresented = true
                }
            }
            Button("Replace from Library") {
                pendingImageType = selectedImageType
                selectHeroImageSlot(selectedImageType)
                imagePickerSource = .photoLibrary
                isImagePickerPresented = true
            }
            if getImage(for: selectedImageType) != nil {
                Button("Edit Image") {
                    presentCropperForImage(type: selectedImageType)
                }
                Button("Share Image") {
                    beginShareImage(type: selectedImageType)
                }
            }
            if selectedImageType == .worn, getImage(for: .worn) != nil {
                Button("Remove Image", role: .destructive) {
                    DispatchQueue.main.async {
                        showRemoveWornImageConfirmation = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Top-trailing control on the hero image area.
    private var heroDisplayAreaOptionsButton: some View {
        Button {
            showHeroDisplayOptionsDialog = true
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(12)
        .accessibilityLabel("More options")
    }

    private func heroImagePlaceholder(for type: ImageType) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: screenWidth, height: screenWidth)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: heroPlaceholderSystemImage(for: type))
                        .foregroundStyle(.secondary)
                        .font(.system(size: 40))
                    Text(heroPlaceholderMessage(for: type))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isReadOnly else { return }
                presentImagePicker(for: type)
            }
    }

    private func heroPlaceholderSystemImage(for type: ImageType) -> String {
        switch type {
        case .worn:
            return "person.crop.square.badge.camera"
        case .front:
            return "photo"
        }
    }

    private func heroPlaceholderMessage(for type: ImageType) -> String {
        switch type {
        case .front:
            return "Tap to add a photo of the front of the item"
        case .worn:
            return isReadOnly
                ? "No image available"
                : "Tap to add a photo of you wearing this item"
        }
    }
    
    private func shareActiveImage() {
        beginShareImage(type: selectedImageType)
    }

    @ViewBuilder
    private var shareSelectionSheetContent: some View {
        if let frontImage = getImage(for: .front) {
            ShareSelectionView(
                item: item,
                selectedAttributes: $selectedShareAttributes,
                onShare: { shareText in
                    pendingShareText = shareText
                    pendingShareImage = frontImage
                    showShareSelectionSheet = false
                }
            )
        }
    }

    private func handleShareSelectionSheetDismissed() {
        guard let image = pendingShareImage else { return }

        if let shareText = pendingShareText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !shareText.isEmpty {
            shareItems = [shareText, image]
        } else {
            shareItems = [image]
        }
        pendingShareText = nil
        pendingShareImage = nil
        presentShareSheetAfterSelectionSheetDismissed()
    }

    private func presentShareSheetAfterSelectionSheetDismissed() {
        isPreparingShareSheet = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            showShareSheet = true
        }
    }

    private func beginShareImage(type: ImageType, afterConfirmationDialog: Bool = true) {
        guard getImage(for: type) != nil else { return }
        isPreparingShareSheet = true
        if afterConfirmationDialog {
            showHeroDisplayOptionsDialog = false
        }
        let delayNanoseconds: UInt64 = afterConfirmationDialog ? 350_000_000 : 0
        Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            presentShareImage(type: type)
        }
    }

    private func presentShareImage(type: ImageType) {
        let image = getImage(for: type)
        if let image = image {
            // Create share text: item name, or brand + category if name is nil
            var shareText: String?
            
            if let name = item.name, !name.isEmpty {
                shareText = name
            } else {
                var components: [String] = []
                if let brandName = item.brand?.name, !brandName.isEmpty {
                    components.append(brandName)
                }
                if let categoryName = item.category?.name, !categoryName.isEmpty {
                    if let subcategoryName = item.subcategory?.name, !subcategoryName.isEmpty {
                        components.append("\(categoryName) • \(subcategoryName)")
                    } else {
                        components.append(categoryName)
                    }
                }
                if !components.isEmpty {
                    shareText = components.joined(separator: " ")
                }
            }
            
            // Add text and image to share items
            if let text = shareText {
                shareItems = [text, image]
            } else {
                shareItems = [image]
            }
            showShareSheet = true
        } else {
            isPreparingShareSheet = false
        }
    }
    
    private func imageThumbnailRow() -> some View {
        let size: CGFloat = (UIScreen.main.bounds.width - 4) / 2
        
        return HStack(spacing: 2) {
            thumbnailMenu(for: .front) {
                imageThumbnail(type: .front, image: getImage(for: .front), size: size)
                    .contentShape(Rectangle())
            }
            thumbnailMenu(for: .worn) {
                imageThumbnail(type: .worn, image: getImage(for: .worn), size: size)
                    .contentShape(Rectangle())
            }
        }
    }
    
    private func imageThumbnail(type: ImageType, image: UIImage?, size: CGFloat) -> some View {
        let isSelected = selectedImageType == type
        
        return ZStack {
            if let uiImage = image {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
                    .overlay(
                        Rectangle()
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // If already selected, show action sheet; otherwise select it
                        if selectedImageType == type {
                            showThumbnailActionSheet(for: type)
                        } else {
                            withAnimation {
                                selectedImageType = type
                            }
                            syncHeroCarouselWithSelectedImageType()
                            // Ensure photos relationship is loaded when switching images
                            _ = item.photos
                        }
                    }
                
            } else {
                // Placeholder with text
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                                .foregroundColor(.gray.opacity(0.5))
                                .font(.system(size: 20))
                            Text(placeholderText(for: type))
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.7))
                        }
                    )
                    .overlay(
                        Rectangle()
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                    )
                    .onTapGesture {
                        // If no image, open image picker
                        presentImagePicker(for: type)
                    }
                    .contentShape(Rectangle())
            }
        }
    }
    
    private func thumbnailMenu<Content: View>(for type: ImageType, @ViewBuilder content: () -> Content) -> some View {
        content()
    }
    
    private func placeholderText(for type: ImageType) -> String {
        switch type {
        case .front:
            return "Front"
        case .worn:
            return "Worn"
        }
    }
    
    private func showThumbnailActionSheet(for type: ImageType) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        // Camera option
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: "Retake Photo", style: .default) { _ in
                pendingImageType = type
                imagePickerSource = .camera
                isImagePickerPresented = true
            })
        }
        
        // Replace from library
        alert.addAction(UIAlertAction(title: "Replace from Library", style: .default) { _ in
            pendingImageType = type
            imagePickerSource = .photoLibrary
            isImagePickerPresented = true
        })
        
        // Edit option (only if image exists)
        if getImage(for: type) != nil {
            alert.addAction(UIAlertAction(title: "Edit Image", style: .default) { _ in
                presentCropperForImage(type: type)
            })
            
            // Share Image option (only if image exists)
            alert.addAction(UIAlertAction(title: "Share Image", style: .default) { _ in
                beginShareImage(type: type, afterConfirmationDialog: false)
            })
        }
        
        // Remove Image option (worn only — front is required)
        if type == .worn && getImage(for: .worn) != nil {
            alert.addAction(UIAlertAction(title: "Remove Image", style: .destructive) { _ in
                DispatchQueue.main.async {
                    showRemoveWornImageConfirmation = true
                }
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            // For iPad
            if let popover = alert.popoverPresentationController {
                popover.sourceView = rootViewController.view
                popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func presentImagePicker(for type: ImageType) {
        pendingImageType = type
        selectHeroImageSlot(type)

        // Show action sheet to choose camera or library
        let alert = UIAlertController(title: "Add \(placeholderText(for: type)) Photo", message: nil, preferredStyle: .actionSheet)
        
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: "Take Photo", style: .default) { _ in
                imagePickerSource = .camera
                isImagePickerPresented = true
            })
        }
        
        alert.addAction(UIAlertAction(title: "Choose from Library", style: .default) { _ in
            imagePickerSource = .photoLibrary
            isImagePickerPresented = true
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            pendingImageType = nil
        })
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            // For iPad
            if let popover = alert.popoverPresentationController {
                popover.sourceView = rootViewController.view
                popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func presentCropperForImage(type: ImageType) {
        viewContext.refresh(item, mergeChanges: true)

        guard let image = getImage(for: type) else { return }
        pendingImageType = type
        imageToEdit = image
        cropEditorSessionID = UUID()
        // Let the photo confirmation dialog finish dismissing before presenting the sheet.
        DispatchQueue.main.async {
            isCropEditorPresented = true
        }
    }

    // MARK: - History

    private struct ItemHistoryEntry: Identifiable {
        let id: String
        let label: String
        let date: Date
        let caption: String?
        /// When set, the row shows "Worn to" plus this name (truncated).
        let eventName: String?
    }

    private var displayWishedDate: Date? {
        if let wishedAt = item.wishedAt { return wishedAt }
        guard isWishlistItem else { return nil }
        return item.createdAt ?? item.timestamp
    }

    private var displayPurchasedDate: Date? {
        if let purchasedAt = item.purchasedAt { return purchasedAt }
        guard !isWishlistItem else { return nil }
        return item.createdAt ?? item.timestamp
    }

    private var itemHistoryEntries: [ItemHistoryEntry] {
        var entries: [ItemHistoryEntry] = []

        if let date = displayWishedDate {
            entries.append(ItemHistoryEntry(id: "wishlist", label: "Added to Wishlist", date: date, caption: nil, eventName: nil))
        }
        if let date = displayPurchasedDate {
            entries.append(ItemHistoryEntry(id: "closet", label: "Added to Closet", date: date, caption: nil, eventName: nil))
        }

        for event in pastWornEvents(for: item) {
            guard let sortDate = eventEffectiveEndDate(event) else { continue }
            let entryID = event.id?.uuidString ?? String(ObjectIdentifier(event).hashValue)
            let trimmedName = event.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            entries.append(ItemHistoryEntry(
                id: "event-\(entryID)",
                label: wornEventHistoryLabel(for: event),
                date: sortDate,
                caption: wornEventHistoryLocationCaption(for: event),
                eventName: trimmedName.isEmpty ? "Event" : trimmedName
            ))
        }

        return entries.sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private var historyRows: some View {
        ForEach(itemHistoryEntries) { entry in
            historyDateRow(
                label: entry.label,
                date: entry.date,
                caption: entry.caption,
                eventName: entry.eventName
            )
        }
    }

    private func historyDateRow(label: String, date: Date, caption: String? = nil, eventName: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                historyRowLabel(label: label, eventName: eventName)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.leading, 12)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Text(date, style: .date)
                .foregroundColor(.gray)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private func historyRowLabel(label: String, eventName: String?) -> some View {
        if let eventName {
            HStack(spacing: 0) {
                Text("Worn to ")
                Text(eventName)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundColor(.gray)
        } else {
            Text(label)
                .foregroundColor(.gray)
        }
    }

    // MARK: - Helper Functions
    
    private func getImage(for type: ImageType) -> UIImage? {
        // Ensure we have the latest photos by accessing the relationship
        // Force fault loading by accessing the relationship and converting to array
        guard let photosSet = item.photos as? Set<Photo> else {
            return nil
        }
        // Convert to array to ensure all faults are loaded
        let photos = Array(photosSet)
        
        // Also ensure each photo's data is loaded by accessing the type property
        // This helps with Core Data faulting
        _ = photos.compactMap { $0.type }
        
        switch type {
        case .front:
            // Look for type="front" first, then fall back to isPrimary (for backward compatibility)
            if let frontPhoto = photos.first(where: {
                ($0.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "front"
            }) {
                return UIImage(data: frontPhoto.data ?? Data())
            } else if let primaryPhoto = photos.first(where: {
                $0.isPrimary && ($0.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                    return UIImage(data: primaryPhoto.data ?? Data())
                }
                return nil
        case .worn:
            if let wornPhoto = photos.first(where: { $0.type == "worn" }) {
                return UIImage(data: wornPhoto.data ?? Data())
            }
            return nil
        }
    }
    
    // MARK: - Header Image (deprecated, keeping for reference)

    private func itemImageHeader() -> some View {
        ZStack {
            // Get front photo data if available
            let displayImage = getImage(for: .front)
            
            if let uiImage = displayImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .onTapGesture { isImageFullScreen = true }
                   /* .background(LinearGradient(colors: [.white, .gray.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomLeading))*/
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.gray)
                    .clipped()
                   /* .background(LinearGradient(colors: [.white, .gray.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomLeading))*/
            }

        }
    }

    
    // MARK: - Add to Closet (wishlist items)

    private var addItemAndOutfitsButtonTitle: String {
        let count = outfitCountForItemActions
        return "Add Item + \(count) Outfit\(count == 1 ? "" : "s")"
    }

    /// Removes wishlist wardrobe links and attaches the user's primary closet wardrobe.
    private func applyAddItemToClosetWardrobes() -> Bool {
        guard let closetWardrobe = fetchWardrobe(type: "closet") else { return false }

        let wardrobes = item.wardrobes as? Set<Wardrobe> ?? []
        for wardrobe in wardrobes where wardrobe.type?.lowercased() == "wishlist" {
            item.removeFromWardrobes(wardrobe)
        }
        item.addToWardrobes(closetWardrobe)

        ItemLifecycleDates.stampPurchasedOnMoveToCloset(for: item)
        setUpdatedAt(item)
        return true
    }

    /// Keeps the item in all containing outfits; outfit tabs rebucket by item wardrobes after save.
    private func addItemAndOutfitsToCloset() {
        guard applyAddItemToClosetWardrobes() else { return }

        do {
            try viewContext.save()
            SyncService.shared.syncItemIfNeeded(item)
            fetchOutfits()
            showAddToClosetToast(message: "Added to closet.")
        } catch {
            print("Failed to add item to closet: \(error)")
        }
    }

    /// Adds the item to closet and removes it from every outfit (including drafts).
    private func addItemOnlyToCloset() {
        guard applyAddItemToClosetWardrobes() else { return }

        let sanitizerResult = OutfitSanitizer.sanitizeOutfitsAfterDeleting(deletedItems: [item], in: viewContext)
        let removedFromOutfitsCount = sanitizerResult.affectedOutfits.count

        do {
            try viewContext.save()
            SyncService.shared.syncItemIfNeeded(item)
            for outfit in sanitizerResult.affectedOutfits {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }
            let message: String
            if removedFromOutfitsCount == 0 {
                message = "Added to closet."
            } else {
                message = "Added to closet. Removed from \(removedFromOutfitsCount) outfit\(removedFromOutfitsCount == 1 ? "" : "s")."
            }
            fetchOutfits()
            showAddToClosetToast(message: message)
        } catch {
            print("Failed to add item to closet: \(error)")
        }
    }

    private func showAddToClosetToast(message: String) {
        addToClosetToastMessage = message
        withAnimation(.easeInOut(duration: 0.18)) {
            showAddToClosetToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeInOut(duration: 0.22)) {
                showAddToClosetToast = false
            }
        }
    }

    
    private func fetchWardrobe(type: String) -> Wardrobe? {
        guard let uid = effectiveReferenceDataUserId(
            signedInUserId: authSession.userId,
            entityUserId: item.userId
        ) else { return nil }
        return try? WardrobeBootstrap.fetchPrimaryWardrobe(forType: type, userIdString: uid, in: viewContext)
    }
    
    private func fetchOutfits() {
        guard !item.objectID.isTemporaryID else {
            outfits = []
            return
        }

        guard let userId = effectiveReferenceDataUserId(
            signedInUserId: authSession.userId,
            entityUserId: item.userId
        ), !userId.isEmpty else {
            outfits = []
            return
        }

        let request: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "ANY items == %@", item),
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "isDraft != YES"),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        ])
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Outfit.createdAt, ascending: false)]

        do {
            let fetched = try viewContext.fetch(request)
            outfits = fetched
            Task { await excludePendingRedressSuggestions(from: fetched) }
        } catch {
            print("❌ Failed to fetch outfits: \(error.localizedDescription)")
            outfits = []
        }
    }

    /// Hides still-pending Redress suggestions from the outfits section (same rule as ItemGridView).
    @MainActor
    private func excludePendingRedressSuggestions(from fetched: [Outfit]) async {
        guard appCapabilities.enablesFriendsAndSharing else { return }
        let pendingIds = await pendingRedressSuggestionIdsForItem()
        guard !pendingIds.isEmpty else { return }
        outfits = fetched.filter { outfit in
            guard let outfitId = outfit.id else { return true }
            return !pendingIds.contains(outfitId)
        }
    }

    private func pendingRedressSuggestionIdsForItem() async -> Set<UUID> {
        let wardrobeIds = ((item.wardrobes as? Set<Wardrobe>) ?? []).compactMap(\.id)
        guard !wardrobeIds.isEmpty else { return [] }

        var pendingIds = Set<UUID>()
        for wardrobeId in wardrobeIds {
            if let suggestions = try? await supabaseService.fetchRecipientOutfitSuggestions(
                wardrobeId: wardrobeId
            ) {
                pendingIds.formUnion(suggestions.map(\.id))
            }
        }
        return pendingIds
    }
    
    
    func toggleFavorite() {
        item.isFavorite.toggle()
        
        // Set updatedAt on item since we're modifying it
        setUpdatedAt(item)
        
        do {
            try viewContext.save()
        } catch {
            print("Failed to toggle favorite: \(error.localizedDescription)")
        }
    }

    private var canToggleSocialLike: Bool {
        guard isReadOnly, !isLikeBusy, let viewerId = authSession.userId else { return false }
        let ownerId = item.userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !ownerId.isEmpty, let ownerUUID = UUID(uuidString: ownerId) else { return false }
        return viewerId != ownerUUID
    }

    /// Owner viewing their own item (Closet editable or Profile read-only).
    private var isViewingOwnContent: Bool {
        if !isReadOnly { return true }
        guard let viewerId = authSession.userId else { return false }
        let ownerId = item.userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let ownerUUID = UUID(uuidString: ownerId) else { return false }
        return viewerId == ownerUUID
    }

    private func refreshSocialLikeState(itemId: UUID) async {
        do {
            let state = try await supabaseService.fetchContentLikeState(targetType: .item, targetId: itemId)
            likeCount = state.likeCount
            isLikedByMe = state.likedByMe
        } catch {}
    }

    private func toggleSocialLike() {
        guard canToggleSocialLike, let itemId = item.id else { return }
        isLikeBusy = true
        let previousCount = likeCount
        let previousLiked = isLikedByMe
        if isLikedByMe {
            isLikedByMe = false
            likeCount = max(0, likeCount - 1)
        } else {
            isLikedByMe = true
            likeCount += 1
        }
        Task {
            defer { isLikeBusy = false }
            do {
                let state = try await supabaseService.toggleContentLike(targetType: .item, targetId: itemId)
                likeCount = state.likeCount
                isLikedByMe = state.likedByMe
            } catch {
                likeCount = previousCount
                isLikedByMe = previousLiked
            }
        }
    }
    
    private var outfitCountForItemActions: Int {
        outfitsContainingItem(includeDrafts: true).count
    }

    private var deleteItemAndOutfitsButtonTitle: String {
        let count = outfitCountForItemActions
        return "Delete Item + \(count) Outfit\(count == 1 ? "" : "s")"
    }

    private var deleteItemOnlyButtonTitle: String {
        outfitCountForItemActions > 0 ? "Delete Item Only" : "Delete Item"
    }

    private var addItemOnlyButtonTitle: String {
        outfitCountForItemActions > 0 ? "Add Item Only" : "Add Item"
    }

    private func outfitsContainingItem(includeDrafts: Bool) -> [Outfit] {
        guard !item.objectID.isTemporaryID else { return [] }

        guard let userId = effectiveReferenceDataUserId(
            signedInUserId: authSession.userId,
            entityUserId: item.userId
        ), !userId.isEmpty else {
            return []
        }

        var subpredicates: [NSPredicate] = [
            NSPredicate(format: "ANY items == %@", item),
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil"),
        ]
        if !includeDrafts {
            subpredicates.append(NSPredicate(format: "isDraft != YES"))
        }

        let request: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)

        do {
            return try viewContext.fetch(request)
        } catch {
            print("❌ Failed to fetch outfits containing item: \(error.localizedDescription)")
            return []
        }
    }

    private func sanitizePairsBeforeDeletingItem() -> Set<Item> {
        let paired = (item.pairedItems as? Set<Item>) ?? []
        var modifiedPairedItems: Set<Item> = []
        for other in paired {
            var othersPairs = (other.pairedItems as? Set<Item>) ?? []
            if othersPairs.remove(item) != nil {
                other.pairedItems = othersPairs as NSSet
                setUpdatedAt(other)
                modifiedPairedItems.insert(other)
            }
        }
        if !paired.isEmpty {
            item.pairedItems = NSSet()
            setUpdatedAt(item)
        }
        return modifiedPairedItems
    }

    private func deleteItemOnly() {
        let itemBrand = item.brand

        let sanitizerResult = OutfitSanitizer.sanitizeOutfitsAfterDeleting(deletedItems: [item], in: viewContext)
        let removedFromOutfitsCount = sanitizerResult.affectedOutfits.count

        let modifiedPairedItems = sanitizePairsBeforeDeletingItem()

        softDelete(item)

        do {
            try viewContext.save()

            SyncService.shared.syncItemIfNeeded(item)

            for pairedItem in modifiedPairedItems {
                SyncService.shared.syncItemIfNeeded(pairedItem)
            }

            for outfit in sanitizerResult.affectedOutfits {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }

            NotificationCenter.default.post(
                name: Notification.Name("Closet.ItemDeletionToast"),
                object: nil,
                userInfo: [
                    "message": "Deleted item. Removed from \(removedFromOutfitsCount) outfit\(removedFromOutfitsCount == 1 ? "" : "s")."
                ]
            )

            if let brand = itemBrand {
                cleanupBrandIfOrphaned(brand)
            }

            dismiss()
        } catch {
            print("Failed to delete item: \(error.localizedDescription)")
        }
    }

    private func deleteItemAndOutfits() {
        let itemBrand = item.brand
        let outfitsToDelete = outfitsContainingItem(includeDrafts: true)
        let deletedOutfitsCount = outfitsToDelete.count

        for outfit in outfitsToDelete {
            softDelete(outfit)
        }

        let modifiedPairedItems = sanitizePairsBeforeDeletingItem()

        softDelete(item)

        do {
            try viewContext.save()

            SyncService.shared.syncItemIfNeeded(item)

            for pairedItem in modifiedPairedItems {
                SyncService.shared.syncItemIfNeeded(pairedItem)
            }

            for outfit in outfitsToDelete {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }

            let message: String
            if deletedOutfitsCount == 0 {
                message = "Deleted item."
            } else {
                message = "Deleted item and \(deletedOutfitsCount) outfit\(deletedOutfitsCount == 1 ? "" : "s")."
            }

            NotificationCenter.default.post(
                name: Notification.Name("Closet.ItemDeletionToast"),
                object: nil,
                userInfo: ["message": message]
            )

            if let brand = itemBrand {
                cleanupBrandIfOrphaned(brand)
            }

            dismiss()
        } catch {
            print("Failed to delete item and outfits: \(error.localizedDescription)")
        }
    }

    // Outfit sanitation for delete-item-only is handled by `OutfitSanitizer`.
    
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
    
    private func SearchWithGoogleLens() {
        guard let image = getImage(for: .front) else {
            print("❌ No front image found")
            return
        }
        
        // Save image to temporary directory
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = "lens_search_\(UUID().uuidString).jpg"
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            print("❌ Failed to convert image to JPEG")
            return
        }
        
        do {
            try jpegData.write(to: fileURL)
            
            // Try Google app first, then fall back to browser
            if let googleLensURL = URL(string: "googleapp://lens") {
                if UIApplication.shared.canOpenURL(googleLensURL) {
                    // Copy image to pasteboard so Google Lens can access it
                    UIPasteboard.general.image = image
                    UIApplication.shared.open(googleLensURL)
                } else {
                    // Fallback: Open Google Lens web version
                    openGoogleLensWeb(with: image)
                }
            }
        } catch {
            print("❌ Failed to save image: \(error.localizedDescription)")
        }
    }
    
    private func openGoogleLensWeb(with image: UIImage) {
        // Copy image to pasteboard for potential paste
        UIPasteboard.general.image = image
        
        // Open Google Lens web interface
        if let url = URL(string: "https://lens.google.com/") {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Share Functions
    private func getAvailableAttributes() -> Set<ShareableAttribute> {
        var available: Set<ShareableAttribute> = []
        
        if let name = item.name, !name.isEmpty {
            available.insert(.name)
        }
        if item.category != nil {
            available.insert(.category)
        }
        if item.brand != nil {
            available.insert(.brand)
        }
        if item.itemSize != nil {
            available.insert(.size)
        }
        if let colors = item.colors as? Set<AppColor>, !colors.isEmpty {
            available.insert(.color)
        }
        if let seasons = item.seasons as? Set<Season>, !seasons.isEmpty {
            available.insert(.season)
        }
        if let location = item.location?.name, !location.isEmpty {
            available.insert(.location)
        }
        if item.price != nil {
            available.insert(.price)
        }
        // Use primitiveValue to properly check optional scalar types
        if appCapabilities.showsWeatherAttribute,
           item.primitiveValue(forKey: "minTemperature") != nil,
           item.primitiveValue(forKey: "maxTemperature") != nil {
            available.insert(.weather)
        }
        if appCapabilities.showsWeightAttribute,
           item.primitiveValue(forKey: "weight") != nil {
            available.insert(.weight)
        }
        if let links = item.links as? Set<Link>, !links.isEmpty {
            available.insert(.link)
        }
        if let tags = item.tags as? Set<Tag>, !tags.isEmpty {
            available.insert(.tag)
        }
        if let notes = item.notes, !notes.isEmpty {
            available.insert(.notes)
        }
        
        return available
    }
}

// MARK: - ShareableAttribute Enum
enum ShareableAttribute: String, CaseIterable, Identifiable {
    case name
    case category
    case brand
    case size
    case color
    case season
    case location
    case price
    case weather
    case weight
    case link
    case tag
    case notes
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .name: return "Name"
        case .category: return "Category"
        case .brand: return "Brand"
        case .size: return "Size"
        case .color: return "Colors"
        case .season: return "Seasons"
        case .location: return "Location"
        case .price: return "Price"
        case .weather: return "Weather"
        case .weight: return "Weight"
        case .link: return "Links"
        case .tag: return "Tags"
        case .notes: return "Notes"
        }
    }
}

// MARK: - Default Share Attributes
private struct DefaultShareAttributes {
    private static let userDefaultsKey = "defaultShareAttributes"
    
    static func save(_ attributes: Set<ShareableAttribute>) {
        let attributeStrings = attributes.map { $0.rawValue }
        UserDefaults.standard.set(attributeStrings, forKey: userDefaultsKey)
    }
    
    static func load() -> Set<ShareableAttribute> {
        guard let attributeStrings = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] else {
            return []
        }
        return Set(attributeStrings.compactMap { ShareableAttribute(rawValue: $0) })
    }
    
    static func hasDefaults() -> Bool {
        return UserDefaults.standard.array(forKey: userDefaultsKey) != nil
    }
}

// MARK: - ShareSelectionView
struct ShareSelectionView: View {
    @ObservedObject var item: Item
    @Binding var selectedAttributes: Set<ShareableAttribute>
    let onShare: (String?) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appCapabilities) private var appCapabilities
    
    private let currencySymbol = Locale.current.currencySymbol ?? "$"
    
    var availableAttributes: Set<ShareableAttribute> {
        var available: Set<ShareableAttribute> = []
        
        if let name = item.name, !name.isEmpty {
            available.insert(.name)
        }
        if item.category != nil {
            available.insert(.category)
        }
        if item.brand != nil {
            available.insert(.brand)
        }
        if item.itemSize != nil {
            available.insert(.size)
        }
        if let colors = item.colors as? Set<AppColor>, !colors.isEmpty {
            available.insert(.color)
        }
        if let seasons = item.seasons as? Set<Season>, !seasons.isEmpty {
            available.insert(.season)
        }
        if let location = item.location?.name, !location.isEmpty {
            available.insert(.location)
        }
        if item.price != nil {
            available.insert(.price)
        }
        // Use primitiveValue to properly check optional scalar types
        if appCapabilities.showsWeatherAttribute,
           item.primitiveValue(forKey: "minTemperature") != nil,
           item.primitiveValue(forKey: "maxTemperature") != nil {
            available.insert(.weather)
        }
        if appCapabilities.showsWeightAttribute,
           item.primitiveValue(forKey: "weight") != nil {
            available.insert(.weight)
        }
        if let links = item.links as? Set<Link>, !links.isEmpty {
            available.insert(.link)
        }
        if let tags = item.tags as? Set<Tag>, !tags.isEmpty {
            available.insert(.tag)
        }
        if let notes = item.notes, !notes.isEmpty {
            available.insert(.notes)
        }
        
        return available
    }
    
    var allSelected: Bool {
        !availableAttributes.isEmpty && availableAttributes.isSubset(of: selectedAttributes)
    }

    /// Image + a custom attribute mix (not empty, not all, not the saved default preset).
    private var isCustomSelectedAttributes: Bool {
        !selectedAttributes.isEmpty && !allSelected && !isDefaultSelected
    }
    
    var defaultAttributes: Set<ShareableAttribute> {
        DefaultShareAttributes.load()
    }
    
    var hasDefaultAttributes: Bool {
        DefaultShareAttributes.hasDefaults()
    }
    
    var isDefaultSelected: Bool {
        guard hasDefaultAttributes else { return false }
        let defaults = defaultAttributes.intersection(availableAttributes)
        return !defaults.isEmpty && defaults == selectedAttributes.intersection(availableAttributes)
    }
    
    var matchesDefaultAttributes: Bool {
        guard hasDefaultAttributes else { return false }
        let defaults = defaultAttributes.intersection(availableAttributes)
        return defaults == selectedAttributes.intersection(availableAttributes)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(
                        get: { selectedAttributes.isEmpty },
                        set: { newValue in
                            if newValue {
                                selectedAttributes.removeAll()
                            }
                        }
                    )) {
                        Text("Image Only")
                            .foregroundColor(.black)
                    }

                    Toggle(isOn: Binding(
                        get: { allSelected },
                        set: { newValue in
                            if newValue {
                                selectedAttributes = availableAttributes
                            } else {
                                selectedAttributes.removeAll()
                            }
                        }
                    )) {
                        Text("Image + All Attributes")
                            .foregroundColor(.black)
                    }
                    
                    if hasDefaultAttributes {
                        Toggle(isOn: Binding(
                            get: { isDefaultSelected },
                            set: { newValue in
                                let defaults = defaultAttributes.intersection(availableAttributes)
                                if newValue {
                                    selectedAttributes = defaults
                                } else {
                                    selectedAttributes.removeAll()
                                }
                            }
                        )) {
                            Text("Image + Default Attributes")
                                .foregroundColor(.black)
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { isCustomSelectedAttributes },
                        set: { newValue in
                            if newValue {
                                if allSelected || isDefaultSelected {
                                    selectedAttributes.removeAll()
                                }
                            } else if isCustomSelectedAttributes {
                                selectedAttributes.removeAll()
                            }
                        }
                    )) {
                        Text("Image + Selected Attributes")
                            .foregroundColor(.black)
                    }
                } header: {
                    Text("Details")
                }
                
                Section {
                    ForEach(ShareableAttribute.allCases) { attribute in
                        if availableAttributes.contains(attribute) {
                            Toggle(isOn: Binding(
                                get: { selectedAttributes.contains(attribute) },
                                set: { newValue in
                                    if newValue {
                                        selectedAttributes.insert(attribute)
                                    } else {
                                        selectedAttributes.remove(attribute)
                                    }
                                }
                            )) {
                                Text(attribute.displayName)
                                    .foregroundColor(.black)
                            }
                        }
                    }
                } header: {
                    Text("Attributes")
                } footer: {
                    HStack {
                        Spacer()
                        if selectedAttributes.isEmpty || (hasDefaultAttributes && matchesDefaultAttributes) {
                            Button {
                                if !selectedAttributes.isEmpty {
                                    DefaultShareAttributes.save(selectedAttributes)
                                }
                            } label: {
                                Text("Save as Default")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderless)
                            .padding(.vertical, 7)
                            .foregroundColor(.gray)
                            .disabled(true)
                        } else {
                            Button {
                                DefaultShareAttributes.save(selectedAttributes)
                            } label: {
                                Text("Save as Default")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("External Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let shareText: String?
                        if selectedAttributes.isEmpty {
                            shareText = nil
                        } else {
                            let generated = generateShareText(from: selectedAttributes)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            shareText = generated.isEmpty ? nil : generated
                        }
                        onShare(shareText)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func generateShareText(from attributes: Set<ShareableAttribute>) -> String {
        var lines: [String] = []
        
        if attributes.contains(.name), let name = item.name, !name.isEmpty {
            lines.append(name)
        }
        
        if attributes.contains(.category) {
            if let categoryName = item.category?.name {
                if let subName = item.subcategory?.name {
                    lines.append("Category: \(categoryName) • \(subName)")
                } else {
                    lines.append("Category: \(categoryName)")
                }
            }
        }
        
        if attributes.contains(.brand), let brand = item.brand?.name {
            lines.append("Brand: \(brand)")
        }
        
        if attributes.contains(.size), let size = item.itemSize?.value {
            lines.append("Size: \(size)")
        }
        
        if attributes.contains(.color), let colors = item.colors as? Set<AppColor>, !colors.isEmpty {
            let colorNames = colors.compactMap { $0.name }.sorted().joined(separator: ", ")
            lines.append("Colors: \(colorNames)")
        }
        
        if attributes.contains(.season), let seasons = item.seasons as? Set<Season>, !seasons.isEmpty {
            let seasonNames = seasons.compactMap { $0.name }.sorted().joined(separator: ", ")
            lines.append("Seasons: \(seasonNames)")
        }
        
        if attributes.contains(.location), let location = item.location?.name {
            lines.append("Location: \(location)")
        }
        
        if attributes.contains(.price), let price = item.price, let amount = price.amount {
            let currencyCode = price.currency ?? Locale.current.currency?.identifier ?? "USD"
            let formattedPrice = CurrencyFormatting.displayPrice(
                amount: amount,
                currencyCode: currencyCode
            )
            lines.append("Price: \(formattedPrice)")
        }
        
        if appCapabilities.showsWeatherAttribute,
           attributes.contains(.weather),
           let minC = item.primitiveValue(forKey: "minTemperature") as? Double,
           let maxC = item.primitiveValue(forKey: "maxTemperature") as? Double {
            let unit = (item.primitiveValue(forKey: "temperatureUnit") as? String) ?? "C"
            let symbol = unit == "C" ? "°C" : "°F"
            let displayMin = unit == "C" ? Int(minC) : Int((minC * 9/5) + 32)
            let displayMax = unit == "C" ? Int(maxC) : Int((maxC * 9/5) + 32)
            lines.append("Weather: \(displayMin) to \(displayMax)\(symbol)")
        }
        
        if appCapabilities.showsWeightAttribute,
           attributes.contains(.weight),
           let weightKg = item.primitiveValue(forKey: "weight") as? Double {
            let unit = (item.primitiveValue(forKey: "weightUnit") as? String) ?? "kg"
            let symbol = unit == "kg" ? "kg" : "lbs"
            let displayWeight = unit == "kg" ? weightKg : weightKg * 2.20462
            lines.append("Weight: \(String(format: "%.1f", displayWeight)) \(symbol)")
        }
        
        if attributes.contains(.link), let links = item.links as? Set<Link>, !links.isEmpty {
            let linkStrings = links.compactMap { link -> String? in
                if let url = link.url?.absoluteString {
                    return url
                }
                return nil
            }
            if !linkStrings.isEmpty {
                lines.append("Links: \(linkStrings.joined(separator: ", "))")
            }
        }
        
        if attributes.contains(.tag), let tags = item.tags as? Set<Tag>, !tags.isEmpty {
            let tagNames = tags.compactMap { $0.name }.sorted().joined(separator: ", ")
            lines.append("Tags: \(tagNames)")
        }
        
        if attributes.contains(.notes), let notes = item.notes, !notes.isEmpty {
            lines.append("Notes: \(notes)")
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - ActivityViewController Wrapper
struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    @Binding var isPresented: Bool
    var onShareSheetPresented: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var hasPresentedShareSheet = false
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard isPresented, !context.coordinator.hasPresentedShareSheet, uiViewController.presentedViewController == nil else {
            if !isPresented {
                context.coordinator.hasPresentedShareSheet = false
            }
            return
        }

        context.coordinator.hasPresentedShareSheet = true

        let activityVC = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )

        // Configure for iPad
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = uiViewController.view
            popover.sourceRect = CGRect(x: uiViewController.view.bounds.midX, y: uiViewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        // Dismiss handler
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async {
                isPresented = false
            }
        }

        uiViewController.present(activityVC, animated: true) {
            DispatchQueue.main.async {
                onShareSheetPresented?()
            }
        }
    }
}




