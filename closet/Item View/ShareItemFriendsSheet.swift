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

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession

    @State private var friends: [PublicUserProfile] = []
    @State private var displayedFriends: [PublicUserProfile] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var loadError: String?
    @State private var sendError: String?
    @State private var selectedFriend: PublicUserProfile?

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSend: Bool {
        selectedFriend != nil && !isSending
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if authSession.isAuthenticated, selectedFriend != nil {
                    sendComposerBar
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(Color(.systemBackground))
        }
        .presentationDetents([.medium, .large])
        .task {
            await loadFriends()
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

    private var sendComposerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(sendPromptText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await sendTapped() }
            } label: {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
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
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.45)
            .accessibilityLabel("Share")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private var sendPromptText: String {
        let username = selectedFriend?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = username.isEmpty ? "friend" : username
        return "Share this \(contentKind.noun) with \(label)"
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
                    Button {
                        if selectedFriend?.userId == friend.userId {
                            selectedFriend = nil
                        } else {
                            selectedFriend = friend
                        }
                    } label: {
                        ShareItemFriendRow(
                            profile: friend,
                            isSelected: selectedFriend?.userId == friend.userId
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color(.systemBackground))
                    .disabled(isSending)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(.systemBackground))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func sendTapped() async {
        guard let recipient = selectedFriend else { return }
        await MainActor.run {
            isSending = true
            sendError = nil
        }
        do {
            try await supabaseService.shareContentWithFriend(
                recipientUserId: recipient.userId,
                targetType: contentKind.targetType,
                targetId: targetId
            )
            await MainActor.run {
                isSending = false
                onSent?()
                dismiss()
            }
        } catch {
            await MainActor.run {
                isSending = false
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
            if let selected = selectedFriend,
               !filtered.contains(where: { $0.userId == selected.userId }) {
                selectedFriend = nil
            }
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
    var isSelected: Bool = false

    private var trimmedDisplayName: String {
        profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Selected")
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}
