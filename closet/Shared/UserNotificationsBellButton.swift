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
    @Binding var isPresented: Bool

    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession

    @State private var unreadNotificationsCount = 0

    var body: some View {
        Button {
            isPresented = true
        } label: {
            bellLabel
        }
        .task(id: authSession.userId) {
            await refreshUnreadCount()
        }
        .onChange(of: isPresented) { _, presented in
            if !presented {
                Task { await refreshUnreadCount() }
            }
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

    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession
    @Environment(\.managedObjectContext) private var viewContext

    @State private var notifications: [NotificationRecord] = []
    @State private var isLoadingNotifications = false
    @State private var notificationsError: String?
    @State private var respondingNotificationIds: Set<UUID> = []
    @State private var selectedPendingRedress: PendingRedressNavigationDestination?
    @State private var openingSuggestionId: UUID?
    @State private var suggestionThumbnailURLs: [UUID: URL] = [:]

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
                    }
                )
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
        } else if notifications.isEmpty {
            Text("No new notifications")
                .foregroundColor(.secondary)
                .padding()
        } else {
            List(notifications) { notification in
                notificationRow(notification)
            }
            .listStyle(.plain)
        }
    }

    private func notificationRow(_ notification: NotificationRecord) -> some View {
        Group {
            if notification.type == "outfit_suggestion" {
                outfitSuggestionNotificationRow(notification)
            } else if notification.type == "content_like" {
                contentLikeNotificationRow(notification)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    notificationRowContent(notification)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func contentLikeNotificationRow(_ notification: NotificationRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            notificationRowContent(notification)
            RemoteSquareThumbnailView(url: contentLikeImageURL(for: notification))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func outfitSuggestionNotificationRow(_ notification: NotificationRecord) -> some View {
        let isOpening = openingSuggestionId == suggestionId(for: notification)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                outfitSuggestionHeaderContent(notification)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isOpening else { return }
            Task { await openOutfitSuggestion(from: notification) }
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

    private func outfitSuggestionHeaderContent(_ notification: NotificationRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(outfitSuggestionDisplayText(for: notification))
                .font(.headline)
                .foregroundStyle(.primary)
            Text(notification.created_at, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func notificationRowContent(_ notification: NotificationRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(notificationPrimaryText(notification))
                    .font(.headline)
                if notification.type != "outfit_suggestion",
                   let body = notification.body, !body.isEmpty {
                    Text(body)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Text(notification.created_at, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if notification.type == "friend_request", notification.is_read == false {
                friendRequestActions(for: notification)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func notificationPrimaryText(_ notification: NotificationRecord) -> String {
        guard notification.type == "outfit_suggestion" else {
            return notification.title
        }
        return outfitSuggestionDisplayText(for: notification)
    }

    private func outfitSuggestionDisplayText(for notification: NotificationRecord) -> String {
        if notification.title.contains("redressed you") {
            return notification.title
        }
        if let body = notification.body, body.hasSuffix(" suggested an outfit for you") {
            let name = String(body.dropLast(" suggested an outfit for you".count))
            return "\(name) redressed you"
        }
        if !notification.title.isEmpty, notification.title != "Outfit Suggestion" {
            return notification.title
        }
        return notification.body ?? "Someone redressed you"
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
            return
        }

        isLoadingNotifications = true
        notificationsError = nil

        do {
            var fetched = try await supabaseService.fetchNotifications()

            if markPassiveAsRead {
                let idsToMarkRead = fetched
                    .filter { !$0.is_read && !notificationRequiresAction($0) }
                    .map(\.id)

                if !idsToMarkRead.isEmpty {
                    for notificationId in idsToMarkRead {
                        try await supabaseService.markNotificationRead(id: notificationId)
                    }
                    fetched = try await supabaseService.fetchNotifications()
                }
            }

            await MainActor.run {
                notifications = fetched
            }
            if fetched.contains(where: { $0.type == "friend_accepted" }) {
                await supabaseService.refreshOwnFriendshipStateFromServer()
            }
            await loadSuggestionThumbnailURLs(for: fetched)
        } catch {
            await MainActor.run {
                notificationsError = error.localizedDescription
                notifications = []
                suggestionThumbnailURLs = [:]
            }
        }

        await MainActor.run {
            isLoadingNotifications = false
        }
    }

    private func notificationRequiresAction(_ notification: NotificationRecord) -> Bool {
        notification.type == "friend_request"
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
