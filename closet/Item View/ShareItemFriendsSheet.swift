//
//  ShareItemFriendsSheet.swift
//  closet
//
//  Sheet: pick a friend to share an item with.
//

import SwiftUI

enum ShareFriendsContentKind {
    case item
    case outfit

    var noun: String {
        switch self {
        case .item: return "item"
        case .outfit: return "outfit"
        }
    }

    var targetType: String { noun }
}

struct ShareItemFriendsSheet: View {
    var navigationTitle: String = "Share Item"
    let targetId: UUID
    var onSent: (() -> Void)? = nil

    var body: some View {
        ShareFriendsPickerSheet(
            navigationTitle: navigationTitle,
            contentKind: .item,
            targetId: targetId,
            onSent: onSent
        )
    }
}

/// Pick a friend to share an item or outfit with.
struct ShareFriendsPickerSheet: View {
    let navigationTitle: String
    let contentKind: ShareFriendsContentKind
    let targetId: UUID
    var onSent: (() -> Void)? = nil

    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession

    @State private var friends: [PublicUserProfile] = []
    @State private var displayedFriends: [PublicUserProfile] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var sendingRecipientId: UUID?
    @State private var sentRecipientIds: Set<UUID> = []
    @State private var loadError: String?
    @State private var sendError: String?

    private var isSending: Bool {
        sendingRecipientId != nil
    }

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SelectionHeader(title: navigationTitle)
                if authSession.isAuthenticated {
                    searchBar
                }
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(Color(.systemBackground))
        }
        .presentationDetents([.medium, .large])
        .task {
            await loadFriends()
        }
        .onAppear {
            sendingRecipientId = nil
            sentRecipientIds = []
        }
        // Same pattern as UsersView Add Friend: debounce search updates so the list
        // does not rebuild (and remount avatars) on every keystroke.
        .task(id: searchText) {
            await applySearchFilter()
        }
        .alert("Couldn’t send", isPresented: Binding(
            get: { sendError != nil },
            set: { if !$0 { sendError = nil } }
        )) {
            Button("OK", role: .cancel) { sendError = nil }
        } message: {
            Text(sendError ?? "")
        }
    }

    private var searchBar: some View {
        HStack {
            TextField("Search users", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if !authSession.isAuthenticated {
                Text("Sign in to see your friends.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading {
                ProgressView("Loading friends…")
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                Text(loadError)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if friends.isEmpty {
                Text("You don’t have any friends yet. Add friends from your profile.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedFriends.isEmpty && isSearchActive {
                Text("No users found for “\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))”")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedFriends.isEmpty {
                Text("Search by username to find friends.")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(displayedFriends) { friend in
                    ShareItemFriendRow(
                        profile: friend,
                        isSendingThisRow: sendingRecipientId == friend.userId,
                        isSent: sentRecipientIds.contains(friend.userId),
                        isDisabled: isSending && sendingRecipientId != friend.userId
                    ) {
                        Task { await sendTapped(to: friend) }
                    }
                    .listRowBackground(Color(.systemBackground))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(.systemBackground))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func sendTapped(to recipient: PublicUserProfile) async {
        await MainActor.run {
            sendingRecipientId = recipient.userId
            sendError = nil
        }
        do {
            try await supabaseService.shareContentWithFriend(
                recipientUserId: recipient.userId,
                targetType: contentKind.targetType,
                targetId: targetId
            )
            await MainActor.run {
                sendingRecipientId = nil
                sentRecipientIds.insert(recipient.userId)
            }
        } catch {
            await MainActor.run {
                sendingRecipientId = nil
                sendError = error.localizedDescription
            }
        }
    }

    private func applySearchFilter() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            await MainActor.run {
                displayedFriends = friends
            }
            return
        }

        // Match UsersView Add Friend debounce so typing stays responsive
        // (avoids rebuilding the list / remounting avatars on every keystroke).
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }

        let filtered = friends.filter { profile in
            profile.username.localizedCaseInsensitiveContains(query)
                || (profile.displayName ?? "").localizedCaseInsensitiveContains(query)
        }
        await MainActor.run {
            displayedFriends = filtered
        }
    }

    private func loadFriends() async {
        guard authSession.isAuthenticated else {
            await MainActor.run {
                friends = []
                displayedFriends = []
                isLoading = false
            }
            return
        }
        await MainActor.run {
            isLoading = true
            loadError = nil
        }
        do {
            let list = try await supabaseService.fetchFriends()
            await MainActor.run {
                friends = list
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    displayedFriends = list
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                friends = []
                displayedFriends = []
                isLoading = false
            }
        }
    }
}

// MARK: - Row

private struct ShareItemFriendRow: View {
    let profile: PublicUserProfile
    var isSendingThisRow: Bool = false
    var isSent: Bool = false
    var isDisabled: Bool = false
    var onShare: () -> Void

    private var trimmedDisplayName: String {
        profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var shareControlDisabled: Bool {
        isSent || isDisabled || isSendingThisRow
    }

    var body: some View {
        HStack(spacing: 12) {
            PublicUserProfileAvatarView(profile: profile, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.username)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !trimmedDisplayName.isEmpty {
                    Text(trimmedDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Button {
                onShare()
            } label: {
                if isSendingThisRow {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                } else if isSent {
                    Label("Sent", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                } else {
                    Label("Share", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                (isSent ? Color.secondary : Color.accentColor),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .disabled(shareControlDisabled)
            .opacity(isDisabled && !isSendingThisRow && !isSent ? 0.45 : 1)
            .accessibilityLabel(
                isSent
                    ? "Sent to \(profile.username)"
                    : "Share with \(profile.username)"
            )
        }
        .padding(.vertical, 4)
    }
}
