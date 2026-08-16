//
//  ItemGridView.swift
//  closet
//
//  Created by Dan Warner on 7/30/25.
//


import SwiftUI
import UIKit
import CoreData

struct ProfileView: View {
    /// When set, shows another user's public profile. `nil` = signed-in user's own profile tab.
    var viewedProfile: PublicUserProfile? = nil
    /// When this profile is pushed from Friends/Users, reuse the root Profile tab's hide flag
    /// so the tab bar stays hidden for the full push path.
    var sharedTabBarHideState: TabBarHideState? = nil
    /// Nested other-user profiles append onto the Profile tab stack (no second `NavigationStack`).
    var sharedNavigationPath: Binding<NavigationPath>? = nil

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appCapabilities) private var appCapabilities
    @EnvironmentObject var supabaseService: SupabaseService
    @EnvironmentObject var authSession: AuthSession
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter
    
    /// All active wardrobes; scoped to the signed-in user via computed properties (FetchRequest cannot use dynamic `userId`).
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.createdAt, ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
    ) private var allActiveWardrobes: FetchedResults<Wardrobe>
    
    /// Matches `ItemGridView` tab pattern: segmented control + paged `TabView` for swiping.
    @State private var selectedProfileWardrobeTab: String = "Closet"
    @State private var selectedProfileWardrobe: Wardrobe?
    @State private var showWardrobesSheet = false
    @State private var isProfileItemGridInSelectionMode = false
    @State private var isProfileGridDetailNavigationActive = false
    @State private var isProfileFilterActionsVisible = true
    @StateObject private var profileFilterModel = ItemFilterModel()
    @StateObject private var profileOutfitFilterModel = OutfitFilterModel()
    @StateObject private var ownedTabBarHideState = TabBarHideState()
    @State private var profileHowToPage = 0
    @State private var navigationPath = NavigationPath()

    private var tabBarHideState: TabBarHideState {
        sharedTabBarHideState ?? ownedTabBarHideState
    }
    
    @FetchRequest(
        entity: Item.entity(),
        sortDescriptors: []
    ) private var allItems: FetchedResults<Item>
    
    // Fetch user profile to observe changes
    @FetchRequest(
        entity: UserProfile.entity(),
        sortDescriptors: []
    ) private var allUserProfiles: FetchedResults<UserProfile>
    
    @State private var isProfilePhotoActionDialogPresented = false
    @State private var isProfileLibraryPickerPresented = false
    @State private var profilePickerImage: UIImage?
    @State private var profileImagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var isAvatarUploading = false
    @State private var avatarUploadError: String?
    /// Prevents `getUsername` + `refreshAllObjects` on every navigation back (was reloading the avatar / AsyncImage).
    @State private var didBootstrapProfileFromServerForUserId: String?

    /// Diameter of the profile photo in the header.
    private static let profileHeaderAvatarSize: CGFloat = 104
    /// Space above the profile image.
    private static let profileHeaderTopPadding: CGFloat = 8
    /// Matches the default vertical padding formerly on the wardrobe bar’s top edge.
    private static let wardrobeBarEdgePadding: CGFloat = 16
    private static let profileHeaderBottomPadding: CGFloat = 4 + wardrobeBarEdgePadding
    /// Gap between avatar row and display name.
    private static let profileHeaderNameTopPadding: CGFloat = 8
    private static let profileHeaderActionIconSize: CGFloat = 20
    /// Full header template (bio/tags/location/socials/Sizes flanking) — see `.cursor/rules/profile-header-full-template-deferred.mdc`.

    @State private var refreshToken = UUID()

    @State private var remoteWardrobes: [VisibleWardrobe] = []
    @State private var selectedRemoteWardrobe: VisibleWardrobe?
    @State private var isLoadingRemoteWardrobes = false
    @State private var remoteWardrobesError: String?
    @State private var showRemoteWardrobesSheet = false
    @State private var selectedRemoteWardrobeTab: String = "Closet"
    @State private var viewedUserFollowingCount: Int?
    @State private var viewedUserFollowersCount: Int?
    @State private var isFriendWithViewedUser = false
    /// Accepted outgoing edge: current user → viewed user.
    @State private var isFollowingViewedUser = false
    /// Reciprocal accepted edges both ways.
    @State private var isMutualFriendWithViewedUser = false
    @State private var showRemoveFriendAlert = false
    @State private var isUpdatingFriendship = false
    @State private var showOtherUserProfileOptionsDialog = false
    @State private var canShowRedress = false
    @State private var isRedressOutfitPresented = false
    @State private var remoteGridRefreshToken = UUID()
    @State private var remoteGridPreferredTab = "Items"
    @State private var ownEmptyGridPreferredTab = "Items"
    // Deferred: other-user WARDROBE/CALENDAR tab — see `.cursor/rules/other-user-profile-calendar-deferred.mdc`
    // @State private var otherUserContentTab = "WARDROBE"
    @State private var lastOwnFriendshipRefreshAt: Date?

    private var isViewingOtherUser: Bool {
        guard let viewedProfile else { return false }
        return viewedProfile.userId != authSession.userId
    }

    private var remoteClosets: [VisibleWardrobe] {
        remoteWardrobes.filter { $0.wardrobeType == "closet" }
    }

    private var remoteWishlists: [VisibleWardrobe] {
        remoteWardrobes.filter { $0.wardrobeType == "wishlist" }
    }

    /// Closets a friend would see on this profile (public or friends) — earliest `createdAt` first via fetch order.
    private var friendVisibleUserClosets: [Wardrobe] {
        userClosets.filter { $0.wardrobeVisibility != .private }
    }

    /// Wishlists a friend would see on this profile (public or friends).
    private var friendVisibleUserWishlists: [Wardrobe] {
        userWishlists.filter { $0.wardrobeVisibility != .private }
    }

    /// Same order a friend sees: first public/friends closet, else first public/friends wishlist.
    private var preferredFriendVisibleProfileWardrobe: Wardrobe? {
        friendVisibleUserClosets.first ?? friendVisibleUserWishlists.first
    }

    /// First visible closet (public, or friends when RPC includes it), else first visible wishlist — earliest `createdAt`.
    private var preferredRemoteProfileWardrobe: VisibleWardrobe? {
        earliestCreatedRemoteWardrobe(in: remoteClosets)
            ?? earliestCreatedRemoteWardrobe(in: remoteWishlists)
    }

    private func earliestCreatedRemoteWardrobe(in wardrobes: [VisibleWardrobe]) -> VisibleWardrobe? {
        wardrobes.sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (l?, r?):
                if l != r { return l < r }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }.first
    }

    // Filter user profiles by current user (if authenticated)
    private var userProfiles: [UserProfile] {
        guard let userId = authSession.userId?.uuidString else {
            return []
        }
        return allUserProfiles.filter { $0.userId == userId }
    }
    
    // Get profile from fetched results (observes Core Data changes)
    private var userProfile: UserProfile? {
        userProfiles.first
    }

    private var currentUserId: String? {
        authSession.userId?.uuidString
    }

    private var userClosets: [Wardrobe] {
        guard let uid = currentUserId else { return [] }
        return allActiveWardrobes.filter { wardrobe in
            (wardrobe.type ?? "").lowercased() == "closet" && wardrobe.userId == uid
        }
    }

    private var userWishlists: [Wardrobe] {
        guard let uid = currentUserId else { return [] }
        return allActiveWardrobes.filter { wardrobe in
            (wardrobe.type ?? "").lowercased() == "wishlist" && wardrobe.userId == uid
        }
    }
    
    // MARK: - Helper Functions
    
    private func itemsForWardrobeType(_ wardrobeType: String) -> [Item] {
        // Same baseline inclusion as ItemGridView.fetchItems (no attribute filters): userId, not draft, not soft-deleted, wardrobe type match.
        var uniqueItems: [UUID: Item] = [:]
        guard let uid = currentUserId else { return [] }

        for item in allItems {
            guard item.userId == uid else { continue }
            guard itemIncludedLikeItemGrid(item) else { continue }

            guard let wardrobes = item.wardrobes as? Set<Wardrobe>,
                  wardrobes.contains(where: { ($0.type ?? "").lowercased() == wardrobeType.lowercased() }) else {
                continue
            }
            
            // Use item ID to ensure uniqueness (each item only counted once)
            if let itemId = item.id {
                uniqueItems[itemId] = item
            }
        }
        
        return Array(uniqueItems.values)
    }
    
    private func totalValueForWardrobeType(_ wardrobeType: String) -> Decimal {
        // Sum all items for the specified wardrobe type, treating items without prices as 0
        let items = itemsForWardrobeType(wardrobeType)
        return items.reduce(Decimal(0)) { total, item in
            guard let price = item.price,
                  let amount = price.amount else {
                return total // Items without prices contribute 0
            }
            // Convert NSDecimalNumber to Decimal
            let decimalAmount = amount as Decimal
            return total + decimalAmount
        }
    }
    
    private func formattedValueForWardrobeType(_ wardrobeType: String) -> String {
        let totalValue = totalValueForWardrobeType(wardrobeType)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: totalValue as NSDecimalNumber) ?? "$0.00"
    }
    
    // MARK: - Computed Properties
    
    private var totalClosetValue: Decimal {
        totalValueForWardrobeType("closet")
    }
    
    private var formattedTotalValue: String {
        formattedValueForWardrobeType("closet")
    }
    
    private var totalWishlistValue: Decimal {
        totalValueForWardrobeType("wishlist")
    }
    
    private var formattedWishlistValue: String {
        formattedValueForWardrobeType("wishlist")
    }
    
    // MARK: - User Profile Data from Core Data
    
    private var profileRepository: UserProfileRepository {
        UserProfileRepository(context: viewContext)
    }
    
    private var username: String? {
        userProfile?.username
    }
    
    private var currentDisplayName: String? {
        userProfile?.displayName
    }

    // TODO: Revisit profile style tags — UI removed for now; keep ProfileStyleTag model / sync for a later pass.
    // private var currentStyleTagLabels: [String] {
    //     userProfile?.profileStyleTags.map(\.rawValue) ?? []
    // }

    private var profileNavigationTitle: String {
        appCapabilities.tier == .testflight ? "Info" : "Profile"
    }

    private var profileUsernameText: String {
        if isViewingOtherUser, let viewedProfile {
            return sanitizeUsername(viewedProfile.username)
        }
        let raw = (username ?? supabaseService.cachedUsername ?? "username")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitizeUsername(raw)
    }

    private func sanitizeUsername(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private var profileScreenNavigationTitle: String {
        if isViewingOtherUser {
            return profileUsernameText
        }
        if appCapabilities.showsWishlistTab {
            return profileUsernameText
        }
        return profileNavigationTitle
    }

    /// Header avatar uses the same remote URL + initials pattern as friend lists.
    private var profileForAvatar: PublicUserProfile? {
        if isViewingOtherUser, let viewedProfile {
            return viewedProfile
        }
        guard let uid = authSession.userId else { return nil }
        return PublicUserProfile(
            userId: uid,
            username: username ?? supabaseService.cachedUsername ?? "",
            displayName: currentDisplayName,
            avatarUrl: userProfile?.storedProfileAvatarURL
        )
    }

    /// Stable identity for forcing image reload when the avatar URL changes (upload/remove).
    private var avatarHeaderViewIdentity: String {
        if isViewingOtherUser {
            return viewedProfile?.avatarUrl ?? viewedProfile?.userId.uuidString ?? "other"
        }
        return userProfile?.storedProfileAvatarURL ?? ""
    }
    
    private var followingCount: Int { supabaseService.cachedFollowingCount ?? 0 }
    private var followersCount: Int { supabaseService.cachedFollowersCount ?? 0 }

    private var displayedFollowingCount: Int {
        if isViewingOtherUser {
            return viewedUserFollowingCount ?? 0
        }
        return followingCount
    }

    private var displayedFollowersCount: Int {
        if isViewingOtherUser {
            return viewedUserFollowersCount ?? 0
        }
        return followersCount
    }

    private var displayedProfileUserId: UUID? {
        viewedProfile?.userId ?? authSession.userId
    }
    
    /// Items linked to this wardrobe that ItemGridView would show with no extra filters (userId, not draft, not soft-deleted).
    private func nonDraftItemCount(for wardrobe: Wardrobe) -> Int {
        guard let uid = currentUserId else { return 0 }
        guard let set = wardrobe.items as? Set<Item> else { return 0 }
        return set.filter { item in
            item.userId == uid && itemIncludedLikeItemGrid(item)
        }.count
    }

    /// Mirrors ItemGridView base predicates: `isDraft != YES`, `isSoftDeleted != YES OR nil`.
    private func itemIncludedLikeItemGrid(_ item: Item) -> Bool {
        if item.value(forKey: "isDraft") as? Bool == true { return false }
        if item.value(forKey: "isSoftDeleted") as? Bool == true { return false }
        return true
    }
    
    private func wardrobeTypeLabel(for wardrobe: Wardrobe) -> String {
        switch wardrobe.type?.lowercased() {
        case "wishlist": return "Wishlist"
        default: return "Closet"
        }
    }

    private var profileWardrobeNavigationTitle: String {
        selectedProfileWardrobe?.name ?? "Wardrobes"
    }

    private func setInitialProfileWardrobe() {
        guard currentUserId != nil else { return }

        if let selected = selectedProfileWardrobe {
            let stillValid = friendVisibleUserClosets.contains(where: { $0.objectID == selected.objectID })
                || friendVisibleUserWishlists.contains(where: { $0.objectID == selected.objectID })
            if !stillValid {
                selectedProfileWardrobe = nil
            }
        }

        if selectedProfileWardrobe == nil {
            selectedProfileWardrobe = preferredFriendVisibleProfileWardrobe
        }
    }

    private func presentNotificationsIfRequestedFromPush() {
        guard deepLinkRouter.shouldOpenNotifications, !isViewingOtherUser else { return }
        appendProfileRoute(.notifications)
        deepLinkRouter.consumeOpenNotifications()
        PushNotificationService.shared.clearBadge()
    }

    private func appendProfileRoute(_ route: ProfileRoute) {
        tabBarHideState.shouldHideTabBar = true
        if ownsNavigationStack {
            navigationPath.append(route)
        } else {
            sharedNavigationPath?.wrappedValue.append(route)
        }
    }

    /// Avoid hammering the server (and remounting UI) on every Profile tab return.
    private func refreshOwnFriendshipStateIfStale() async {
        let now = Date()
        if let last = lastOwnFriendshipRefreshAt, now.timeIntervalSince(last) < 30 {
            return
        }
        lastOwnFriendshipRefreshAt = now
        await supabaseService.refreshOwnFriendshipStateFromServer()
    }

    private func syncProfileWardrobeSheetTabToSelection() {
        if (selectedProfileWardrobe?.type ?? "").lowercased() == "wishlist" {
            selectedProfileWardrobeTab = "Wishlist"
        } else {
            selectedProfileWardrobeTab = "Closet"
        }
    }

    private func selectProfileWardrobe(_ wardrobe: Wardrobe) {
        if selectedProfileWardrobe?.objectID != wardrobe.objectID {
            profileFilterModel.clearAll()
            profileOutfitFilterModel.clearAll()
            navigationPath = NavigationPath()
        }
        selectedProfileWardrobe = wardrobe
        showWardrobesSheet = false
    }
    
    private func wardrobeSubtitle(for wardrobe: Wardrobe) -> String {
        let type = wardrobeTypeLabel(for: wardrobe)
        let n = nonDraftItemCount(for: wardrobe)
        let countPart = n == 1 ? "1 item" : "\(n) items"
        return "\(type) · \(countPart)"
    }

    /// Closet / wishlist picker + lists — shown in the Wardrobes sheet (production only).
    /// Private wardrobes are omitted so the owner sees the same set a friend would.
    private var profileWardrobesSheetContent: some View {
        VStack(spacing: 0) {
            SelectionPanelHeader(title: "Wardrobes") {
                Picker("", selection: $selectedProfileWardrobeTab) {
                    Text("Closet (\(friendVisibleUserClosets.count))")
                        .tag("Closet")
                    Text("Wishlist (\(friendVisibleUserWishlists.count))")
                        .tag("Wishlist")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Group {
                if selectedProfileWardrobeTab == "Closet" {
                    profileWardrobePage(wardrobes: friendVisibleUserClosets, emptyNoun: "closets")
                } else {
                    profileWardrobePage(wardrobes: friendVisibleUserWishlists, emptyNoun: "wishlists")
                }
            }
        }
    }

    private var profileWardrobesSheet: some View {
        profileWardrobesSheetContent
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }
    
    @ViewBuilder
    private func profileWardrobePage(wardrobes: [Wardrobe], emptyNoun: String) -> some View {
        List {
            if wardrobes.isEmpty {
                Text("No \(emptyNoun) yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
            } else {
                ForEach(wardrobes, id: \.objectID) { wardrobe in
                    Button {
                        selectProfileWardrobe(wardrobe)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: wardrobe.wardrobeVisibility.iconName)
                                .foregroundStyle(.secondary)
                                .frame(width: 22, alignment: .center)
                                .accessibilityLabel(wardrobe.wardrobeVisibility.menuLabel)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(wardrobe.name ?? "Untitled")
                                    .fontWeight(selectedProfileWardrobe?.objectID == wardrobe.objectID ? .bold : .regular)
                                    .foregroundStyle(.primary)
                                Text(wardrobeSubtitle(for: wardrobe))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            if selectedProfileWardrobe?.objectID == wardrobe.objectID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                }
            }
        }
        .listStyle(.plain)
    }

    private var shouldHideTabBar: Bool {
        isViewingOtherUser
            || isRedressOutfitPresented
            || isProfileItemGridInSelectionMode
            || isProfileGridDetailNavigationActive
            || (ownsNavigationStack && !navigationPath.isEmpty)
    }

    /// Own-profile ItemGridView fills the screen and owns nav toolbar items (same as Closet).
    private var profileItemGridOwnsNavigationToolbar: Bool {
        !isViewingOtherUser
            && appCapabilities.tier != .testflight
            && appCapabilities.showsWishlistTab
            && selectedProfileWardrobe != nil
    }

    var body: some View {
        // Own profile tab owns the stack. Nested profiles (Friends / Users / Redress)
        // must join that stack — a second NavigationStack orphans Friends and makes
        // Back from item detail jump to the root profile.
        if ownsNavigationStack {
            // Single stack for the Profile tab. Nested other-user profiles join this
            // stack — do not wrap Profile content in another NavigationStack.
            NavigationStack(path: $navigationPath) {
                profileWithPresentations
                    .navigationDestination(for: ProfileRoute.self) { route in
                        profileRouteDestination(route)
                    }
            }
        } else {
            profileWithPresentations
        }
    }

    /// `true` only for the Profile tab root (`viewedProfile == nil`).
    private var ownsNavigationStack: Bool {
        viewedProfile == nil
    }

    private var profileWithPresentations: some View {
        profileWithLifecycle
            .alert("Photo", isPresented: avatarUploadErrorPresented) {
                Button("OK", role: .cancel) { avatarUploadError = nil }
            } message: {
                Text(avatarUploadError ?? "")
            }
            .sheet(isPresented: $isProfileLibraryPickerPresented) {
                profileLibraryPickerSheet
            }
            .toolbar {
                if isViewingOtherUser {
                    otherUserProfileToolbar()
                } else if !profileItemGridOwnsNavigationToolbar {
                    profileNavigationToolbar()
                }
            }
            // Keyboard must not resize/push the nested profile scroll (Cancel jump).
            .ignoresSafeArea(isViewingOtherUser ? .keyboard : [])
            .toolbar(shouldHideTabBar ? .hidden : .automatic, for: .tabBar)
            .onAppear {
                tabBarHideState.shouldHideTabBar = shouldHideTabBar
            }
            .onChange(of: navigationPath.count) { _, _ in
                tabBarHideState.shouldHideTabBar = shouldHideTabBar
            }
            .confirmationDialog(
                "Profile",
                isPresented: $showOtherUserProfileOptionsDialog,
                titleVisibility: .visible
            ) {
                Button("Share Profile") {
                    // Share action TBD
                }
                Button("Block User", role: .destructive) {}
                Button("Report User", role: .destructive) {}
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: wardrobesSheetPresented) {
                profileWardrobesSheet
            }
            .sheet(isPresented: $showRemoteWardrobesSheet) {
                remoteWardrobesSheet
            }
            .alert("Remove Friend?", isPresented: $showRemoveFriendAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Remove Friend", role: .destructive) {
                    Task { await removeFriendshipWithViewedUser() }
                }
            } message: {
                Text("Are you sure you want to remove this friend?")
            }
    }

    private var profileWithLifecycle: some View {
        profileWithDestinations
            .task(id: authSession.userId) {
                guard !isViewingOtherUser else { return }
                await bootstrapProfileIfNeeded()
            }
            .task(id: viewedProfile?.userId) {
                guard isViewingOtherUser, appCapabilities.enablesCloudSync else { return }
                // otherUserContentTab = "WARDROBE" // deferred: other-user-profile-calendar-deferred.mdc
                hydrateOtherUserProfileFromCacheIfNeeded()
                async let wardrobes: Void = loadRemoteWardrobes()
                async let social: Void = loadViewedUserSocialMetadata()
                async let redress: Void = loadRedressAvailability()
                _ = await (wardrobes, social, redress)
            }
            .onAppear(perform: handleProfileAppear)
            .onChange(of: deepLinkRouter.shouldOpenNotifications) { _, open in
                guard open else { return }
                presentNotificationsIfRequestedFromPush()
            }
            .onChange(of: authSession.userId) { _, newId in
                handleAuthUserIdChange(newId)
            }
            .onChange(of: userProfiles.count) { _ in
                viewContext.refreshAllObjects()
            }
            .onChange(of: userProfile?.displayName) { _ in
                viewContext.refreshAllObjects()
            }
            .onChange(of: userProfile?.username) { _ in
                viewContext.refreshAllObjects()
            }
    }

    @ViewBuilder
    private func profileRouteDestination(_ route: ProfileRoute) -> some View {
        switch route {
        case .settings:
            SettingsView(navigationPath: $navigationPath)
        case .attributePreferences:
            AttributePreferencesView(navigationPath: $navigationPath)
        case .categoryVisibility:
            CategoryVisibilityView()
        case .colorVisibility:
            ColorVisibilityView()
        case .seasonVisibility:
            SeasonVisibilityView()
        case .developerSettings:
            DeveloperSettingsView(navigationPath: $navigationPath)
        case .developerSignIn:
            SignInView()
        case .developerRegister:
            RegisterView()
        case .notifications:
            UserNotificationsView(tabBarHideState: tabBarHideState)
        case .users:
            UsersView(tabBarHideState: tabBarHideState, navigationPath: $navigationPath)
        case .friends(let userId, let followersCount, let followingCount):
            FriendsView(
                userId: userId,
                followersCount: followersCount,
                followingCount: followingCount,
                tabBarHideState: tabBarHideState,
                navigationPath: $navigationPath
            )
        case .editProfile:
            EditProfileView()
        case .otherUser(let profile):
            ProfileView(
                viewedProfile: profile,
                sharedTabBarHideState: tabBarHideState,
                sharedNavigationPath: $navigationPath
            )
        case .readOnlyItem(let destination):
            ReadOnlyItemDetailView(
                ownerUserId: destination.ownerUserId,
                wardrobeId: destination.wardrobeId,
                itemSummary: destination.item,
                wardrobeType: destination.wardrobeType,
                ownerProfile: destination.ownerProfile ?? PublicUserProfile(
                    userId: destination.ownerUserId,
                    username: supabaseService.cachedUsername ?? "",
                    displayName: nil
                ),
                tabBarHideState: tabBarHideState,
                navigationPath: $navigationPath
            )
        case .readOnlyOutfit(let ownerUserId, let wardrobeId, let outfit, let wardrobeType, let ownerProfile):
            if outfit.isPendingSuggestion {
                PendingOutfitDetailView(
                    recipientUserId: ownerUserId,
                    wardrobeId: wardrobeId,
                    suggestionSummary: outfit,
                    viewerRole: .submitter,
                    onSuggestionResolved: {
                        supabaseService.invalidateWardrobeGridOutfitsCache(forUserId: ownerUserId)
                    },
                    counterpartUsername: ownerProfile?.username,
                    counterpartDisplayName: ownerProfile?.displayName,
                    backButtonTitle: ownerProfile?.username
                )
            } else {
                ReadOnlyOutfitDetailView(
                    ownerUserId: ownerUserId,
                    wardrobeId: wardrobeId,
                    outfitSummary: outfit,
                    wardrobeType: wardrobeType,
                    ownerProfile: ownerProfile,
                    tabBarHideState: tabBarHideState,
                    navigationPath: $navigationPath
                )
            }
        case .itemRedress(let destination):
            OutfitAddView(
                redressRecipient: destination.recipient,
                preselectedItem: destination.item,
                preselectedWardrobeType: destination.wardrobeType,
                sessionID: destination.id
            )
            .id(destination.id)
        case .itemFilter:
            ItemFilterView(
                filterModel: profileFilterModel,
                tabBarHideState: tabBarHideState,
                wardrobeType: (selectedProfileWardrobe?.type ?? "closet").lowercased(),
                attributesReadOnly: true,
                selectedWardrobe: selectedProfileWardrobe
            )
        case .outfitFilter:
            OutfitFilterView(
                filterModel: profileOutfitFilterModel,
                wardrobeType: (selectedProfileWardrobe?.type ?? "closet").lowercased(),
                attributesReadOnly: true,
                selectedWardrobe: selectedProfileWardrobe
            )
        }
    }

    private var profileWithDestinations: some View {
        // Nested other-user profiles join the root NavigationStack — do not re-register
        // root path destinations or they fight Friends → profile.
        Group {
            if ownsNavigationStack {
                profileNavigationChrome
            } else {
                profileNavigationChrome
                    .navigationDestination(isPresented: $isRedressOutfitPresented) {
                        redressOutfitDestination
                    }
            }
        }
    }

    private var profileNavigationChrome: some View {
        profileRootStack
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.systemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isViewingOtherUser
                    && appCapabilities.enablesFriendsAndSharing
                    && !isRedressOutfitPresented {
                    otherUserRedressBottomBar
                }
            }
            .navigationTitle(profileScreenNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar(.visible, for: .navigationBar)
            .modifier(NavigationBarHairlineHidden(backgroundColor: UIColor.systemBackground))
    }

    @ViewBuilder
    private var redressOutfitDestination: some View {
        if let profile = viewedProfile {
            OutfitAddView(redressRecipient: profile) {
                if let ownerId = viewedProfile?.userId {
                    supabaseService.invalidateWardrobeGridOutfitsCache(forUserId: ownerId)
                }
                remoteGridRefreshToken = UUID()
                remoteGridPreferredTab = "Outfits"
            }
        }
    }

    private var profileLibraryPickerSheet: some View {
        ImagePicker(
            image: $profilePickerImage,
            sourceType: $profileImagePickerSource,
            allowsEditing: true,
            usesProfileCrop: true
        ) { image in
            isProfileLibraryPickerPresented = false
            guard let image else { return }
            Task { await uploadProfileAvatarFromLibrary(image) }
        }
    }

    private func handleProfileAppear() {
        if isViewingOtherUser {
            hydrateOtherUserProfileFromCacheIfNeeded()
        } else if appCapabilities.showsWishlistTab {
            if let uid = authSession.userId {
                try? WardrobeBootstrap.ensureDefaultWardrobes(for: uid, in: viewContext)
            }
            setInitialProfileWardrobe()
        } else {
            selectedProfileWardrobeTab = "Closet"
        }
        presentNotificationsIfRequestedFromPush()
        if !isViewingOtherUser, appCapabilities.enablesFriendsAndSharing {
            Task { await refreshOwnFriendshipStateIfStale() }
        }
    }

    private func handleAuthUserIdChange(_ newId: UUID?) {
        if newId == nil {
            didBootstrapProfileFromServerForUserId = nil
            selectedProfileWardrobe = nil
        } else if appCapabilities.showsWishlistTab {
            setInitialProfileWardrobe()
        }
    }

    @ViewBuilder
    private var profileRootStack: some View {
        if isViewingOtherUser {
            otherUserProfileContent
        } else if appCapabilities.tier == .testflight {
            HowToTipsCarousel(
                currentPage: $profileHowToPage,
                pages: HowToPage.testFlightPages(displayName: currentDisplayName)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal)
        } else if appCapabilities.showsWishlistTab, let selectedWardrobe = selectedProfileWardrobe {
            ItemGridView(
                filterModel: profileFilterModel,
                outfitFilterModel: profileOutfitFilterModel,
                wardrobeType: (selectedWardrobe.type ?? "closet").lowercased(),
                selectedWardrobe: selectedWardrobe,
                isReadOnly: true,
                showsProfilePendingRedressSuggestions: true,
                isInSelectionMode: $isProfileItemGridInSelectionMode,
                isDetailNavigationActive: $isProfileGridDetailNavigationActive,
                isTabActionsBarVisible: $isProfileFilterActionsVisible,
                onOpenItemFilter: {
                    appendProfileRoute(.itemFilter)
                },
                onOpenOutfitFilter: {
                    appendProfileRoute(.outfitFilter)
                },
                onOpenProfileReadOnlyItem: { destination in
                    appendProfileRoute(.readOnlyItem(destination))
                },
                tabBarHideState: tabBarHideState,
                profileCollapsingHeader: {
                    profileHeaderSection
                },
                profileStickyPrefix: {
                    profileWardrobeBar
                }
            )
            // Closet-style: toolbar on the leaf content that fills the nav stack,
            // not only on the Profile wrapper (nested UIKit scroll otherwise wins).
            .toolbar {
                if !isProfileItemGridInSelectionMode {
                    profileNavigationToolbar()
                }
            }
            .id(selectedWardrobe.objectID)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if appCapabilities.showsWishlistTab {
            ownProfileEmptyPublicWardrobesContent
                .toolbar {
                    profileNavigationToolbar()
                }
        } else {
            VStack(spacing: 0) {
                profileHeaderSection
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var avatarUploadErrorPresented: Binding<Bool> {
        Binding(
            get: { avatarUploadError != nil },
            set: { if !$0 { avatarUploadError = nil } }
        )
    }

    private var wardrobesSheetPresented: Binding<Bool> {
        Binding(
            get: { appCapabilities.showsWishlistTab && showWardrobesSheet },
            set: { showWardrobesSheet = $0 }
        )
    }

    @ViewBuilder
    private var profileHeaderSection: some View {
        if isViewingOtherUser {
            otherUserProfileHeaderSection
        } else {
            ownProfileHeaderSection
        }
    }

    /// Own-profile header: avatar left, display name + Friends / Sizes / Edit Profile right.
    /// Full template (bio/tags/location/socials/etc.) — `.cursor/rules/profile-header-full-template-deferred.mdc`.
    @ViewBuilder
    private var ownProfileHeaderSection: some View {
        HStack(alignment: .top, spacing: 16) {
            ownProfileAvatarWithPhotoTap

            VStack(alignment: .leading, spacing: 0) {
                Text(displayNameForHeader)
                    .font(.headline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)

                Text("redress.me/\(profileUsernameText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)

                ownProfileHeaderActionsRow
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, Self.profileHeaderTopPadding)
        .padding(.bottom, Self.profileHeaderBottomPadding)
        .id(refreshToken)
    }

    /// Friends, Edit, Share — equal-width, equal-height icon-over-label buttons.
    private var ownProfileHeaderActionsRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if appCapabilities.enablesFriendsAndSharing {
                Button {
                    if let userId = displayedProfileUserId {
                        appendProfileRoute(
                            .friends(
                                userId: userId,
                                followersCount: displayedFollowersCount,
                                followingCount: displayedFollowingCount
                            )
                        )
                    }
                } label: {
                    ownProfileHeaderIconLabelStack(
                        title: "Friends",
                        systemImage: "person.2"
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .accessibilityLabel("Friends")
            }

            Button {
                appendProfileRoute(.editProfile)
            } label: {
                ownProfileHeaderIconLabelStack(
                    title: "Edit",
                    systemImage: "pencil"
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .accessibilityLabel("Edit profile")

            Button {
                // Share sheet for own profile — wire later.
            } label: {
                ownProfileHeaderIconLabelStack(
                    title: "Share",
                    systemImage: "square.and.arrow.up"
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .accessibilityLabel("Share profile")
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func ownProfileHeaderIconLabelStack(
        title: String,
        systemImage: String,
        iconRotation: Double = 0
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .rotationEffect(.degrees(iconRotation))
                .frame(width: 16, height: 16)
            Text(title)
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.vertical, 8)
    }

    private var ownProfileAvatarWithPhotoTap: some View {
        ZStack {
            avatarImageContent(size: Self.profileHeaderAvatarSize)

            Button {
                isProfilePhotoActionDialogPresented = true
            } label: {
                Color.clear
                    .frame(
                        width: Self.profileHeaderAvatarSize,
                        height: Self.profileHeaderAvatarSize
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isAvatarUploading)
            .confirmationDialog(
                "Profile Photo",
                isPresented: $isProfilePhotoActionDialogPresented,
                titleVisibility: .visible
            ) {
                Button("Take Photo") { }
                Button("Choose from Library") {
                    profileImagePickerSource = .photoLibrary
                    isProfileLibraryPickerPresented = true
                }
                Button("Remove Current Photo", role: .destructive) {
                    Task { await removeProfileAvatar() }
                }
                Button("Cancel", role: .cancel) { }
            }
        }
        .frame(width: Self.profileHeaderAvatarSize, height: Self.profileHeaderAvatarSize)
        .accessibilityLabel("Profile photo")
    }

    /// Shared corner radius for own / other-user header action buttons.
    private static let otherUserHeaderActionCornerRadius: CGFloat = 8
    /// Gap between display name ↔ action buttons, and action buttons ↔ wardrobe row.
    private static let otherUserHeaderActionsVerticalSpacing: CGFloat = 14

    // MARK: - Other-user header (avatar left; Friends + Add Friend like own-profile actions)

    @ViewBuilder
    private var otherUserProfileHeaderSection: some View {
        HStack(alignment: .top, spacing: 16) {
            avatarImageContent(size: Self.profileHeaderAvatarSize)

            VStack(alignment: .leading, spacing: 0) {
                Text(displayNameForHeader)
                    .font(.headline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)

                Text("redress.me/\(profileUsernameText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)

                if appCapabilities.enablesFriendsAndSharing {
                    otherUserHeaderActionsRow
                        .padding(.top, 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, Self.profileHeaderTopPadding)
        .padding(.bottom, Self.profileHeaderBottomPadding)
        .id(refreshToken)
    }

    /// Friends (list) + Add Friend / Remove + Share — equal-width icon-over-label buttons.
    private var otherUserHeaderActionsRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                if let userId = displayedProfileUserId {
                    appendProfileRoute(
                        .friends(
                            userId: userId,
                            followersCount: displayedFollowersCount,
                            followingCount: displayedFollowingCount
                        )
                    )
                }
            } label: {
                ownProfileHeaderIconLabelStack(
                    title: "Friends",
                    systemImage: "person.2"
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .accessibilityLabel("Friends")

            otherUserFriendshipButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            Button {
                // Share sheet for this user's profile — wire later.
            } label: {
                ownProfileHeaderIconLabelStack(
                    title: "Share",
                    systemImage: "square.and.arrow.up"
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .accessibilityLabel("Share profile")
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var otherUserFriendshipButton: some View {
        let title: String
        let systemImage: String
        let accessibility: String
        let showsConnectedState: Bool

        if isFollowingViewedUser || isMutualFriendWithViewedUser {
            title = "Remove"
            systemImage = "person.badge.minus"
            accessibility = "Remove friend"
            showsConnectedState = true
        } else {
            title = "Add Friend"
            systemImage = "person.badge.plus"
            accessibility = "Add friend"
            showsConnectedState = false
        }

        return Button {
            if showsConnectedState {
                showRemoveFriendAlert = true
            } else {
                Task { await sendFriendRequestToViewedUser() }
            }
        } label: {
            ownProfileHeaderIconLabelStack(
                title: title,
                systemImage: systemImage
            )
        }
        .buttonStyle(.plain)
        .disabled(isUpdatingFriendship)
        .accessibilityLabel(accessibility)
    }

    private var otherUserRedressButton: some View {
        let enabled = isRedressHeaderActionEnabled
        return Button {
            guard enabled else { return }
            isRedressOutfitPresented = true
        } label: {
            otherUserOutlinedRedressHeaderButtonLabel(enabled: enabled)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(enabled)
        .accessibilityLabel("Redress")
        .accessibilityHint(enabled ? "" : "Unavailable")
    }

    private var otherUserRedressBottomBar: some View {
        otherUserRedressButton
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .background(Color(UIColor.systemBackground))
    }

    private func otherUserOutlinedRedressHeaderButtonLabel(enabled: Bool) -> some View {
        HStack(spacing: 8) {
            Image("Redress.SFSymbol")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text("Redress")
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.7))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Self.otherUserHeaderActionCornerRadius, style: .continuous)
                .fill(enabled ? AnyShapeStyle(Color.cayenne.gradient) : AnyShapeStyle(Color.cayenne.opacity(0.45)))
        )
        .opacity(enabled ? 1 : 0.7)
    }

    private var isRedressHeaderActionEnabled: Bool {
        canShowRedress && !remoteWardrobes.isEmpty
    }

    private func avatarImageContent(size: CGFloat) -> some View {
        ZStack {
            if let p = profileForAvatar {
                PublicUserProfileAvatarView(profile: p, size: size)
                    // Identity = avatar URL only. Do not include @State UUIDs — those reset when
                    // ProfileView is recreated (tab switch) and would remount/reload the image.
                    .id(avatarHeaderViewIdentity)
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .foregroundColor(.gray)
            }
            if isAvatarUploading {
                Circle()
                    .fill(.ultraThinMaterial)
                ProgressView()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .contentShape(Circle())
    }

    private var displayNameForHeader: String {
        if isViewingOtherUser, let viewedProfile {
            let name = viewedProfile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? "Name" : name
        }
        return currentDisplayName ?? "Name"
    }

    @ViewBuilder
    private var profileWardrobeBar: some View {
        if !isProfileItemGridInSelectionMode {
            HStack {
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    if !isViewingOtherUser {
                        profileWardrobeVisibilityIcon
                    }
                    profileWardrobeSelectionButton()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, Self.wardrobeBarEdgePadding)
            .background(Color(.systemBackground))
        }
    }

    private var selectedProfileWardrobeVisibility: WardrobeVisibility {
        selectedProfileWardrobe?.wardrobeVisibility ?? .public
    }

    private var profileWardrobeVisibilityIcon: some View {
        Image(systemName: selectedProfileWardrobeVisibility.iconName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityLabel(selectedProfileWardrobeVisibility.menuLabel)
    }

    @ToolbarContentBuilder
    private func otherUserProfileToolbar() -> some ToolbarContent {
        // Do not place a custom `.principal` title — it often collapses the system
        // back button to a bare chevron (losing "< Friends"). Title comes from
        // `.navigationTitle` on `profileNavigationChrome`.
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showOtherUserProfileOptionsDialog = true
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
            }
            .accessibilityLabel("More options")
        }
    }

    @ToolbarContentBuilder
    private func profileNavigationToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                appendProfileRoute(.settings)
            } label: {
                Image(systemName: "gearshape")
            }
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if appCapabilities.enablesFriendsAndSharing {
                UserNotificationsBellButton {
                    appendProfileRoute(.notifications)
                }
            }
            if appCapabilities.enablesCloudSync {
                Button {
                    appendProfileRoute(.users)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add friend")
            }
        }
    }

    private func profileWardrobeSelectionButton() -> some View {
        Button {
            syncProfileWardrobeSheetTabToSelection()
            showWardrobesSheet = true
        } label: {
            HStack(spacing: 4) {
                Text(profileWardrobeNavigationTitle)
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var otherUserProfileContent: some View {
        if !appCapabilities.enablesFriendsAndSharing {
            Text("Profile viewing is not available in this build.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !appCapabilities.enablesCloudSync {
            Text("Sign in with cloud sync to view profiles.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoadingRemoteWardrobes {
            ProgressView("Loading profile…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let remoteWardrobesError {
            Text(remoteWardrobesError)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if preferredRemoteProfileWardrobe == nil {
            otherUserEmptyPublicWardrobesContent
        } else if let wardrobe = selectedRemoteWardrobe, let ownerId = viewedProfile?.userId {
            RemoteProfileView(
                ownerUserId: ownerId,
                wardrobe: wardrobe,
                ownerProfile: viewedProfile,
                refreshToken: remoteGridRefreshToken,
                preferredTab: $remoteGridPreferredTab,
                tabBarHideState: tabBarHideState,
                navigationPath: sharedNavigationPath,
                profileCollapsingHeader: {
                    profileHeaderSection
                },
                profileStickyPrefix: {
                    // Deferred WARDROBE/CALENDAR tab row — other-user-profile-calendar-deferred.mdc
                    // VStack(spacing: 0) {
                    //     otherUserSectionTabBar
                    //     remoteProfileWardrobeBar(wardrobe: wardrobe)
                    // }
                    remoteProfileWardrobeBar(wardrobe: wardrobe)
                }
            )
            .id("\(wardrobe.id)-\(remoteGridRefreshToken.uuidString)")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /*
    // MARK: Deferred — other-user WARDROBE / CALENDAR (other-user-profile-calendar-deferred.mdc)

    private var otherUserSectionTabBar: some View {
        UnderlineTabBar(
            selectedTab: $otherUserContentTab,
            tabs: ["WARDROBE", "CALENDAR"]
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }

    private var otherUserCalendarContent: some View {
        VStack(spacing: 0) {
            profileHeaderSection
            otherUserSectionTabBar
            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2),
                    ],
                    spacing: 2
                ) {
                    ForEach(Self.otherUserCalendarPlaceholderEvents) { event in
                        OtherUserPlaceholderEventCard(event: event)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemBackground))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
    }

    private static let otherUserCalendarPlaceholderEvents: [OtherUserPlaceholderEvent] = [
        OtherUserPlaceholderEvent(day: "Friday", date: "14", time: "7:00 PM", location: "Downtown"),
        OtherUserPlaceholderEvent(day: "Saturday", date: "15", time: "11:30 AM", location: "City Park"),
        OtherUserPlaceholderEvent(day: "Sunday", date: "16", time: "6:00 PM", location: "Harbor"),
    ]
    */

    /// Own profile with no public wardrobes: same nested chrome; wardrobe bar still opens the picker.
    private var ownProfileEmptyPublicWardrobesContent: some View {
        ProfileNestedScrollContainer(
            selectedTab: $ownEmptyGridPreferredTab,
            header: profileHeaderSection,
            sticky: VStack(spacing: 0) {
                profileWardrobeBar
                Picker("", selection: $ownEmptyGridPreferredTab) {
                    Text("Items (0)").tag("Items")
                    Text("Outfits (0)").tag("Outfits")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(true)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
            }
            .background(Color(.systemBackground)),
            itemsPage: emptyPublicWardrobeTabMessage,
            outfitsPage: emptyPublicWardrobeTabMessage,
            snapsHeaderCollapse: true
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Other-user profile with no public wardrobes: same UIKit nested chrome as a populated grid.
    private var otherUserEmptyPublicWardrobesContent: some View {
        ProfileNestedScrollContainer(
            selectedTab: $remoteGridPreferredTab,
            header: profileHeaderSection,
            sticky: VStack(spacing: 0) {
                // otherUserSectionTabBar // deferred: other-user-profile-calendar-deferred.mdc
                remoteLockedClosetWardrobeBar
                Picker("", selection: $remoteGridPreferredTab) {
                    Text("Items (0)").tag("Items")
                    Text("Outfits (0)").tag("Outfits")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(true)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
            }
            .background(Color(.systemBackground)),
            itemsPage: emptyPublicWardrobeTabMessage,
            outfitsPage: emptyPublicWardrobeTabMessage,
            onRefresh: {
                await loadRemoteWardrobes()
            },
            snapsHeaderCollapse: true
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyPublicWardrobeTabMessage: some View {
        ScrollView(showsIndicators: false) {
            Text("No public wardrobes")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        }
    }

    private var remoteLockedClosetWardrobeBar: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: WardrobeVisibility.private.iconName)
                    .font(.profileSerif(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(WardrobeVisibility.private.menuLabel)

                Text("Closet")
                    .font(.profileSerif(.headline, weight: .bold))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 0)
        .padding(.bottom, Self.wardrobeBarEdgePadding)
        .background(Color(.systemBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Closet, private")
    }

    private func remoteProfileWardrobeBar(wardrobe: VisibleWardrobe) -> some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: wardrobe.wardrobeVisibility.iconName)
                    .font(.profileSerif(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(wardrobe.wardrobeVisibility.menuLabel)

                Button {
                    syncRemoteWardrobeSheetTabToSelection()
                    showRemoteWardrobesSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Text(wardrobe.name)
                            .font(.profileSerif(.headline, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.profileSerif(.caption))
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 0)
        .padding(.bottom, Self.wardrobeBarEdgePadding)
        .background(Color(.systemBackground))
    }

    private var remoteWardrobesSheet: some View {
        VStack(spacing: 0) {
            SelectionPanelHeader(title: "Wardrobes") {
                Picker("", selection: $selectedRemoteWardrobeTab) {
                    Text("Closet (\(remoteClosets.count))").tag("Closet")
                    Text("Wishlist (\(remoteWishlists.count))").tag("Wishlist")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Group {
                if selectedRemoteWardrobeTab == "Closet" {
                    remoteWardrobePage(wardrobes: remoteClosets, emptyNoun: "closets")
                } else {
                    remoteWardrobePage(wardrobes: remoteWishlists, emptyNoun: "wishlists")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func remoteWardrobePage(wardrobes: [VisibleWardrobe], emptyNoun: String) -> some View {
        List {
            if wardrobes.isEmpty {
                Text("No public \(emptyNoun)")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
            } else {
                ForEach(wardrobes) { wardrobe in
                    Button {
                        selectedRemoteWardrobe = wardrobe
                        showRemoteWardrobesSheet = false
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(wardrobe.name)
                                    .font(.profileSerif(.body, weight: selectedRemoteWardrobe?.id == wardrobe.id ? .bold : .regular))
                                    .foregroundStyle(.primary)
                                Text(wardrobe.wardrobeType == "wishlist" ? "Wishlist" : "Closet")
                                    .font(.profileSerif(.subheadline))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if selectedRemoteWardrobe?.id == wardrobe.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                }
            }
        }
        .listStyle(.plain)
    }

    private func syncRemoteWardrobeSheetTabToSelection() {
        if selectedRemoteWardrobe?.wardrobeType == "wishlist" {
            selectedRemoteWardrobeTab = "Wishlist"
        } else {
            selectedRemoteWardrobeTab = "Closet"
        }
    }

    private func setInitialRemoteWardrobe() {
        if let selected = selectedRemoteWardrobe,
           !remoteWardrobes.contains(where: { $0.id == selected.id }) {
            selectedRemoteWardrobe = nil
        }
        if selectedRemoteWardrobe == nil {
            selectedRemoteWardrobe = preferredRemoteProfileWardrobe
        }
    }

    private func loadRedressAvailability() async {
        guard let userId = viewedProfile?.userId else { return }
        do {
            let wardrobes = try await supabaseService.fetchRedressWardrobes(forUserId: userId)
            var hasItems = false
            for wardrobe in wardrobes {
                let items = try await supabaseService.fetchRedressWardrobeItems(
                    userId: userId,
                    wardrobeId: wardrobe.id
                )
                if !items.isEmpty {
                    hasItems = true
                    break
                }
            }
            await MainActor.run {
                canShowRedress = hasItems
            }
        } catch {
            print("⚠️ Failed to load Redress availability: \(error.localizedDescription)")
            await MainActor.run {
                canShowRedress = false
            }
        }
    }

    private func hydrateOtherUserProfileFromCacheIfNeeded() {
        guard let userId = viewedProfile?.userId else { return }

        if let cachedWardrobes = supabaseService.cachedVisibleWardrobes(forUserId: userId) {
            remoteWardrobes = cachedWardrobes
            setInitialRemoteWardrobe()
            isLoadingRemoteWardrobes = false
        }
        if let counts = supabaseService.cachedViewedUserFollowCounts(forUserId: userId) {
            viewedUserFollowingCount = counts.following
            viewedUserFollowersCount = counts.followers
        }
        if let details = supabaseService.cachedViewedUserFriendshipDetails(forUserId: userId) {
            applyViewedUserFriendshipDetails(details)
        } else if let isFriend = supabaseService.cachedViewedUserIsFriend(forUserId: userId) {
            isFriendWithViewedUser = isFriend
            isFollowingViewedUser = isFriend
            isMutualFriendWithViewedUser = false
        }
    }

    private func loadRemoteWardrobes() async {
        guard let userId = viewedProfile?.userId else { return }
        let hasCachedWardrobes = supabaseService.cachedVisibleWardrobes(forUserId: userId) != nil
        if !hasCachedWardrobes {
            await MainActor.run {
                isLoadingRemoteWardrobes = true
                remoteWardrobesError = nil
            }
        }
        do {
            let wardrobes = try await supabaseService.fetchVisibleWardrobes(forUserId: userId, forceRefresh: true)
            await MainActor.run {
                remoteWardrobes = wardrobes
                setInitialRemoteWardrobe()
                isLoadingRemoteWardrobes = false
            }
        } catch {
            await MainActor.run {
                if !hasCachedWardrobes {
                    remoteWardrobes = []
                    selectedRemoteWardrobe = nil
                }
                remoteWardrobesError = error.localizedDescription
                isLoadingRemoteWardrobes = false
            }
        }
    }

    private func loadViewedUserSocialMetadata() async {
        guard let userId = viewedProfile?.userId else { return }
        let hasCachedCounts = supabaseService.cachedViewedUserFollowCounts(forUserId: userId) != nil
        let hasCachedFriendshipDetails = supabaseService.cachedViewedUserFriendshipDetails(forUserId: userId) != nil
        if hasCachedCounts || hasCachedFriendshipDetails || supabaseService.cachedViewedUserIsFriend(forUserId: userId) != nil {
            await MainActor.run {
                if let counts = supabaseService.cachedViewedUserFollowCounts(forUserId: userId) {
                    viewedUserFollowingCount = counts.following
                    viewedUserFollowersCount = counts.followers
                }
                if let details = supabaseService.cachedViewedUserFriendshipDetails(forUserId: userId) {
                    applyViewedUserFriendshipDetails(details)
                } else if let isFriend = supabaseService.cachedViewedUserIsFriend(forUserId: userId) {
                    isFriendWithViewedUser = isFriend
                    isFollowingViewedUser = isFriend
                    isMutualFriendWithViewedUser = false
                }
            }
        }
        do {
            async let friendshipsTask = supabaseService.fetchFriendshipsForCurrentUser()
            let counts: FollowCounts
            if hasCachedCounts, let cached = supabaseService.cachedViewedUserFollowCounts(forUserId: userId) {
                counts = cached
            } else {
                counts = try await supabaseService.fetchFollowCounts(forUserId: userId)
            }
            let friendships = try await friendshipsTask
            let details = Self.friendshipDetails(
                with: userId,
                currentUserId: authSession.userId,
                friendships: friendships
            )
            await MainActor.run {
                viewedUserFollowingCount = counts.following
                viewedUserFollowersCount = counts.followers
                applyViewedUserFriendshipDetails(details)
            }
            supabaseService.storeViewedUserFriendshipDetails(details, forUserId: userId)
        } catch {
            print("⚠️ Failed to load viewed user social metadata: \(error.localizedDescription)")
        }
    }

    private func applyViewedUserFriendshipDetails(_ details: ViewedUserFriendshipDetails) {
        isFriendWithViewedUser = details.isFriend
        isFollowingViewedUser = details.isFollowing
        isMutualFriendWithViewedUser = details.isMutual
    }

    private static func friendshipDetails(
        with userId: UUID,
        currentUserId: UUID?,
        friendships: [FriendshipRecord]
    ) -> ViewedUserFriendshipDetails {
        guard let currentId = currentUserId else {
            return ViewedUserFriendshipDetails(isFriend: false, isFollowing: false, isMutual: false)
        }
        let iFollow = friendships.contains {
            $0.status == "accepted" && $0.user_id == currentId && $0.friend_user_id == userId
        }
        let theyFollow = friendships.contains {
            $0.status == "accepted" && $0.user_id == userId && $0.friend_user_id == currentId
        }
        return ViewedUserFriendshipDetails(
            isFriend: iFollow || theyFollow,
            isFollowing: iFollow,
            isMutual: iFollow && theyFollow
        )
    }

    private func sendFriendRequestToViewedUser() async {
        guard let profile = viewedProfile else { return }
        await MainActor.run { isUpdatingFriendship = true }
        defer { Task { @MainActor in isUpdatingFriendship = false } }
        do {
            try await supabaseService.sendFriendRequest(
                toUserId: profile.userId,
                toUsername: profile.username,
                toDisplayName: profile.displayName
            )
        } catch {
            print("⚠️ Failed to send friend request: \(error.localizedDescription)")
        }
    }

    private func removeFriendshipWithViewedUser() async {
        guard let userId = viewedProfile?.userId else { return }
        await MainActor.run { isUpdatingFriendship = true }
        defer { Task { @MainActor in isUpdatingFriendship = false } }
        do {
            try await supabaseService.unfriend(userId: userId)
            await supabaseService.refreshOwnFriendshipStateFromServer()
            await MainActor.run {
                isFriendWithViewedUser = false
                isFollowingViewedUser = false
                isMutualFriendWithViewedUser = false
                viewedUserFollowingCount = nil
                viewedUserFollowersCount = nil
            }
            // Force a fresh fetch after cache invalidation from unfriend.
            do {
                let counts = try await supabaseService.fetchFollowCounts(forUserId: userId, forceRefresh: true)
                await MainActor.run {
                    viewedUserFollowingCount = counts.following
                    viewedUserFollowersCount = counts.followers
                }
            } catch {
                print("⚠️ Failed to refresh viewed user follow counts: \(error.localizedDescription)")
            }
        } catch {
            print("⚠️ Failed to unfriend: \(error.localizedDescription)")
        }
    }

    private func bootstrapProfileIfNeeded() async {
        guard authSession.isAuthenticated, let uid = authSession.userId else { return }
        try? profileRepository.restoreLocalAvatarIfNeeded(userId: uid.uuidString)
        // Production: drop any leftover local JPEG so it cannot shadow the CDN avatar.
        if appCapabilities.enablesCloudSync, let uuid = authSession.userId {
            ProfileAvatarLocalStorage.delete(userId: uuid)
        }
        if didBootstrapProfileFromServerForUserId != uid.uuidString {
            do {
                _ = try await supabaseService.getUsername(forceRefresh: true)
                try? await Task.sleep(nanoseconds: 100_000_000)
                viewContext.refreshAllObjects()
                didBootstrapProfileFromServerForUserId = uid.uuidString
            } catch {
                print("⚠️ Error loading profile in ProfileView: \(error.localizedDescription)")
            }
        }
    }
}

extension ProfileView {
    /// Square-crops, flattens to opaque JPEG. Production uploads to R2 + Supabase; TestFlight stores on device only.
    private func uploadProfileAvatarFromLibrary(_ image: UIImage) async {
        guard let userId = authSession.userId else { return }
        let prepared = image.profileAvatarImageForUpload()
        guard let data = prepared.encodeForR2Upload() else {
            await MainActor.run {
                avatarUploadError = "Could not process image."
            }
            return
        }

        await MainActor.run {
            isAvatarUploading = true
            avatarUploadError = nil
        }
        defer {
            Task { @MainActor in
                isAvatarUploading = false
            }
        }

        do {
            let previousAvatarURL = userProfile?.storedProfileAvatarURL
            if appCapabilities.enablesCloudSync {
                let url = try await supabaseService.uploadProfileAvatar(imageData: data, userId: userId)
                try await supabaseService.updateProfileAvatarURL(url)
                // Don't let a leftover local JPEG shadow the CDN URL in the header avatar.
                ProfileAvatarLocalStorage.delete(userId: userId)
            } else {
                _ = try ProfileAvatarLocalStorage.saveJPEG(userId: userId, data: data)
                let repository = UserProfileRepository(context: viewContext)
                try repository.updateAvatarUrl(
                    ProfileAvatarLocalStorage.canonicalStoredURLString(for: userId),
                    userId: userId.uuidString,
                    syncToCloud: false
                )
            }
            if let previousAvatarURL {
                ProfileAvatarImageCache.remove(for: previousAvatarURL)
            }
            await MainActor.run {
                viewContext.refreshAllObjects()
                refreshToken = UUID()
            }
        } catch {
            await MainActor.run {
                avatarUploadError = error.localizedDescription
            }
        }
    }

    private func removeProfileAvatar() async {
        guard let userId = authSession.userId else { return }
        let previousAvatarURL = userProfile?.storedProfileAvatarURL
        await MainActor.run {
            isAvatarUploading = true
            avatarUploadError = nil
        }
        defer {
            Task { @MainActor in
                isAvatarUploading = false
            }
        }
        do {
            if appCapabilities.enablesCloudSync {
                try? await supabaseService.deleteProfileAvatar(userId: userId)
                try await supabaseService.updateProfileAvatarURL(nil)
                ProfileAvatarLocalStorage.delete(userId: userId)
            } else {
                ProfileAvatarLocalStorage.delete(userId: userId)
                let repository = UserProfileRepository(context: viewContext)
                try repository.updateAvatarUrl(nil, userId: userId.uuidString, syncToCloud: false)
            }
            if let previousAvatarURL {
                ProfileAvatarImageCache.remove(for: previousAvatarURL)
            }
            await MainActor.run {
                viewContext.refreshAllObjects()
                refreshToken = UUID()
            }
        } catch {
            await MainActor.run {
                avatarUploadError = error.localizedDescription
            }
        }
    }

}

// MARK: - Other-user calendar placeholders (deferred — other-user-profile-calendar-deferred.mdc)
// Kept as design stubs for event-redress profile calendar; not shown in UI yet.

struct OtherUserPlaceholderEvent: Identifiable {
    let id = UUID()
    let day: String
    let date: String
    let time: String
    let location: String
}

/// Placeholder event card: SelectionHeader-style gray band + square outfit/items stub + location.
struct OtherUserPlaceholderEventCard: View {
    let event: OtherUserPlaceholderEvent

    private let cornerRadius: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(event.day.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(event.date)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text(event.time)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(Color(UIColor.systemGray))

            Color(UIColor.tertiarySystemFill)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: "hanger")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Chosen items or outfit placeholder")

            HStack(spacing: 3) {
                Image(systemName: "mappin")
                    .font(.caption2)
                Text(event.location)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .background(Color(.systemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(UIColor.separator), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.day) \(event.date), \(event.time), \(event.location)")
    }
}
