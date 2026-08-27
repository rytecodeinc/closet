//
//  AppEnvironment.swift
//  closet
//
//  Compile-time product tier (TestFlight vs Production). Set via the TestFlight
//  build configuration (`TESTFLIGHT` in Active Compilation Conditions).
//

import SwiftUI

// MARK: - Tier

/// Product slice baked into the binary — not per-user and not the App Store distribution channel.
enum AppTier: String, Equatable {
    case testflight = "TestFlight"
    case production = "Production"
}

// MARK: - Capabilities

struct AppCapabilities: Equatable {
    let tier: AppTier

    let showsClosetTab: Bool
    let showsCalendarTab: Bool
    let showsProfileTab: Bool
    let showsWishlistTab: Bool
    let showsFittingTab: Bool
    let enablesCloudSync: Bool
    let enablesFriendsAndSharing: Bool
    let enablesTombstonePurge: Bool
    /// Item weather range attribute (deferred to v2; gated via `showsWeatherAttribute`).
    let showsWeatherAttribute: Bool
    /// Item weight attribute (deferred to v2; gated via `showsWeightAttribute`).
    let showsWeightAttribute: Bool
    /// Color / season visibility settings (hidden in TestFlight tier).
    let showsColorSeasonSettings: Bool
    /// Developer-only maintenance actions in Settings (hidden in TestFlight tier).
    let showsDeveloperSettings: Bool
    /// Category picker during sign-up; TestFlight auto-seeds the full catalog after step 2.
    let requiresCategoryOnboarding: Bool
    /// Add Multiple → From Camera (not ready for TestFlight).
    let enablesAddMultipleCamera: Bool

    static let testflight = AppCapabilities(
        tier: .testflight,
        showsClosetTab: true,
        showsCalendarTab: true,
        showsProfileTab: true,
        showsWishlistTab: false,
        showsFittingTab: false,
        enablesCloudSync: false,
        enablesFriendsAndSharing: false,
        enablesTombstonePurge: false,
        showsWeatherAttribute: false,
        showsWeightAttribute: false,
        showsColorSeasonSettings: false,
        showsDeveloperSettings: false,
        requiresCategoryOnboarding: false,
        enablesAddMultipleCamera: false
    )

    static let production = AppCapabilities(
        tier: .production,
        showsClosetTab: true,
        showsCalendarTab: true,
        showsProfileTab: true,
        showsWishlistTab: true,
        showsFittingTab: true,
        enablesCloudSync: true,
        enablesFriendsAndSharing: true,
        enablesTombstonePurge: true,
        showsWeatherAttribute: false,
        showsWeightAttribute: false,
        showsColorSeasonSettings: true,
        showsDeveloperSettings: true,
        requiresCategoryOnboarding: true,
        enablesAddMultipleCamera: true
    )
}

// MARK: - Environment

enum AppEnvironment {
    static let capabilities: AppCapabilities = {
        #if TESTFLIGHT
        return .testflight
        #else
        return .production
        #endif
    }()
}

private struct AppCapabilitiesKey: EnvironmentKey {
    static let defaultValue = AppEnvironment.capabilities
}

extension EnvironmentValues {
    var appCapabilities: AppCapabilities {
        get { self[AppCapabilitiesKey.self] }
        set { self[AppCapabilitiesKey.self] = newValue }
    }
}
