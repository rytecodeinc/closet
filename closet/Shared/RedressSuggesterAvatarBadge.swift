//
//  RedressSuggesterAvatarBadge.swift
//  closet
//
//  Suggester avatar overlay for Redress outfit grid cells (photo or initials).
//

import SwiftUI

struct RedressSuggesterAvatarBadge: View {
    let profile: PublicUserProfile
    let size: CGFloat

    var body: some View {
        PublicUserProfileAvatarView(profile: profile, size: size)
            .overlay(Circle().stroke(Color.white, lineWidth: max(1, size * 0.04)))
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
    }
}

extension VisibleOutfitSuggestion {
    var suggesterProfile: PublicUserProfile? {
        guard let userId = suggesterUserId else { return nil }
        let username = suggesterUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !username.isEmpty else { return nil }
        return PublicUserProfile(
            userId: userId,
            username: username,
            displayName: suggesterDisplayName,
            avatarUrl: suggesterAvatarUrl
        )
    }
}

extension VisibleWardrobeOutfit {
    var suggesterProfile: PublicUserProfile? {
        guard let userId = suggesterUserId else { return nil }
        let username = suggesterUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !username.isEmpty else { return nil }
        return PublicUserProfile(
            userId: userId,
            username: username,
            displayName: suggesterDisplayName,
            avatarUrl: suggesterAvatarUrl
        )
    }
}

extension Outfit {
    var redressSuggesterProfile: PublicUserProfile? {
        guard isRedressOutfit else { return nil }
        let username = redressSuggesterUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !username.isEmpty else { return nil }
        let userId = redressSuggesterUserId ?? UUID()
        return PublicUserProfile(
            userId: userId,
            username: username,
            displayName: redressSuggesterDisplayName,
            avatarUrl: redressSuggesterAvatarUrl
        )
    }
}
