//
//  SyncEngine+Profile.swift
//  closet
//

import CoreData
import Foundation

extension SyncEngine {

    // MARK: - Profile download (Supabase → viewContext)

    func syncUsernameToCoreData(_ username: String, userId: String?, usernameChangedAt: Date? = nil) async {
        guard let context = viewContext else {
            print("⚠️ No context available for username sync")
            return
        }
        await MainActor.run {
            let repository = UserProfileRepository(context: context)
            do {
                try repository.updateUsername(
                    username,
                    userId: userId,
                    usernameChangedAt: usernameChangedAt,
                    enforceCooldown: false
                )
            } catch {
                print("⚠️ Failed to sync username to Core Data: \(error.localizedDescription)")
            }
        }
    }

    func syncDisplayNameToCoreData(_ displayName: String, userId: String?) async {
        guard let context = viewContext else {
            print("⚠️ No context available for display name sync")
            return
        }
        await MainActor.run {
            let repository = UserProfileRepository(context: context)
            do {
                try repository.updateDisplayName(displayName, userId: userId)
            } catch {
                print("⚠️ Failed to sync display name to Core Data: \(error.localizedDescription)")
            }
        }
    }

    func syncAvatarUrlToCoreData(_ avatarUrl: String?, userId: String?) async {
        guard let context = viewContext else {
            print("⚠️ No context available for avatar URL sync")
            return
        }
        await MainActor.run {
            let repository = UserProfileRepository(context: context)
            do {
                try repository.updateAvatarUrl(avatarUrl, userId: userId, syncToCloud: false)
            } catch {
                print("⚠️ Failed to sync avatar URL to Core Data: \(error.localizedDescription)")
            }
        }
    }

    func syncStyleTagsToCoreData(_ styleTags: [String], userId: String?) async {
        guard let context = viewContext else {
            print("⚠️ No context available for style tags sync")
            return
        }
        await MainActor.run {
            let repository = UserProfileRepository(context: context)
            do {
                let tags = ProfileStyleTag.ordered(from: styleTags)
                try repository.updateStyleTags(tags, userId: userId)
            } catch {
                print("⚠️ Failed to sync style tags to Core Data: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Profile upload (viewContext → Supabase)

    func syncUserProfile(objectID: NSManagedObjectID, userId: UUID) async throws {
        guard let viewContext else {
            throw SyncError.noContext
        }

        let profileData = try await MainActor.run { () throws -> SyncUserProfileData? in
            guard let profile = try viewContext.existingObject(with: objectID) as? UserProfile else {
                return nil
            }
            let weightKg = profile.weightKg
            let hasWeight = weightKg > 0 && weightKg.isFinite && !weightKg.isNaN
            let hasWeightUnit = profile.weightUnit != nil && !profile.weightUnit!.isEmpty
            return SyncUserProfileData(
                userId: userId.uuidString,
                weightKg: hasWeight && hasWeightUnit ? weightKg : nil,
                weightUnit: hasWeightUnit ? profile.weightUnit : nil,
                username: (profile.username?.isEmpty == false) ? profile.username : nil,
                displayName: (profile.displayName?.isEmpty == false) ? profile.displayName : nil,
                styleTags: {
                    let tags = profile.profileStyleTags.map(\.rawValue)
                    return tags.isEmpty ? nil : tags
                }(),
                updatedAt: profile.updatedAt?.ISO8601String
            )
        }
        guard let profileData else { return }

        let hasData = profileData.weightKg != nil ||
            profileData.weightUnit != nil ||
            profileData.username != nil ||
            profileData.displayName != nil ||
            profileData.styleTags != nil
        guard hasData else { return }

        let supabase = await getSupabase()
        try await supabase.supabaseClient.from("user_profiles")
            .upsert(profileData, onConflict: "user_id")
            .execute()

        try await MainActor.run {
            guard let profile = try viewContext.existingObject(with: objectID) as? UserProfile else {
                return
            }
            profile.syncedAt = Date()
            try viewContext.save()
        }
    }

    func syncUserProfileIfNeeded(objectID: NSManagedObjectID, userId: UUID) async throws {
        try await syncUserProfile(objectID: objectID, userId: userId)
    }
}
