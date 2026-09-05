//
//  OutfitDetailView.swift
//  closet
//
//  Created by Dan Warner on 9/20/25.
//

import Foundation
import SwiftUI
import CoreData
import UIKit

private enum OutfitHeroImageSlot {
    case collage
    case worn
}

struct OutfitDetailView: View {
    @ObservedObject var outfit: Outfit
    var isReadOnly: Bool = false
    /// Closet/Wishlist tab path — item taps append `ItemGridFilterRoute.itemDetail` (no nested `item:`).
    var navigationPath: Binding<NavigationPath>? = nil
    /// Wardrobe the user was browsing when they opened this outfit (drives Edit → item sheet).
    var initialWardrobe: Wardrobe? = nil
    /// When true (non-default wardrobe context), Edit locks item source like Outfit Add.
    var lockWardrobeSource: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appCapabilities) private var appCapabilities
    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession
    
    @State private var attributesSheet: OutfitAttributesSectionView.Sheet?
    @State private var isItemsSectionExpanded = false
    @State private var isAttributesExpanded = true
    @State private var isHistoryExpanded = false
    @State private var likeCount = 0
    @State private var isLikedByMe = false
    @State private var isLikeBusy = false
    
    @State private var isEditingOutfit = false
    /// Inline hero: 0 = collage (tshirt), 1 = worn (person).
    @State private var heroCarouselPage: Int = 0
    @State private var cachedCollageUIImage: UIImage?
    @State private var cachedWornUIImage: UIImage?
    @State private var isOutfitImageFullScreen = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showShareSelectionSheet = false
    @State private var selectedShareAttributes: Set<ShareableOutfitAttribute> = []
    @State private var pendingShareText: String?
    @State private var pendingShareImage: UIImage?
    @State private var showShareFriendsSheet = false
    @State private var showDeleteOutfitConfirmation = false
    @State private var showRemoveWornImageConfirmation = false
    /// Set when a worn photo is saved/replaced. Consumed after any collage reset so Worn wins.
    @State private var pendingSelectWornHero = false

    @State private var showOutfitHeroOptionsDialog = false
    @State private var isOutfitHeroImagePickerPresented = false
    @State private var outfitHeroImagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var pickedOutfitHeroUIImage: UIImage?
    @State private var outfitHeroImagePickerSlot: OutfitHeroImageSlot = .collage

    @State private var isOutfitImageCropperPresented = false
    @State private var outfitHeroImageToEdit: UIImage?
    @State private var outfitHeroCropSlot: OutfitHeroImageSlot = .collage
    @State private var outfitCropEditorSessionID = UUID()
    @State private var selectedItemURIForNavigation: String?
    @State private var redressSuggestionContext: OutfitRedressSuggestionContext?

    private var screenWidth: CGFloat { UIScreen.main.bounds.width }

    private var editWardrobeType: String {
        (initialWardrobe?.type ?? "closet").lowercased() == "wishlist" ? "wishlist" : "closet"
    }
    
    // Computed property to get ordered items array (preserves insertion order from canvas)
    private var orderedItems: [Item] {
        // Try to use transformationData first (preserves order from canvas)
        if let transformationData = outfit.transformationData {
            let decoder = JSONDecoder()
            if let savedItems = try? decoder.decode([SavedOutfitItem].self, from: transformationData) {
                let itemsSet = outfit.items as? Set<Item> ?? []
                // Build lookup by both portable UUID and legacy Core Data ObjectID URI
                var itemsByUUID: [String: Item] = [:]
                var itemsByObjectID: [String: Item] = [:]
                for item in itemsSet {
                    if let uuid = item.id?.uuidString { itemsByUUID[uuid] = item }
                    itemsByObjectID[item.objectID.uriRepresentation().absoluteString] = item
                }
                // Return items in canvas order; match UUID first, then legacy ObjectID
                return savedItems.compactMap { savedItem in
                    itemsByUUID[savedItem.itemID] ?? itemsByObjectID[savedItem.itemID]
                }
            }
        }
        // Fallback: if no transformationData, use Set (unordered, but better than nothing)
        if let itemsSet = outfit.items as? Set<Item> {
            return Array(itemsSet)
        }
        return []
    }

    private let featuredItemsGridColumns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    /// Same rule as `ItemDetailView.isWishlistItem`: any linked wishlist wardrobe.
    private func itemIsWishlistMember(_ item: Item) -> Bool {
        (item.wardrobes as? Set<Wardrobe>)?.contains { $0.type?.lowercased() == "wishlist" } ?? false
    }

    private var orderedWishlistFeaturedItems: [Item] {
        orderedItems.filter { itemIsWishlistMember($0) }
    }

    private var orderedClosetFeaturedItems: [Item] {
        orderedItems.filter { !itemIsWishlistMember($0) }
    }

    private var shouldSplitFeaturedItemsByWardrobeType: Bool {
        !orderedWishlistFeaturedItems.isEmpty && !orderedClosetFeaturedItems.isEmpty
    }

    /// Parallel to `ItemDetailView.isWishlistItem`: outfit has no closet items (wishlist-only).
    private var isWishlistOutfit: Bool {
        orderedClosetFeaturedItems.isEmpty && !orderedWishlistFeaturedItems.isEmpty
    }

    private var pastWornEventCount: Int {
        pastWornEvents(for: outfit).count
    }

    private var showsCalendarActions: Bool {
        !isReadOnly && !isWishlistOutfit && pastWornEventCount > 0
    }
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    outfitDisplayArea

                    SocialEngagementActionsRow(
                        segmentSelection: Binding(
                            get: { heroCarouselPage == 0 ? .tshirt : .worn },
                            set: { segment in
                                withAnimation {
                                    heroCarouselPage = segment == .tshirt ? 0 : 1
                                }
                            }
                        ),
                        favoriteSelection: isViewingOwnContent ? outfit.isFavorite : isLikedByMe,
                        likeCount: isReadOnly ? likeCount : nil,
                        calendarCount: showsCalendarActions
                            ? pastWornEventCount
                            : nil,
                        showsLikeButton: true,
                        isLikeInteractive: isReadOnly ? canToggleSocialLike : true,
                        showsCalendarButton: showsCalendarActions,
                        showsShareButton: appCapabilities.enablesFriendsAndSharing,
                        showsWornSegment: outfit.wornImage != nil || !isReadOnly,
                        onLike: {
                            if isReadOnly {
                                toggleSocialLike()
                            } else {
                                withAnimation {
                                    toggleOwnFavorite()
                                }
                            }
                        },
                        onCalendar: {},
                        onShare: { showShareFriendsSheet = true }
                    )
                }
                .listRowInsets(EdgeInsets(.zero))
                .listRowSeparator(.hidden)
                .listSectionSpacing(0)

                Section {
                    if isItemsSectionExpanded {
                        featuredItemsContent
                            .transition(.opacity.combined(with: .slide))
                    }
                } header: {
                    HStack {
                        Text("ITEMS")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: itemsSectionHeaderIconName)
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
                .listRowInsets(EdgeInsets(.zero))
                .listSectionSpacing(0)
                .padding(.horizontal)

                if !isReadOnly || OutfitAttributesSectionView.hasReadOnlyVisibleContent(for: outfit) {
                Section {
                    if isAttributesExpanded {
                        OutfitAttributesSectionView(
                            outfit: outfit,
                            activeSheet: $attributesSheet,
                            isReadOnly: isReadOnly,
                            showsCost: true
                        )
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

                if isReadOnly {
                    ReadOnlyOutfitHistorySection(
                        label: "Outfit Created",
                        date: displayCreatedDate,
                        isExpanded: $isHistoryExpanded
                    )
                } else {
                Section {
                    if isHistoryExpanded {
                        historyRows
                            .transition(.opacity.combined(with: .slide))
                    }
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
                .listSectionSpacing(0)
                .padding(.horizontal)
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Outfit Details")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(OutfitDetailNestedItemDestinationModifier(
            navigationPath: navigationPath,
            selectedItemURIForNavigation: $selectedItemURIForNavigation,
            isReadOnly: isReadOnly,
            viewContext: viewContext
        ))
        .onAppear {
            // Always land on collage first; a pending worn selection re-applies after (and async).
            heroCarouselPage = 0
            applyPendingWornHeroSelectionIfNeeded(clearAfterApplying: true)
            refreshOutfitHeroImageCache()
            viewContext.refresh(outfit, mergeChanges: true)
            if isReadOnly {
                // Match ReadOnlyOutfitDetailView: attributes expanded; items/history collapsed.
                isItemsSectionExpanded = false
                isHistoryExpanded = false
            } else {
                isItemsSectionExpanded = !orderedItems.isEmpty
            }
        }
        .onDisappear {
            // Real navigation pop (not a covering sheet/cover): drop pending worn intent.
            guard !isCoveringModalPresented else { return }
            pendingSelectWornHero = false
            heroCarouselPage = 0
        }
        .task(id: outfit.id) {
            await loadRedressSuggestionContextIfNeeded()
            if isReadOnly, let outfitId = outfit.id {
                await refreshSocialLikeState(outfitId: outfitId)
            }
        }
        .toolbar {
            if !isReadOnly {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if currentOutfitHeroUIImage() != nil {
                        Button {
                            let available = getAvailableOutfitAttributes()
                            let defaults = DefaultOutfitShareAttributes.load().intersection(available)
                            selectedShareAttributes = defaults.isEmpty ? available : defaults
                            showShareSelectionSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share outfit")
                    }
                    Button(role: .destructive) {
                        showDeleteOutfitConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .accessibilityLabel("Delete outfit")
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !isReadOnly && isEditingOutfit },
            set: { isEditingOutfit = $0 }
        ), onDismiss: refreshOutfitHeroImageCache) {
            NavigationView {
                OutfitAddView(
                    outfitToEdit: outfit,
                    wardrobeType: editWardrobeType,
                    initialWardrobe: initialWardrobe,
                    lockWardrobeSource: false,
                    wardrobeMembershipOnSave: (initialWardrobe?.isDefault != true) ? initialWardrobe : nil
                )
            }
        }
        .fullScreenCover(isPresented: $isOutfitImageFullScreen) {
            fullScreenOutfitImageView()
        }
        .sheet(item: Binding(
            get: { isReadOnly ? nil : attributesSheet },
            set: { attributesSheet = $0 }
        )) { $0.destination(for: outfit) }
        .sheet(isPresented: $showShareSelectionSheet, onDismiss: {
            if let image = pendingShareImage {
                if let shareText = pendingShareText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !shareText.isEmpty {
                    shareItems = [shareText, image]
                } else {
                    shareItems = [image]
                }
                pendingShareText = nil
                pendingShareImage = nil
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    showShareSheet = true
                }
            }
        }) {
            if let heroImage = currentOutfitHeroUIImage() {
                OutfitShareSelectionView(
                    outfit: outfit,
                    selectedAttributes: $selectedShareAttributes,
                    onShare: { shareText in
                        pendingShareText = shareText
                        pendingShareImage = heroImage
                        showShareSelectionSheet = false
                    }
                )
            }
        }
        .overlay {
            if showShareSheet {
                ActivityViewController(activityItems: shareItems, isPresented: $showShareSheet)
                    .frame(width: 0, height: 0)
            }
        }
        .alert("Delete Outfit", isPresented: $showDeleteOutfitConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteOutfit()
            }
        } message: {
            Text("Delete this outfit? This action cannot be undone.")
        }
        .alert("Remove Photo", isPresented: $showRemoveWornImageConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                removeOutfitWornImage()
            }
        } message: {
            Text("Remove this worn photo? This action cannot be undone.")
        }
        .confirmationDialog(outfitHeroOptionsDialogTitle, isPresented: $showOutfitHeroOptionsDialog, titleVisibility: .visible) {
            outfitHeroOptionsDialogContent
        }
        .sheet(isPresented: $isOutfitHeroImagePickerPresented, onDismiss: {
            // Reinforce worn after dismiss without clearing the flag — onAppear clears it.
            applyPendingWornHeroSelectionIfNeeded(clearAfterApplying: false)
        }) {
            ImagePicker(
                image: $pickedOutfitHeroUIImage,
                sourceType: $outfitHeroImagePickerSource,
                allowsEditing: true,
                completionHandler: { image in
                    if let image = image {
                        switch outfitHeroImagePickerSlot {
                        case .collage:
                            saveCollageOutfitImage(image)
                        case .worn:
                            saveWornOutfitImage(image)
                        }
                    }
                    isOutfitHeroImagePickerPresented = false
                    pickedOutfitHeroUIImage = nil
                }
            )
        }
        .sheet(isPresented: $isOutfitImageCropperPresented, onDismiss: {
            applyPendingWornHeroSelectionIfNeeded(clearAfterApplying: false)
        }) {
            outfitImageCropperSheetContent
        }
        .sheet(isPresented: Binding(
            get: { appCapabilities.enablesFriendsAndSharing && showShareFriendsSheet },
            set: { showShareFriendsSheet = $0 }
        )) {
            if let outfitId = outfit.id {
                ShareOutfitFriendsSheet(targetId: outfitId)
                    .environmentObject(supabaseService)
            } else {
                Text("This outfit isn’t ready to share yet.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .toolbar(.hidden, for: .tabBar)
    };

    /// Sheets / covers that can re-fire `onAppear` without leaving the detail screen.
    private var isCoveringModalPresented: Bool {
        isOutfitHeroImagePickerPresented
            || isOutfitImageCropperPresented
            || isOutfitImageFullScreen
            || isEditingOutfit
            || showShareSelectionSheet
            || showShareFriendsSheet
            || attributesSheet != nil
    }

    private var outfitHeroOptionsDialogTitle: String {
        if heroCarouselPage == 0 { return "Outfit" }
        return outfit.wornImage == nil ? "Add Worn Photo" : "Photo"
    }

    @ViewBuilder
    private var outfitHeroOptionsDialogContent: some View {
        if heroCarouselPage == 0 {
            Button("Edit Outfit") {
                isEditingOutfit = true
            }
            if currentOutfitHeroUIImage() != nil {
                Button("Share Image") {
                    shareOutfitImage()
                }
            }
            Button("Cancel", role: .cancel) {}
        } else {
            let hasWornImage = outfit.wornImage != nil
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(hasWornImage ? "Retake Photo" : "Take Photo") {
                    outfitHeroImagePickerSlot = .worn
                    outfitHeroImagePickerSource = .camera
                    isOutfitHeroImagePickerPresented = true
                }
            }
            Button(hasWornImage ? "Replace from Library" : "Choose from Library") {
                outfitHeroImagePickerSlot = .worn
                outfitHeroImagePickerSource = .photoLibrary
                isOutfitHeroImagePickerPresented = true
            }
            if hasWornImage {
                Button("Edit Image") {
                    presentOutfitHeroImageCropper()
                }
                Button("Share Image") {
                    shareOutfitImage()
                }
                Button("Remove Image", role: .destructive) {
                    // Present after the options sheet finishes dismissing.
                    DispatchQueue.main.async {
                        showRemoveWornImageConfirmation = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var outfitImageCropperSheetContent: some View {
        if let image = outfitHeroImageToEdit {
            NavigationView {
                ImageCropperView(
                    originalImage: image,
                    onCrop: { croppedImage in
                        switch outfitHeroCropSlot {
                        case .collage:
                            saveCollageOutfitImage(croppedImage)
                        case .worn:
                            saveWornOutfitImage(croppedImage)
                        }
                        outfitHeroImageToEdit = nil
                        isOutfitImageCropperPresented = false
                    },
                    isEditing: true
                )
                .id(outfitCropEditorSessionID)
            }
        } else {
            Text("No image found to edit.")
                .padding()
        }
    }

    /// Hero pages present in fullscreen (skips missing): collage first, then worn when both exist.
    private func outfitFullscreenHeroPages(hasCollage: Bool, hasWorn: Bool) -> [Int] {
        var pages: [Int] = []
        if hasCollage { pages.append(0) }
        if hasWorn { pages.append(1) }
        return pages
    }

    private func outfitFullscreenIndexForHero(hasCollage: Bool, hasWorn: Bool, heroPage: Int) -> Int {
        let slots = outfitFullscreenHeroPages(hasCollage: hasCollage, hasWorn: hasWorn)
        return slots.firstIndex(of: heroPage) ?? 0
    }

    private func heroCarouselPageForOutfitFullscreenIndex(hasCollage: Bool, hasWorn: Bool, fsIndex: Int) -> Int {
        let slots = outfitFullscreenHeroPages(hasCollage: hasCollage, hasWorn: hasWorn)
        guard fsIndex >= 0, fsIndex < slots.count else { return 0 }
        return slots[fsIndex]
    }

    private func outfitFullscreenSelectedPageIndexBinding(collage: UIImage?, worn: UIImage?) -> Binding<Int> {
        let hasCollage = collage != nil
        let hasWorn = worn != nil
        return Binding(
            get: {
                self.outfitFullscreenIndexForHero(
                    hasCollage: hasCollage,
                    hasWorn: hasWorn,
                    heroPage: self.heroCarouselPage
                )
            },
            set: { newIndex in
                let newHero = self.heroCarouselPageForOutfitFullscreenIndex(
                    hasCollage: hasCollage,
                    hasWorn: hasWorn,
                    fsIndex: newIndex
                )
                if self.heroCarouselPage != newHero {
                    self.heroCarouselPage = newHero
                }
                _ = self.outfit.image
                _ = self.outfit.wornImage
            }
        )
    }

    private func fullScreenOutfitImageView() -> some View {
        OutfitFullScreenView(
            collageImage: cachedCollageUIImage,
            wornImage: cachedWornUIImage,
            selectedPageIndex: outfitFullscreenSelectedPageIndexBinding(
                collage: cachedCollageUIImage,
                worn: cachedWornUIImage
            ),
            isPresented: $isOutfitImageFullScreen
        )
    }

    private var outfitDisplayArea: some View {
        let allowsHeroSwipe = !isReadOnly || cachedWornUIImage != nil

        return ZStack(alignment: .topTrailing) {
            Group {
                if allowsHeroSwipe {
                    TabView(selection: $heroCarouselPage) {
                        Group {
                            if let uiImage = cachedCollageUIImage {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(1, contentMode: .fill)
                                    .frame(width: screenWidth, height: screenWidth)
                                    .clipped()
                                    .onTapGesture {
                                        isOutfitImageFullScreen = true
                                    }
                            } else {
                                collageEmptyPlaceholder
                            }
                        }
                        .tag(0)

                        Group {
                            if let uiImage = cachedWornUIImage {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(1, contentMode: .fill)
                                    .frame(width: screenWidth, height: screenWidth)
                                    .clipped()
                                    .onTapGesture {
                                        isOutfitImageFullScreen = true
                                    }
                            } else {
                                wornEmptyPlaceholder
                            }
                        }
                        .tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                } else {
                    Group {
                        if let uiImage = cachedCollageUIImage {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(1, contentMode: .fill)
                                .frame(width: screenWidth, height: screenWidth)
                                .clipped()
                                .onTapGesture {
                                    isOutfitImageFullScreen = true
                                }
                        } else {
                            collageEmptyPlaceholder
                        }
                    }
                }
            }

            if !isReadOnly,
               (heroCarouselPage == 0 && outfit.image != nil)
                || (heroCarouselPage == 1 && outfit.wornImage != nil) {
                outfitDisplayAreaOptionsButton
            }
        }
        .frame(width: screenWidth, height: screenWidth)
        .onChange(of: heroCarouselPage) { _, _ in
            _ = outfit.image
            _ = outfit.wornImage
        }
    }

    private var collageEmptyPlaceholder: some View {
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
                    Text("Tap to edit outfit")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isReadOnly else { return }
                isEditingOutfit = true
            }
    }

    /// Top-trailing control on the hero image area.
    private var outfitDisplayAreaOptionsButton: some View {
        Button {
            showOutfitHeroOptionsDialog = true
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

    private var wornEmptyPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: screenWidth, height: screenWidth)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.square.badge.camera")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 40))
                    Text("Tap to add a photo of you wearing this outfit")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isReadOnly else { return }
                showOutfitHeroOptionsDialog = true
            }
    }

    private func refreshOutfitHeroImageCache() {
        cachedCollageUIImage = outfit.image.flatMap { UIImage(data: $0) }
        cachedWornUIImage = outfit.wornImage.flatMap { UIImage(data: $0) }
    }

    private func currentOutfitHeroUIImage() -> UIImage? {
        heroCarouselPage == 0 ? cachedCollageUIImage : cachedWornUIImage
    }

    private func presentOutfitHeroImageCropper() {
        guard let uiImage = currentOutfitHeroUIImage() else { return }
        outfitHeroCropSlot = heroCarouselPage == 0 ? .collage : .worn
        outfitHeroImageToEdit = uiImage
        outfitCropEditorSessionID = UUID()
        isOutfitImageCropperPresented = true
    }

    private func saveCollageOutfitImage(_ image: UIImage) {
        guard let data = image.processForStorage() else { return }
        outfit.image = data
        cachedCollageUIImage = image
        setUpdatedAt(outfit)
        do {
            try viewContext.save()
            if outfit.isDraft != true {
                SyncService.shared.syncOutfitIfNeeded(outfit)
            }
        } catch {
            print("Failed to save outfit collage image: \(error.localizedDescription)")
        }
    }

    private func removeOutfitWornImage() {
        outfit.wornImage = nil
        cachedWornUIImage = nil
        setUpdatedAt(outfit)
        do {
            try viewContext.save()
            print("✅ Deleted Worn photo.")
            if outfit.isDraft != true {
                // Same idea as item worn delete: clear R2 + remote URL, skip full outfit upsert.
                SyncService.shared.syncOutfitWornRemovalIfNeeded(outfit)
            }
        } catch {
            print("Failed to remove worn outfit image: \(error.localizedDescription)")
        }
    }

    private func saveWornOutfitImage(_ image: UIImage) {
        guard let data = image.processForStorage() else { return }
        outfit.wornImage = data
        cachedWornUIImage = image
        // Keep pending until onAppear applies it after collage reset (do not clear here).
        pendingSelectWornHero = true
        withAnimation {
            heroCarouselPage = 1
        }
        // Fallback if sheet dismiss does not re-fire onAppear.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard pendingSelectWornHero else { return }
            withAnimation {
                heroCarouselPage = 1
            }
            pendingSelectWornHero = false
        }
        setUpdatedAt(outfit)
        do {
            try viewContext.save()
            if outfit.isDraft != true {
                SyncService.shared.syncOutfitWornUploadIfNeeded(outfit)
            }
        } catch {
            print("Failed to save worn outfit image: \(error.localizedDescription)")
        }
    }

    /// Re-selects Worn after a collage reset when `pendingSelectWornHero` is set.
    /// - Parameter clearAfterApplying: When true (onAppear), clear the flag on the next turn
    ///   after re-asserting Worn so late resets still lose.
    private func applyPendingWornHeroSelectionIfNeeded(clearAfterApplying: Bool) {
        guard pendingSelectWornHero else { return }
        withAnimation {
            heroCarouselPage = 1
        }
        guard clearAfterApplying else { return }
        DispatchQueue.main.async {
            guard pendingSelectWornHero else { return }
            withAnimation {
                heroCarouselPage = 1
            }
            pendingSelectWornHero = false
        }
    }

    private func shareOutfitImage() {
        guard let image = currentOutfitHeroUIImage() else { return }

        if let name = outfit.name, !name.isEmpty {
            shareItems = [name, image]
        } else {
            shareItems = [image]
        }
        showShareSheet = true
    }

    private func deleteOutfit() {
        softDelete(outfit)
        do {
            try viewContext.save()
            SyncService.shared.syncOutfitIfNeeded(outfit)
            dismiss()
        } catch {
            print("Failed to delete outfit: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Featured Items

    @ViewBuilder
    private var featuredItemsContent: some View {
        if orderedItems.isEmpty {
            EmptyView()
        } else if shouldSplitFeaturedItemsByWardrobeType {
            VStack(alignment: .leading, spacing: 4) {
                featuredItemsSubsectionHeader("WISHLIST")
                    .padding(.top, 4)
                featuredItemsGrid(items: orderedWishlistFeaturedItems)
                featuredItemsSubsectionHeader("CLOSET")
                featuredItemsGrid(items: orderedClosetFeaturedItems)
            }
        } else {
            featuredItemsGrid(items: orderedItems)
        }
    }

    private func featuredItemsSubsectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .fontWeight(.semibold)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func openItem(_ item: Item) {
        let uri = item.objectID.uriRepresentation().absoluteString
        if let navigationPath {
            navigationPath.wrappedValue.append(ItemGridFilterRoute.itemDetail(uri: uri))
        } else {
            selectedItemURIForNavigation = uri
        }
    }

    private func featuredItemsGrid(items: [Item]) -> some View {
        LazyVGrid(columns: featuredItemsGridColumns, spacing: 4) {
            ForEach(items, id: \.objectID) { item in
                Button {
                    openItem(item)
                } label: {
                    ItemView(item: item, showsFavoriteOverlay: !isReadOnly)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var itemsSectionHeaderIconName: String {
        if orderedItems.isEmpty {
            return "plus"
        }
        return isItemsSectionExpanded ? "minus" : "plus"
    }

    private func loadRedressSuggestionContextIfNeeded() async {
        guard appCapabilities.enablesFriendsAndSharing,
              !isReadOnly,
              let outfitId = outfit.id else {
            await MainActor.run { redressSuggestionContext = nil }
            return
        }

        let context = await supabaseService.fetchOutfitRedressSuggestionContext(suggestionId: outfitId)
        await MainActor.run {
            redressSuggestionContext = context
            if let context, outfit.persistRedressHistoryIfNeeded(from: context) {
                try? viewContext.save()
            }
        }
    }

    private var canToggleSocialLike: Bool {
        guard isReadOnly, !isLikeBusy, let viewerId = authSession.userId else { return false }
        let ownerId = outfit.userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !ownerId.isEmpty, let ownerUUID = UUID(uuidString: ownerId) else { return false }
        return viewerId != ownerUUID
    }

    /// Owner viewing their own outfit (Closet editable or Profile read-only).
    private var isViewingOwnContent: Bool {
        if !isReadOnly { return true }
        guard let viewerId = authSession.userId else { return false }
        let ownerId = outfit.userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let ownerUUID = UUID(uuidString: ownerId) else { return false }
        return viewerId == ownerUUID
    }

    private func toggleOwnFavorite() {
        outfit.isFavorite.toggle()
        setUpdatedAt(outfit)
        do {
            try viewContext.save()
            SyncService.shared.syncOutfitIfNeeded(outfit)
        } catch {
            viewContext.rollback()
        }
    }

    private func refreshSocialLikeState(outfitId: UUID) async {
        do {
            let state = try await supabaseService.fetchContentLikeState(targetType: .outfit, targetId: outfitId)
            likeCount = state.likeCount
            isLikedByMe = state.likedByMe
        } catch {}
    }

    private func toggleSocialLike() {
        guard canToggleSocialLike, let outfitId = outfit.id else { return }
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
                let state = try await supabaseService.toggleContentLike(targetType: .outfit, targetId: outfitId)
                likeCount = state.likeCount
                isLikedByMe = state.likedByMe
            } catch {
                likeCount = previousCount
                isLikedByMe = previousLiked
            }
        }
    }

    // MARK: - History

    private struct OutfitHistoryEntry: Identifiable {
        let id: String
        let label: String
        let date: Date
        let caption: String?
        let eventName: String?
    }

    private var historySectionHeaderIconName: String {
        isHistoryExpanded ? "minus" : "plus"
    }

    private var outfitHistoryEntries: [OutfitHistoryEntry] {
        var entries: [OutfitHistoryEntry] = []

        if let redressHistory = resolvedRedressHistoryEntry {
            entries.append(redressHistory)
        } else if let date = displayCreatedDate {
            entries.append(OutfitHistoryEntry(
                id: "created",
                label: "Outfit Created",
                date: date,
                caption: nil,
                eventName: nil
            ))
        }

        for event in pastWornEvents(for: outfit) {
            guard let sortDate = eventEffectiveEndDate(event) else { continue }
            let entryID = event.id?.uuidString ?? String(ObjectIdentifier(event).hashValue)
            let trimmedName = event.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            entries.append(OutfitHistoryEntry(
                id: "event-\(entryID)",
                label: wornEventHistoryLabel(for: event),
                date: sortDate,
                caption: wornEventHistoryLocationCaption(for: event),
                eventName: trimmedName.isEmpty ? "Event" : trimmedName
            ))
        }

        return entries.sorted { $0.date > $1.date }
    }

    private var resolvedRedressHistoryEntry: OutfitHistoryEntry? {
        if let redress = redressSuggestionContext {
            return OutfitHistoryEntry(
                id: "redressed",
                label: "Redressed You",
                date: redress.suggestedAt ?? displayCreatedDate ?? Date(),
                caption: redress.submitterCaption,
                eventName: nil
            )
        }

        guard outfit.redressSuggestedAt != nil || outfit.redressSuggesterUsername != nil
            || outfit.redressSuggesterDisplayName != nil else {
            return nil
        }

        let date = outfit.redressSuggestedAt ?? displayCreatedDate ?? Date()
        let caption = outfit.redressSubmitterCaption ?? "Someone"

        return OutfitHistoryEntry(
            id: "redressed",
            label: "Redressed You",
            date: date,
            caption: caption,
            eventName: nil
        )
    }

    private var displayCreatedDate: Date? {
        outfit.createdAt ?? outfit.timestamp
    }

    @ViewBuilder
    private var historyRows: some View {
        ForEach(outfitHistoryEntries) { entry in
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

    // MARK: - Share Functions

    private func getAvailableOutfitAttributes() -> Set<ShareableOutfitAttribute> {
        var available: Set<ShareableOutfitAttribute> = []

        if let name = outfit.name, !name.isEmpty {
            available.insert(.name)
        }
        if outfit.category != nil {
            available.insert(.category)
        }
        if let tags = outfit.tags as? Set<Tag>, !tags.isEmpty {
            available.insert(.tag)
        }
        if let notes = outfit.notes, !notes.isEmpty {
            available.insert(.notes)
        }

        return available
    }
}

// MARK: - ShareableOutfitAttribute

enum ShareableOutfitAttribute: String, CaseIterable, Identifiable {
    case name
    case category
    case tag
    case notes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .name: return "Name"
        case .category: return "Category"
        case .tag: return "Tags"
        case .notes: return "Notes"
        }
    }
}

// MARK: - Default Outfit Share Attributes

private struct DefaultOutfitShareAttributes {
    private static let userDefaultsKey = "defaultOutfitShareAttributes"

    static func save(_ attributes: Set<ShareableOutfitAttribute>) {
        let attributeStrings = attributes.map { $0.rawValue }
        UserDefaults.standard.set(attributeStrings, forKey: userDefaultsKey)
    }

    static func load() -> Set<ShareableOutfitAttribute> {
        guard let attributeStrings = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] else {
            return []
        }
        return Set(attributeStrings.compactMap { ShareableOutfitAttribute(rawValue: $0) })
    }

    static func hasDefaults() -> Bool {
        UserDefaults.standard.array(forKey: userDefaultsKey) != nil
    }
}

// MARK: - OutfitShareSelectionView

struct OutfitShareSelectionView: View {
    @ObservedObject var outfit: Outfit
    @Binding var selectedAttributes: Set<ShareableOutfitAttribute>
    let onShare: (String?) -> Void

    var availableAttributes: Set<ShareableOutfitAttribute> {
        var available: Set<ShareableOutfitAttribute> = []

        if let name = outfit.name, !name.isEmpty {
            available.insert(.name)
        }
        if outfit.category != nil {
            available.insert(.category)
        }
        if let tags = outfit.tags as? Set<Tag>, !tags.isEmpty {
            available.insert(.tag)
        }
        if let notes = outfit.notes, !notes.isEmpty {
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

    var defaultAttributes: Set<ShareableOutfitAttribute> {
        DefaultOutfitShareAttributes.load()
    }

    var hasDefaultAttributes: Bool {
        DefaultOutfitShareAttributes.hasDefaults()
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
                }

                Section {
                    ForEach(ShareableOutfitAttribute.allCases) { attribute in
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
                                    DefaultOutfitShareAttributes.save(selectedAttributes)
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
                                DefaultOutfitShareAttributes.save(selectedAttributes)
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
                        Label("Share", systemImage: "square.and.arrow.up")
                            .labelStyle(.titleAndIcon)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func generateShareText(from attributes: Set<ShareableOutfitAttribute>) -> String {
        var lines: [String] = []

        if attributes.contains(.name), let name = outfit.name, !name.isEmpty {
            lines.append(name)
        }

        if attributes.contains(.category), let category = outfit.category?.name, !category.isEmpty {
            lines.append("Category: \(category)")
        }

        if attributes.contains(.tag), let tags = outfit.tags as? Set<Tag>, !tags.isEmpty {
            let tagNames = tags.compactMap { $0.name }.sorted().joined(separator: ", ")
            lines.append("Tags: \(tagNames)")
        }

        if attributes.contains(.notes), let notes = outfit.notes, !notes.isEmpty {
            lines.append("Notes: \(notes)")
        }

        return lines.joined(separator: "\n")
    }
}

/// Nested item push only when not on Closet/Wishlist `NavigationPath` (those append `itemDetail`).
private struct OutfitDetailNestedItemDestinationModifier: ViewModifier {
    var navigationPath: Binding<NavigationPath>?
    @Binding var selectedItemURIForNavigation: String?
    var isReadOnly: Bool
    var viewContext: NSManagedObjectContext

    @ViewBuilder
    func body(content: Content) -> some View {
        if navigationPath != nil {
            content
        } else {
            content
                .navigationDestination(item: $selectedItemURIForNavigation) { uriString in
                    Group {
                        if let url = URL(string: uriString),
                           let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
                           let item = try? viewContext.existingObject(with: objectID) as? Item {
                            ItemDetailView(item: item, isReadOnly: isReadOnly)
                                .onAppear {
                                    selectedItemURIForNavigation = nil
                                }
                        } else {
                            EmptyView()
                                .onAppear {
                                    selectedItemURIForNavigation = nil
                                }
                        }
                    }
                }
        }
    }
}
