//
//  UserProfileRepository.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import Foundation
import CoreData

class UserProfileRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    /// Gets the existing user profile or creates a new one if none exists.
    /// When `userId` is provided, only matches that account (never reuses another user's row).
    func getOrCreateProfile(userId: String? = nil) -> UserProfile {
        if let userId = userId?.trimmingCharacters(in: .whitespacesAndNewlines), !userId.isEmpty {
            if let existing = fetchProfile(userId: userId) {
                return existing
            }
            return createProfile(userId: userId)
        }

        let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        request.fetchLimit = 1
        do {
            if let existing = try context.fetch(request).first {
                return existing
            }
        } catch {
            print("⚠️ Error fetching user profile: \(error)")
        }
        return createProfile(userId: nil)
    }

    func fetchProfile(userId: String) -> UserProfile? {
        let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// Re-links Core Data to an on-disk TestFlight avatar when the JPEG still exists.
    /// Never runs when cloud sync is enabled — a leftover local JPEG must not overwrite the CDN URL.
    func restoreLocalAvatarIfNeeded(userId: String) throws {
        guard !AppEnvironment.capabilities.enablesCloudSync else { return }
        guard let uuid = UUID(uuidString: userId),
              ProfileAvatarLocalStorage.hasSavedAvatar(userId: uuid) else { return }
        let urlString = ProfileAvatarLocalStorage.canonicalStoredURLString(for: uuid)
        try updateAvatarUrl(urlString, userId: userId, syncToCloud: false)
    }

    private func createProfile(userId: String?) -> UserProfile {
        let profile = UserProfile(context: context)
        profile.id = UUID()
        profile.createdAt = Date()
        profile.updatedAt = Date()
        if let userId, !userId.isEmpty {
            profile.userId = userId
        }
        do {
            try context.save()
        } catch {
            print("⚠️ Error creating user profile: \(error)")
        }
        return profile
    }
    
    /// Updates the user's weight
    /// - Parameters:
    ///   - weightKg: Weight in kilograms
    ///   - unit: Weight unit ("kg" or "lbs")
    ///   - userId: Optional user ID from Supabase session. If nil, will try to get from profile.
    func updateWeight(weightKg: Double, unit: String, userId: String? = nil) throws {
        let profile = getOrCreateProfile(userId: userId)

        let weightUnchanged = abs(profile.weightKg - weightKg) < 1e-9
        let unitSame = (profile.weightUnit ?? "") == unit
        if weightUnchanged && unitSame {
            if let userId = userId, !userId.isEmpty, profile.userId != userId {
                profile.userId = userId
                guard context.hasChanges else { return }
                try context.save()
            }
            return
        }

        profile.weightKg = weightKg
        profile.weightUnit = unit
        profile.updatedAt = Date()

        if let userId = userId, !userId.isEmpty {
            profile.userId = userId
        }

        guard context.hasChanges else { return }
        try context.save()

        SyncService.shared.syncUserProfileIfNeeded(profile)
    }
    
    /// Gets the user's weight, returns nil if not set
    func getWeight() -> (weightKg: Double, unit: String)? {
        let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        request.fetchLimit = 1
        
        do {
            guard let profile = try context.fetch(request).first else {
                return nil
            }
            
            // Check if weightKg exists and is valid
            let weightKg = profile.weightKg
            guard weightKg > 0, weightKg.isFinite && !weightKg.isNaN else {
                return nil
            }
            
            // Check if unit exists
            guard let unit = profile.weightUnit, !unit.isEmpty else {
                return nil
            }
            
            return (weightKg, unit)
        } catch {
            print("⚠️ Error fetching user weight: \(error)")
            return nil
        }
    }
    
    /// Gets the user's weight in kg, returns 0 if not set
    func getWeightKg() -> Double {
        return getWeight()?.weightKg ?? 0
    }
    
    /// Gets the user's weight unit, returns default based on locale if not set
    func getWeightUnit() -> String {
        return getWeight()?.unit ?? (Locale.current.measurementSystem == .metric ? "kg" : "lbs")
    }
    
    /// Updates the user's username
    /// - Parameters:
    ///   - username: The username to set
    ///   - userId: Optional user ID from Supabase session. If nil, will try to get from profile.
    func updateUsername(_ username: String, userId: String? = nil) throws {
        let profile = getOrCreateProfile(userId: userId)
        let next = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = (profile.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if current == next {
            if let userId = userId, !userId.isEmpty, profile.userId != userId {
                profile.userId = userId
                guard context.hasChanges else { return }
                try context.save()
            }
            return
        }

        profile.username = next
        profile.updatedAt = Date()

        if let userId = userId, !userId.isEmpty {
            profile.userId = userId
        }

        guard context.hasChanges else { return }
        try context.save()

        SyncService.shared.syncUserProfileIfNeeded(profile)
    }
    
    /// Updates the user's display name
    /// - Parameters:
    ///   - displayName: The display name to set
    ///   - userId: Optional user ID from Supabase session. If nil, will try to get from profile.
    func updateDisplayName(_ displayName: String, userId: String? = nil) throws {
        let profile = getOrCreateProfile(userId: userId)
        let next = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = (profile.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if current == next {
            if let userId = userId, !userId.isEmpty, profile.userId != userId {
                profile.userId = userId
                guard context.hasChanges else { return }
                try context.save()
            }
            return
        }

        profile.displayName = next
        profile.updatedAt = Date()

        if let userId = userId, !userId.isEmpty {
            profile.userId = userId
        }

        guard context.hasChanges else { return }
        try context.save()

        SyncService.shared.syncUserProfileIfNeeded(profile)
    }

    /// Updates the user's profile style tags (max 3, catalog values only).
    func updateStyleTags(_ tags: [ProfileStyleTag], userId: String? = nil) throws {
        let profile = getOrCreateProfile(userId: userId)
        let next = Array(tags.prefix(ProfileStyleTag.maxSelectionCount))
        let current = profile.profileStyleTags
        if current == next {
            if let userId = userId, !userId.isEmpty, profile.userId != userId {
                profile.userId = userId
                guard context.hasChanges else { return }
                try context.save()
            }
            return
        }

        profile.profileStyleTags = next
        profile.updatedAt = Date()

        if let userId = userId, !userId.isEmpty {
            profile.userId = userId
        }

        guard context.hasChanges else { return }
        try context.save()

        SyncService.shared.syncUserProfileIfNeeded(profile)
    }

    /// Sets the profile avatar URL (`https://…` from R2 or `file://…` for local-only builds). Pass `nil` to clear.
    func updateAvatarUrl(_ url: String?, userId: String? = nil, syncToCloud: Bool = true) throws {
        let profile = getOrCreateProfile(userId: userId)
        let incomingTrimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let incoming = (incomingTrimmed?.isEmpty == false) ? incomingTrimmed : nil
        if incoming == profile.storedProfileAvatarURL {
            if let userId = userId, !userId.isEmpty, profile.userId != userId {
                profile.userId = userId
                guard context.hasChanges else { return }
                try context.save()
            }
            return
        }

        profile.setStoredProfileAvatarURL(incoming)
        profile.updatedAt = Date()

        if let userId = userId, !userId.isEmpty {
            profile.userId = userId
        }

        guard context.hasChanges else { return }
        try context.save()

        if syncToCloud {
            SyncService.shared.syncUserProfileIfNeeded(profile)
        }
    }

    /// Gets the cached friend count (last known value) from Core Data.
    /// Returns nil if not present.
    func getFriendCount() -> Int? {
        let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        request.fetchLimit = 1
        
        do {
            guard let profile = try context.fetch(request).first else {
                return nil
            }
            // friendCount is optional in the model; treat missing as nil
            let raw = profile.value(forKey: "friendCount") as? Int64
            return raw.map { Int($0) }
        } catch {
            print("⚠️ Error fetching friend count: \(error)")
            return nil
        }
    }
    
    /// Updates (persists) the cached friend count in Core Data.
    /// Does not touch `updatedAt` — that field is used for avatar remount identity.
    func updateFriendCount(_ count: Int, userId: String? = nil) throws {
        let profile = getOrCreateProfile(userId: userId)
        profile.setValue(Int64(count), forKey: "friendCount")
        profile.setValue(Date(), forKey: "friendCountUpdatedAt")
        
        if let userId = userId, !userId.isEmpty {
            profile.userId = userId
        }
        
        guard context.hasChanges else { return }
        try context.save()
    }
    
    /// Gets the user's username from Core Data
    func getUsername() -> String? {
        let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        request.fetchLimit = 1
        
        do {
            guard let profile = try context.fetch(request).first else {
                return nil
            }
            return profile.username
        } catch {
            print("⚠️ Error fetching username: \(error)")
            return nil
        }
    }
    
    /// Gets the user's display name from Core Data
    func getDisplayName() -> String? {
        let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        request.fetchLimit = 1
        
        do {
            guard let profile = try context.fetch(request).first else {
                return nil
            }
            return profile.displayName
        } catch {
            print("⚠️ Error fetching display name: \(error)")
            return nil
        }
    }
    
    /// Clears user profile data for a specific userId (used on sign-out)
    func clearUserProfileData(userId: String) throws {
        let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId)
        
        do {
            let profiles = try context.fetch(request)
            for profile in profiles {
                // Clear user-specific data but keep the profile entity
                profile.username = nil
                profile.displayName = nil
                profile.setStoredProfileAvatarURL(nil)
                profile.userId = nil
                profile.setValue(nil, forKey: "friendCount")
                profile.setValue(nil, forKey: "friendCountUpdatedAt")
                // Note: We keep weight data as it might be useful for the next user
                // If you want to clear everything, you can delete the profile instead:
                // context.delete(profile)
            }
            
            if context.hasChanges {
                try context.save()
                print("✅ Cleared user profile data for userId: \(userId)")
            }
        } catch {
            print("⚠️ Error clearing user profile data: \(error)")
            throw error
        }
    }
}

