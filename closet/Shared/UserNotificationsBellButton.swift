//
//  UserNotificationsBellButton.swift
//  closet
//
//  Notifications bell + list (friend requests, Redress, etc.).
//

import SwiftUI
import CoreData
import UIKit

private struct RemoteSquareThumbnailView: View {
    let url: URL?
    var size: CGFloat = 56

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if url != nil, isLoading {
                placeholder
                    .overlay { ProgressView().scaleEffect(0.7) }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: url?.absoluteString ?? "") {
            await loadImage()
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(.systemGray6)
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func loadImage() async {
        image = nil
        guard let url else {
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let loaded = UIImage(data: data) else {
                return
            }
            image = loaded
        } catch {
            // Keep placeholder on failure.
        }
    }
}

struct UserNotificationsBellButton: View {
    var onTap: () -> Void

    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession

    @State private var unreadNotificationsCount = 0

    var body: some View {
        Button {
            onTap()
        } label: {
            bellLabel
        }
        .task(id: authSession.userId) {
            await refreshUnreadCount()
        }
        .onAppear {
            Task { await refreshUnreadCount() }
        }
    }

    private var bellLabel: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "bell")
            if unreadNotificationsCount > 0 {
                Text("\(min(unreadNotificationsCount, 99))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .clipShape(Capsule())
                    .offset(x: 8, y: -8)
            }
        }
    }

    private func refreshUnreadCount() async {
        guard authSession.isAuthenticated else {
            unreadNotificationsCount = 0
            return
        }

        do {
            let fetched = try await supabaseService.fetchNotifications()
            unreadNotificationsCount = fetched.filter { !$0.is_read }.count
        } catch {
            unreadNotificationsCount = 0
        }
    }
}

struct UserNotificationsView: View {
    var onDismiss: () -> Void = {}
    var tabBarHideState: TabBarHideState? = nil

    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession
    @Environment(\.managedObjectContext) private var viewContext

    private enum NotificationFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case items = "Items"
        case outfits = "Outfits"
        case friends = "Friends"

