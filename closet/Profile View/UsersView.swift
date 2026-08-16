//
//  UsersView.swift
//  closet
//
//  Search and browse other users (same list styling as Closet/Wishlist Shared Users sheet).
//

import SwiftUI

private enum AddFriendSegment: String, CaseIterable, Identifiable {
    case search = "Search"
    case pending = "Pending"

    var id: String { rawValue }
}

struct UsersView: View {
    var tabBarHideState: TabBarHideState? = nil
    var navigationPath: Binding<NavigationPath>? = nil

    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession

    @State private var selectedSegment: AddFriendSegment = .search
    @State private var searchText = ""
    @State private var searchResults: [PublicUserProfile] = []
    @State private var connectedFriends: [PublicUserProfile] = []
    @State private var pendingOutgoingProfiles: [PublicUserProfile] = []
    @State private var isSearching = false
    @State private var isLoadingFriends = false
    @State private var isLoadingPending = false
    @State private var loadError: String?
    @State private var friendUserIds: Set<UUID> = []
    @State private var pendingFriendRequestUserIds: Set<UUID> = []
    @State private var showUnfriendAlert = false
    @State private var unfriendTargetUserId: UUID?
    @State private var selectedProfile: PublicUserProfile?

    private var displayedSearchProfiles: [PublicUserProfile] {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? connectedFriends
            : searchResults
    }

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        if navigationPath != nil {
            usersChrome
        } else {
            usersChrome
                .navigationDestination(item: $selectedProfile) { profile in
                    ProfileView(viewedProfile: profile, sharedTabBarHideState: tabBarHideState)
                }
        }
    }

    private var usersChrome: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedSegment) {
                ForEach(AddFriendSegment.allCases) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))

            TabView(selection: $selectedSegment) {
                searchSegmentContent
                    .tag(AddFriendSegment.search)
                pendingSegmentContent
                    .tag(AddFriendSegment.pending)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemBackground))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationTitle("Add Friend")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar((tabBarHideState?.shouldHideTabBar ?? true) ? .hidden : .automatic, for: .tabBar)
        .onAppear {
            tabBarHideState?.shouldHideTabBar = true
        }
        .toolbarBackground(Color(UIColor.systemBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .modifier(NavigationBarHairlineHidden(backgroundColor: UIColor.systemBackground))
        .task(id: supabaseService.friendshipEpoch) {
            await loadConnectedFriends()
            await loadOutgoingPendingRequests()
            await refreshFriendshipBadges()
        }
        .task(id: searchText) {
            await searchUsers()
        }
        .onChange(of: selectedSegment) { _, segment in
            if segment == .pending {
                Task { await loadOutgoingPendingRequests() }
            }
        }
        .alert("Unfriend?", isPresented: $showUnfriendAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Unfriend", role: .destructive) {
                guard let targetId = unfriendTargetUserId else { return }
                Task { await unfriend(userId: targetId) }
            }
        } message: {
            Text("Are you sure you want to remove this friend?")
        }
    }

    @ViewBuilder
    private var searchSegmentContent: some View {
        VStack(spacing: 0) {
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

            Group {
                if isSearching {
                    ProgressView("Searching…")
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLoadingFriends && !isSearchActive {
                    ProgressView("Loading friends…")
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError, selectedSegment == .search {
                    Text(loadError)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if displayedSearchProfiles.isEmpty && isSearchActive {
                    Text("No users found for “\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))”")
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if displayedSearchProfiles.isEmpty {
                    Text("Search by username to find other users.")
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(displayedSearchProfiles) { profile in
                        userRow(profile, context: .search)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var pendingSegmentContent: some View {
        Group {
            if isLoadingPending && pendingOutgoingProfiles.isEmpty {
                ProgressView("Loading pending requests…")
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if pendingOutgoingProfiles.isEmpty {
                Text("No pending friend requests.")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(pendingOutgoingProfiles) { profile in
                    userRow(profile, context: .pending)
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

    private func openProfile(_ profile: PublicUserProfile) {
        if let navigationPath {
            navigationPath.wrappedValue.append(ProfileRoute.otherUser(profile))
        } else {
            selectedProfile = profile
        }
    }

    private enum RowContext {
        case search
        case pending
    }

    @ViewBuilder
    private func userRow(_ profile: PublicUserProfile, context: RowContext) -> some View {
        HStack(spacing: 12) {
            Button {
                openProfile(profile)
            } label: {
                HStack(spacing: 12) {
                    PublicUserProfileAvatarView(profile: profile, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.username)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let name = profile.displayName, !name.isEmpty {
                            Text(name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            friendshipActionButton(for: profile, context: context)
        }
    }

    @ViewBuilder
    private func friendshipActionButton(for profile: PublicUserProfile, context: RowContext) -> some View {
        if context == .pending || pendingFriendRequestUserIds.contains(profile.userId) {
            Button("Request Sent") {
                Task { await cancelOutgoingRequest(to: profile.userId) }
            }
            .buttonStyle(.bordered)
            .font(.caption)
        } else if !isSearchActive || friendUserIds.contains(profile.userId) {
            Button {
                unfriendTargetUserId = profile.userId
                showUnfriendAlert = true
            } label: {
                HStack(spacing: 6) {
                    Text("Friends")
                    Image(systemName: "checkmark")
                }
            }
            .buttonStyle(.bordered)
            .font(.caption)
        } else {
            Button("Add Friend") {
                Task {
                    do {
                        try await supabaseService.sendFriendRequest(
                            toUserId: profile.userId,
                            toUsername: profile.username,
                            toDisplayName: profile.displayName
                        )
                        await MainActor.run {
                            pendingFriendRequestUserIds.insert(profile.userId)
                            if !pendingOutgoingProfiles.contains(where: { $0.userId == profile.userId }) {
                                pendingOutgoingProfiles.insert(profile, at: 0)
                            }
                        }
                    } catch {
                        print("Failed to send friend request: \(error.localizedDescription)")
                    }
                }
            }
            .buttonStyle(.bordered)
            .font(.caption)
        }
    }

    private func cancelOutgoingRequest(to userId: UUID) async {
        do {
            try await supabaseService.cancelFriendRequest(toUserId: userId)
            await MainActor.run {
                pendingFriendRequestUserIds.remove(userId)
                pendingOutgoingProfiles.removeAll { $0.userId == userId }
            }
        } catch {
            print("Failed to cancel friend request: \(error.localizedDescription)")
        }
    }

    private func loadConnectedFriends() async {
        guard authSession.isAuthenticated else {
            await MainActor.run {
                connectedFriends = []
                isLoadingFriends = false
            }
            return
        }
        await MainActor.run { isLoadingFriends = true }
        defer { Task { @MainActor in isLoadingFriends = false } }
        do {
            let friends = try await supabaseService.fetchFriends(forceRefresh: true)
            await MainActor.run {
                connectedFriends = friends
                friendUserIds = Set(friends.map(\.userId))
                loadError = nil
            }
        } catch {
            await MainActor.run {
                connectedFriends = []
                loadError = error.localizedDescription
            }
        }
    }

    private func loadOutgoingPendingRequests() async {
        guard authSession.isAuthenticated else {
            await MainActor.run {
                pendingOutgoingProfiles = []
                pendingFriendRequestUserIds = []
                isLoadingPending = false
            }
            return
        }
        await MainActor.run { isLoadingPending = true }
        defer { Task { @MainActor in isLoadingPending = false } }
        do {
            let pending = try await supabaseService.fetchOutgoingPendingFriendRequests(forceRefresh: true)
            await MainActor.run {
                pendingOutgoingProfiles = pending
                pendingFriendRequestUserIds = Set(pending.map(\.userId))
            }
        } catch {
            print("Failed to load pending friend requests: \(error.localizedDescription)")
            await MainActor.run {
                // Keep any locally known pending IDs; clear list if fetch failed cold.
                if pendingOutgoingProfiles.isEmpty {
                    pendingOutgoingProfiles = []
                }
            }
        }
    }

    private func searchUsers() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            await MainActor.run {
                searchResults = []
                loadError = nil
                isSearching = false
            }
            return
        }

        await MainActor.run {
            isSearching = true
            loadError = nil
        }
        defer {
            Task { @MainActor in
                isSearching = false
            }
        }

        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }

        do {
            let results = try await supabaseService.searchUsers(byUsername: query)
            let currentUserId = authSession.userId
            let filtered = results.filter { profile in
                guard let currentUserId else { return true }
                return profile.userId != currentUserId
            }
            await MainActor.run {
                searchResults = filtered
            }
            await refreshFriendshipBadges()
        } catch is CancellationError {
            return
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                searchResults = []
            }
        }
    }

    private func refreshFriendshipBadges() async {
        guard authSession.isAuthenticated else {
            await MainActor.run { friendUserIds = [] }
            return
        }

        do {
            let rows = try await supabaseService.fetchFriendshipsForCurrentUser(forceRefresh: true)
            let currentId = authSession.userId
            let friendIdsFromList = Set(connectedFriends.map(\.userId))

            var accepted: Set<UUID> = friendIdsFromList
            var outgoingPending: Set<UUID> = []

            for row in rows {
                guard let currentId else { continue }
                let otherId: UUID
                if row.user_id == currentId {
                    otherId = row.friend_user_id
                } else if row.friend_user_id == currentId {
                    otherId = row.user_id
                } else {
                    continue
                }

                if row.status == "accepted" {
                    accepted.insert(otherId)
                } else if row.status == "pending", row.user_id == currentId {
                    outgoingPending.insert(otherId)
                }
            }

            await MainActor.run {
                friendUserIds = accepted
                pendingFriendRequestUserIds.formUnion(outgoingPending)
            }
        } catch {
            print("Failed to refresh friendships: \(error.localizedDescription)")
        }
    }

    private func unfriend(userId: UUID) async {
        do {
            try await supabaseService.unfriend(userId: userId)
            await MainActor.run {
                friendUserIds.remove(userId)
                connectedFriends.removeAll { $0.userId == userId }
            }
            await supabaseService.refreshOwnFriendshipStateFromServer()
        } catch {
            print("Failed to unfriend: \(error.localizedDescription)")
        }
    }
}
