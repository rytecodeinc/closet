//
//  SupabaseService.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import Foundation
import Supabase

/// Singleton service for managing Supabase authentication and database operations
@MainActor
class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    
    // MARK: - Published Properties
    
    @Published var currentSession: Session?
    @Published var currentUser: User?
    @Published var cachedUsername: String?
    
    // MARK: - Private Properties
    
    private let client: SupabaseClient
    private var hasLoadedSession = false
    
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
        
        // Load existing session on initialization
        Task {
            await loadSession()
        }
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
        
        // Force a username refresh after sign-in (don't rely on cache check)
        _ = try? await getUsername(forceRefresh: true)
        
        print("✅ User signed in: \(session.user.email ?? "unknown")")
    }
    
    /// Signs up a new user with email and password
    @discardableResult
    func signUp(email: String, password: String) async throws -> Session? {
        let response = try await client.auth.signUp(email: email, password: password)
        // response is AuthResponse, which has a session property
        guard let session = response.session else {
            // Email confirmation required
            print("✅ User signed up. Email confirmation required for: \(email)")
            return nil
        }
        self.currentSession = session
        self.currentUser = session.user
        
        // Create user profile after successful sign up
        await ensureUserProfileExists(userId: session.user.id)
        
        // Force a username refresh after sign-up (don't rely on cache check)
        _ = try? await getUsername(forceRefresh: true)
        
        print("✅ User signed up and signed in: \(session.user.email ?? "unknown")")
        return session
    }
    
    /// Signs out the current user
    func signOut() async throws {
        // Get userId before clearing session
        let userId = currentUser?.id.uuidString
        
        try await client.auth.signOut()
        self.currentSession = nil
        self.currentUser = nil
        self.cachedUsername = nil
        self.hasLoadedSession = false  // Reset to allow re-initialization on next login
        
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
            
            // Force a username refresh when restoring session (don't rely on cache)
            _ = try? await getUsername(forceRefresh: true)
            
            print("✅ Supabase session loaded for user: \(session.user.email ?? "unknown")")
        } catch {
            print("⚠️ No existing Supabase session: \(error.localizedDescription)")
            self.currentSession = nil
            self.currentUser = nil
            self.cachedUsername = nil
        }
    }
    
    /// Refreshes the current session
    func refreshSession() async throws {
        let session = try await client.auth.refreshSession()
        // refreshSession() returns Session directly, not AuthResponse
        self.currentSession = session
        self.currentUser = session.user
        print("✅ Supabase session refreshed")
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
            // Check if error is due to unique constraint violation
            if let errorDescription = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String,
               errorDescription.contains("unique") || errorDescription.contains("duplicate") {
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
    
    /// Gets the current user's username from cache or user_profiles
    /// - Parameter forceRefresh: If true, fetches from server even if cached
    /// - Returns: The username if it exists, nil otherwise
    func getUsername(forceRefresh: Bool = false) async throws -> String? {
        guard let userId = currentUser?.id else { return nil }
        
        // Return cached username if available and not forcing refresh
        if !forceRefresh, let cached = cachedUsername {
            return cached
        }
        
        // Fetch from server (include display_name for full profile sync)
        let response = try await client.from("user_profiles")
            .select("user_id, username, display_name")
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
    
    /// Uploads a photo to Cloudflare R2 via Worker and returns the public URL
    /// Each photo (front, back, worn) has a unique photoId, so they won't conflict
    /// - Parameters:
    ///   - imageData: The image data to upload (should be compressed JPEG)
    ///   - itemId: The ID of the item this photo belongs to
    ///   - photoId: The ID of the photo (unique for each photo, including front/back/worn)
    ///   - userId: The ID of the user
    /// - Returns: The public URL of the uploaded photo
    func uploadPhoto(imageData: Data, itemId: UUID, photoId: UUID, userId: UUID) async throws -> String {
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
        return try await CloudflareR2Service.shared.uploadOutfitImage(
            imageData: imageData,
            outfitId: outfitId,
            userId: userId
        )
    }

    /// Deletes an outfit collage image from Cloudflare R2
    func deleteOutfitImage(outfitId: UUID, userId: UUID) async throws {
        try await CloudflareR2Service.shared.deleteOutfitImage(
            outfitId: outfitId,
            userId: userId
        )
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
    let created_at: String?
    let updated_at: String?
}
