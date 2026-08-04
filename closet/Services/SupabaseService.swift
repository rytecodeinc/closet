//
//  SupabaseService.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import Auth
import Foundation
import Supabase

struct PublicUserProfile: Decodable, Identifiable {
    let userId: UUID
    let username: String
    let displayName: String?
    /// Public avatar URL when exposed by RPC (e.g. `avatar_url` on `user_profiles`). Optional for backward compatibility.
    let avatarUrl: String?

    var id: UUID { userId }

    init(userId: UUID, username: String, displayName: String?, avatarUrl: String? = nil) {
        self.userId = userId
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(UUID.self, forKey: .userId)
        username = try c.decode(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
    }
}

struct FriendshipRecord: Decodable, Identifiable {
    let id: UUID
    let user_id: UUID
    let friend_user_id: UUID
    let status: String
    let created_at: Date?
    let updated_at: Date?
}

/// Directional friendship flags for a viewed profile (accepted edges only).
struct ViewedUserFriendshipDetails: Equatable {
    /// Any accepted edge between current user and viewed user.
    var isFriend: Bool
    /// Current user has an accepted outgoing edge to the viewed user.
    var isFollowing: Bool
    /// Both accepted edges exist (mutual friends).
    var isMutual: Bool
}

/// Accepted directional follow counts (`user_id` = following, `friend_user_id` = followers).
/// After reciprocal accept edges exist, mutual friends contribute 1 to each side.
struct FollowCounts: Equatable {
    var following: Int
    var followers: Int

    static let zero = FollowCounts(following: 0, followers: 0)
}

/// Model for decoding rows from the `notifications` table.
/// Keys match the Supabase column names (id, user_id, type, title, body, payload, is_read, created_at).
struct NotificationRecord: Decodable, Identifiable {
    let id: UUID
    let user_id: UUID
    let type: String
    let title: String
    let body: String?
    let payload: [String: String]?
    let is_read: Bool
    let created_at: Date
    
    enum CodingKeys: String, CodingKey {
        case id, user_id, type, title, body, payload, is_read, created_at
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        user_id = try container.decode(UUID.self, forKey: .user_id)
        type = try container.decode(String.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        is_read = try container.decode(Bool.self, forKey: .is_read)
        created_at = try container.decode(Date.self, forKey: .created_at)
        
        // jsonb comes back as a generic object — decode as [String: JSONValue] then convert
        if let raw = try container.decodeIfPresent([String: JSONValue].self, forKey: .payload) {
            payload = raw.compactMapValues { $0.stringValue }
        } else {
            payload = nil
        }
    }
}

/// Lightweight JSON value helper for decoding jsonb payloads.
/// We only care about string values for now.
enum JSONValue: Decodable {
    case string(String)
    case other
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            self = .other
        }
    }
    
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

/// Singleton service for managing Supabase authentication and database operations
@MainActor
class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    
    // MARK: - Published Properties
    
    @Published var currentSession: Session?
    @Published var currentUser: User?
    @Published var cachedUsername: String?
    @Published var cachedFriendCount: Int?
    /// Accepted rows where the signed-in user is the requester (`user_id`).
    @Published var cachedFollowingCount: Int?
    /// Accepted rows where the signed-in user is the recipient (`friend_user_id`).
    @Published var cachedFollowersCount: Int?
    /// Bumped whenever friendships change so Profile/Users lists can reload.
    @Published private(set) var friendshipEpoch: Int = 0
    
    // MARK: - Private Properties
    
    private let client: SupabaseClient
    private var hasLoadedSession = false
    private var hasLoadedFriendCountCache = false
    /// Session-scoped caches for remote friend profiles (cleared on sign-out).
    private var friendsListCache: [PublicUserProfile]?
    private var friendshipsCache: [FriendshipRecord]?
    private var visibleWardrobesCache: [UUID: [VisibleWardrobe]] = [:]
    private var visibleWardrobeItemsCache: [String: [VisibleWardrobeItem]] = [:]
    private var visibleWardrobeOutfitsCache: [String: [VisibleWardrobeOutfit]] = [:]
    private var visibleOutfitSuggestionsCache: [String: [VisibleOutfitSuggestion]] = [:]
    private var viewedUserFriendCountCache: [UUID: Int] = [:]
    private var viewedUserFollowCountsCache: [UUID: FollowCounts] = [:]
    private var viewedUserIsFriendCache: [UUID: Bool] = [:]
    private var viewedUserFriendshipDetailsCache: [UUID: ViewedUserFriendshipDetails] = [:]
    private var redressWardrobesCache: [UUID: [VisibleWardrobe]] = [:]
    private var redressWardrobeItemsCache: [String: [VisibleWardrobeItem]] = [:]
    /// Cold-start session restore; created on first `awaitSessionRestoration()` so `self` is fully initialized.
    private lazy var sessionRestorationTask: Task<Void, Never> = {
        Task { await self.loadSession() }
    }()
    
    // MARK: - Initialization
    
