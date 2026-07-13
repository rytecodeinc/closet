//
//  PushNotificationService.swift
//  closet
//
//  Registers for APNs, upserts device tokens to Supabase, and clears tokens on sign-out.
//

import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushNotificationService: ObservableObject {
    static let shared = PushNotificationService()

    private let tokenDefaultsKey = "apns.deviceToken"
    private var lastUploadedToken: String?

    private init() {}

    /// Request permission and register with APNs when friends/sharing is enabled.
    func requestAuthorizationAndRegisterIfNeeded() {
        guard AppEnvironment.capabilities.enablesFriendsAndSharing else { return }
        guard AppEnvironment.capabilities.enablesCloudSync else { return }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    if let error {
                        print("⚠️ Push auth error: \(error.localizedDescription)")
                    }
                    guard granted else {
                        print("ℹ️ Push permission denied")
                        return
                    }
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            case .denied:
                print("ℹ️ Push permission denied — enable in Settings to receive alerts")
            @unknown default:
                break
            }
        }
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        UserDefaults.standard.set(token, forKey: tokenDefaultsKey)
        Task { await uploadToken(token) }
    }

    func handleRegistrationFailure(_ error: Error) {
        print("⚠️ APNs registration failed: \(error.localizedDescription)")
    }

    /// Re-upload stored token after login (e.g. permission already granted).
    func syncStoredTokenIfNeeded() async {
        guard AppEnvironment.capabilities.enablesFriendsAndSharing,
              AppEnvironment.capabilities.enablesCloudSync else { return }
        guard let token = UserDefaults.standard.string(forKey: tokenDefaultsKey), !token.isEmpty else {
            return
        }
        await uploadToken(token)
    }

    /// Deletes this device's token from Supabase while the session is still valid.
    func unregisterCurrentDevice() async {
        guard let token = UserDefaults.standard.string(forKey: tokenDefaultsKey), !token.isEmpty else {
            return
        }
        do {
            try await SupabaseService.shared.deleteDeviceToken(token)
        } catch {
            print("⚠️ Failed to delete device token: \(error.localizedDescription)")
        }
        UserDefaults.standard.removeObject(forKey: tokenDefaultsKey)
        lastUploadedToken = nil
    }

    func clearBadge() {
        UIApplication.shared.applicationIconBadgeNumber = 0
    }

    private func uploadToken(_ token: String) async {
        guard SupabaseService.shared.isAuthenticated else { return }
        if lastUploadedToken == token { return }

        let environment: String
        #if DEBUG
        environment = "sandbox"
        #else
        environment = "production"
        #endif

        do {
            try await SupabaseService.shared.upsertDeviceToken(token: token, environment: environment)
            lastUploadedToken = token
            print("✅ Device token registered (\(environment))")
        } catch {
            print("⚠️ Failed to upsert device token: \(error.localizedDescription)")
        }
    }
}
