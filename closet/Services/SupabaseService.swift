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
        
        UserService.shared.setUserId(session.user.id.uuidString)
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
        UserService.shared.setUserId(session.user.id.uuidString)
        
        // Create user profile after successful sign up
        await ensureUserProfileExists(userId: session.user.id)
        
        print("✅ User signed up and signed in: \(session.user.email ?? "unknown")")
        return session
    }
    
    /// Signs out the current user
    func signOut() async throws {
        try await client.auth.signOut()
        self.currentSession = nil
        self.currentUser = nil
        UserService.shared.clearUserId()
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
            try await client.database
                .from("user_profiles")
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
            UserService.shared.setUserId(session.user.id.uuidString)
            
            // Ensure profile exists when restoring session
            await ensureUserProfileExists(userId: session.user.id)
            
            print("✅ Supabase session loaded for user: \(session.user.email ?? "unknown")")
        } catch {
            print("⚠️ No existing Supabase session: \(error.localizedDescription)")
            self.currentSession = nil
            self.currentUser = nil
        }
    }
    
    /// Refreshes the current session
    func refreshSession() async throws {
        let session = try await client.auth.refreshSession()
        // refreshSession() returns Session directly, not AuthResponse
        self.currentSession = session
        self.currentUser = session.user
        UserService.shared.setUserId(session.user.id.uuidString)
        print("✅ Supabase session refreshed")
    }
    
    // MARK: - Computed Properties
    
    /// Checks if a user is currently authenticated
    var isAuthenticated: Bool {
        return currentSession != nil && currentUser != nil
    }
}
