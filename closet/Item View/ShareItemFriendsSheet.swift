//
//  ShareItemFriendsSheet.swift
//  closet
//
//  Sheet: pick a friend to share an item with (UI only; messaging TBD).
//

import SwiftUI

struct ShareItemFriendsSheet: View {
    var navigationTitle: String = "Friends"

    var body: some View {
        ShareFriendsPickerSheet(navigationTitle: navigationTitle)
    }
}

/// Pick a friend to share an item or outfit with (UI only; messaging TBD).
struct ShareFriendsPickerSheet: View {
    let navigationTitle: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession

    @State private var friends: [PublicUserProfile] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var messageDraft = ""
    @State private var selectedFriendId: UUID?

    private var trimmedMessage: String {
        messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        selectedFriendId != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if authSession.isAuthenticated {
                    messageComposerBar
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .task {
            await loadFriends()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if !authSession.isAuthenticated {
            Text("Sign in to see your friends.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        } else if isLoading {
            ProgressView("Loading friends…")
                .padding()
        } else if let loadError {
            Text(loadError)
                .foregroundStyle(.red)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding()
        } else if friends.isEmpty {
            Text("You don’t have any friends yet. Add friends from your profile.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        } else {
            List(friends) { friend in
                Button {
                    if selectedFriendId == friend.userId {
                        selectedFriendId = nil
                    } else {
                        selectedFriendId = friend.userId
                    }
                } label: {
                    ShareItemFriendRow(
                        profile: friend,
                        isSelected: selectedFriendId == friend.userId
                    )
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    private var messageComposerBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message", text: $messageDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Button {
                    sendTapped()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(UIColor.systemBackground))
        }
    }

    private func sendTapped() {
        // Messaging / share pipeline TBD
        guard canSend else { return }
        _ = trimmedMessage
        dismiss()
    }

    private func loadFriends() async {
        guard authSession.isAuthenticated else {
            await MainActor.run { friends = []; isLoading = false }
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
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                friends = []
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
            PublicUserProfileAvatarView(profile: profile, size: 48)

            VStack(alignment: .leading, spacing: 2) {
                if trimmedDisplayName.isEmpty {
                    Text("@\(profile.username)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                } else {
                    Text(trimmedDisplayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("@\(profile.username)")
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
    }
}
