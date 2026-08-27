//
//  AuthSession.swift
//  closet
//
//  App-wide identity for the signed-in account (UUID + email). Mirrors Supabase auth state
//  so SwiftUI and Core Data scoping can depend on this type instead of `SupabaseService`
//  for “who is logged in?” while leaving API calls on `SupabaseService`.
//
//  Identity is also persisted so a logged-in user can open the full app offline (Core Data)
//  without being gated back to AuthView when token refresh cannot reach the network.
//

import Combine
import Foundation
import Supabase

@MainActor
final class AuthSession: ObservableObject {

    /// Supabase `auth.users` id for the current session, when signed in.
    @Published private(set) var userId: UUID?

    /// Primary email from the auth session, when available.
    @Published private(set) var userEmail: String?

    var isAuthenticated: Bool { userId != nil }

    private var cancellables = Set<AnyCancellable>()

    private static let persistedUserIdKey = "AuthSession.persistedUserId"
    private static let persistedUserEmailKey = "AuthSession.persistedUserEmail"

    init(supabase: SupabaseService = .shared) {
        restorePersistedIdentity()
        if let user = supabase.currentUser {
            apply(user: user)
        }

        Publishers.CombineLatest(supabase.$currentUser, supabase.$didFinishSessionRestoration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user, didFinishRestoration in
                guard let self else { return }
                if let user {
                    self.apply(user: user)
                } else if didFinishRestoration {
                    // Real sign-out (or no stored session) — not a transient offline nil.
                    self.clearIdentity()
                }
            }
            .store(in: &cancellables)
    }

    private func apply(user: User) {
        userId = user.id
        userEmail = user.email
        persistIdentity()
    }

    private func clearIdentity() {
        userId = nil
        userEmail = nil
        UserDefaults.standard.removeObject(forKey: Self.persistedUserIdKey)
        UserDefaults.standard.removeObject(forKey: Self.persistedUserEmailKey)
    }

    private func persistIdentity() {
        guard let userId else { return }
        UserDefaults.standard.set(userId.uuidString, forKey: Self.persistedUserIdKey)
        if let userEmail {
            UserDefaults.standard.set(userEmail, forKey: Self.persistedUserEmailKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.persistedUserEmailKey)
        }
    }

    private func restorePersistedIdentity() {
        guard let idString = UserDefaults.standard.string(forKey: Self.persistedUserIdKey),
              let id = UUID(uuidString: idString) else {
            return
        }
        userId = id
        userEmail = UserDefaults.standard.string(forKey: Self.persistedUserEmailKey)
    }

    /// Re-reads identity from Supabase after async session restore so routing matches before Combine delivers.
    func refreshIdentityFromSupabase(_ supabase: SupabaseService = .shared) {
        if let user = supabase.currentUser {
            apply(user: user)
        } else if let localUser = supabase.supabaseClient.auth.currentSession?.user {
            apply(user: localUser)
        }
        // else keep persisted identity for offline Core Data use
    }
}