        var id: String { rawValue }
    }

    @State private var notifications: [NotificationRecord] = []
    @State private var selectedFilter: NotificationFilter = .all
    @State private var isLoadingNotifications = false
    @State private var notificationsError: String?
    @State private var respondingNotificationIds: Set<UUID> = []
    @State private var selectedPendingRedress: PendingRedressNavigationDestination?
    @State private var selectedLikedOutfitURI: String?
    @State private var selectedLikedItemURI: String?
    @State private var selectedProfile: PublicUserProfile?
    @State private var actorProfilesByUserId: [UUID: PublicUserProfile] = [:]
    @State private var openingSuggestionId: UUID?
    @State private var openingLikedOutfitId: UUID?
    @State private var openingLikedItemId: UUID?
    @State private var suggestionThumbnailURLs: [UUID: URL] = [:]

    private var filteredNotifications: [NotificationRecord] {
        notifications.filter { matchesFilter($0, selectedFilter) }
    }

    var body: some View {
        notificationsContent
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedPendingRedress) { destination in
                PendingOutfitDetailView(
                    recipientUserId: destination.recipientUserId,
                    wardrobeId: destination.wardrobeId,
                    suggestionSummary: destination.suggestionSummary,
                    viewerRole: destination.viewerRole,
                    onSuggestionResolved: {
                        Task { await loadNotifications() }
                    },
                    backButtonTitle: "Notifications"
                )
            }
            .navigationDestination(item: $selectedLikedOutfitURI) { uriString in
                Group {
                    if let outfit = managedOutfit(forURI: uriString) {
                        OutfitDetailView(outfit: outfit)
                    } else {
                        Text("This outfit is no longer available.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationDestination(item: $selectedLikedItemURI) { uriString in
                Group {
                    if let item = managedItem(forURI: uriString) {
                        ItemDetailView(item: item)
                    } else {
                        Text("This item is no longer available.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationDestination(item: $selectedProfile) { profile in
                // Keep binding until system pop — same as FriendsView → profile.
                // Clearing onAppear orphans this push and breaks Back.
                ProfileView(viewedProfile: profile, sharedTabBarHideState: tabBarHideState)
            }
            .task {
                await loadNotifications(markPassiveAsRead: true)
            }
            .onDisappear {
                onDismiss()
            }
    }

    @ViewBuilder
    private var notificationsContent: some View {
        if isLoadingNotifications {
            ProgressView("Loading notifications…")
        } else if let error = notificationsError {
            Text(error)
                .foregroundColor(.red)
                .padding()
        } else {
            VStack(spacing: 0) {
                notificationFilterPicker
                if notifications.isEmpty {
                    Text("No new notifications")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                } else if filteredNotifications.isEmpty {
                    Text(emptyFilterMessage)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                } else {
                    List(filteredNotifications) { notification in
                        notificationRow(notification)
                            .listRowBackground(Color(.systemBackground))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemBackground))
                }
            }
        }
    }

    private var notificationFilterPicker: some View {
        Picker("Filter", selection: $selectedFilter) {
            ForEach(NotificationFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var emptyFilterMessage: String {
        switch selectedFilter {
        case .all:
            return "No new notifications"
        case .items:
            return "No item notifications"
        case .outfits:
            return "No outfit notifications"
        case .friends:
            return "No friend notifications"
        }
    }

    private func matchesFilter(_ notification: NotificationRecord, _ filter: NotificationFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .items:
            if notification.type == "content_share",
               notification.payload?["target_type"] == "item" {
                return true
            }
            return notification.type == "content_like"
                && notification.payload?["target_type"] == "item"
        case .outfits:
            if notification.type == "outfit_suggestion" { return true }
            if notification.type == "content_share",
               notification.payload?["target_type"] == "outfit" {
                return true
            }
            return notification.type == "content_like"
                && notification.payload?["target_type"] == "outfit"
        case .friends:
            return notification.type == "friend_request"
                || notification.type == "friend_accepted"
        }
    }

    private func notificationRow(_ notification: NotificationRecord) -> some View {
        // Match FriendsView row: 44pt avatar, headline title, subheadline secondary date.
        HStack(spacing: 12) {
            actorAvatarButton(for: notification)

            if isOutfitLikeNotification(notification) {
                Button {
                    openLikedOutfitIfNeeded(from: notification)
                } label: {
                    notificationTextAndThumbnail(notification)
                }
                .buttonStyle(.plain)
                .disabled(openingLikedOutfitId == likedOutfitId(for: notification))
            } else {
                notificationTextAndThumbnail(notification)
            }
        }
        .padding(.vertical, 4)
    }

    private func notificationTextAndThumbnail(_ notification: NotificationRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                notificationPrimaryLine(notification)

                if notification.type != "outfit_suggestion",
                   let body = notification.body, !body.isEmpty {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                notificationDateLine(notification)

                if notification.type == "friend_request", notification.is_read == false {
                    friendRequestActions(for: notification)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingContentThumbnail(for: notification)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func actorAvatarButton(for notification: NotificationRecord) -> some View {
        if let profile = actorProfile(for: notification) {
            Button {
                selectedProfile = profile
            } label: {
                PublicUserProfileAvatarView(profile: profile, size: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(actorDisplayName(for: notification))'s profile")
        } else {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                }
        }
    }

    @ViewBuilder
    private func notificationPrimaryLine(_ notification: NotificationRecord) -> some View {
        let name = actorDisplayName(for: notification)
        let suffix = notificationActionSuffix(for: notification)
        let linksActionSuffix = notification.type == "outfit_suggestion"
            || isOutfitLikeNotification(notification)

        // Single Text flow so wrapping stays left-aligned (HStack + Buttons right-align wrap).
        Text(notificationTitleAttributed(name: name, suffix: suffix, linksActionSuffix: linksActionSuffix))
            .font(.headline)
            .foregroundStyle(.primary)
            .tint(.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                switch url.scheme {
                case "closet-notification-profile":
                    if let profile = actorProfile(for: notification) {
                        selectedProfile = profile
                    }
                    return .handled
                case "closet-notification-action":
                    if isOutfitLikeNotification(notification) {
                        openLikedOutfitIfNeeded(from: notification)
                    } else {
                        openOutfitSuggestionIfNeeded(from: notification)
                    }
                    return .handled
                default:
                    return .systemAction
                }
            })
    }

    private func notificationTitleAttributed(
        name: String,
        suffix: String,
        linksActionSuffix: Bool
    ) -> AttributedString {
        var namePart = AttributedString(name)
        namePart.font = .headline
        namePart.foregroundColor = .primary
        namePart.link = URL(string: "closet-notification-profile://actor")

        var suffixPart = AttributedString(suffix)
        suffixPart.font = .headline
        suffixPart.foregroundColor = .primary
        if linksActionSuffix {
            suffixPart.link = URL(string: "closet-notification-action://content")
        }

        return namePart + suffixPart
    }

    @ViewBuilder
    private func notificationDateLine(_ notification: NotificationRecord) -> some View {
        // Same typography as FriendsView display name.
        let dateText = Text(notification.created_at, style: .date)
            .font(.subheadline)
            .foregroundStyle(.secondary)

        if notification.type == "outfit_suggestion" {
            Button {
                openOutfitSuggestionIfNeeded(from: notification)
            } label: {
                dateText
            }
            .buttonStyle(.plain)
        } else {
            dateText
        }
    }

    @ViewBuilder
    private func trailingContentThumbnail(for notification: NotificationRecord) -> some View {
        if notification.type == "outfit_suggestion" {
            let isOpening = openingSuggestionId == suggestionId(for: notification)
            Button {
                openOutfitSuggestionIfNeeded(from: notification)
            } label: {
                ZStack {
                    outfitSuggestionThumbnail(for: notification)
                    if isOpening {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.25))
                        ProgressView()
                            .tint(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isOpening)
        } else if isOutfitLikeNotification(notification) {
            let isOpening = openingLikedOutfitId == likedOutfitId(for: notification)
            ZStack {
                RemoteSquareThumbnailView(url: contentLikeImageURL(for: notification))
                if isOpening {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.25))
                    ProgressView()
                        .tint(.white)
                }
            }
        } else if isItemLikeNotification(notification) {
            let isOpening = openingLikedItemId == likedContentId(for: notification)
            Button {
                openLikedItemIfNeeded(from: notification)
            } label: {
                ZStack {
                    RemoteSquareThumbnailView(url: contentLikeImageURL(for: notification))
                    if isOpening {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.25))
                        ProgressView()
                            .tint(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isOpening)
        } else if notification.type == "content_like" || notification.type == "content_share" {
            RemoteSquareThumbnailView(url: contentLikeImageURL(for: notification))
        }
    }

    private func openOutfitSuggestionIfNeeded(from notification: NotificationRecord) {
        let isOpening = openingSuggestionId == suggestionId(for: notification)
        guard !isOpening else { return }
        Task { await openOutfitSuggestion(from: notification) }
    }

    private func isOutfitLikeNotification(_ notification: NotificationRecord) -> Bool {
        notification.type == "content_like" && notification.payload?["target_type"] == "outfit"
    }

    private func isItemLikeNotification(_ notification: NotificationRecord) -> Bool {
        notification.type == "content_like" && notification.payload?["target_type"] == "item"
    }

    private func likedContentId(for notification: NotificationRecord) -> UUID? {
        notification.payload?["target_id"].flatMap(UUID.init(uuidString:))
    }

    private func likedOutfitId(for notification: NotificationRecord) -> UUID? {
        likedContentId(for: notification)
    }

    private func openLikedOutfitIfNeeded(from notification: NotificationRecord) {
        guard isOutfitLikeNotification(notification),
              let outfitId = likedOutfitId(for: notification),
              openingLikedOutfitId != outfitId else { return }

        openingLikedOutfitId = outfitId
        notificationsError = nil

        guard let outfit = localOutfit(id: outfitId) else {
            openingLikedOutfitId = nil
            notificationsError = "Could not open this outfit."
            return
        }

        selectedLikedOutfitURI = outfit.objectID.uriRepresentation().absoluteString
        openingLikedOutfitId = nil
    }

    private func openLikedItemIfNeeded(from notification: NotificationRecord) {
        guard isItemLikeNotification(notification),
              let itemId = likedContentId(for: notification),
              openingLikedItemId != itemId else { return }

        openingLikedItemId = itemId
        notificationsError = nil

        guard let item = localItem(id: itemId) else {
            openingLikedItemId = nil
            notificationsError = "Could not open this item."
            return
        }

        selectedLikedItemURI = item.objectID.uriRepresentation().absoluteString
        openingLikedItemId = nil
    }

    private func localItem(id: UUID) -> Item? {
        let request = NSFetchRequest<Item>(entityName: "Item")
        request.fetchLimit = 1
        var predicates = [
            NSPredicate(format: "id == %@", id as CVarArg),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil"),
            NSPredicate(format: "isDraft != YES")
        ]
        if let userId = authSession.userId?.uuidString {
            predicates.append(NSPredicate(format: "userId == %@", userId))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return try? viewContext.fetch(request).first
    }

    private func localOutfit(id: UUID) -> Outfit? {
        let request = NSFetchRequest<Outfit>(entityName: "Outfit")
        request.fetchLimit = 1
        var predicates = [
            NSPredicate(format: "id == %@", id as CVarArg),
            NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil"),
            NSPredicate(format: "isDraft != YES")
        ]
        if let userId = authSession.userId?.uuidString {
            predicates.append(NSPredicate(format: "userId == %@", userId))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return try? viewContext.fetch(request).first
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

    private func managedItem(forURI uriString: String) -> Item? {
        guard let url = URL(string: uriString),
              let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
              let item = try? viewContext.existingObject(with: objectID) as? Item,
              item.isSoftDeleted != true else {
            return nil
        }
        return item
    }

    private func actorUserId(for notification: NotificationRecord) -> UUID? {
        if let from = notification.payload?["from_user_id"].flatMap(UUID.init(uuidString:)) {
            return from
        }
        return notification.payload?["suggester_user_id"].flatMap(UUID.init(uuidString:))
    }

    private func actorProfile(for notification: NotificationRecord) -> PublicUserProfile? {
        guard let userId = actorUserId(for: notification) else { return nil }
        if let cached = actorProfilesByUserId[userId] {
            return cached
        }
        let username = resolvedActorUsername(for: notification)
        return PublicUserProfile(
            userId: userId,
            username: username,
            displayName: nil,
            avatarUrl: nil
        )
    }

    private func resolvedActorUsername(for notification: NotificationRecord) -> String {
        if let fromUsername = notification.payload?["from_username"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fromUsername.isEmpty {
            return fromUsername
        }
        if let parsed = actorNameParsedFromTitle(notification) {
            return parsed
        }
        return "Someone"
    }

    private func actorNameParsedFromTitle(_ notification: NotificationRecord) -> String? {
        let title = notification.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = [
            " sent you a friend request",
            " accepted your friend request",
            " redressed you",
            " liked your item",
            " liked your outfit",
            " shared an item with you",
            " shared an outfit with you"
        ]
        for suffix in suffixes where title.hasSuffix(suffix) {
            let name = String(title.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        if let body = notification.body, body.hasSuffix(" suggested an outfit for you") {
            let name = String(body.dropLast(" suggested an outfit for you".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return nil
    }

    private func actorDisplayName(for notification: NotificationRecord) -> String {
        if let userId = actorUserId(for: notification),
           let profile = actorProfilesByUserId[userId] {
            let display = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !display.isEmpty { return display }
            let username = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !username.isEmpty { return username }
        }
        return resolvedActorUsername(for: notification)
    }

    private func notificationActionSuffix(for notification: NotificationRecord) -> String {
        switch notification.type {
        case "friend_request":
            return " sent you a friend request"
        case "friend_accepted":
            return " accepted your friend request"
        case "content_like":
            let noun = notification.payload?["target_type"] == "outfit" ? "outfit" : "item"
            return " liked your \(noun)"
        case "content_share":
            let noun = notification.payload?["target_type"] == "outfit" ? "outfit" : "item"
            return " shared an \(noun) with you"
        case "outfit_suggestion":
            return " redressed you"
        default:
            let name = actorDisplayName(for: notification)
            if notification.title.hasPrefix(name) {
                return String(notification.title.dropFirst(name.count))
            }
            return notification.title.isEmpty ? "" : " — \(notification.title)"
        }
    }

    private func defaultClosetWardrobeId() -> UUID? {
        guard let uid = authSession.userId?.uuidString else { return nil }
        return try? WardrobeBootstrap.fetchPrimaryWardrobe(
            forType: "closet",
            userIdString: uid,
            in: viewContext
        )?.id
    }

    private func openOutfitSuggestion(from notification: NotificationRecord) async {
        guard let suggestionId = suggestionId(for: notification),
              let recipientUserId = authSession.userId,
              let wardrobeId = defaultClosetWardrobeId() else {
            await MainActor.run {
                notificationsError = "Could not open this outfit suggestion."
            }
            return
        }

        await MainActor.run {
            openingSuggestionId = suggestionId
            notificationsError = nil
        }

        let imageUrl = suggestionThumbnailURLs[suggestionId]?.absoluteString
        let summary = VisibleWardrobeOutfit(
            id: suggestionId,
            name: nil,
            imageUrl: imageUrl,
            wornImageUrl: nil,
            isPendingSuggestion: true
        )

        await MainActor.run {
            selectedPendingRedress = PendingRedressNavigationDestination(
                recipientUserId: recipientUserId,
                wardrobeId: wardrobeId,
                suggestionSummary: summary,
                viewerRole: .recipient
            )
            openingSuggestionId = nil
        }
    }

    private func outfitSuggestionImageURL(for notification: NotificationRecord) -> URL? {
        payloadImageURL(for: notification)
    }

    private func contentLikeImageURL(for notification: NotificationRecord) -> URL? {
        payloadImageURL(for: notification)
    }

    private func payloadImageURL(for notification: NotificationRecord) -> URL? {
        guard let urlString = notification.payload?["image_url"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else {
            return nil
        }
        return URL(string: urlString)
    }

    private func suggestionId(for notification: NotificationRecord) -> UUID? {
        notification.payload?["suggestion_id"].flatMap(UUID.init(uuidString:))
    }

    private func resolvedThumbnailURL(for notification: NotificationRecord) -> URL? {
        if let suggestionId = suggestionId(for: notification),
           let cached = suggestionThumbnailURLs[suggestionId] {
            return cached
        }
        return outfitSuggestionImageURL(for: notification)
    }

    @ViewBuilder
    private func outfitSuggestionThumbnail(for notification: NotificationRecord) -> some View {
        RemoteSquareThumbnailView(url: resolvedThumbnailURL(for: notification))
    }

    @ViewBuilder
    private func friendRequestActions(for notification: NotificationRecord) -> some View {
        let isBusy = respondingNotificationIds.contains(notification.id)
        let friendshipIdString = notification.payload?["friendship_id"]
        let friendshipId = friendshipIdString.flatMap { UUID(uuidString: $0) }

        if friendshipId == nil {
            Text("Unable to respond to this request.")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            HStack(spacing: 12) {
                Button {
                    Task { await respondToFriendRequest(notification: notification, accept: true) }
                } label: {
                    if isBusy {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("Accept")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)

                Button(role: .destructive) {
                    Task { await respondToFriendRequest(notification: notification, accept: false) }
                } label: {
                    Text("Decline")
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
        }
    }

    private func loadNotifications(markPassiveAsRead: Bool = false) async {
        guard authSession.isAuthenticated else {
            notifications = []
            suggestionThumbnailURLs = [:]
            actorProfilesByUserId = [:]
            return
        }

        isLoadingNotifications = true
        notificationsError = nil

        do {
            var fetched = try await supabaseService.fetchNotifications()
            let actorIds = fetched.compactMap { actorUserId(for: $0) }

            await MainActor.run {
                notifications = fetched
                actorProfilesByUserId.merge(supabaseService.cachedPublicProfiles(userIds: actorIds)) { _, new in new }
                isLoadingNotifications = false
            }

            if markPassiveAsRead {
                let idsToMarkRead = fetched
                    .filter { !$0.is_read && !notificationRequiresAction($0) }
                    .map(\.id)

                if !idsToMarkRead.isEmpty {
                    try? await supabaseService.markNotificationsRead(ids: idsToMarkRead)
                    fetched = (try? await supabaseService.fetchNotifications()) ?? fetched
                    await MainActor.run {
                        notifications = fetched
                    }
                }
            }
            if fetched.contains(where: { $0.type == "friend_accepted" }) {
                await supabaseService.refreshOwnFriendshipStateFromServer()
            }
            await loadActorProfiles(for: fetched)
            await loadSuggestionThumbnailURLs(for: fetched)
        } catch {
            await MainActor.run {
                notificationsError = error.localizedDescription
                notifications = []
                suggestionThumbnailURLs = [:]
                actorProfilesByUserId = [:]
            }
        }

        await MainActor.run {
            isLoadingNotifications = false
        }
    }

    private func loadActorProfiles(for notifications: [NotificationRecord]) async {
        let userIds = Array(Set(notifications.compactMap { actorUserId(for: $0) }))
        guard !userIds.isEmpty else { return }

        var profilesById = supabaseService.cachedPublicProfiles(userIds: userIds)
        await MainActor.run {
            actorProfilesByUserId.merge(profilesById) { _, new in new }
        }

        let missingAfterCache = userIds.filter { profilesById[$0] == nil }
        if !missingAfterCache.isEmpty, let friends = try? await supabaseService.fetchFriends() {
            for friend in friends where missingAfterCache.contains(friend.userId) {
                profilesById[friend.userId] = friend
            }
        }

        let missingIds = userIds.filter { profilesById[$0] == nil }
        if !missingIds.isEmpty,
           let fetched = try? await supabaseService.fetchPublicProfiles(userIds: missingIds) {
            for profile in fetched {
                profilesById[profile.userId] = profile
            }
        }

        supabaseService.rememberPublicProfiles(Array(profilesById.values))

        await MainActor.run {
            actorProfilesByUserId.merge(profilesById) { _, new in new }
        }
    }

    private func notificationRequiresAction(_ notification: NotificationRecord) -> Bool {
        notification.type == "friend_request"
            || notification.type == "outfit_suggestion"
    }

    private func loadSuggestionThumbnailURLs(for notifications: [NotificationRecord]) async {
        var urls: [UUID: URL] = [:]

        for notification in notifications where notification.type == "outfit_suggestion" {
            guard let suggestionId = suggestionId(for: notification) else { continue }

            if let payloadURL = outfitSuggestionImageURL(for: notification) {
                urls[suggestionId] = payloadURL
                continue
            }

            if let fetchedURL = try? await supabaseService.fetchOutfitSuggestionImageURL(suggestionId: suggestionId) {
                urls[suggestionId] = fetchedURL
            }
        }

        await MainActor.run {
            suggestionThumbnailURLs = urls
        }
    }

    private func respondToFriendRequest(notification: NotificationRecord, accept: Bool) async {
        guard let friendshipIdString = notification.payload?["friendship_id"],
              let friendshipId = UUID(uuidString: friendshipIdString) else {
            return
        }

        await MainActor.run {
            respondingNotificationIds.insert(notification.id)
        }

        do {
            try await supabaseService.respondToFriendRequest(friendshipId: friendshipId, accept: accept)
            try await supabaseService.markNotificationRead(id: notification.id)
            await loadNotifications()
        } catch {
            await MainActor.run {
                notificationsError = error.localizedDescription
            }
        }

        await MainActor.run {
            respondingNotificationIds.remove(notification.id)
        }
    }
}
