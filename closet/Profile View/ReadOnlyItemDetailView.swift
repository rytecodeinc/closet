//
//  ReadOnlyItemDetailView.swift
//  closet
//
//  Read-only item detail for another user's public wardrobe item (matches ItemDetailView read-only styling).
//

import SwiftUI
import UIKit
import CoreData

struct ReadOnlyItemDetailView: View {
    let ownerUserId: UUID
    let wardrobeId: UUID
    let itemSummary: VisibleWardrobeItem
    /// Closet vs wishlist — used for history label and Redress canvas source type.
    var wardrobeType: String = "closet"
    /// Owner profile for Redress; falls back to a minimal profile from `ownerUserId`.
    var ownerProfile: PublicUserProfile? = nil
    /// Shared with Profile / Closet grid — same pattern as `ItemFilterView`.
    var tabBarHideState: TabBarHideState? = nil

    @Environment(\.appCapabilities) private var appCapabilities
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession

    @State private var detail: VisibleItemDetail?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var heroCarouselPage = 0
    @State private var isAttributesExpanded = true
    @State private var isPairsExpanded = false
    @State private var isOutfitsExpanded = false
    @State private var isHistoryExpanded = false
    @State private var isImageFullScreen = false
    @State private var attributeDetailSheet: VisibleAttributeDetailSheet?
    @State private var selectedPairedItem: VisibleWardrobeItem?
    @State private var selectedOutfit: VisibleWardrobeOutfit?
    @State private var showViewAllPairsSheet = false
    @State private var showViewAllOutfitsSheet = false
    @State private var likeCount = 0
    @State private var isLikedByMe = false
    @State private var isLikeBusy = false
    /// Friends-style nested push — see `.cursor/rules/profile-nested-navigation.mdc`.
    @State private var redressDestination: ItemRedressDestination?
    @State private var showShareSheet = false
    @State private var isPreparingShare = false
    @State private var shareItems: [Any] = []

    private var screenWidth: CGFloat { UIScreen.main.bounds.width }

    private var pairedItems: [VisibleWardrobeItem] {
        detail?.pairedItems ?? []
    }

    private var outfits: [VisibleWardrobeOutfit] {
        detail?.outfits ?? []
    }

    private var canToggleLike: Bool {
        authSession.userId != nil && authSession.userId != ownerUserId && !isLikeBusy
    }

    private var isViewingOwnContent: Bool {
        authSession.userId == ownerUserId
    }

    private var canRedress: Bool {
        appCapabilities.enablesFriendsAndSharing
            && authSession.userId != nil
            && authSession.userId != ownerUserId
    }

    private var resolvedOwnerProfile: PublicUserProfile {
        if let ownerProfile { return ownerProfile }
        return PublicUserProfile(userId: ownerUserId, username: "", displayName: nil)
    }

    private var normalizedWardrobeType: String {
        wardrobeType.lowercased() == "wishlist" ? "wishlist" : "closet"
    }

    private var historyAddedLabel: String {
        normalizedWardrobeType == "wishlist" ? "Added to Wishlist" : "Added to Closet"
    }

    private var historyDate: Date? {
        itemSummary.createdAt
    }

    private var itemForRedress: VisibleWardrobeItem {
        guard let detail else { return itemSummary }
        let frontURL = preferredRemotePhoto(for: "front", in: detail.photos)?.displayURL
        let frontRaw = frontURL?.absoluteString
        return VisibleWardrobeItem(
            id: detail.id,
            name: detail.name ?? itemSummary.name,
            thumbnailUrl: frontRaw ?? itemSummary.thumbnailUrl,
            imageUrl: frontRaw ?? itemSummary.imageUrl,
            createdAt: itemSummary.createdAt,
            brandName: detail.brandName ?? itemSummary.brandName,
            categoryName: detail.categoryName ?? itemSummary.categoryName,
            subcategoryName: detail.subcategoryName ?? itemSummary.subcategoryName,
            sizeValue: detail.sizeValue ?? itemSummary.sizeValue
        )
    }

    private var categoryDisplayText: String? {
        guard let detail else { return nil }
        let cat = detail.categoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sub = detail.subcategoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if cat.isEmpty { return nil }
        if !sub.isEmpty { return "\(cat) • \(sub)" }
        return cat
    }

