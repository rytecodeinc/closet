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
    @State private var heroSegment: SocialEngagementToolbarSegment = .tshirt
    @State private var isOutfitImageFullScreen = false
    @State private var fullscreenPageIndex = 0
    @State private var localItemSheet: PendingOutfitLocalItemSheet?
    @State private var remoteItemSheet: PendingOutfitRemoteItemSheet?
    @State private var isRespondingToSuggestion = false
    @State private var suggestionActionError: String?
    @State private var acceptedOutfit: Outfit?
    @State private var showWithdrawConfirmation = false
    @State private var profileToView: PublicUserProfile?

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

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading suggestion…")
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
        .navigationTitle("Redressed You")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: suggestionSummary.id) {
            await loadDetail()
        }
        .navigationDestination(item: $profileToView) { profile in
            ProfileView(viewedProfile: profile)
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
        .alert("Couldn't Update Suggestion", isPresented: suggestionActionErrorPresented) {
            Button("OK", role: .cancel) { suggestionActionError = nil }
        } message: {
            Text(suggestionActionError ?? "")
        }
        .alert("Withdraw Suggestion?", isPresented: $showWithdrawConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Withdraw", role: .destructive) {
                Task { await withdrawSuggestion() }
            }
        } message: {
            Text("This will remove your pending outfit suggestion. This can't be undone.")
        }
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    suggestionHeroDisplayArea

                    redressActionsEngagementRow
                }
                .listRowInsets(EdgeInsets(.zero))
                .listRowSeparator(.hidden)
                .listSectionSpacing(0)

                if !itemThumbs.isEmpty {
                    Section {
                        if isItemsSectionExpanded {
                            featuredItemsGrid
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
        }
    }

    private var heroImageURLs: [URL] {
        if let collage = collageURL { return [collage] }
        return []
    }

    private var suggestionHeroDisplayArea: some View {
        Group {
            if let url = collageURL {
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

    /// Picker row with optional suggester chip; Decline/Accept (or Withdraw) sit on the row below.
    private var redressActionsEngagementRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if showsSuggesterLeadingControl, let profile = suggesterProfile {
                    suggesterLeadingControl(profile: profile)
                }

                Spacer(minLength: 0)

                Picker("", selection: $heroSegment) {
                    Image(systemName: SocialEngagementToolbarSegment.tshirt.systemImage)
                        .tag(SocialEngagementToolbarSegment.tshirt)
                        .accessibilityLabel(SocialEngagementToolbarSegment.tshirt.accessibilityLabel)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 70)
            }

            if showsActionButtonsRow {
                Group {
                    if showsRecipientActions {
                        redressRecipientActionsRow
                    } else if showsSubmitterActions {
                        redressSubmitterActionsRow
                    }
                }
                .padding(.top, 6)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
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

    private var featuredItemsGrid: some View {
        LazyVGrid(columns: featuredItemsGridColumns, spacing: 4) {
            ForEach(itemThumbs) { thumb in
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
                        Image("Redress.SFSymbol")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .fixedSize(horizontal: true, vertical: true)
                            .transaction { $0.animation = nil }
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
        Button {
            showWithdrawConfirmation = true
        } label: {
            HStack(spacing: 6) {
                if isRespondingToSuggestion {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.uturn.backward")
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
                    .fill(Color(.secondarySystemFill))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRespondingToSuggestion)
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
                loadError = "This suggestion is not available."
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
}

private struct PendingOutfitLocalItemSheet: Identifiable {
    let item: Item
    var id: String { item.objectID.uriRepresentation().absoluteString }
}

private struct PendingOutfitRemoteItemSheet: Identifiable {
    let summary: VisibleWardrobeItem
    var id: UUID { summary.id }
}
