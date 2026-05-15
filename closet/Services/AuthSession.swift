//
//  AuthSession.swift
//  closet
//
//  App-wide identity for the signed-in account (UUID + email). Mirrors Supabase auth state
//  so SwiftUI and Core Data scoping can depend on this type instead of `SupabaseService`
//  for “who is logged in?” while leaving API calls on `SupabaseService`.
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

    init(supabase: SupabaseService = .shared) {
        apply(user: supabase.currentUser)

        supabase.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                self?.apply(user: user)
            }
            .store(in: &cancellables)
    }

    private func apply(user: User?) {
        userId = user?.id
        userEmail = user?.email
    }
    
    /// Re-reads identity from Supabase after async session restore so routing matches before Combine delivers.
    func refreshIdentityFromSupabase(_ supabase: SupabaseService = .shared) {
        apply(user: supabase.currentUser)
    }
}