    var body: some View {
        Group {
            if let loadError, detail == nil, !isLoading {
                Text(loadError)
                    .foregroundStyle(.red)
                    .padding()
            } else {
                itemDetailMainContent
            }
        }
        .overlay {
            if isLoading && detail == nil {
                ProgressView("Loading item…")
            }
        }
        .navigationTitle("Item Details")
        .navigationBarTitleDisplayMode(.inline)
        // Always hide — `.automatic` when `tabBarHideState` is nil was re-showing the tab bar
        // on Friends → profile → detail (parent hide no longer applies on the pushed screen).
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await shareActiveHeroImage() }
                } label: {
                    if isPreparingShare {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled((activeShareUIImage == nil && activeShareImageURL == nil) || isPreparingShare || showShareSheet)
                .accessibilityLabel("Share photo")
            }
        }
        .background {
            if showShareSheet {
                ActivityViewController(
                    activityItems: shareItems,
                    isPresented: $showShareSheet,
                    onShareSheetPresented: { isPreparingShare = false }
                )
                .frame(width: 0, height: 0)
            }
        }
        .onChange(of: showShareSheet) { _, isShowing in
            if !isShowing {
                isPreparingShare = false
                shareItems = []
            }
        }
        .onAppear {
            tabBarHideState?.shouldHideTabBar = true
        }
        .task(id: itemSummary.id) {
            await loadDetail()
            await refreshLikeState()
        }
        .sheet(item: $attributeDetailSheet) { sheet in
            visibleAttributeDetailSheet(sheet)
        }
        .fullScreenCover(isPresented: $isImageFullScreen) {
            visibleItemFullScreenImage
        }
        .navigationDestination(item: $selectedPairedItem) { item in
            ReadOnlyItemDetailView(
                ownerUserId: ownerUserId,
                wardrobeId: wardrobeId,
                itemSummary: item,
                wardrobeType: normalizedWardrobeType,
                ownerProfile: ownerProfile ?? resolvedOwnerProfile,
                tabBarHideState: tabBarHideState
            )
        }
        .navigationDestination(item: $selectedOutfit) { outfit in
            ReadOnlyOutfitDetailView(
                ownerUserId: ownerUserId,
                wardrobeId: wardrobeId,
                outfitSummary: outfit,
                tabBarHideState: tabBarHideState
            )
        }
        .navigationDestination(item: $redressDestination) { destination in
            // Stay on parent Profile NavigationStack — same as Friends → other-user profile.
            OutfitAddView(
                redressRecipient: destination.recipient,
                preselectedItem: destination.item,
                preselectedWardrobeType: destination.wardrobeType,
                sessionID: destination.id
            )
            .id(destination.id)
        }
        .sheet(isPresented: $showViewAllPairsSheet) {
            NavigationStack {
                RemoteVisibleItemsGridSheet(
                    title: "Paired Items",
                    items: pairedItems,
                    onSelect: { item in
                        showViewAllPairsSheet = false
                        selectedPairedItem = item
                    }
                )
            }
            .presentationDetents(pairedItems.count > 6 ? [.medium, .large] : [.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showViewAllOutfitsSheet) {
            NavigationStack {
                RemoteVisibleOutfitsGridSheet(
                    title: "Outfits",
                    outfits: outfits,
                    onSelect: { outfit in
                        showViewAllOutfitsSheet = false
                        selectedOutfit = outfit
                    }
                )
            }
            .presentationDetents(outfits.count > 6 ? [.medium, .large] : [.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var itemDetailMainContent: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                List {
                    Section {
                        itemImageDisplay
                        SocialEngagementActionsRow(
                            segmentSelection: Binding(
                                get: { heroCarouselPage == 0 ? .tshirt : .worn },
                                set: { segment in
                                    withAnimation {
                                        heroCarouselPage = segment == .tshirt ? 0 : 1
                                    }
                                }
                            ),
                            favoriteSelection: isViewingOwnContent ? false : isLikedByMe,
                            likeCount: likeCount,
                            showsLikeButton: true,
                            isLikeInteractive: canToggleLike,
                            showsRedressButton: canRedress,
                            // Deferred: share → social messaging (see `.cursor/rules/readonly-detail-share-messaging-deferred.mdc`).
                            showsShareButton: false,
                            showsMoveToClosetButton: false,
                            showsWornSegment: photoURL(for: "worn") != nil,
                            onLike: { toggleLike() },
                            onRedress: { openRedress() },
                            onShare: {},
                            onMoveToCloset: {}
                        )
                    }
                    .listRowInsets(EdgeInsets(.zero))
                    .listRowSeparator(.hidden)
                    .listSectionSpacing(0)

                    if hasAttributeContent {
                        Section {
                            if isAttributesExpanded {
                                visibleAttributesContent
                                    .transition(.opacity.combined(with: .slide))
                                    .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
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
                    }

                    if !pairedItems.isEmpty {
                        Section {
                            if isPairsExpanded {
                                RedressFeaturedItemsSubsectionRow(
                                    pairedItems: pairedItems,
                                    isReadOnly: true,
                                    onSelectItem: { selectedPairedItem = $0 },
                                    onViewAll: { showViewAllPairsSheet = true }
                                )
                                .transition(.opacity.combined(with: .slide))
                            }
                        } header: {
                            HStack {
                                Text("PAIRS")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: isPairsExpanded ? "minus" : "plus")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation {
                                    isPairsExpanded.toggle()
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(.zero))
                        .listSectionSpacing(0)
                        .padding(.horizontal)
                    }

                    if !outfits.isEmpty {
                        Section {
                            if isOutfitsExpanded {
                                RemoteOutfitsSubsectionRow(
                                    outfits: outfits,
                                    onSelectOutfit: { selectedOutfit = $0 },
                                    onViewAll: { showViewAllOutfitsSheet = true }
                                )
                                .transition(.opacity.combined(with: .slide))
                            }
                        } header: {
                            HStack {
                                Text("OUTFITS")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: isOutfitsExpanded ? "minus" : "plus")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation {
                                    isOutfitsExpanded.toggle()
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(.zero))
                        .listSectionSpacing(0)
                        .padding(.horizontal)
                    }

                    if let historyDate {
                        ReadOnlyOutfitHistorySection(
                            label: historyAddedLabel,
                            date: historyDate,
                            isExpanded: $isHistoryExpanded
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            heroCarouselPage = 0
            isHistoryExpanded = false
        }
    }

    private func openRedress() {
        guard canRedress else { return }
        redressDestination = ItemRedressDestination(
            id: UUID(),
            recipient: resolvedOwnerProfile,
            item: itemForRedress,
            wardrobeType: normalizedWardrobeType
        )
    }

    private var hasAttributeContent: Bool {
        guard detail != nil || !isLoading else { return false }
        if let name = displayName, !name.isEmpty { return true }
        if categoryDisplayText != nil { return true }
        if let brand = detail?.brandName, !brand.isEmpty { return true }
        if let size = detail?.sizeValue, !size.isEmpty { return true }
        return false
    }

    private var displayName: String? {
        let name = detail?.name ?? itemSummary.name
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @ViewBuilder
    private var visibleAttributesContent: some View {
        if let name = displayName {
            VisibleReadOnlyAttributeTextRow(
                title: "Name",
                text: name,
                activeSheet: $attributeDetailSheet
            )
        }
        if let label = categoryDisplayText {
            VisibleReadOnlyAttributeTextRow(
                title: "Category",
                text: label,
                activeSheet: $attributeDetailSheet
            )
        }
        if let brand = detail?.brandName, !brand.isEmpty {
            VisibleReadOnlyAttributeTextRow(
                title: "Brand",
                text: brand,
                activeSheet: $attributeDetailSheet
            )
        }
        if let size = detail?.sizeValue, !size.isEmpty {
            VisibleReadOnlyAttributeTextRow(
                title: "Size",
                text: size,
                activeSheet: $attributeDetailSheet
            )
        }
    }

    private var hasWornPhoto: Bool {
        localHeroUIImage(for: "worn") != nil || photoURL(for: "worn") != nil
    }

    /// Front when carousel page 0 (or no worn); worn when page 1.
    private var activeShareImageURL: URL? {
        if hasWornPhoto, heroCarouselPage == 1 {
            return photoURL(for: "worn")
        }
        return photoURL(for: "front")
    }

    private var activeShareUIImage: UIImage? {
        let type = (hasWornPhoto && heroCarouselPage == 1) ? "worn" : "front"
        return localHeroUIImage(for: type)
    }

    private func shareActiveHeroImage() async {
        if let local = activeShareUIImage {
            await MainActor.run {
                shareItems = [local]
                showShareSheet = true
            }
            return
        }
        guard let url = activeShareImageURL else { return }
        await MainActor.run {
            isPreparingShare = true
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            guard let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            await MainActor.run {
                shareItems = [image]
                showShareSheet = true
            }
        } catch {
            await MainActor.run {
                isPreparingShare = false
            }
        }
    }

    private var itemImageDisplay: some View {
        Group {
            if hasWornPhoto {
                TabView(selection: $heroCarouselPage) {
                    heroSlot(for: "front").tag(0)
                    heroSlot(for: "worn").tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else {
                heroSlot(for: "front")
            }
        }
        .frame(width: screenWidth, height: screenWidth)
    }

    @ViewBuilder
    private func heroSlot(for type: String) -> some View {
        let heroType: HeroImageType = type == "worn" ? .worn : .front
        if let local = localHeroUIImage(for: type) {
            localHeroImage(local)
        } else if let url = photoURL(for: type) {
            remoteHeroImage(url: url, placeholderType: heroType)
        } else {
            heroImagePlaceholder(for: heroType)
        }
    }

    private func localHeroImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: screenWidth, height: screenWidth)
            .clipped()
            .onTapGesture { isImageFullScreen = true }
    }

    private func remoteHeroImage(url: URL, placeholderType: HeroImageType) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: screenWidth, height: screenWidth)
                    .clipped()
            case .failure:
                heroImagePlaceholder(for: placeholderType)
            default:
                ProgressView()
                    .frame(width: screenWidth, height: screenWidth)
            }
        }
        .onTapGesture { isImageFullScreen = true }
    }

    private enum HeroImageType {
        case front
        case worn
    }

    private func heroImagePlaceholder(for type: HeroImageType) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: screenWidth, height: screenWidth)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: type == .worn ? "person.crop.square.badge.camera" : "photo")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 40))
                    Text(type == .worn ? "No image available" : "Tap to add a photo of the front of the item")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
    }

    /// Own Profile: prefer live Core Data blobs so a just-replaced front shows immediately.
    private func fetchedOwnItem() -> Item? {
        guard isViewingOwnContent else { return nil }
        let request = Item.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", itemSummary.id as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }

    private func localHeroUIImage(for type: String) -> UIImage? {
        guard let item = fetchedOwnItem(),
              let photosSet = item.photos as? Set<Photo> else { return nil }
        let photos = Array(photosSet)
        let target = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let photo = photos.first(where: {
            ($0.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target
        }), let data = photo.data, let image = UIImage(data: data), image.size.width > 0 {
            return image
        }
        if target == "front",
           let photo = photos.first(where: {
               $0.isPrimary && ($0.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
           }),
           let data = photo.data, let image = UIImage(data: data), image.size.width > 0 {
            return image
        }
        return nil
    }

    private func preferredRemotePhoto(for type: String, in photos: [VisibleItemPhoto]) -> VisibleItemPhoto? {
        let target = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let typed = photos.filter {
            ($0.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target
        }
        if let best = typed.first(where: { $0.isPrimary && $0.displayURL != nil })
            ?? typed.first(where: { $0.displayURL != nil }) {
            return best
        }
        if target == "front" {
            let legacy = photos.filter {
                $0.isPrimary && ($0.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return legacy.first(where: { $0.displayURL != nil })
        }
        return nil
    }

    private func photoURL(for type: String) -> URL? {
        if let match = preferredRemotePhoto(for: type, in: detail?.photos ?? []) {
            return match.displayURL
        }
        // Grid summary only while remote detail has not loaded — never after, or a replaced
        // front keeps showing the stale wardrobe-grid URL.
        if type.lowercased() == "front", detail == nil,
           let raw = itemSummary.imageUrl ?? itemSummary.thumbnailUrl,
           let url = URL(string: raw) {
            return url
        }
        return nil
    }

    @ViewBuilder
    private var visibleItemFullScreenImage: some View {
        let type = heroCarouselPage == 0 ? "front" : "worn"
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let local = localHeroUIImage(for: type) {
                Image(uiImage: local)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let url = photoURL(for: type) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    default:
                        ProgressView()
                            .tint(.white)
                    }
                }
            }
            Button {
                isImageFullScreen = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding()
            }
        }
    }

    @ViewBuilder
    private func visibleAttributeDetailSheet(_ sheet: VisibleAttributeDetailSheet) -> some View {
        VStack(spacing: 0) {
            SelectionPanelHeader(title: sheet.title)
            ScrollView {
                Text(sheet.value)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .presentationDetents([.height(200)])
        .presentationDragIndicator(.visible)
    }

    private func loadDetail() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            detail = try await supabaseService.fetchVisibleItemDetail(
                userId: ownerUserId,
                itemId: itemSummary.id,
                wardrobeId: wardrobeId
            )
            if detail == nil {
                loadError = "This item is not available."
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func refreshLikeState() async {
        do {
            let state = try await supabaseService.fetchContentLikeState(
                targetType: .item,
                targetId: itemSummary.id
            )
            likeCount = state.likeCount
            isLikedByMe = state.likedByMe
        } catch {
            // Keep prior local state if like RPCs are not deployed yet.
        }
    }

    private func toggleLike() {
        guard canToggleLike else { return }
        isLikeBusy = true
        let previousCount = likeCount
        let previousLiked = isLikedByMe
        // Optimistic UI
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
                let state = try await supabaseService.toggleContentLike(
                    targetType: .item,
                    targetId: itemSummary.id
                )
                likeCount = state.likeCount
                isLikedByMe = state.likedByMe
            } catch {
                likeCount = previousCount
                isLikedByMe = previousLiked
            }
        }
    }
}

/// Nested Redress push from read-only item detail (`navigationDestination(item:)`).
private struct ItemRedressDestination: Identifiable, Hashable {
    let id: UUID
    let recipient: PublicUserProfile
    let item: VisibleWardrobeItem
    let wardrobeType: String
}

// MARK: - Read-only attribute rows (matches AttributesSectionView read-only styling)

private struct VisibleAttributeDetailSheet: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

private struct VisibleReadOnlyAttributeTextRow: View {
    let title: String
    let text: String
    @Binding var activeSheet: VisibleAttributeDetailSheet?
    @State private var isTruncated = false

    var body: some View {
        let content = HStack {
            Text(title).foregroundColor(.primary)
            Spacer()
            Text(text)
                .foregroundColor(.gray)
                .lineLimit(1)
                .truncationMode(.tail)
            if isTruncated {
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { updateTruncation(rowWidth: geometry.size.width) }
                    .onChange(of: geometry.size.width) { _, width in
                        updateTruncation(rowWidth: width)
                    }
            }
        )

        if isTruncated {
            Button {
                activeSheet = VisibleAttributeDetailSheet(title: title, value: text)
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func updateTruncation(rowWidth: CGFloat) {
        guard rowWidth > 0 else { return }
        let font = UIFont.preferredFont(forTextStyle: .body)
        let titleWidth = (title as NSString).size(withAttributes: [.font: font]).width
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let availableWithoutChevron = rowWidth - titleWidth
        if textWidth <= availableWithoutChevron {
            isTruncated = false
            return
        }
        let availableWithChevron = rowWidth - titleWidth - 20
        isTruncated = textWidth > max(availableWithChevron, 0)
    }
}

// MARK: - View-all sheets for remote pairs / outfits

private struct RemoteVisibleItemsGridSheet: View {
    let title: String
    let items: [VisibleWardrobeItem]
    let onSelect: (VisibleWardrobeItem) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        VStack(spacing: 0) {
            SelectionPanelHeader(title: title)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(items) { item in
                        RedressSetItemCell(item: item) {
                            onSelect(item)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}

private struct RemoteVisibleOutfitsGridSheet: View {
    let title: String
    let outfits: [VisibleWardrobeOutfit]
    let onSelect: (VisibleWardrobeOutfit) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        VStack(spacing: 0) {
            SelectionPanelHeader(title: title)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(outfits) { outfit in
                        Button {
                            onSelect(outfit)
                        } label: {
                            ZStack {
                                if let url = outfit.collageImageURL {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().aspectRatio(1, contentMode: .fill)
                                        default:
                                            ProgressView()
                                        }
                                    }
                                } else {
                                    Image(systemName: "photo").foregroundStyle(.secondary)
                                }
                            }
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}
