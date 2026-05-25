//
//  HowToOnboardingStore.swift
//  closet
//
//  Per-user flag: post-registration how-to carousel was completed.
//

import Foundation

enum HowToOnboardingStore {
    private static func key(for userId: UUID) -> String {
        "hasCompletedHowToOnboarding.\(userId.uuidString)"
    }

    static func hasCompleted(userId: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: userId))
    }

    static func markCompleted(userId: UUID) {
        UserDefaults.standard.set(true, forKey: key(for: userId))
    }

    /// Settings preview / debugging — show the flow again on next launch.
    static func reset(userId: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: userId))
    }
}
