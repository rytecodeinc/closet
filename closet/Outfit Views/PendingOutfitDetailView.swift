//
//  PendingOutfitDetailView.swift
//  closet
//
//  Read-only detail for a pending Redress outfit suggestion (recipient or submitter).
//

import SwiftUI
import CoreData

struct PendingOutfitDetailView: View {
    let recipientUserId: UUID
    let wardrobeId: UUID
    let suggestionSummary: VisibleWardrobeOutfit
    var viewerRole: RedressSuggestionViewerRole = .submitter
    var onSuggestionResolved: (() -> Void)? = nil
    /// Optional @username shown under the Redress nav title (e.g. recipient when viewing as submitter).
    var counterpartUsername: String? = nil
    /// Optional display name for the counterpart (used as Edit Redress headline / recipient profile).
    var counterpartDisplayName: String? = nil
    /// When set, replaces the system back button so the label matches the screen we came from
    /// (needed when this view is pushed from a child that doesn’t own `navigationTitle`).
    var backButtonTitle: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appCapabilities) private var appCapabilities
    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession

    @State private var detail: VisibleOutfitSuggestionDetail?
    @State private var redressContext: OutfitRedressSuggestionContext?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isItemsSectionExpanded = true
    @State private var isAttributesExpanded = false
    @State private var isHistoryExpanded = false
    @State private var heroCarouselPage = 0
    @State private var isOutfitImageFullScreen = false
    @State private var fullscreenPageIndex = 0
    @State private var localItemSheet: PendingOutfitLocalItemSheet?
    @State private var remoteItemSheet: PendingOutfitRemoteItemSheet?
    @State private var isRespondingToSuggestion = false
    @State private var suggestionActionError: String?
    @State private var acceptedOutfit: Outfit?
    @State private var showWithdrawConfirmation = false
    @State private var profileToView: PublicUserProfile?
    @State private var editRedressDestination: PendingRedressEditDestination?

    private var screenWidth: CGFloat { UIScreen.main.bounds.width }

    private let featuredItemsGridColumns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    private var displayName: String? {
        detail?.proposedName ?? suggestionSummary.name
    }

    private var displayNotes: String? {
        detail?.proposedNotes
    }

    private var itemThumbs: [VisibleOutfitItemThumb] {
        detail?.itemThumbnails ?? []
    }

    private var collageURL: URL? {
        detail?.collageImageURL ?? suggestionSummary.collageImageURL
    }

    private var wornURL: URL? {
        urlFrom(suggestionSummary.wornImageUrl)
    }

    private var historyCaption: String? {
        redressContext?.submitterCaption
            ?? suggestionSummary.redressSubmitterCaption
            ?? "Someone"
    }

    private var showsRecipientActions: Bool {
        viewerRole == .recipient && appCapabilities.enablesFriendsAndSharing
    }

    private var showsSubmitterActions: Bool {
        viewerRole == .submitter && appCapabilities.enablesFriendsAndSharing
    }

    private var showsActionButtonsRow: Bool {
        showsRecipientActions || showsSubmitterActions
    }

    /// Prefer summary fields (grid), then detail context (notifications / late hydrate).
    private var suggesterProfile: PublicUserProfile? {
        if let profile = suggestionSummary.suggesterProfile {
            return profile
        }
        guard let userId = redressContext?.suggesterUserId else { return nil }
        let username = redressContext?.suggesterUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !username.isEmpty else { return nil }
        return PublicUserProfile(
            userId: userId,
            username: username,
            displayName: redressContext?.suggesterDisplayName,
            avatarUrl: redressContext?.suggesterAvatarUrl
        )
    }

    /// Leading suggester chip is for the recipient (“who redressed you”).
    private var showsSuggesterLeadingControl: Bool {
        viewerRole == .recipient && suggesterProfile != nil
    }

    private var resolvedCounterpartUsername: String {
        if let counterpartUsername {
            let trimmed = counterpartUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if viewerRole == .recipient {
            let fromSuggester = suggesterProfile?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !fromSuggester.isEmpty { return fromSuggester }
            let caption = historyCaption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !caption.isEmpty, caption != "Someone" { return caption }
        }
        return "user"
    }

    private var sanitizedBackButtonTitle: String? {
        guard let backButtonTitle else { return nil }
        let trimmed = backButtonTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("@") {
            let withoutAt = String(trimmed.dropFirst())
            return withoutAt.isEmpty ? nil : withoutAt
        }
        return trimmed
    }

    private var recipientProfileForEdit: PublicUserProfile? {
        guard showsSubmitterActions else { return nil }
        let username = resolvedCounterpartUsername
        let display = counterpartDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return PublicUserProfile(
            userId: recipientUserId,
            username: username.hasPrefix("@") ? String(username.dropFirst()) : username,
            displayName: display.isEmpty ? nil : display
        )
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading redress…")
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
        .navigationTitle("Redress")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(sanitizedBackButtonTitle != nil)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let sanitizedBackButtonTitle {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(sanitizedBackButtonTitle)
                        }
                    }
                    .accessibilityLabel("Back to \(sanitizedBackButtonTitle)")
                }
            }
        }
        .task(id: suggestionSummary.id) {
            await loadDetail()
        }
        .onAppear {
            heroCarouselPage = 0
        }
        .onChange(of: wornURL?.absoluteString) { _, _ in
            if wornURL == nil, heroCarouselPage == 1 {
                heroCarouselPage = 0
            }
        }
        .navigationDestination(item: $profileToView) { profile in
            ProfileView(viewedProfile: profile)
        }
        .navigationDestination(item: $editRedressDestination) { destination in
            // Same pattern as ItemDetailView → OutfitAddView / OutfitDetailView → ItemDetailView:
            // clear the item binding on appear so SwiftUI does not re-evaluate this
            // destination in a loop (which freezes the stack).
            OutfitAddView(
                redressRecipient: destination.recipient,
                editingSuggestionId: destination.suggestionId,
                editingSuggestionWardrobeId: destination.wardrobeId,
                editingProposedName: destination.proposedName,
                editingProposedNotes: destination.proposedNotes,
                editingItemThumbnails: destination.itemThumbnails,
                sessionID: destination.id,
                onRedressSent: {
                    onSuggestionResolved?()
                    dismiss()
                }
            )
            .id(destination.id)
            .onAppear {
                print("🧭 [PendingOutfitDetailView] OutfitAddView appeared; resetting editRedressDestination to nil.")
                editRedressDestination = nil
            }
        }
        .sheet(item: $localItemSheet) { presentation in
            NavigationStack {
                ItemDetailView(item: presentation.item, isReadOnly: true)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { localItemSheet = nil }
                        }
                    }
            }
        }
        .sheet(item: $remoteItemSheet) { presentation in
            NavigationStack {
                ReadOnlyItemDetailView(
                    ownerUserId: recipientUserId,
                    wardrobeId: wardrobeId,
                    itemSummary: presentation.summary
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { remoteItemSheet = nil }
                    }
                }
            }
        }
        .navigationDestination(item: $acceptedOutfit) { outfit in
            OutfitDetailView(outfit: outfit)
        }
        .fullScreenCover(isPresented: $isOutfitImageFullScreen) {
            RemoteOutfitFullScreenView(
                imageURLs: heroImageURLs,
                selectedPageIndex: $fullscreenPageIndex,
                isPresented: $isOutfitImageFullScreen
            )
        }
        .alert("Couldn't Update Redress", isPresented: suggestionActionErrorPresented) {
            Button("OK", role: .cancel) { suggestionActionError = nil }
        } message: {
            Text(suggestionActionError ?? "")
        }
        .alert("Withdraw Redress?", isPresented: $showWithdrawConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Withdraw", role: .destructive) {
                Task { await withdrawSuggestion() }
            }
        } message: {
            Text("This will remove your pending Redress. This can't be undone.")
        }
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    suggestionHeroDisplayArea

                    pendingHeroToolbarRow

                    redressActionsEngagementRow
                }
                .listRowInsets(EdgeInsets(.zero))
                .listRowSeparator(.hidden)
                .listSectionSpacing(0)

                if !itemThumbs.isEmpty {
                    Section {
                        if isItemsSectionExpanded {
                            featuredItemsContent
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
                    label: "Redressed You",
                    date: detail?.createdAt,
                    caption: historyCaption,
                    isExpanded: $isHistoryExpanded
                )
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
        }
    }

    private var heroImageURLs: [URL] {
        var urls: [URL] = []
        if let collage = collageURL { urls.append(collage) }
        if let worn = wornURL, !urls.contains(worn) { urls.append(worn) }
        return urls
    }

    private func urlFrom(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string) else { return nil }
        return url
    }

    private var suggestionHeroDisplayArea: some View {
        Group {
            if wornURL != nil {
                TabView(selection: $heroCarouselPage) {
                    Group {
                        if let url = collageURL {
                            suggestionHeroImage(url: url)
                        } else {
                            suggestionPlaceholder
                        }
                    }
                    .tag(0)

                    Group {
                        if let url = wornURL {
                            suggestionHeroImage(url: url)
                        } else {
                            suggestionWornPlaceholder
                        }
                    }
                    .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else if let url = collageURL {
                suggestionHeroImage(url: url)
            } else {
                suggestionPlaceholder
            }
        }
        .frame(width: screenWidth, height: screenWidth)
    }

    private func suggestionHeroImage(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: screenWidth, height: screenWidth)
                    .clipped()
            case .failure:
                suggestionPlaceholder
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

    private var suggestionPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: screenWidth, height: screenWidth)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "tshirt")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 40))
                    Text("No collage")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
    }

    private var suggestionWornPlaceholder: some View {
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

    /// Optional suggester chip (recipient) and Decline/Accept or Withdraw/Edit actions.
    private var redressActionsEngagementRow: some View {
        Group {
            if showsActionButtonsRow {
                Group {
                    if showsRecipientActions {
                        redressRecipientActionsRow
                    } else if showsSubmitterActions {
                        redressSubmitterActionsRow
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
            }
        }
    }

    private var pendingHeroToolbarRow: some View {
        HStack(spacing: 12) {
            if showsSuggesterLeadingControl, let profile = suggesterProfile {
                suggesterLeadingControl(profile: profile)
            }
            Spacer(minLength: 12)
            Picker("", selection: heroSegmentSelection) {
                ForEach(pendingHeroSegments, id: \.self) { segment in
                    Image(systemName: segment.systemImage)
                        .tag(segment)
                        .accessibilityLabel(segment.accessibilityLabel)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: wornURL != nil ? 140 : 70)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }

    private var pendingHeroSegments: [SocialEngagementToolbarSegment] {
        wornURL != nil
            ? SocialEngagementToolbarSegment.allCases
            : [.tshirt]
    }

    private var heroSegmentSelection: Binding<SocialEngagementToolbarSegment> {
        Binding(
            get: { heroCarouselPage == 0 ? .tshirt : .worn },
            set: { segment in
                withAnimation {
                    heroCarouselPage = segment == .tshirt ? 0 : 1
                }
            }
        )
    }

    private func suggesterLeadingControl(profile: PublicUserProfile) -> some View {
        Button {
            profileToView = profile
        } label: {
            HStack(spacing: 8) {
                PublicUserProfileAvatarView(profile: profile, size: 28)
                Text(profile.username)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View \(profile.username)'s profile")
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

    @ViewBuilder
    private var featuredItemsContent: some View {
        if shouldSplitPendingItemsByWardrobe {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(pendingNamedWardrobeSections.enumerated()), id: \.element.id) { index, section in
                    pendingItemsSubsectionHeader(section.name)
                        .padding(.top, index == 0 ? 4 : 0)
                    featuredItemsGrid(items: section.items)
                }
            }
        } else {
            featuredItemsGrid(items: itemThumbs)
        }
    }

    private func pendingItemsSubsectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .fontWeight(.semibold)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var sourceWardrobeTypeForPending: String {
        resolveWardrobeMeta(id: wardrobeId)?.type ?? "closet"
    }

    private var shouldSplitPendingItemsByWardrobe: Bool {
        pendingNamedWardrobeSections.count >= 2
    }

    private struct PendingWardrobeThumbSection: Identifiable {
        let id: UUID
        let name: String
        let wardrobeType: String
        let items: [VisibleOutfitItemThumb]
    }

    private var pendingNamedWardrobeSections: [PendingWardrobeThumbSection] {
        struct Acc {
            var name: String
            var type: String
            var items: [VisibleOutfitItemThumb]
        }
        var grouped: [UUID: Acc] = [:]
        var orderKeys: [UUID] = []

        for thumb in itemThumbs {
            let meta = preferredWardrobeMeta(for: thumb.id)
            let key = meta?.id ?? wardrobeId
            let name = meta?.name ?? "Wardrobe"
            let type = meta?.type ?? sourceWardrobeTypeForPending
            if grouped[key] == nil {
                grouped[key] = Acc(name: name, type: type, items: [])
                orderKeys.append(key)
            }
            grouped[key]?.items.append(thumb)
        }

        let sourceType = sourceWardrobeTypeForPending
        let sections = orderKeys.compactMap { key -> PendingWardrobeThumbSection? in
            guard let acc = grouped[key], !acc.items.isEmpty else { return nil }
            return PendingWardrobeThumbSection(
                id: key,
                name: acc.name,
                wardrobeType: acc.type,
                items: acc.items
            )
        }

        guard sections.count >= 2 else { return sections }

        return sections.sorted { a, b in
            // Viewing / source wardrobe first.
            if a.id == wardrobeId && b.id != wardrobeId { return true }
            if b.id == wardrobeId && a.id != wardrobeId { return false }
            let ra = a.wardrobeType == sourceType ? 0 : 1
            let rb = b.wardrobeType == sourceType ? 0 : 1
            if ra != rb { return ra < rb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func preferredWardrobeMeta(for itemId: UUID) -> (id: UUID, name: String, type: String)? {
        guard let item = localItem(for: itemId) else {
            return resolveWardrobeMeta(id: wardrobeId)
        }
        let wardrobes = ((item.wardrobes as? Set<Wardrobe>) ?? []).filter {
            $0.isSoftDeleted != true
        }
        if let preferred = wardrobes.first(where: { $0.id == wardrobeId }),
           let id = preferred.id {
            let type = (preferred.type ?? "closet").lowercased() == "wishlist" ? "wishlist" : "closet"
            let trimmed = preferred.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = trimmed.isEmpty ? (type == "wishlist" ? "Wishlist" : "Closet") : trimmed
            return (id, name, type)
        }
        // Prefer a wardrobe of the non-source type when item isn't in the viewing wardrobe.
        let sourceType = sourceWardrobeTypeForPending
        let otherType = sourceType == "wishlist" ? "closet" : "wishlist"
        let ordered = wardrobes.sorted { a, b in
            let aType = (a.type ?? "closet").lowercased()
            let bType = (b.type ?? "closet").lowercased()
            let ar = aType == otherType ? 0 : 1
            let br = bType == otherType ? 0 : 1
            if ar != br { return ar < br }
            return (a.name ?? "").localizedCaseInsensitiveCompare(b.name ?? "") == .orderedAscending
        }
        guard let pick = ordered.first, let id = pick.id else {
            return resolveWardrobeMeta(id: wardrobeId)
        }
        let type = (pick.type ?? "closet").lowercased() == "wishlist" ? "wishlist" : "closet"
        let trimmed = pick.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmed.isEmpty ? (type == "wishlist" ? "Wishlist" : "Closet") : trimmed
        return (id, name, type)
    }

    private func resolveWardrobeMeta(id: UUID) -> (id: UUID, name: String, type: String)? {
        let request = Wardrobe.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let wardrobe = try? viewContext.fetch(request).first, let wid = wardrobe.id else { return nil }
        let type = (wardrobe.type ?? "closet").lowercased() == "wishlist" ? "wishlist" : "closet"
        let trimmed = wardrobe.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmed.isEmpty ? (type == "wishlist" ? "Wishlist" : "Closet") : trimmed
        return (wid, name, type)
    }

    private func featuredItemsGrid(items: [VisibleOutfitItemThumb]) -> some View {
        LazyVGrid(columns: featuredItemsGridColumns, spacing: 4) {
            ForEach(items) { thumb in
                Button {
                    openItem(thumb: thumb)
                } label: {
                    if let item = localItem(for: thumb.id) {
                        ItemView(item: item)
                    } else {
                        RemoteReadOnlyOutfitItemCell(thumb: thumb, usesClearBackground: true)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func localItem(for itemId: UUID) -> Item? {
        guard let userId = authSession.userId?.uuidString else { return nil }
        let request = NSFetchRequest<Item>(entityName: "Item")
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "id == %@", itemId as CVarArg),
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "isDraft != YES"),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
        ])
        return try? viewContext.fetch(request).first
    }

    private func openItem(thumb: VisibleOutfitItemThumb) {
        if let item = localItem(for: thumb.id) {
            localItemSheet = PendingOutfitLocalItemSheet(item: item)
            return
        }

        remoteItemSheet = PendingOutfitRemoteItemSheet(
            summary: VisibleWardrobeItem(
                id: thumb.id,
                name: thumb.name,
                thumbnailUrl: thumb.thumbnailUrl,
                imageUrl: nil
            )
        )
    }

    private var suggestionActionErrorPresented: Binding<Bool> {
        Binding(
            get: { suggestionActionError != nil },
            set: { if !$0 { suggestionActionError = nil } }
        )
    }

    @ViewBuilder
    private var redressRecipientActionsRow: some View {
        HStack(spacing: 8) {
            Button {
                Task { await respondToSuggestion(accept: true) }
            } label: {
                HStack(spacing: 6) {
                    if isRespondingToSuggestion {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "hanger")
                            .font(.subheadline.weight(.semibold))
                        Text("Accept")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.cayenne.gradient)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRespondingToSuggestion)

            Button {
                Task { await respondToSuggestion(accept: false) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                    Text("Decline")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRespondingToSuggestion)
        }
    }

    @ViewBuilder
    private var redressSubmitterActionsRow: some View {
        HStack(spacing: 8) {
            Button {
                showWithdrawConfirmation = true
            } label: {
                HStack(spacing: 6) {
                    if isRespondingToSuggestion {
                        ProgressView()
                    } else {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                        Text("Withdraw")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.clear)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRespondingToSuggestion)
            .frame(maxWidth: .infinity)

            Button {
                guard let recipient = recipientProfileForEdit else { return }
                editRedressDestination = PendingRedressEditDestination(
                    suggestionId: suggestionSummary.id,
                    wardrobeId: wardrobeId,
                    recipient: recipient,
                    proposedName: detail?.proposedName ?? suggestionSummary.name,
                    proposedNotes: detail?.proposedNotes,
                    itemThumbnails: detail?.itemThumbnails ?? []
                )
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.semibold))
                    Text("Edit")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.cayenne.gradient)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRespondingToSuggestion)
            .frame(maxWidth: .infinity)
        }
    }

    private func loadDetail() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            detail = try await supabaseService.fetchOutfitSuggestionDetail(
                suggestionId: suggestionSummary.id,
                recipientId: recipientUserId,
                wardrobeId: wardrobeId
            )
            if detail == nil {
                loadError = "This Redress is not available."
            } else {
                isItemsSectionExpanded = !itemThumbs.isEmpty
                redressContext = await supabaseService.fetchOutfitRedressSuggestionContext(
                    suggestionId: suggestionSummary.id
                )
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func withdrawSuggestion() async {
        guard authSession.userId != nil else { return }

        await MainActor.run {
            isRespondingToSuggestion = true
            suggestionActionError = nil
        }

        do {
            try await supabaseService.withdrawRedressSuggestion(
                suggestionId: suggestionSummary.id,
                recipientId: recipientUserId
            )
            await deleteSuggestionImageFromR2IfPossible()
            await MainActor.run {
                onSuggestionResolved?()
                dismiss()
            }
        } catch {
            await MainActor.run {
                suggestionActionError = error.localizedDescription
            }
        }

        await MainActor.run {
            isRespondingToSuggestion = false
        }
    }

    private func respondToSuggestion(accept: Bool) async {
        guard let recipientUserId = authSession.userId else { return }
        let suggestionId = suggestionSummary.id

        await MainActor.run {
            isRespondingToSuggestion = true
            suggestionActionError = nil
        }

        do {
            if accept {
                // Materialize while still `pending` — respond() flips status to `accepted`,
                // which would make a post-respond materialize fail as "no longer available".
                let outfit = try await OutfitSuggestionMaterializer.materializeOutfitSuggestion(
                    suggestionId: suggestionId,
                    recipientUserId: recipientUserId,
                    in: viewContext,
                    supabaseService: supabaseService
                )
                try await supabaseService.respondToOutfitSuggestion(suggestionId: suggestionId, accept: true)
                await markRedressNotificationReadIfNeeded(suggestionId: suggestionId)
                // Suggestion collage is superseded by the materialized outfit collage upload.
                await deleteSuggestionImageFromR2IfPossible()

                if let context = redressContext {
                    outfit.persistRedressHistory(from: context)
                }
                _ = outfit.persistRedressSuggesterIfNeeded(from: suggestionSummary)
                setUpdatedAt(outfit)
                try viewContext.save()
                SyncService.shared.syncOutfitIfNeeded(outfit)
                await MainActor.run {
                    onSuggestionResolved?()
                    acceptedOutfit = outfit
                }
            } else {
                try await supabaseService.respondToOutfitSuggestion(suggestionId: suggestionId, accept: false)
                await markRedressNotificationReadIfNeeded(suggestionId: suggestionId)
                OutfitSuggestionMaterializer.deleteMaterializedOutfitIfExists(
                    suggestionId: suggestionId,
                    recipientUserId: recipientUserId,
                    in: viewContext
                )
                await deleteSuggestionImageFromR2IfPossible()
                await MainActor.run {
                    onSuggestionResolved?()
                    dismiss()
                }
            }
        } catch {
            await MainActor.run {
                suggestionActionError = error.localizedDescription
            }
        }

        await MainActor.run {
            isRespondingToSuggestion = false
        }
    }

    private func markRedressNotificationReadIfNeeded(suggestionId: UUID) async {
        guard let notifications = try? await supabaseService.fetchNotifications() else { return }
        let matching = notifications.filter {
            $0.type == "outfit_suggestion"
                && $0.payload?["suggestion_id"] == suggestionId.uuidString
                && !$0.is_read
        }
        for notification in matching {
            try? await supabaseService.markNotificationRead(id: notification.id)
        }
    }

    /// Suggestion collages live under the suggester's R2 prefix.
    private func deleteSuggestionImageFromR2IfPossible() async {
        let ownerId =
            suggestionSummary.suggesterUserId
            ?? redressContext?.suggesterUserId
            ?? (viewerRole == .submitter ? authSession.userId : nil)
        guard let ownerId else {
            print("⚠️ Skipping suggestion R2 delete — missing suggester user id")
            return
        }
        do {
            try await supabaseService.deleteOutfitSuggestionImage(
                suggestionId: suggestionSummary.id,
                ownerUserId: ownerId
            )
        } catch {
            print("⚠️ Failed to delete suggestion image from R2: \(error.localizedDescription)")
        }
    }
}

/// Edit Redress push payload (`navigationDestination(item:)`).
struct PendingRedressEditDestination: Identifiable, Hashable {
    let suggestionId: UUID
    let wardrobeId: UUID
    let recipient: PublicUserProfile
    let proposedName: String?
    let proposedNotes: String?
    let itemThumbnails: [VisibleOutfitItemThumb]

    var id: UUID { suggestionId }
}

private struct PendingOutfitLocalItemSheet: Identifiable {
    let item: Item
    var id: String { item.objectID.uriRepresentation().absoluteString }
}

private struct PendingOutfitRemoteItemSheet: Identifiable {
    let summary: VisibleWardrobeItem
    var id: UUID { summary.id }
}
