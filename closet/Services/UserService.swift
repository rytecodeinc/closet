//
//  UserService.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import Foundation
import SwiftUI

/// Service to manage the current authenticated user ID
/// Now reads from Supabase session instead of UserDefaults for security
@MainActor
class UserService: ObservableObject {
    static let shared = UserService()
    
    private let supabaseService: SupabaseService
    
    private init() {
        self.supabaseService = SupabaseService.shared
    }
    
    /// Gets the current user ID from Supabase session (not UserDefaults)
    var currentUserId: String? {
        return supabaseService.currentUser?.id.uuidString
    }
    
    /// Checks if a user is currently logged in
    var isLoggedIn: Bool {
        return supabaseService.isAuthenticated && currentUserId != nil
    }
}



