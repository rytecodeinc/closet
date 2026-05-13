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
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var supabaseService: SupabaseService
    
    /// All active wardrobes; scoped to the signed-in user via computed properties (FetchRequest cannot use dynamic `userId`).
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Wardrobe.createdAt, ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
    ) private var allActiveWardrobes: FetchedResults<Wardrobe>
    
    /// Matches `ItemGridView` tab pattern: segmented control + paged `TabView` for swiping.
    @State private var selectedProfileWardrobeTab: String = "Closet"
    
    @FetchRequest(
        entity: Item.entity(),
        sortDescriptors: []
    ) private var allItems: FetchedResults<Item>
    
    // Fetch user profile to observe changes
    @FetchRequest(
        entity: UserProfile.entity(),
        sortDescriptors: []
    ) private var allUserProfiles: FetchedResults<UserProfile>
    
    @State private var notifications: [NotificationRecord] = []
    @State private var isNotificationsSheetPresented = false
    @State private var isLoadingNotifications = false
    @State private var notificationsError: String?
    @State private var respondingNotificationIds: Set<UUID> = []
    @State private var isFriendsSheetPresented = false
    @State private var friends: [PublicUserProfile] = []
    @State private var isLoadingFriends = false
    @State private var friendsError: String?
    
    @State private var isProfilePhotoActionDialogPresented = false
    @State private var isProfileLibraryPickerPresented = false
    @State private var profilePickerImage: UIImage?
    @State private var profileImagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var isAvatarUploading = false
    @State private var avatarUploadError: String?
    /// Prevents `getUsername` + `refreshAllObjects` on every navigation back (was reloading the avatar / AsyncImage).
    @State private var didBootstrapProfileFromServerForUserId: String?

    @State private var isEditingDisplayName = false
    @State private var editedDisplayName: String = ""
    @State private var isSavingDisplayName = false
    @State private var errorMessage: String?
    @State private var refreshToken = UUID()

    // Filter user profiles by current user (if authenticated)
    private var userProfiles: [UserProfile] {
        guard let userId = supabaseService.currentUser?.id.uuidString else {
            return []
        }
        return allUserProfiles.filter { $0.userId == userId }
    }
    
    // Get profile from fetched results (observes Core Data changes)
    private var userProfile: UserProfile? {
        userProfiles.first
    }

    private var currentUserId: String? {
        supabaseService.currentUser?.id.uuidString
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

    /// Header avatar uses the same remote URL + initials pattern as friend lists.
    private var profileForAvatar: PublicUserProfile? {
        guard let uid = supabaseService.currentUser?.id else { return nil }
        return PublicUserProfile(
            userId: uid,
            username: username ?? supabaseService.cachedUsername ?? "",
            displayName: currentDisplayName,
            avatarUrl: userProfile?.storedProfileAvatarURL
        )
    }

    /// Stable identity for forcing image reload when avatar bytes change at the same URL (single R2 key).
    private var avatarHeaderViewIdentity: String {
        let url = userProfile?.storedProfileAvatarURL ?? ""
        let t = userProfile?.updatedAt?.timeIntervalSinceReferenceDate ?? 0
        return "\(url)#\(t)"
    }
    
    private var friendsCount: Int { supabaseService.cachedFriendCount ?? 0 }
    
    private var unreadNotificationsCount: Int {
        notifications.filter { !$0.is_read }.count
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
    
    private func wardrobeSubtitle(for wardrobe: Wardrobe) -> String {
        let type = wardrobeTypeLabel(for: wardrobe)
        let n = nonDraftItemCount(for: wardrobe)
        let countPart = n == 1 ? "1 item" : "\(n) items"
        return "\(type) · \(countPart)"
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(wardrobe.name ?? "Untitled")
                        Text(wardrobeSubtitle(for: wardrobe))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                }
            }
        }
        .listStyle(.plain)
    }

    private func startEditingDisplayName() {
        editedDisplayName = currentDisplayName ?? ""
        isEditingDisplayName = true
    }

    private func saveDisplayName() async {
        let trimmed = editedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentTrimmed = (currentDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed != currentTrimmed else {
            errorMessage = nil
            isEditingDisplayName = false
            return
        }

        isSavingDisplayName = true
        errorMessage = nil

        do {
            try await supabaseService.updateDisplayName(trimmed)
            // Display name is automatically synced to Core Data by updateDisplayName()
            try? await Task.sleep(nanoseconds: 100_000_000)
            viewContext.refreshAllObjects()
            refreshToken = UUID()
            isEditingDisplayName = false
        } catch {
            errorMessage = error.localizedDescription
            // Keep editing mode on error so user can try again
        }

        isSavingDisplayName = false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Profile Header Section (trailing edit control applies to whole profile info block)
            HStack(alignment: .top, spacing: 16) {
                // Profile Image (R2 URL when set; initials fallback)
                Button {
                    isProfilePhotoActionDialogPresented = true
                } label: {
                    ZStack {
                        if let p = profileForAvatar {
                            PublicUserProfileAvatarView(profile: p, size: 80)
                                // Same CDN URL after replace — bump id when profile updates so AsyncImage refetches bytes.
                                .id(avatarHeaderViewIdentity)
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .foregroundColor(.gray)
                        }
                        if isAvatarUploading {
                            Circle()
                                .fill(.ultraThinMaterial)
                            ProgressView()
                        }
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
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
                        Task { await removeProfileAvatarFromR2AndServer() }
                    }
                    Button("Cancel", role: .cancel) { }
                }

                VStack(alignment: .leading, spacing: 4) {
                    if isEditingDisplayName {
                        TextField("Display Name", text: $editedDisplayName)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.words)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(currentDisplayName ?? "Name")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("Lifestyle | Vintage | Fashion")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    Button {
                        isFriendsSheetPresented = true
                    } label: {
                        Text("\(friendsCount) friends")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(refreshToken)

                if supabaseService.isAuthenticated {
                    Button {
                        if isEditingDisplayName {
                            Task { await saveDisplayName() }
                        } else {
                            startEditingDisplayName()
                        }
                    } label: {
                        if isSavingDisplayName {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        } else if isEditingDisplayName {
                            Image(systemName: "checkmark")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "pencil")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isSavingDisplayName)
                    .accessibilityLabel(isEditingDisplayName ? "Save profile" : "Edit profile")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.vertical, 12)
            
            Picker("", selection: $selectedProfileWardrobeTab) {
                Text("Closet (\(userClosets.count))")
                    .tag("Closet")
                Text("Wishlist (\(userWishlists.count))")
                    .tag("Wishlist")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            
            TabView(selection: $selectedProfileWardrobeTab) {
                profileWardrobePage(wardrobes: userClosets, emptyNoun: "closets")
                    .tag("Closet")
                profileWardrobePage(wardrobes: userWishlists, emptyNoun: "wishlists")
                    .tag("Wishlist")
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
            .navigationTitle(username ?? supabaseService.cachedUsername ?? "@username")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: supabaseService.currentUser?.id) {
                guard supabaseService.isAuthenticated, let uid = supabaseService.currentUser?.id else { return }
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
                // Bell badge: refresh when returning to Profile is OK; profile bootstrap above runs once per user session.
                await loadNotifications()
            }
            .onChange(of: supabaseService.currentUser?.id) { _, newId in
                if newId == nil {
                    didBootstrapProfileFromServerForUserId = nil
                    isEditingDisplayName = false
                    editedDisplayName = ""
                    errorMessage = nil
                }
            }
            .onChange(of: userProfiles.count) { _ in
                // Refresh when user profile changes
                viewContext.refreshAllObjects()
            }
            .onChange(of: userProfile?.displayName) { _ in
                // Refresh when displayName changes
                viewContext.refreshAllObjects()
            }
            .onChange(of: userProfile?.username) { _ in
                // Refresh when username changes
                viewContext.refreshAllObjects()
            }
            .alert("Photo", isPresented: Binding(
                get: { avatarUploadError != nil },
                set: { if !$0 { avatarUploadError = nil } }
            )) {
                Button("OK", role: .cancel) { avatarUploadError = nil }
            } message: {
                Text(avatarUploadError ?? "")
            }
            .sheet(isPresented: $isProfileLibraryPickerPresented) {
                ImagePicker(
                    image: $profilePickerImage,
                    sourceType: $profileImagePickerSource,
                    allowsEditing: true
                ) { image in
                    isProfileLibraryPickerPresented = false
                    guard let image else { return }
                    Task { await uploadProfileAvatarFromLibrary(image) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
              /*  ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        // Action not defined yet
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }*/
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isNotificationsSheetPresented = true
                    } label: {
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
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // Action not defined yet
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isNotificationsSheetPresented) {
                NavigationView {
                    Group {
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
                                VStack(alignment: .leading, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(notification.title)
                                            .font(.headline)
                                        if let body = notification.body, !body.isEmpty {
                                            Text(body)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        Text(notification.created_at, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if notification.type == "friend_request",
                                       notification.is_read == false {
                                        friendRequestActions(for: notification)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                            .listStyle(.plain)
                        }
                    }
                    .navigationTitle("Notifications")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                isNotificationsSheetPresented = false
                            }
                        }
                    }
                    .task {
                        await loadNotifications(markPassiveAsRead: true)
                    }
                }
            }
            .sheet(isPresented: $isFriendsSheetPresented) {
                NavigationView {
                    Group {
                        if isLoadingFriends {
                            ProgressView("Loading friends…")
                        } else if let error = friendsError {
                            Text(error)
                                .foregroundColor(.red)
                                .padding()
                        } else if friends.isEmpty {
                            Text("No friends yet")
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            List(friends) { friend in
                                HStack(spacing: 12) {
                                    PublicUserProfileAvatarView(profile: friend, size: 44)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(friend.username)
                                            .font(.headline)
                                        if let name = friend.displayName, !name.isEmpty {
                                            Text(name)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listStyle(.plain)
                        }
                    }
                    .navigationTitle("Friends")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                isFriendsSheetPresented = false
                            }
                        }
                    }
                    .task {
                        await loadFriends()
                    }
                }
            }
        
    }
}

extension ProfileView {
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
        guard supabaseService.isAuthenticated else {
            notifications = []
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
        } catch {
            await MainActor.run {
                notificationsError = error.localizedDescription
                notifications = []
            }
        }
        
        await MainActor.run {
            isLoadingNotifications = false
        }
    }
    
    private func notificationRequiresAction(_ notification: NotificationRecord) -> Bool {
        notification.type == "friend_request"
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
            if accept {
                supabaseService.applyFriendCountDelta(1)
            }
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
    
    /// Square-crops, flattens to opaque JPEG, then `encodeForR2Upload` enforces the worker’s sub‑5 MB limit.
    /// R2 uses a fixed key per user (`…/profile/avatar.jpg`); this upload **replaces** the previous file — one object, one `avatar_url`.
    private func uploadProfileAvatarFromLibrary(_ image: UIImage) async {
        guard let userId = supabaseService.currentUser?.id else { return }
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
            let url = try await supabaseService.uploadProfileAvatar(imageData: data, userId: userId)
            try await supabaseService.updateProfileAvatarURL(url)
            await MainActor.run {
                viewContext.refreshAllObjects()
            }
        } catch {
            await MainActor.run {
                avatarUploadError = error.localizedDescription
            }
        }
    }

    private func removeProfileAvatarFromR2AndServer() async {
        guard let userId = supabaseService.currentUser?.id else { return }
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
            try? await supabaseService.deleteProfileAvatar(userId: userId)
            try await supabaseService.updateProfileAvatarURL(nil)
            await MainActor.run {
                viewContext.refreshAllObjects()
            }
        } catch {
            await MainActor.run {
                avatarUploadError = error.localizedDescription
            }
        }
    }

    private func loadFriends() async {
        guard supabaseService.isAuthenticated else {
            await MainActor.run { friends = [] }
            return
        }
        
        await MainActor.run {
            isLoadingFriends = true
            friendsError = nil
        }
        
        do {
            let fetched = try await supabaseService.fetchFriends()
            await MainActor.run {
                friends = fetched
                isLoadingFriends = false
            }
        } catch {
            await MainActor.run {
                friendsError = error.localizedDescription
                friends = []
                isLoadingFriends = false
            }
        }
    }
}
