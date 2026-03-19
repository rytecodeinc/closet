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
    @State private var friendCount: Int = 0
    @State private var isFriendsSheetPresented = false
    @State private var friends: [PublicUserProfile] = []
    @State private var isLoadingFriends = false
    @State private var friendsError: String?
    
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
    
    // MARK: - Helper Functions
    
    private func itemsForWardrobeType(_ wardrobeType: String) -> [Item] {
        // Filter items that belong to wardrobes of the specified type, excluding drafts
        // Use a dictionary keyed by item ID to ensure each item is only counted once
        var uniqueItems: [UUID: Item] = [:]
        
        for item in allItems {
            // Skip drafts
            guard !item.isDraft else { continue }
            
            guard let wardrobes = item.wardrobes as? Set<Wardrobe>,
                  wardrobes.contains(where: { $0.type == wardrobeType }) else {
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
    
    private var displayName: String? {
        userProfile?.displayName
    }
    
    private var friendsCount: Int { friendCount }
    
    private var unreadNotificationsCount: Int {
        notifications.filter { !$0.is_read }.count
    }

    var body: some View {
        List {
                // Profile Header Section
                HStack(spacing: 16) {
                    // Profile Image
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.gray)
                        .clipShape(Circle())
                    
                    // Name Info
                    VStack(alignment: .leading, spacing: 4) {
                        // Display Name (show displayName if available, otherwise show placeholder)
                        // Don't fallback to username here to avoid showing username twice
                        Text(displayName ?? "Name")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        // Description
                        Text("Lifestyle | Vintage | Fashion")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        // Friends count (e.g., "123 friends")
                        Button {
                            isFriendsSheetPresented = true
                        } label: {
                            Text("\(friendsCount) friends")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                /*
                // Closet Value Row
                HStack {
                    Text("Closet")
                        .foregroundColor(.primary)
                    Spacer()
                    Text(formattedTotalValue)
                        .foregroundColor(.gray)
                }
                
                // Wishlist Value Row
                HStack {
                    Text("Wishlist")
                        .foregroundColor(.primary)
                    Spacer()
                    Text(formattedWishlistValue)
                        .foregroundColor(.gray)
                }
                
                // Share links
                HStack {
                    Text("Share Links")
                }
                
                // Check Photo Sizes (Debug)
                Button {
                    checkPhotoSizes(context: viewContext)
                } label: {
                    HStack {
                        Image(systemName: "chart.bar.doc.horizontal")
                        Text("Check Photo Sizes")
                    }
                    .foregroundColor(.blue)
                }
                
                // Vacuum Database (Reclaim Space)
                Button {
                    vacuumCoreData(context: viewContext)
                } label: {
                    HStack {
                        Image(systemName: "trash.circle")
                        Text("Reclaim Database Space")
                    }
                    .foregroundColor(.orange)
                }*/
            }
            .listStyle(.plain)
            .navigationTitle(username ?? supabaseService.cachedUsername ?? "@username")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Load username and displayName from Supabase if not in Core Data and authenticated
                if supabaseService.isAuthenticated {
                    // Load username if needed
                    if username == nil && supabaseService.cachedUsername == nil {
                        do {
                            _ = try await supabaseService.getUsername()
                            // Refresh after loading
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                            viewContext.refreshAllObjects()
                        } catch {
                            print("⚠️ Error loading username in ProfileView: \(error.localizedDescription)")
                        }
                    }
                    
                    // Load displayName if not in Core Data
                    if displayName == nil {
                        do {
                            // getUsername() also loads displayName and syncs it to Core Data
                            _ = try await supabaseService.getUsername()
                            // Refresh after loading
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                            viewContext.refreshAllObjects()
                        } catch {
                            print("⚠️ Error loading display name in ProfileView: \(error.localizedDescription)")
                        }
                    }
                }
            }
            .task(id: supabaseService.currentUser?.id) {
                // Preload notifications so the bell badge shows without opening the sheet
                await loadNotifications()
                await loadFriendCount()
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
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(friend.username)
                                        .font(.headline)
                                    if let name = friend.displayName, !name.isEmpty {
                                        Text(name)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
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
    
    private func loadFriendCount() async {
        guard supabaseService.isAuthenticated else {
            await MainActor.run { friendCount = 0 }
            return
        }
        
        do {
            let count = try await supabaseService.fetchFriendCount()
            await MainActor.run { friendCount = count }
        } catch {
            // Keep UI resilient; default to 0 if fetch fails
            await MainActor.run { friendCount = 0 }
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