    private init() {
        // Validate configuration
        do {
            try SupabaseConfig.validate()
        } catch {
            print("⚠️ Supabase configuration error: \(error.localizedDescription)")
        }
        
        // Initialize Supabase client
        guard let url = URL(string: SupabaseConfig.supabaseURL) else {
            fatalError("Invalid Supabase URL")
        }
        
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: SupabaseConfig.supabaseAnonKey
        )
    }
    
    /// Await until the initial stored-credentials session restore attempt has finished (signed in or not).
    func awaitSessionRestoration() async {
        await sessionRestorationTask.value
    }
    
    // MARK: - Authentication Methods
    
    /// Signs in with email and password
    func signIn(email: String, password: String) async throws {
        // response IS the Session object
        let session = try await client.auth.signIn(email: email, password: password)
        
        // No need to check 'response.session'
        self.currentSession = session
        self.currentUser = session.user
        
        // Ensure profile exists after successful sign in
        await ensureUserProfileExists(userId: session.user.id)
        
        // Load cached friend count from Core Data (and seed from server if missing)
        await loadFriendCountCacheForCurrentUserIfNeeded(seedFromServerIfMissing: true)
        
        // Force a username refresh after sign-in (don't rely on cache check)
        _ = try? await getUsername(forceRefresh: true)
        
        print("✅ User signed in: \(session.user.email ?? "unknown")")
    }
    
    /// Shown in `RegisterView` when Supabase Auth rejects a duplicate email.
    static let emailAlreadyInUseMessage = "Email already in use"

    /// Registers a new user with email and password.
    @discardableResult
    func register(email: String, password: String) async throws -> Session? {
        do {
            let response = try await client.auth.signUp(email: email, password: password)
            guard let session = response.session else {
                print("✅ User registered. Email confirmation required for: \(email)")
                return nil
            }
            self.currentSession = session
            self.currentUser = session.user

            await ensureUserProfileExists(userId: session.user.id)
            await loadFriendCountCacheForCurrentUserIfNeeded(seedFromServerIfMissing: true)
            _ = try? await getUsername(forceRefresh: true)

            print("✅ User registered and signed in: \(session.user.email ?? "unknown")")
            return session
        } catch {
            if Self.isEmailAlreadyRegistered(error) {
                throw Self.emailAlreadyRegisteredError()
            }
            throw error
        }
    }

    /// Maps registration failures to user-facing copy (duplicate email → `emailAlreadyInUseMessage`).
    static func registerErrorMessage(for error: Error) -> String {
        if isEmailAlreadyRegistered(error) {
            return emailAlreadyInUseMessage
        }
        return error.localizedDescription
    }

    private static func emailAlreadyRegisteredError() -> NSError {
        NSError(
            domain: "SupabaseService",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: emailAlreadyInUseMessage]
        )
    }

    private static func isEmailAlreadyRegistered(_ error: Error) -> Bool {
        if let authError = error as? AuthError {
            switch authError {
            case let .api(_, errorCode, _, _):
                if errorCode == .emailExists
                    || errorCode == .userAlreadyExists
                    || errorCode == .identityAlreadyExists {
                    return true
                }
            default:
                break
            }
            if isDuplicateEmailRegistrationText(authError.message) {
                return true
            }
        }

        if let nsError = error as NSError?, nsError.domain == "SupabaseService", nsError.code == -3 {
            return true
        }

        return isDuplicateEmailRegistrationText(error.localizedDescription)
    }

    private static func isDuplicateEmailRegistrationText(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("user already registered")
            || normalized.contains("already been registered")
            || normalized.contains("email address has already been registered")
            || normalized.contains("a user with this email address has already been registered")
            || normalized.contains("email_exists")
            || normalized.contains("user_already_exists")
            || normalized.contains("identity_already_exists")
    }
    
    /// Signs out the current user
    func signOut() async throws {
        // Get userId before clearing session
        let userId = currentUser?.id.uuidString

        await PushNotificationService.shared.unregisterCurrentDevice()
        
        try await client.auth.signOut()
        self.currentSession = nil
        self.currentUser = nil
        self.cachedUsername = nil
        self.cachedFriendCount = nil
        self.cachedFollowingCount = nil
        self.cachedFollowersCount = nil
        self.hasLoadedSession = false  // Reset to allow re-initialization on next login
        self.hasLoadedFriendCountCache = false
        clearVisibleProfileCaches()
        
        // Clear UserProfile data from Core Data for this user
        if let userId = userId {
            // Get the main context from PersistenceController
            let context = PersistenceController.shared.container.viewContext
            let repository = UserProfileRepository(context: context)
            do {
                try repository.clearUserProfileData(userId: userId)
            } catch {
                print("⚠️ Error clearing user profile data on sign-out: \(error.localizedDescription)")
            }
        }
        
        print("✅ User signed out")
    }

    /// Permanently deletes the signed-in account (server RPC + local Core Data wipe), then signs out.
    /// Requires `delete_my_account` RPC in Supabase — see `SUPABASE_DELETE_MY_ACCOUNT.sql`.
    func deleteAccount() async throws {
        guard let userId = currentUser?.id else {
            throw NSError(
                domain: "SupabaseService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No authenticated user"]
            )
        }

        let context = PersistenceController.shared.container.viewContext

        if AppEnvironment.capabilities.enablesCloudSync {
            try? await deleteProfileAvatar(userId: userId)
        }

        do {
            try await client.rpc("delete_my_account").execute()
        } catch {
            print("❌ delete_my_account RPC failed: \(error.localizedDescription)")
            throw NSError(
                domain: "SupabaseService",
                code: -10,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not delete your account on the server. If this continues, contact redressme@icloud.com."
                ]
            )
        }

        try AccountDeletionService.wipeLocalData(for: userId.uuidString, in: context)

        await PushNotificationService.shared.unregisterCurrentDevice()

        try await client.auth.signOut()
        currentSession = nil
        currentUser = nil
        cachedUsername = nil
        cachedFriendCount = nil
        cachedFollowingCount = nil
        cachedFollowersCount = nil
        hasLoadedSession = false
        hasLoadedFriendCountCache = false
        clearVisibleProfileCaches()

        print("✅ Account deleted and signed out")
    }
    
    /// Sends a password reset email
    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email)
        print("✅ Password reset email sent to: \(email)")
    }
    
    /// Ensures a user profile exists in the database, creating one if it doesn't
    private func ensureUserProfileExists(userId: UUID) async {
        do {
            let now = ISO8601DateFormatter().string(from: Date())
            
            // Use upsert to insert or update if exists
            // This requires a unique constraint on user_id in your Supabase table
            try await client.from("user_profiles")
                .upsert([
                    "user_id": userId.uuidString,
                    "created_at": now,
                    "updated_at": now
                ],
                onConflict: "user_id")
                .execute()
            
            print("✅ Ensured user profile exists for: \(userId.uuidString)")
        } catch {
            print("⚠️ Error ensuring user profile exists: \(error.localizedDescription)")
            // Don't throw - profile creation is not critical
        }
    }
    
    // MARK: - User Search
    
    /// Searches for users by username using a secure RPC function.
    /// Returns only non-sensitive fields (user_id, username, display_name, avatar_url).
    func searchUsers(byUsername query: String) async throws -> [PublicUserProfile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        let response = try await client
            .rpc("search_profiles_by_username", params: ["p_query": trimmed])
            .execute()
        
        struct ProfileRow: Decodable {
            let user_id: UUID
            let username: String
            let display_name: String?
            let avatar_url: String?
        }
        
        let decoder = JSONDecoder()
        let rows = try decoder.decode([ProfileRow].self, from: response.data)
        return rows.map { row in
            PublicUserProfile(
                userId: row.user_id,
                username: row.username,
                displayName: row.display_name,
                avatarUrl: row.avatar_url
            )
        }
    }
    
    /// Fetches accepted friends for the current user (public profile fields only).
    /// Requires the `get_friends()` RPC to be installed in Supabase.
    func fetchFriends(forceRefresh: Bool = false) async throws -> [PublicUserProfile] {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }

        if !forceRefresh, let friendsListCache {
            return friendsListCache
        }
        
        let response = try await client
            .rpc("get_friends")
            .execute()
        
        struct FriendRow: Decodable {
            let user_id: UUID
            let username: String
            let display_name: String?
            let avatar_url: String?
        }
        
        let decoder = JSONDecoder()
        let rows = try decoder.decode([FriendRow].self, from: response.data)
        let profiles = rows.map { row in
            PublicUserProfile(
                userId: row.user_id,
                username: row.username,
                displayName: row.display_name,
                avatarUrl: row.avatar_url
            )
        }
        friendsListCache = profiles
        return profiles
    }

    /// Profiles the current user has sent a pending friend request to.
    func fetchOutgoingPendingFriendRequests(forceRefresh: Bool = false) async throws -> [PublicUserProfile] {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }

        let response = try await client
            .rpc("get_outgoing_pending_friend_requests")
            .execute()

        struct PendingRow: Decodable {
            let user_id: UUID
            let username: String
            let display_name: String?
            let avatar_url: String?
        }

        let decoder = JSONDecoder()
        let rows = try decoder.decode([PendingRow].self, from: response.data)
        return rows.map { row in
            PublicUserProfile(
                userId: row.user_id,
                username: row.username,
                displayName: row.display_name,
                avatarUrl: row.avatar_url
            )
        }
    }

    /// Profiles followed by `userId` (`friendships.user_id = userId`).
    func fetchFollowingProfiles(forUserId userId: UUID) async throws -> [PublicUserProfile] {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }

        let response = try await client
            .rpc("get_user_following_profiles", params: ["p_user_id": userId.uuidString])
            .execute()
        return try JSONDecoder().decode([PublicUserProfile].self, from: response.data)
    }

    /// Profiles following `userId` (`friendships.friend_user_id = userId`).
    func fetchFollowerProfiles(forUserId userId: UUID) async throws -> [PublicUserProfile] {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }

        let response = try await client
            .rpc("get_user_follower_profiles", params: ["p_user_id": userId.uuidString])
            .execute()
        return try JSONDecoder().decode([PublicUserProfile].self, from: response.data)
    }

    func cachedFriendsList() -> [PublicUserProfile]? {
        friendsListCache
    }

    func cachedVisibleWardrobes(forUserId userId: UUID) -> [VisibleWardrobe]? {
        visibleWardrobesCache[userId]
    }

    func cachedViewedUserFriendCount(forUserId userId: UUID) -> Int? {
        viewedUserFriendCountCache[userId]
    }

    func cachedViewedUserFollowCounts(forUserId userId: UUID) -> FollowCounts? {
        viewedUserFollowCountsCache[userId]
    }

    func cachedViewedUserIsFriend(forUserId userId: UUID) -> Bool? {
        viewedUserIsFriendCache[userId]
    }

    func storeViewedUserIsFriend(_ isFriend: Bool, forUserId userId: UUID) {
        viewedUserIsFriendCache[userId] = isFriend
    }

    func cachedViewedUserFriendshipDetails(forUserId userId: UUID) -> ViewedUserFriendshipDetails? {
        viewedUserFriendshipDetailsCache[userId]
    }

    func storeViewedUserFriendshipDetails(_ details: ViewedUserFriendshipDetails, forUserId userId: UUID) {
        viewedUserFriendshipDetailsCache[userId] = details
        viewedUserIsFriendCache[userId] = details.isFriend
    }

    func cachedWardrobeGridItems(userId: UUID, wardrobeId: UUID) -> [VisibleWardrobeItem]? {
        visibleWardrobeItemsCache[wardrobeGridCacheKey(userId: userId, wardrobeId: wardrobeId)]
    }

    func cachedWardrobeGridOutfits(userId: UUID, wardrobeId: UUID) -> [VisibleWardrobeOutfit]? {
        visibleWardrobeOutfitsCache[wardrobeGridCacheKey(userId: userId, wardrobeId: wardrobeId)]
    }

    func hasCachedWardrobeGrid(userId: UUID, wardrobeId: UUID) -> Bool {
        let key = wardrobeGridCacheKey(userId: userId, wardrobeId: wardrobeId)
        return visibleWardrobeItemsCache[key] != nil && visibleWardrobeOutfitsCache[key] != nil
    }

    func invalidateFriendshipCaches(affecting otherUserId: UUID) {
        friendsListCache = nil
        friendshipsCache = nil
        viewedUserFriendCountCache[otherUserId] = nil
        viewedUserFollowCountsCache[otherUserId] = nil
        viewedUserIsFriendCache[otherUserId] = nil
        viewedUserFriendshipDetailsCache[otherUserId] = nil
        visibleWardrobesCache[otherUserId] = nil
        redressWardrobesCache[otherUserId] = nil
        let wardrobePrefix = "\(otherUserId.uuidString)-"
        visibleWardrobeItemsCache.keys.filter { $0.hasPrefix(wardrobePrefix) }.forEach {
            visibleWardrobeItemsCache[$0] = nil
        }
        visibleWardrobeOutfitsCache.keys.filter { $0.hasPrefix(wardrobePrefix) }.forEach {
            visibleWardrobeOutfitsCache[$0] = nil
        }
        friendshipEpoch += 1
    }

    /// Clears local friendship list caches and refreshes the signed-in user's follow counts from the server.
    func refreshOwnFriendshipStateFromServer() async {
        friendsListCache = nil
        friendshipsCache = nil
        friendshipEpoch += 1
        await refreshCachedFriendCountFromServer()
    }

    private func refreshCachedFriendCountFromServer() async {
        guard let userId = currentUser?.id.uuidString else { return }
        do {
            let counts = try await fetchFollowCounts()
            applyCachedFollowCounts(counts, persistingTotalForUserId: userId)
        } catch {
            print("⚠️ Failed to refresh follow counts: \(error.localizedDescription)")
        }
    }

    /// Clears cached wardrobe grid items for a user (e.g. after item photo sync).
    func invalidateWardrobeGridItemsCache(forUserId userId: UUID) {
        let prefix = "\(userId.uuidString)-"
        visibleWardrobeItemsCache.keys.filter { $0.hasPrefix(prefix) }.forEach {
            visibleWardrobeItemsCache[$0] = nil
        }
    }

    /// Clears cached outfits/suggestions for a wardrobe grid (e.g. after sending a Redress suggestion).
    func invalidateWardrobeGridOutfitsCache(userId: UUID, wardrobeId: UUID) {
        let key = wardrobeGridCacheKey(userId: userId, wardrobeId: wardrobeId)
        visibleWardrobeOutfitsCache[key] = nil
        visibleOutfitSuggestionsCache[key] = nil
        visibleOutfitSuggestionsCache["recipient-\(wardrobeId.uuidString)"] = nil
    }

    func invalidateWardrobeGridOutfitsCache(forUserId userId: UUID) {
        let prefix = "\(userId.uuidString)-"
        visibleWardrobeOutfitsCache.keys.filter { $0.hasPrefix(prefix) }.forEach {
            visibleWardrobeOutfitsCache[$0] = nil
            visibleOutfitSuggestionsCache[$0] = nil
        }
        visibleOutfitSuggestionsCache.keys.filter { $0.hasPrefix("recipient-") }.forEach {
            visibleOutfitSuggestionsCache[$0] = nil
        }
    }

    private func clearVisibleProfileCaches() {
        friendsListCache = nil
        friendshipsCache = nil
        visibleWardrobesCache = [:]
        visibleWardrobeItemsCache = [:]
        visibleWardrobeOutfitsCache = [:]
        visibleOutfitSuggestionsCache = [:]
        viewedUserFriendCountCache = [:]
        viewedUserFollowCountsCache = [:]
        viewedUserIsFriendCache = [:]
        viewedUserFriendshipDetailsCache = [:]
        redressWardrobesCache = [:]
        redressWardrobeItemsCache = [:]
    }

    private func wardrobeGridCacheKey(userId: UUID, wardrobeId: UUID) -> String {
        "\(userId.uuidString)-\(wardrobeId.uuidString)"
    }

    // MARK: - Redress (relationship-aware wardrobe access for outfit suggestions)

    func fetchRedressWardrobes(forUserId userId: UUID, forceRefresh: Bool = false) async throws -> [VisibleWardrobe] {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        if !forceRefresh, let cached = redressWardrobesCache[userId] {
            return cached
        }
        let response = try await client
            .rpc("get_redress_wardrobes", params: ["p_recipient_id": userId.uuidString])
            .execute()
        let wardrobes = try JSONDecoder().decode([VisibleWardrobe].self, from: response.data)
        redressWardrobesCache[userId] = wardrobes
        return wardrobes
    }

    func fetchRedressWardrobeItems(userId: UUID, wardrobeId: UUID, forceRefresh: Bool = false) async throws -> [VisibleWardrobeItem] {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        let key = redressWardrobeItemsCacheKey(userId: userId, wardrobeId: wardrobeId)
        if !forceRefresh, let cached = redressWardrobeItemsCache[key] {
            return cached
        }
        let response = try await client
            .rpc("get_redress_wardrobe_items", params: [
                "p_recipient_id": userId.uuidString,
                "p_wardrobe_id": wardrobeId.uuidString
            ])
            .execute()
        let items = try JSONDecoder().decode([VisibleWardrobeItem].self, from: response.data)
        redressWardrobeItemsCache[key] = items
        return items
    }

    private func redressWardrobeItemsCacheKey(userId: UUID, wardrobeId: UUID) -> String {
        "redress-\(userId.uuidString)-\(wardrobeId.uuidString)"
    }

    struct CreateOutfitSuggestionPayload {
        let suggestionId: UUID
        let recipientId: UUID
        let proposedName: String?
        let proposedNotes: String?
        let imageURL: String
        let transformationJSON: String
        let itemIds: [UUID]
    }

    static let recipientDuplicateOutfitErrorMessage = "Recipient already has an outfit with these items"

    /// Returns a matching recipient outfit when the proposed item set already exists in their wardrobe.
    func findRecipientDuplicateOutfit(recipientId: UUID, itemIds: [UUID]) async throws -> RecipientDuplicateOutfit? {
        try requireCloudSyncEnabled()
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }

        let itemIdsJSON = String(data: try JSONEncoder().encode(itemIds.map(\.uuidString)), encoding: .utf8) ?? "[]"
        let response = try await client.rpc(
            "find_recipient_duplicate_outfit",
            params: [
                "p_recipient_id": recipientId.uuidString,
                "p_item_ids": itemIdsJSON
            ]
        ).execute()

        let rows = try JSONDecoder().decode([RecipientDuplicateOutfit].self, from: response.data)
        return rows.first
    }

    /// Creates a pending Redress outfit suggestion for another user.
    func createOutfitSuggestion(_ payload: CreateOutfitSuggestionPayload) async throws -> UUID {
        try requireCloudSyncEnabled()
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }

        let itemIdsJSON = String(data: try JSONEncoder().encode(payload.itemIds.map(\.uuidString)), encoding: .utf8) ?? "[]"

        let response = try await client.rpc(
            "create_outfit_suggestion",
            params: [
                "p_suggestion_id": payload.suggestionId.uuidString,
                "p_recipient_id": payload.recipientId.uuidString,
                "p_proposed_name": payload.proposedName ?? "",
                "p_proposed_notes": payload.proposedNotes ?? "",
                "p_image_url": payload.imageURL,
                "p_transformation_json": payload.transformationJSON,
                "p_item_ids": itemIdsJSON
            ]
        ).execute()

        let suggestionId = try JSONDecoder().decode(UUID.self, from: response.data)
        invalidateWardrobeGridOutfitsCache(forUserId: payload.recipientId)
        return suggestionId
    }

    func fetchViewerOutfitSuggestions(
        recipientId: UUID,
        wardrobeId: UUID,
        forceRefresh: Bool = false
    ) async throws -> [VisibleOutfitSuggestion] {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        let key = wardrobeGridCacheKey(userId: recipientId, wardrobeId: wardrobeId)
        if !forceRefresh, let cached = visibleOutfitSuggestionsCache[key] {
            return cached
        }
        let response = try await client.rpc(
            "get_viewer_outfit_suggestions_for_wardrobe",
            params: [
                "p_recipient_id": recipientId.uuidString,
                "p_wardrobe_id": wardrobeId.uuidString
            ]
        ).execute()
        let suggestions = try JSONDecoder().decode([VisibleOutfitSuggestion].self, from: response.data)
        visibleOutfitSuggestionsCache[key] = suggestions
        return suggestions
    }

    func fetchRecipientOutfitSuggestions(
        wardrobeId: UUID,
        forceRefresh: Bool = false
    ) async throws -> [VisibleOutfitSuggestion] {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        let key = "recipient-\(wardrobeId.uuidString)"
        if !forceRefresh, let cached = visibleOutfitSuggestionsCache[key] {
            return cached
        }
        let response = try await client.rpc(
            "get_recipient_outfit_suggestions_for_wardrobe",
            params: ["p_wardrobe_id": wardrobeId.uuidString]
        ).execute()
        let suggestions = try JSONDecoder().decode([VisibleOutfitSuggestion].self, from: response.data)
        visibleOutfitSuggestionsCache[key] = suggestions
        return suggestions
    }

    func fetchOutfitSuggestionDetail(
        suggestionId: UUID,
        recipientId: UUID,
        wardrobeId: UUID
    ) async throws -> VisibleOutfitSuggestionDetail? {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        let response = try await client.rpc(
            "get_outfit_suggestion_detail",
            params: [
                "p_suggestion_id": suggestionId.uuidString,
                "p_recipient_id": recipientId.uuidString,
                "p_wardrobe_id": wardrobeId.uuidString
            ]
        ).execute()
        let rows = try Self.supabaseTimestamptzDecoder().decode([VisibleOutfitSuggestionDetail].self, from: response.data)
        return rows.first
    }

    func fetchOutfitSuggestionImageURL(suggestionId: UUID) async throws -> URL? {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }

        struct Row: Decodable {
            let image_url: String?
        }

        let response = try await client
            .from("outfit_suggestions")
            .select("image_url")
            .eq("id", value: suggestionId.uuidString)
            .single()
            .execute()

        let row = try JSONDecoder().decode(Row.self, from: response.data)
        guard let raw = row.image_url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }

    func fetchOutfitSuggestionForMaterialization(suggestionId: UUID) async throws -> OutfitSuggestionMaterializationRecord {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }

        let response = try await client
            .from("outfit_suggestions")
            .select("id, recipient_user_id, suggester_user_id, status, proposed_name, proposed_notes, image_url, created_at, item_ids, transformation_json")
            .eq("id", value: suggestionId.uuidString)
            .single()
            .execute()

        return try Self.supabaseTimestamptzDecoder().decode(
            OutfitSuggestionMaterializationRecord.self,
            from: response.data
        )
    }

    /// Returns Redress suggestion metadata when `outfitId` matches a suggestion the current user received.
    func fetchOutfitRedressSuggestionContext(suggestionId: UUID) async -> OutfitRedressSuggestionContext? {
        guard currentUser != nil else { return nil }

        struct Row: Decodable {
            let suggestionId: UUID
            let status: String
            let suggesterUserId: UUID?
            let suggesterUsername: String?
            let suggesterDisplayName: String?
            let suggesterAvatarUrl: String?
            let createdAt: Date?

            enum CodingKeys: String, CodingKey {
                case suggestionId = "suggestion_id"
                case status
                case suggesterUserId = "suggester_user_id"
                case suggesterUsername = "suggester_username"
                case suggesterDisplayName = "suggester_display_name"
                case suggesterAvatarUrl = "suggester_avatar_url"
                case createdAt = "created_at"
            }
        }

        do {
            let response = try await client.rpc(
                "get_outfit_redress_suggestion_context",
                params: ["p_suggestion_id": suggestionId.uuidString]
            ).execute()

            let rows = try Self.supabaseTimestamptzDecoder().decode([Row].self, from: response.data)
            guard let row = rows.first else { return nil }

            return OutfitRedressSuggestionContext(
                suggestionId: row.suggestionId,
                status: row.status,
                suggesterUserId: row.suggesterUserId,
                suggesterUsername: row.suggesterUsername,
                suggesterDisplayName: row.suggesterDisplayName,
                suggesterAvatarUrl: row.suggesterAvatarUrl,
                suggestedAt: row.createdAt
            )
        } catch {
            return nil
        }
    }

    // MARK: - Visible public profile (v1: public wardrobes only)

    func fetchVisibleWardrobes(forUserId userId: UUID, forceRefresh: Bool = false) async throws -> [VisibleWardrobe] {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        if !forceRefresh, let cached = visibleWardrobesCache[userId] {
            return cached
        }
        let response = try await client
            .rpc("get_visible_wardrobes", params: ["p_user_id": userId.uuidString])
            .execute()
        let wardrobes = try JSONDecoder().decode([VisibleWardrobe].self, from: response.data)
        visibleWardrobesCache[userId] = wardrobes
        return wardrobes
    }

    func fetchVisibleWardrobeItems(userId: UUID, wardrobeId: UUID, forceRefresh: Bool = false) async throws -> [VisibleWardrobeItem] {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        let key = wardrobeGridCacheKey(userId: userId, wardrobeId: wardrobeId)
        if !forceRefresh, let cached = visibleWardrobeItemsCache[key] {
            return cached
        }
        let response = try await client
            .rpc("get_visible_wardrobe_items", params: [
                "p_user_id": userId.uuidString,
                "p_wardrobe_id": wardrobeId.uuidString
            ])
            .execute()
        let items = try Self.supabaseTimestamptzDecoder().decode([VisibleWardrobeItem].self, from: response.data)
        visibleWardrobeItemsCache[key] = items
        return items
    }

    func fetchVisibleWardrobeOutfits(userId: UUID, wardrobeId: UUID, forceRefresh: Bool = false) async throws -> [VisibleWardrobeOutfit] {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        let key = wardrobeGridCacheKey(userId: userId, wardrobeId: wardrobeId)
        if !forceRefresh, let cached = visibleWardrobeOutfitsCache[key] {
            return cached
        }
        let response = try await client
            .rpc("get_visible_wardrobe_outfits", params: [
                "p_user_id": userId.uuidString,
                "p_wardrobe_id": wardrobeId.uuidString
            ])
            .execute()
        let outfits = try Self.supabaseTimestamptzDecoder().decode([VisibleWardrobeOutfit].self, from: response.data)
        visibleWardrobeOutfitsCache[key] = outfits
        return outfits
    }

    func fetchVisibleItemDetail(userId: UUID, itemId: UUID, wardrobeId: UUID) async throws -> VisibleItemDetail? {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        let response = try await client
            .rpc("get_visible_item_detail", params: [
                "p_user_id": userId.uuidString,
                "p_item_id": itemId.uuidString,
                "p_wardrobe_id": wardrobeId.uuidString
            ])
            .execute()
        let rows = try JSONDecoder().decode([VisibleItemDetail].self, from: response.data)
        return rows.first
    }

    func fetchVisibleOutfitDetail(userId: UUID, outfitId: UUID, wardrobeId: UUID) async throws -> VisibleOutfitDetail? {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        let response = try await client
            .rpc("get_visible_outfit_detail", params: [
                "p_user_id": userId.uuidString,
                "p_outfit_id": outfitId.uuidString,
                "p_wardrobe_id": wardrobeId.uuidString
            ])
            .execute()
        let rows = try Self.supabaseTimestamptzDecoder().decode([VisibleOutfitDetail].self, from: response.data)
        return rows.first
    }

    func fetchRedressOutfitDetail(recipientId: UUID, outfitId: UUID, wardrobeId: UUID) async throws -> VisibleOutfitDetail? {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        let response = try await client
            .rpc("get_redress_outfit_detail", params: [
                "p_recipient_id": recipientId.uuidString,
                "p_outfit_id": outfitId.uuidString,
                "p_wardrobe_id": wardrobeId.uuidString
            ])
            .execute()
        let rows = try Self.supabaseTimestamptzDecoder().decode([VisibleOutfitDetail].self, from: response.data)
        return rows.first
    }

    // MARK: - Content likes (item / outfit)

    enum ContentLikeTargetType: String {
        case item
        case outfit
    }

    struct ContentLikeState: Decodable, Equatable {
        let likeCount: Int
        let likedByMe: Bool

        enum CodingKeys: String, CodingKey {
            case likeCount = "like_count"
            case likedByMe = "liked_by_me"
        }
    }

    func fetchContentLikeState(targetType: ContentLikeTargetType, targetId: UUID) async throws -> ContentLikeState {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        let response = try await client
            .rpc(
                "get_content_like_state",
                params: [
                    "p_target_type": targetType.rawValue,
                    "p_target_id": targetId.uuidString
                ]
            )
            .execute()
        let rows = try JSONDecoder().decode([ContentLikeState].self, from: response.data)
        return rows.first ?? ContentLikeState(likeCount: 0, likedByMe: false)
    }

    func toggleContentLike(targetType: ContentLikeTargetType, targetId: UUID) async throws -> ContentLikeState {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        let response = try await client
            .rpc(
                "toggle_content_like",
                params: [
                    "p_target_type": targetType.rawValue,
                    "p_target_id": targetId.uuidString
                ]
            )
            .execute()
        let rows = try JSONDecoder().decode([ContentLikeState].self, from: response.data)
        guard let state = rows.first else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing like state response"])
        }
        return state
    }

    private static func supabaseTimestamptzDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            let isoFormatterWithFraction = ISO8601DateFormatter()
            isoFormatterWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatterWithFraction.date(from: string) {
                return date
            }

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: string) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return decoder
    }

    /// Accepted friend count for any user (distinct people; not following+followers).
    func fetchFriendCount(forUserId userId: UUID, forceRefresh: Bool = false) async throws -> Int {
        let counts = try await fetchFollowCounts(forUserId: userId, forceRefresh: forceRefresh)
        return max(counts.following, counts.followers)
    }

    /// Directional accepted counts for any user (public profile display).
    func fetchFollowCounts(forUserId userId: UUID, forceRefresh: Bool = false) async throws -> FollowCounts {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        if !forceRefresh, let cached = viewedUserFollowCountsCache[userId] {
            return cached
        }
        struct Row: Decodable {
            let following_count: Int
            let followers_count: Int
        }
        let response = try await client
            .rpc("get_user_follow_counts", params: ["p_user_id": userId.uuidString])
            .execute()
        let rows = try JSONDecoder().decode([Row].self, from: response.data)
        let row = rows.first ?? Row(following_count: 0, followers_count: 0)
        let counts = FollowCounts(following: row.following_count, followers: row.followers_count)
        viewedUserFollowCountsCache[userId] = counts
        viewedUserFriendCountCache[userId] = max(counts.following, counts.followers)
        return counts
    }

    // MARK: - Notifications
    
    /// Fetches notifications for the current user, ordered by newest first.
    /// Relies on RLS to ensure users only see their own notifications.
    func fetchNotifications() async throws -> [NotificationRecord] {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        let response = try await client
            .from("notifications")
            .select("*")
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
        
        let decoder = JSONDecoder()
        // decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            
            // Supabase/Postgres often returns timestamptz with fractional seconds.
            let isoFormatterWithFraction = ISO8601DateFormatter()
            isoFormatterWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatterWithFraction.date(from: string) {
                return date
            }
            
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: string) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return try decoder.decode([NotificationRecord].self, from: response.data)
    }
    
    /// Marks a notification as read by id (sets is_read = true).
    /// RLS on notifications ensures a user can only update their own notifications.
    func markNotificationRead(id: UUID) async throws {
        _ = try await client
            .from("notifications")
            .update(["is_read": true])
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Device tokens (APNs)

    /// Upserts this device’s APNs token for the signed-in user (`SUPABASE_DEVICE_TOKENS.sql`).
    func upsertDeviceToken(token: String, environment: String) async throws {
        try requireCloudSyncEnabled()
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        _ = try await client.rpc(
            "upsert_device_token",
            params: [
                "p_token": token,
                "p_platform": "ios",
                "p_environment": environment
            ]
        ).execute()
    }

    /// Removes a device token (call while still authenticated, e.g. before sign-out).
    func deleteDeviceToken(_ token: String) async throws {
        guard currentUser != nil else { return }
        _ = try await client
            .from("device_tokens")
            .delete()
            .eq("token", value: token)
            .execute()
    }

    /// Recipient accepts or declines a pending Redress outfit suggestion.
    func respondToOutfitSuggestion(suggestionId: UUID, accept: Bool) async throws {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        _ = try await client.rpc(
            "respond_to_outfit_suggestion",
            params: [
                "p_suggestion_id": suggestionId.uuidString,
                "p_accept": accept ? "true" : "false"
            ]
        ).execute()
        if let userId = currentUser?.id {
            invalidateWardrobeGridOutfitsCache(forUserId: userId)
        }
    }

    /// Submitter withdraws their pending Redress outfit suggestion.
    func withdrawRedressSuggestion(suggestionId: UUID, recipientId: UUID) async throws {
        try requireCloudSyncEnabled()
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        _ = try await client.rpc(
            "withdraw_redress",
            params: ["p_suggestion_id": suggestionId.uuidString]
        ).execute()
        invalidateWardrobeGridOutfitsCache(forUserId: recipientId)
    }

    // MARK: - Friendships
    
    /// Sends a friend request from the current user to the specified user.
    /// Creates a row in friendships (status = 'pending').
    /// Notifications are created by a Postgres trigger on the friendships table.
    func sendFriendRequest(toUserId: UUID, toUsername: String?, toDisplayName: String?) async throws {
        guard let currentUser = currentUser else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }

        do {
            // Create friendship row; trigger will handle notifications.
            _ = try await client
                .from("friendships")
                .insert([
                    "user_id": currentUser.id.uuidString,
                    "friend_user_id": toUserId.uuidString,
                    "status": "pending"
                ])
                .execute()
        } catch {
            // If friendship already exists (unique constraint), treat as success.
            let message = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String
                ?? error.localizedDescription
            if message.lowercased().contains("duplicate key")
                || message.contains("idx_friendships_user_friend_unique") {
                print("ℹ️ Friend request already exists for user_id=\(currentUser.id.uuidString), friend_user_id=\(toUserId.uuidString)")
                return
            }
            throw error
        }
    }
    
    /// Responds to a friend request (accept or decline).
    /// Invalidates friendship caches and refreshes friend count on accept.
    func respondToFriendRequest(friendshipId: UUID, accept: Bool) async throws {
        guard let currentUser = currentUser else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }

        struct FriendshipIdRow: Decodable {
            let id: UUID
            let user_id: UUID
            let friend_user_id: UUID
            let status: String
        }

        let existingResponse = try await client
            .from("friendships")
            .select("id, user_id, friend_user_id, status")
            .eq("id", value: friendshipId.uuidString)
            .single()
            .execute()
        let existing = try JSONDecoder().decode(FriendshipIdRow.self, from: existingResponse.data)
        let otherUserId = existing.user_id == currentUser.id
            ? existing.friend_user_id
            : existing.user_id

        let newStatus = accept ? "accepted" : "declined"
        _ = try await client
            .from("friendships")
            .update(["status": newStatus])
            .eq("id", value: friendshipId.uuidString)
            .execute()

        invalidateFriendshipCaches(affecting: otherUserId)

        if accept {
            await refreshCachedFriendCountFromServer()
        }
    }
    
    /// Cancels (un-sends) a pending friend request from the current user to the target user.
    /// Deletes the pending friendships row. RLS enforces the current user is the requester.
    func cancelFriendRequest(toUserId: UUID) async throws {
        guard let currentUser = currentUser else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        _ = try await client
            .from("friendships")
            .delete()
            .eq("user_id", value: currentUser.id.uuidString)
            .eq("friend_user_id", value: toUserId.uuidString)
            .eq("status", value: "pending")
            .execute()
    }
    
    /// Fetches all friendship rows involving the current user (either side).
    /// Uses RLS on friendships to restrict access.
    func fetchFriendshipsForCurrentUser(forceRefresh: Bool = false) async throws -> [FriendshipRecord] {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }

        if !forceRefresh, let friendshipsCache {
            return friendshipsCache
        }
        
        // RLS limits this to rows where current user is user_id OR friend_user_id.
        let response = try await client
            .from("friendships")
            .select("id, user_id, friend_user_id, status, created_at, updated_at")
            .execute()
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            
            let isoFormatterWithFraction = ISO8601DateFormatter()
            isoFormatterWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatterWithFraction.date(from: string) {
                return date
            }
            
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: string) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        let friendships = try decoder.decode([FriendshipRecord].self, from: response.data)
        friendshipsCache = friendships
        return friendships
    }
    
    /// Unfriends (deletes) an accepted friendship between the current user and the other user.
    /// Since the row could have been created in either direction, we delete both possible directions.
    func unfriend(userId otherUserId: UUID) async throws {
        guard let currentUser = currentUser else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Direction 1: current → other
        _ = try await client
            .from("friendships")
            .delete()
            .eq("user_id", value: currentUser.id.uuidString)
            .eq("friend_user_id", value: otherUserId.uuidString)
            .eq("status", value: "accepted")
            .execute()
        
        // Direction 2: other → current
        _ = try await client
            .from("friendships")
            .delete()
            .eq("user_id", value: otherUserId.uuidString)
            .eq("friend_user_id", value: currentUser.id.uuidString)
            .eq("status", value: "accepted")
            .execute()

        invalidateFriendshipCaches(affecting: otherUserId)
    }
    
    /// Returns accepted directional follow counts for the current user.
    /// Following = requester (`user_id`); followers = recipient (`friend_user_id`).
    func fetchFollowCounts() async throws -> FollowCounts {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "SupabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }

        struct FriendshipRowId: Decodable { let id: UUID }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let asRequester = try await client
            .from("friendships")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .eq("status", value: "accepted")
            .execute()

        let asRecipient = try await client
            .from("friendships")
            .select("id")
            .eq("friend_user_id", value: userId.uuidString)
            .eq("status", value: "accepted")
            .execute()

        let requesterRows = try decoder.decode([FriendshipRowId].self, from: asRequester.data)
        let recipientRows = try decoder.decode([FriendshipRowId].self, from: asRecipient.data)

        return FollowCounts(following: requesterRows.count, followers: recipientRows.count)
    }

    /// Returns the number of accepted friends for the current user (unique people).
    func fetchFriendCount() async throws -> Int {
        let counts = try await fetchFollowCounts()
        return max(counts.following, counts.followers)
    }

    /// Loads the existing session if available
    func loadSession() async {
        guard !hasLoadedSession else { return }
        hasLoadedSession = true
        
        do {
            let session = try await client.auth.session
            self.currentSession = session
            self.currentUser = session.user
            
            // Ensure profile exists when restoring session
            await ensureUserProfileExists(userId: session.user.id)
            
            // Load cached friend count from Core Data (and seed from server if missing)
            await loadFriendCountCacheForCurrentUserIfNeeded(seedFromServerIfMissing: true)
            
            // Force a username refresh when restoring session (don't rely on cache)
            _ = try? await getUsername(forceRefresh: true)
            
            print("✅ Supabase session loaded for user: \(session.user.email ?? "unknown")")
        } catch {
            print("⚠️ No existing Supabase session: \(error.localizedDescription)")
            self.currentSession = nil
            self.currentUser = nil
            self.cachedUsername = nil
            self.cachedFriendCount = nil
            self.cachedFollowingCount = nil
            self.cachedFollowersCount = nil
            self.hasLoadedFriendCountCache = false
        }
    }

    // MARK: - Friend Count Cache
    
    /// Loads cached friend count from Core Data into memory. Optionally seeds from server
    /// if Core Data doesn't have a value yet.
    func loadFriendCountCacheForCurrentUserIfNeeded(seedFromServerIfMissing: Bool) async {
        guard !hasLoadedFriendCountCache else { return }
        hasLoadedFriendCountCache = true
        
        guard let userId = currentUser?.id.uuidString else {
            cachedFriendCount = nil
            cachedFollowingCount = nil
            cachedFollowersCount = nil
            return
        }
        
        let context = PersistenceController.shared.container.viewContext
        let repo = UserProfileRepository(context: context)
        
        if let stored = repo.getFriendCount() {
            cachedFriendCount = stored
            // Directional split requires a server fetch; keep totals until refresh.
        }
        
        guard seedFromServerIfMissing else {
            if cachedFriendCount == nil {
                cachedFriendCount = nil
                cachedFollowingCount = nil
                cachedFollowersCount = nil
            }
            return
        }
        
        do {
            let counts = try await fetchFollowCounts()
            applyCachedFollowCounts(counts, persistingTotalForUserId: userId)
        } catch {
            // Keep stability: if we can't fetch, leave nil (UI can show 0 or placeholder)
            print("⚠️ Failed to seed follow counts from server: \(error.localizedDescription)")
        }
    }

    private func applyCachedFollowCounts(_ counts: FollowCounts, persistingTotalForUserId userId: String) {
        cachedFollowingCount = counts.following
        cachedFollowersCount = counts.followers
        // Unique friends under reciprocal mutual edges equals either side (not following+followers).
        // max covers pre-backfill one-edge friendships where only one side is populated.
        cachedFriendCount = max(counts.following, counts.followers)
        let context = PersistenceController.shared.container.viewContext
        let repo = UserProfileRepository(context: context)
        try? repo.updateFriendCount(cachedFriendCount ?? 0, userId: userId)
    }
    
    /// Applies a delta (+1 / -1) to the cached friend count and persists it.
    /// If no cached value exists yet, this will treat it as 0 and still persist.
    /// Prefer `refreshOwnFriendshipStateFromServer()` when directional counts matter.
    func applyFriendCountDelta(_ delta: Int) {
        guard let userId = currentUser?.id.uuidString else { return }
        
        let newValue = max(0, (cachedFriendCount ?? 0) + delta)
        cachedFriendCount = newValue
        
        let context = PersistenceController.shared.container.viewContext
        let repo = UserProfileRepository(context: context)
        try? repo.updateFriendCount(newValue, userId: userId)
    }
    
    /// Refreshes the current session
    func refreshSession() async throws {
        let session = try await client.auth.refreshSession()
        // refreshSession() returns Session directly, not AuthResponse
        self.currentSession = session
        self.currentUser = session.user
        print("✅ Supabase session refreshed")
    }

    /// Returns a session with a non-expired access token.
    /// Prefer this over `currentSession` for outbound auth (e.g. R2 Worker), which may hold a stale JWT.
    /// Uses Auth's live `session` getter (auto-refreshes when expired) and syncs published state.
    func freshSession() async throws -> Session {
        let session = try await client.auth.session
        self.currentSession = session
        self.currentUser = session.user
        return session
    }
    
    // MARK: - Account Management
    
    /// Updates the user's email address
    /// Requires email confirmation - user will receive verification email
    func updateEmail(newEmail: String) async throws {
        guard currentUser != nil else {
            throw NSError(domain: "SupabaseService", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        try await client.auth.update(user: UserAttributes(email: newEmail))
        try await refreshSession()
        print("✅ Email update initiated. Verification email sent to: \(newEmail)")
    }
    
    /// Updates the user's password
    /// Requires the current password for security
    func updatePassword(currentPassword: String, newPassword: String) async throws {
        guard let email = currentUser?.email else {
            throw NSError(domain: "SupabaseService", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "No email found for current user"])
        }
        
        // Verify current password by attempting to sign in
        do {
            _ = try await client.auth.signIn(email: email, password: currentPassword)
        } catch {
            throw NSError(domain: "SupabaseService", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "Current password is incorrect"])
        }
        
        // Update to new password
        try await client.auth.update(user: UserAttributes(password: newPassword))
        print("✅ Password updated successfully")
    }
    
    /// Updates the user's username in user_profiles table
    /// - Parameter username: The new username (3-30 characters, alphanumeric and underscores only)
    func updateUsername(_ username: String) async throws {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "SupabaseService", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Validate username
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else {
            throw NSError(domain: "SupabaseService", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "Username cannot be empty"])
        }
        
        guard trimmedUsername.count >= 3, trimmedUsername.count <= 30 else {
            throw NSError(domain: "SupabaseService", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "Username must be 3-30 characters"])
        }
        
        // Validate username format (alphanumeric and underscores only)
        let usernameRegex = "^[a-zA-Z0-9_]+$"
        guard trimmedUsername.range(of: usernameRegex, options: .regularExpression) != nil else {
            throw NSError(domain: "SupabaseService", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "Username can only contain letters, numbers, and underscores"])
        }
        
        let now = ISO8601DateFormatter().string(from: Date())
        
        do {
            try await client.from("user_profiles")
                .update([
                    "username": trimmedUsername,
                    "updated_at": now
                ])
                .eq("user_id", value: userId.uuidString)
                .execute()
            
            // Update cached username
            self.cachedUsername = trimmedUsername
            
            // Sync to Core Data (via SyncService) - await to ensure it completes
            await SyncService.shared.syncUsernameToCoreData(trimmedUsername)
            
            print("✅ Username updated to: \(trimmedUsername)")
        } catch {
            // Check if error is due to unique constraint violation (message may be in userInfo or localizedDescription)
            let message = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String
                ?? error.localizedDescription
            if message.lowercased().contains("unique") || message.lowercased().contains("duplicate") || message.contains("user_profiles_username_key") {
                throw NSError(domain: "SupabaseService", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Username is already taken"])
            }
            throw error
        }
    }
    
    /// Updates the user's display name in user_profiles table
    /// - Parameter displayName: The new display name
    func updateDisplayName(_ displayName: String) async throws {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "SupabaseService", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Trim whitespace
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let now = ISO8601DateFormatter().string(from: Date())
        
        do {
            try await client.from("user_profiles")
                .update([
                    "display_name": trimmedDisplayName.isEmpty ? nil : trimmedDisplayName,
                    "updated_at": now
                ])
                .eq("user_id", value: userId.uuidString)
                .execute()
            
            // Sync to Core Data (via SyncService) - await to ensure it completes
            await SyncService.shared.syncDisplayNameToCoreData(trimmedDisplayName)
            
            print("✅ Display name updated to: \(trimmedDisplayName.isEmpty ? "(empty)" : trimmedDisplayName)")
        } catch {
            throw error
        }
    }

    /// Persists the profile avatar public URL (e.g. R2 CDN) on `user_profiles`, then syncs Core Data.
    func updateProfileAvatarURL(_ url: String?) async throws {
        try requireCloudSyncEnabled()
        guard let userId = currentUser?.id else {
            throw NSError(domain: "SupabaseService", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }

        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = (trimmed?.isEmpty == false) ? trimmed : nil
        let now = ISO8601DateFormatter().string(from: Date())

        try await client.from("user_profiles")
            .update([
                "avatar_url": value,
                "updated_at": now
            ])
            .eq("user_id", value: userId.uuidString)
            .execute()

        await SyncService.shared.syncAvatarUrlToCoreData(value)
        // Friends/search UIs may hold profiles with the previous avatar URL string.
        friendsListCache = nil
        print("✅ Profile avatar URL updated")
    }
    
    /// Gets the current user's username from cache or user_profiles
    /// - Parameter forceRefresh: If true, fetches from server even if cached
    /// - Returns: The username if it exists, nil otherwise
    func getUsername(forceRefresh: Bool = false) async throws -> String? {
        guard let userId = currentUser?.id else { return nil }
        
        // Return cached username if available and not forcing refresh
        if !forceRefresh, let cached = cachedUsername {
            return cached
        }
        
        // Fetch from server (display_name + avatar_url + style_tags)
        let response = try await client.from("user_profiles")
            .select("user_id, username, display_name, avatar_url, style_tags")
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        // Decode response
        let decoder = JSONDecoder()
        let data: Data = response.data
        
        // Handle empty response gracefully
        guard !data.isEmpty else {
            print("ℹ️ No user profile found in Supabase (empty response)")
            return nil
        }
        
        // Check if response is empty array
        if let jsonString = String(data: data, encoding: .utf8),
           jsonString.trimmingCharacters(in: .whitespacesAndNewlines) == "[]" {
            print("ℹ️ No user profile found in Supabase (empty array)")
            return nil
        }
        
        let profiles: [SupabaseUserProfile]
        do {
            profiles = try decoder.decode([SupabaseUserProfile].self, from: data)
        } catch {
            print("⚠️ Failed to decode user profile response: \(error)")
            // Try to print the raw response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("⚠️ Raw response: \(jsonString)")
            }
            // Return nil instead of throwing - allows UI to continue
            return nil
        }
        
        // Extract username and display_name from response
        if let profile = profiles.first {
            // Sync username if available
            if let username = profile.username, !username.isEmpty {
                // Update cache
                self.cachedUsername = username
                
                // Sync to Core Data (via SyncService) - await to ensure it completes
                await SyncService.shared.syncUsernameToCoreData(username)
            }
            
            // Sync display_name if available
            if let displayName = profile.display_name, !displayName.isEmpty {
                await SyncService.shared.syncDisplayNameToCoreData(displayName)
            }

            // Only apply a server avatar URL when present — do not clear a locally stored URL
            // when `avatar_url` is null (e.g. migration not applied yet).
            if AppEnvironment.capabilities.enablesCloudSync,
               let trimmedAvatar = profile.avatar_url?.trimmingCharacters(in: .whitespacesAndNewlines),
               !trimmedAvatar.isEmpty {
                await SyncService.shared.syncAvatarUrlToCoreData(trimmedAvatar)
            }

            if let styleTags = profile.style_tags {
                await SyncService.shared.syncStyleTagsToCoreData(styleTags, userId: userId.uuidString)
            }
            
            // Return username if available
            if let username = profile.username, !username.isEmpty {
                return username
            }
        }
        
        // Clear cache if no username found
        self.cachedUsername = nil
        return nil
    }
    
    /// Loads username if not already cached
    private func loadUsernameIfNeeded() async {
        guard isAuthenticated, cachedUsername == nil else { return }
        do {
            _ = try await getUsername(forceRefresh: true)
        } catch {
            print("⚠️ Failed to load username: \(error.localizedDescription)")
        }
    }
    
    /// Forces a refresh of the username from the server
    func refreshUsername() async throws {
        _ = try await getUsername(forceRefresh: true)
    }
    
    /// Checks if a username is available
    /// - Parameter username: The username to check
    /// - Returns: true if username is available, false if already taken
    func isUsernameAvailable(_ username: String) async throws -> Bool {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else { return false }
        
        let response = try await client.from("user_profiles")
            .select("user_id")
            .eq("username", value: trimmedUsername)
            .execute()
        
        // Decode response
        let decoder = JSONDecoder()
        let data: Data = response.data
        let profiles: [UserProfileUserId] = try decoder.decode([UserProfileUserId].self, from: data)
        
        // If response has data, username is taken
        return profiles.isEmpty
    }
    
    /// Gets the current user's complete profile data from user_profiles
    /// - Returns: Dictionary containing profile data, or nil if not found
    func getUserProfile() async throws -> [String: Any]? {
        guard let userId = currentUser?.id else { return nil }
        
        let response = try await client.from("user_profiles")
            .select("*")
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        // Decode response
        let decoder = JSONDecoder()
        let data: Data = response.data
        let profiles: [SupabaseUserProfile] = try decoder.decode([SupabaseUserProfile].self, from: data)
        
        guard let profile = profiles.first else { return nil }
        
        // Convert to dictionary
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(profile),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict
        }
        
        return nil
    }
    
    // MARK: - Photo Storage (via Cloudflare R2)

    private func requireCloudSyncEnabled() throws {
        guard AppEnvironment.capabilities.enablesCloudSync else {
            throw NSError(
                domain: "SupabaseService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Cloud sync is disabled for this build."]
            )
        }
    }
    
    /// Uploads a photo to Cloudflare R2 via Worker and returns the public URL
    /// Each photo (front, back, worn) has a unique photoId, so they won't conflict
    /// - Parameters:
    ///   - imageData: The image data to upload (should be compressed JPEG)
    ///   - itemId: The ID of the item this photo belongs to
    ///   - photoId: The ID of the photo (unique for each photo, including front/back/worn)
    ///   - userId: The ID of the user
    /// - Returns: The public URL of the uploaded photo
    func uploadPhoto(imageData: Data, itemId: UUID, photoId: UUID, userId: UUID) async throws -> String {
        try requireCloudSyncEnabled()
        // Delegate to R2 service
        // Each photo has a unique photoId, so front/back/worn photos are stored separately
        // Path format: userId/itemId/photoId.jpg ensures uniqueness
        return try await CloudflareR2Service.shared.uploadPhoto(
            imageData: imageData,
            itemId: itemId,
            photoId: photoId,
            userId: userId
        )
    }
    
    /// Uploads a thumbnail to Cloudflare R2 via Worker and returns the public URL
    /// - Parameters:
    ///   - imageData: The thumbnail image data to upload (should be compressed JPEG)
    ///   - itemId: The ID of the item this photo belongs to
    ///   - photoId: The ID of the photo
    ///   - userId: The ID of the user
    /// - Returns: The public URL of the uploaded thumbnail
    func uploadThumbnail(imageData: Data, itemId: UUID, photoId: UUID, userId: UUID) async throws -> String {
        try requireCloudSyncEnabled()
        // Delegate to R2 service
        // Thumbnails are stored with _thumb suffix: userId/itemId/photoId_thumb.jpg
        return try await CloudflareR2Service.shared.uploadThumbnail(
            imageData: imageData,
            itemId: itemId,
            photoId: photoId,
            userId: userId
        )
    }
    
    /// Deletes a photo from Cloudflare R2 via Worker
    /// - Parameters:
    ///   - itemId: The ID of the item this photo belongs to
    ///   - photoId: The ID of the photo (unique for each photo type)
    ///   - userId: The ID of the user
    func deletePhoto(itemId: UUID, photoId: UUID, userId: UUID) async throws {
        try requireCloudSyncEnabled()
        // Delegate to R2 service
        // Each photo type (front/back/worn) has its own photoId, so deletion is specific
        try await CloudflareR2Service.shared.deletePhoto(
            itemId: itemId,
            photoId: photoId,
            userId: userId
        )
    }

    /// Uploads an outfit collage image to Cloudflare R2
    /// Path format: userId/outfits/outfitId.jpg
    func uploadOutfitImage(imageData: Data, outfitId: UUID, userId: UUID) async throws -> String {
        try requireCloudSyncEnabled()
        return try await CloudflareR2Service.shared.uploadOutfitImage(
            imageData: imageData,
            outfitId: outfitId,
            userId: userId
        )
    }

    /// Uploads a Redress suggestion collage — path `userId/outfit-suggestions/suggestionId.jpg`
    func uploadOutfitSuggestionImage(imageData: Data, suggestionId: UUID, userId: UUID) async throws -> String {
        try requireCloudSyncEnabled()
        return try await CloudflareR2Service.shared.uploadOutfitSuggestionImage(
            imageData: imageData,
            suggestionId: suggestionId,
            userId: userId
        )
    }

    /// Deletes an outfit collage image from Cloudflare R2
    func deleteOutfitImage(outfitId: UUID, userId: UUID) async throws {
        try requireCloudSyncEnabled()
        try await CloudflareR2Service.shared.deleteOutfitImage(
            outfitId: outfitId,
            userId: userId
        )
    }

    /// Uploads a "worn" outfit photo (user wearing the outfit) to R2 — path `userId/outfits/outfitId_worn.jpg`
    func uploadOutfitWornImage(imageData: Data, outfitId: UUID, userId: UUID) async throws -> String {
        try requireCloudSyncEnabled()
        return try await CloudflareR2Service.shared.uploadOutfitWornImage(
            imageData: imageData,
            outfitId: outfitId,
            userId: userId
        )
    }

    func deleteOutfitWornImage(outfitId: UUID, userId: UUID) async throws {
        try requireCloudSyncEnabled()
        try await CloudflareR2Service.shared.deleteOutfitWornImage(
            outfitId: outfitId,
            userId: userId
        )
    }

    func uploadProfileAvatar(imageData: Data, userId: UUID) async throws -> String {
        try requireCloudSyncEnabled()
        return try await CloudflareR2Service.shared.uploadProfileAvatar(imageData: imageData, userId: userId)
    }

    func deleteProfileAvatar(userId: UUID) async throws {
        try requireCloudSyncEnabled()
        try await CloudflareR2Service.shared.deleteProfileAvatar(userId: userId)
    }
    
    // MARK: - Computed Properties
    
    /// Checks if a user is currently authenticated
    var isAuthenticated: Bool {
        return currentSession != nil && currentUser != nil
    }
    
    /// Exposes the Supabase client for sync operations
    var supabaseClient: SupabaseClient {
        return client
    }
}

// MARK: - Helper Types for Decoding

/// Helper struct for decoding username from user_profiles
private struct UserProfileUsername: Codable {
    let username: String?
}

/// Helper struct for decoding user_id from user_profiles
private struct UserProfileUserId: Codable {
    let user_id: String
}

/// Helper struct for decoding complete user profile from Supabase
private struct SupabaseUserProfile: Codable {
    let user_id: String?
    let username: String?
    let display_name: String?
    let avatar_url: String?
    let style_tags: [String]?
    let created_at: String?
    let updated_at: String?
}
