//
//  ReadOnlyOutfitDetailView.swift
//  closet
//
//  Read-only outfit detail for another user's public wardrobe outfit (Supabase RPC).
//

import SwiftUI
import UIKit
import CoreData

struct ReadOnlyOutfitDetailView: View {
    let ownerUserId: UUID
    let wardrobeId: UUID
    let outfitSummary: VisibleWardrobeOutfit
    /// When set, loads detail via Redress RPC (friends/public wardrobes) instead of public-only visible RPC.
    var redressRecipientUserId: UUID? = nil
    /// Closet vs wishlist — forwarded when opening nested item detail.
    var wardrobeType: String = "closet"
    /// Owner profile for nested item Redress; unused for outfit-level actions.
    var ownerProfile: PublicUserProfile? = nil
    /// Shared with Profile / Closet grid — same pattern as `ItemFilterView`.
    var tabBarHideState: TabBarHideState? = nil

    @Environment(\.appCapabilities) private var appCapabilities
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession

    @State private var detail: VisibleOutfitDetail?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var heroCarouselPage = 0
    @State private var isItemsSectionExpanded = true
    @State private var isAttributesExpanded = false
    @State private var isHistoryExpanded = false
    @State private var isOutfitImageFullScreen = false
    @State private var fullscreenPageIndex = 0
    @State private var selectedItem: VisibleWardrobeItem?
    @State private var likeCount = 0
    @State private var isLikedByMe = false
    @State private var isLikeBusy = false
    /// Own-profile: heart reflects Core Data favorite (not social like).
    @State private var isOwnFavorite = false
    @State private var showShareSheet = false
    @State private var isPreparingShare = false
    @State private var shareItems: [Any] = []

    private var screenWidth: CGFloat { UIScreen.main.bounds.width }

    private var localOwnedOutfit: Outfit? {
        guard isViewingOwnContent else { return nil }
        let request: NSFetchRequest<Outfit> = Outfit.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(
            format: "id == %@ AND userId == %@ AND (isSoftDeleted != YES OR isSoftDeleted == nil)",
            outfitSummary.id as CVarArg,
            ownerUserId.uuidString
        )
        return try? viewContext.fetch(request).first
    }

    private var canToggleLike: Bool {
        authSession.userId != nil && authSession.userId != ownerUserId && !isLikeBusy
    }

    private var isViewingOwnContent: Bool {
        authSession.userId == ownerUserId
    }

    private var historyDate: Date? {
        detail?.createdAt ?? outfitSummary.createdAt
    }

    private let featuredItemsGridColumns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    private var displayName: String? {
        let raw = (detail?.name ?? outfitSummary.name)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Sync historically wrote "unnamed" when name was nil — treat as unset for display.
        if raw.isEmpty || raw.lowercased() == "unnamed" { return nil }
        return raw
    }

    private var displayNotes: String? {
        detail?.notes
    }

