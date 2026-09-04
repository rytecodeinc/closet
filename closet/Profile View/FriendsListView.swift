//
//  FriendsListView.swift
//  closet
//
//  Dedicated mutual-friends list (search + rows). Used from Profile and
//  share / invite pickers so layout stays in one place.
//

import SwiftUI

/// Shared identity chrome for a friend row (avatar + username + display name).
struct FriendsListProfileIdentity: View {
    let profile: PublicUserProfile

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
        }
    }
}

/// Mutual friends for `userId`, with search. Browse mode opens profiles; pickers pass trailing actions.
struct FriendsListView<Trailing: View>: View {
    let userId: UUID
    var navigationTitle: String = "Friends"
    var emptyMessage: String = "No friends yet"
    /// Shown when friends exist but all are filtered out via `excludedUserIds`.
    var exclusionEmptyMessage: String = "No friends available."
    /// Hide these users from the list (e.g. already invited to an event).
    var excludedUserIds: Set<UUID> = []
    /// When true, wraps content with navigation title / tab-bar hide (Profile push).
    var isPushed: Bool = true
    var allowsOpeningProfile: Bool = true
    var tabBarHideState: TabBarHideState? = nil
    var navigationPath: Binding<NavigationPath>? = nil
    @ViewBuilder var rowTrailing: (PublicUserProfile) -> Trailing

    @EnvironmentObject private var supabaseService: SupabaseService
    @EnvironmentObject private var authSession: AuthSession

    @State private var friends: [PublicUserProfile] = []
    @State private var displayedFriends: [PublicUserProfile] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedProfile: PublicUserProfile?

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isViewingOwnFriends: Bool {
        authSession.userId == userId
    }

    private var exclusionKey: String {
        excludedUserIds.map(\.uuidString).sorted().joined(separator: ",")
    }

    var body: some View {
        Group {
            if isPushed {
                listChrome
                    .navigationTitle(navigationTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar((tabBarHideState?.shouldHideTabBar ?? false) ? .hidden : .automatic, for: .tabBar)
                    .onAppear { tabBarHideState?.shouldHideTabBar = true }
                    .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .modifier(NavigationBarHairlineHidden(backgroundColor: UIColor.secondarySystemBackground))
            } else {
                listChrome
            }
        }
        .background(Color(.systemBackground))
        .task(id: "\(userId.uuidString)-\(supabaseService.friendshipEpoch)") {
            await loadFriends()
        }
        .task(id: "\(searchText)-\(exclusionKey)") {
            await applySearchFilter()
        }
        .modifier(FriendsListProfileDestinationModifier(
            selectedProfile: $selectedProfile,
            tabBarHideState: tabBarHideState,
            usesItemDestination: navigationPath == nil && allowsOpeningProfile
        ))
    }

    private var listChrome: some View {
        VStack(spacing: 0) {
            searchBar
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
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
        if !authSession.isAuthenticated {
            Text("Sign in to see friends.")
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
            Text(
                isViewingOwnFriends
                    ? emptyMessage
                    : "No friends to show."
            )
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
            Text(exclusionEmptyMessage)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(displayedFriends) { profile in
                friendRow(profile)
                    .listRowBackground(Color(.systemBackground))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
        }
    }

    @ViewBuilder
    private func friendRow(_ profile: PublicUserProfile) -> some View {
        HStack(spacing: 12) {
            if allowsOpeningProfile {
                Button {
                    openProfile(profile)
                } label: {
                    FriendsListProfileIdentity(profile: profile)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                FriendsListProfileIdentity(profile: profile)
                Spacer(minLength: 8)
            }
            rowTrailing(profile)
        }
        .padding(.vertical, 4)
    }

    private func openProfile(_ profile: PublicUserProfile) {
        if let navigationPath {
            navigationPath.wrappedValue.append(ProfileRoute.otherUser(profile))
        } else {
            selectedProfile = profile
        }
    }

    private func profilesExcludingBlocked(_ list: [PublicUserProfile]) -> [PublicUserProfile] {
        guard !excludedUserIds.isEmpty else { return list }
        return list.filter { !excludedUserIds.contains($0.userId) }
    }

    private func applySearchFilter() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let eligible = profilesExcludingBlocked(friends)
        if query.isEmpty {
            await MainActor.run { displayedFriends = eligible }
            return
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        let filtered = eligible.filter { profile in
            profile.username.localizedCaseInsensitiveContains(query)
                || (profile.displayName ?? "").localizedCaseInsensitiveContains(query)
        }
        await MainActor.run { displayedFriends = filtered }
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
            let list = try await supabaseService.fetchFriends(forUserId: userId)
            await MainActor.run {
                friends = list
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    displayedFriends = profilesExcludingBlocked(list)
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

extension FriendsListView where Trailing == EmptyView {
    init(
        userId: UUID,
        navigationTitle: String = "Friends",
        emptyMessage: String = "No friends yet",
        exclusionEmptyMessage: String = "No friends available.",
        excludedUserIds: Set<UUID> = [],
        isPushed: Bool = true,
        allowsOpeningProfile: Bool = true,
        tabBarHideState: TabBarHideState? = nil,
        navigationPath: Binding<NavigationPath>? = nil
    ) {
        self.init(
            userId: userId,
            navigationTitle: navigationTitle,
            emptyMessage: emptyMessage,
            exclusionEmptyMessage: exclusionEmptyMessage,
            excludedUserIds: excludedUserIds,
            isPushed: isPushed,
            allowsOpeningProfile: allowsOpeningProfile,
            tabBarHideState: tabBarHideState,
            navigationPath: navigationPath
        ) { _ in
            EmptyView()
        }
    }
}

private struct FriendsListProfileDestinationModifier: ViewModifier {
    @Binding var selectedProfile: PublicUserProfile?
    var tabBarHideState: TabBarHideState?
    var usesItemDestination: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesItemDestination {
            content.navigationDestination(item: $selectedProfile) { profile in
                ProfileView(viewedProfile: profile, sharedTabBarHideState: tabBarHideState)
            }
        } else {
            content
        }
    }
}
