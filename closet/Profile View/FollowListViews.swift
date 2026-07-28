//
//  FollowListViews.swift
//  closet
//

import SwiftUI

enum FriendsSegment: String, CaseIterable, Identifiable, Hashable {
    case followers
    case following

    var id: String { rawValue }

    var emptyMessage: String {
        switch self {
        case .followers: "No followers yet"
        case .following: "Not following anyone yet"
        }
    }
}

/// Combined Followers / Following lists with search, opened from the profile Friends button.
struct FriendsView: View {
    let userId: UUID
    let followersCount: Int
    let followingCount: Int
    var initialSegment: FriendsSegment = .followers
    /// Shared with Profile — same pattern as `ItemFilterView` / read-only detail.
    var tabBarHideState: TabBarHideState? = nil

    @EnvironmentObject private var supabaseService: SupabaseService

    @State private var selectedSegment: FriendsSegment
    @State private var followersSearchText = ""
    @State private var followingSearchText = ""
    @State private var followers: [PublicUserProfile] = []
    @State private var following: [PublicUserProfile] = []
    @State private var isLoadingFollowers = true
    @State private var isLoadingFollowing = true
    @State private var followersError: String?
    @State private var followingError: String?
    @State private var selectedProfile: PublicUserProfile?

    init(
        userId: UUID,
        followersCount: Int,
        followingCount: Int,
        initialSegment: FriendsSegment = .followers,
        tabBarHideState: TabBarHideState? = nil
    ) {
        self.userId = userId
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.initialSegment = initialSegment
        self.tabBarHideState = tabBarHideState
        _selectedSegment = State(initialValue: initialSegment)
    }

    private var displayedFollowers: [PublicUserProfile] {
        filtered(followers, query: followersSearchText)
    }

    private var displayedFollowing: [PublicUserProfile] {
        filtered(following, query: followingSearchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedSegment) {
                Text("Followers (\(followersCount))").tag(FriendsSegment.followers)
                Text("Following (\(followingCount))").tag(FriendsSegment.following)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(Color(UIColor.secondarySystemBackground))

            TabView(selection: $selectedSegment) {
                friendsPage(
                    segment: .followers,
                    searchText: $followersSearchText,
                    profiles: displayedFollowers,
                    isLoading: isLoadingFollowers,
                    loadError: followersError
                )
                .tag(FriendsSegment.followers)

                friendsPage(
                    segment: .following,
                    searchText: $followingSearchText,
                    profiles: displayedFollowing,
                    isLoading: isLoadingFollowing,
                    loadError: followingError
                )
                .tag(FriendsSegment.following)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemBackground))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar((tabBarHideState?.shouldHideTabBar ?? false) ? .hidden : .automatic, for: .tabBar)
        .onAppear {
            tabBarHideState?.shouldHideTabBar = true
        }
        .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .modifier(NavigationBarHairlineHidden(backgroundColor: UIColor.secondarySystemBackground))
        .navigationDestination(item: $selectedProfile) { profile in
            // Stay on the parent Profile NavigationStack (no nested stack).
            ProfileView(viewedProfile: profile, sharedTabBarHideState: tabBarHideState)
        }
        .task(id: supabaseService.friendshipEpoch) {
            await loadAll()
        }
    }

    @ViewBuilder
    private func friendsPage(
        segment: FriendsSegment,
        searchText: Binding<String>,
        profiles: [PublicUserProfile],
        isLoading: Bool,
        loadError: String?
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search users", text: searchText)
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
                if isLoading {
                    ProgressView("Loading \(segment.rawValue)…")
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if profiles.isEmpty {
                    Text(
                        searchText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? segment.emptyMessage
                            : "No users found"
                    )
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(profiles) { profile in
                        Button {
                            selectedProfile = profile
                        } label: {
                            profileRow(profile)
                        }
                        .buttonStyle(.plain)
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

    private func profileRow(_ profile: PublicUserProfile) -> some View {
        HStack(spacing: 12) {
            PublicUserProfileAvatarView(profile: profile, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.username)
                    .font(.headline)
                if let name = profile.displayName, !name.isEmpty {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func filtered(_ profiles: [PublicUserProfile], query: String) -> [PublicUserProfile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return profiles }
        return profiles.filter { profile in
            profile.username.localizedCaseInsensitiveContains(trimmed)
                || (profile.displayName ?? "").localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func loadAll() async {
        async let followersLoad: Void = loadFollowers()
        async let followingLoad: Void = loadFollowing()
        _ = await (followersLoad, followingLoad)
    }

    private func loadFollowers() async {
        await MainActor.run {
            isLoadingFollowers = true
            followersError = nil
        }
        do {
            let fetched = try await supabaseService.fetchFollowerProfiles(forUserId: userId)
            await MainActor.run {
                followers = fetched
                isLoadingFollowers = false
            }
        } catch {
            await MainActor.run {
                followers = []
                followersError = error.localizedDescription
                isLoadingFollowers = false
            }
        }
    }

    private func loadFollowing() async {
        await MainActor.run {
            isLoadingFollowing = true
            followingError = nil
        }
        do {
            let fetched = try await supabaseService.fetchFollowingProfiles(forUserId: userId)
            await MainActor.run {
                following = fetched
                isLoadingFollowing = false
            }
        } catch {
            await MainActor.run {
                following = []
                followingError = error.localizedDescription
                isLoadingFollowing = false
            }
        }
    }
}

/// Back-compat wrappers (deep links / older call sites).
struct FollowingView: View {
    let userId: UUID
    var followingCount: Int = 0
    var followersCount: Int = 0

    var body: some View {
        FriendsView(
            userId: userId,
            followersCount: followersCount,
            followingCount: followingCount,
            initialSegment: .following
        )
    }
}

struct FollowersView: View {
    let userId: UUID
    var followingCount: Int = 0
    var followersCount: Int = 0

    var body: some View {
        FriendsView(
            userId: userId,
            followersCount: followersCount,
            followingCount: followingCount,
            initialSegment: .followers
        )
    }
}