    private var itemThumbs: [VisibleOutfitItemThumb] {
        detail?.itemThumbnails ?? []
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading outfit…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                Text(loadError)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                listContent
            }
        }
        .navigationTitle("Outfit Details")
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
                .disabled(activeShareImageURL == nil || isPreparingShare || showShareSheet)
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
        .task(id: outfitSummary.id) {
            syncOwnFavoriteFromLocalOutfit()
            await loadDetail()
            await refreshLikeState()
        }
        .navigationDestination(item: $selectedItem) { item in
            ReadOnlyItemDetailView(
                ownerUserId: ownerUserId,
                wardrobeId: wardrobeId,
                itemSummary: item,
                wardrobeType: wardrobeType.lowercased() == "wishlist" ? "wishlist" : "closet",
                ownerProfile: ownerProfile,
                tabBarHideState: tabBarHideState
            )
        }
        .fullScreenCover(isPresented: $isOutfitImageFullScreen) {
            RemoteOutfitFullScreenView(
                imageURLs: heroImageURLs,
                selectedPageIndex: $fullscreenPageIndex,
                isPresented: $isOutfitImageFullScreen
            )
        }
        .onAppear {
            tabBarHideState?.shouldHideTabBar = true
            heroCarouselPage = 0
        }
        .onChange(of: wornURL?.absoluteString) { _, _ in
            if wornURL == nil, heroCarouselPage == 1 {
                heroCarouselPage = 0
            }
        }
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    remoteOutfitDisplayArea
                    SocialEngagementActionsRow(
                        segmentSelection: Binding(
                            get: { heroCarouselPage == 0 ? .tshirt : .worn },
                            set: { segment in
                                withAnimation {
                                    heroCarouselPage = segment == .tshirt ? 0 : 1
                                }
                            }
                        ),
                        favoriteSelection: isViewingOwnContent
                            ? isOwnFavorite
                            : isLikedByMe,
                        likeCount: likeCount,
                        showsLikeButton: true,
                        isLikeInteractive: canToggleLike,
                        showsRedressButton: false,
                        // Deferred: share → social messaging (see `.cursor/rules/readonly-detail-share-messaging-deferred.mdc`).
                        showsShareButton: false,
                        showsMoveToClosetButton: false,
                        showsWornSegment: wornURL != nil,
                        onLike: { toggleLike() },
                        onRedress: {},
                        onShare: {},
                        onMoveToCloset: {}
                    )
                }
                .listRowInsets(EdgeInsets(.zero))
                .listRowSeparator(.hidden)
                .listSectionSpacing(0)

                if !itemThumbs.isEmpty {
                    Section {
                        if isItemsSectionExpanded {
                            remoteFeaturedItemsGrid
                                .transition(.opacity.combined(with: .slide))
                        }
                    } header: {
                        itemsSectionHeader
                    }
                    .listRowInsets(EdgeInsets(.zero))
                    .listSectionSpacing(0)
                    .padding(.horizontal)
                }

                Section {
                    if isAttributesExpanded {
                        ReadOnlyRemoteOutfitAttributesSection(name: displayName, notes: displayNotes)
                            .transition(.opacity.combined(with: .slide))
                            .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                    }
                } header: {
                    attributesSectionHeader
                }

                ReadOnlyOutfitHistorySection(
                    label: "Outfit Created",
                    date: historyDate,
                    isExpanded: $isHistoryExpanded
                )
            }
            .listStyle(.plain)
        }
    }

    private var itemsSectionHeader: some View {
        HStack {
            Text("ITEMS")
                .fontWeight(.semibold)
            Spacer()
            Image(systemName: isItemsSectionExpanded ? "minus" : "plus")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isItemsSectionExpanded.toggle()
            }
        }
    }

    private var attributesSectionHeader: some View {
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

    private var remoteOutfitDisplayArea: some View {
        Group {
            if wornURL != nil {
                TabView(selection: $heroCarouselPage) {
                    Group {
                        if let url = collageURL {
                            remoteHeroImage(url: url)
                        } else {
                            remoteCollagePlaceholder
                        }
                    }
                    .tag(0)

                    Group {
                        if let url = wornURL {
                            remoteHeroImage(url: url)
                        } else {
                            remoteWornPlaceholder
                        }
                    }
                    .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else {
                Group {
                    if let url = collageURL {
                        remoteHeroImage(url: url)
                    } else {
                        remoteCollagePlaceholder
                    }
                }
            }
        }
        .frame(width: screenWidth, height: screenWidth)
    }

    private var collageURL: URL? {
        urlFrom(detail?.imageUrl ?? outfitSummary.imageUrl)
    }

    private var wornURL: URL? {
        urlFrom(detail?.wornImageUrl ?? outfitSummary.wornImageUrl)
    }

    /// Collage when carousel page 0 (or no worn); worn when page 1.
    private var activeShareImageURL: URL? {
        if wornURL != nil, heroCarouselPage == 1 {
            return wornURL
        }
        return collageURL
    }

    private var heroImageURLs: [URL] {
        var urls: [URL] = []
        if let collage = collageURL { urls.append(collage) }
        if let worn = wornURL, !urls.contains(worn) { urls.append(worn) }
        return urls
    }

    private func shareActiveHeroImage() async {
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

    private func urlFrom(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string) else { return nil }
        return url
    }

    private func remoteHeroImage(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: screenWidth, height: screenWidth)
                    .clipped()
            case .failure:
                remoteCollagePlaceholder
            default:
                ProgressView()
                    .frame(width: screenWidth, height: screenWidth)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard let index = heroImageURLs.firstIndex(of: url) else { return }
            fullscreenPageIndex = index
            isOutfitImageFullScreen = true
        }
    }

    private var remoteCollagePlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: screenWidth, height: screenWidth)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "tshirt")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 40))
                    Text("No collage yet")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
    }

    private var remoteWornPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: screenWidth, height: screenWidth)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.square.badge.camera")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 40))
                    Text("No worn photo")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
    }

    private var remoteFeaturedItemsGrid: some View {
        LazyVGrid(columns: featuredItemsGridColumns, spacing: 4) {
            ForEach(itemThumbs) { thumb in
                Button {
                    selectedItem = VisibleWardrobeItem(
                        id: thumb.id,
                        name: thumb.name,
                        thumbnailUrl: thumb.thumbnailUrl,
                        imageUrl: nil
                    )
                } label: {
                    RemoteReadOnlyOutfitItemCell(thumb: thumb, usesClearBackground: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadDetail() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            if let redressRecipientUserId {
                detail = try await supabaseService.fetchRedressOutfitDetail(
                    recipientId: redressRecipientUserId,
                    outfitId: outfitSummary.id,
                    wardrobeId: wardrobeId
                )
            } else {
                detail = try await supabaseService.fetchVisibleOutfitDetail(
                    userId: ownerUserId,
                    outfitId: outfitSummary.id,
                    wardrobeId: wardrobeId
                )
            }
            if detail == nil {
                loadError = "This outfit is not available."
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func refreshLikeState() async {
        do {
            let state = try await supabaseService.fetchContentLikeState(
                targetType: .outfit,
                targetId: outfitSummary.id
            )
            likeCount = state.likeCount
            isLikedByMe = state.likedByMe
        } catch {
            // Keep prior local state if like RPCs are not deployed yet.
        }
    }

    private func syncOwnFavoriteFromLocalOutfit() {
        guard isViewingOwnContent else {
            isOwnFavorite = false
            return
        }
        isOwnFavorite = localOwnedOutfit?.isFavorite ?? false
    }

    private func toggleLike() {
        guard canToggleLike else { return }
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
                let state = try await supabaseService.toggleContentLike(
                    targetType: .outfit,
                    targetId: outfitSummary.id
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

struct RemoteReadOnlyOutfitItemCell: View {
    let thumb: VisibleOutfitItemThumb
    var usesClearBackground: Bool = false

    var body: some View {
        Group {
            if let url = thumb.displayURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        ProgressView()
                    }
                }
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fill)
        .clipped()
    }
}

/// Light fullscreen pager used by read-only outfit collage/worn and item front/worn.
struct RemoteOutfitFullScreenView: View {
    struct Page: Identifiable {
        let id: Int
        let url: URL?
        let uiImage: UIImage?

        init(id: Int, url: URL? = nil, uiImage: UIImage? = nil) {
            self.id = id
            self.url = url
            self.uiImage = uiImage
        }
    }

    let pages: [Page]
    @Binding var selectedPageIndex: Int
    @Binding var isPresented: Bool
    @State private var dragOffset: CGSize = .zero

    init(imageURLs: [URL], selectedPageIndex: Binding<Int>, isPresented: Binding<Bool>) {
        self.pages = imageURLs.enumerated().map { Page(id: $0.offset, url: $0.element) }
        self._selectedPageIndex = selectedPageIndex
        self._isPresented = isPresented
    }

    init(pages: [Page], selectedPageIndex: Binding<Int>, isPresented: Binding<Bool>) {
        self.pages = pages
        self._selectedPageIndex = selectedPageIndex
        self._isPresented = isPresented
    }

    var body: some View {
        ZStack {
            Color(red: 247 / 255, green: 247 / 255, blue: 247 / 255)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            if pages.isEmpty {
                VStack {
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No images available")
                        .foregroundColor(.secondary)
                        .padding(.top, 16)
                }
            } else {
                TabView(selection: $selectedPageIndex) {
                    ForEach(pages) { page in
                        Group {
                            if let uiImage = page.uiImage {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .background(.white)
                            } else if let url = page.url {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .background(.white)
                                    default:
                                        ProgressView()
                                    }
                                }
                            } else {
                                ProgressView()
                            }
                        }
                        .tag(page.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .automatic : .never))

                VStack {
                    HStack {
                        Spacer()
                        Button { isPresented = false } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.gray.opacity(0.7))
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 20)
                    }
                    Spacer()
                }
            }
        }
        .statusBarHidden()
        .offset(y: dragOffset.height)
        .opacity(1.0 - abs(dragOffset.height) / UIScreen.main.bounds.height * 0.5)
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    if abs(value.translation.height) > abs(value.translation.width) * 2, value.translation.height > 0 {
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    let threshold = min(100, UIScreen.main.bounds.height * 0.3)
                    if value.translation.height > threshold
                        || value.predictedEndTranslation.height > UIScreen.main.bounds.height * 0.5 {
                        withAnimation(.easeOut(duration: 0.3)) {
                            isPresented = false
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .onChange(of: isPresented) { _, newValue in
            if !newValue { dragOffset = .zero }
        }
    }
}
