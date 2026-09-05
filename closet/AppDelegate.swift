//
//  AppDelegate.swift
//  closet
//
//  APNs registration + notification tap handling.
//

import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleRegistrationFailure(error)
        }
    }

    // Show banner while app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // Tap → Profile notifications list (and invite preview when payload includes event_id).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        var eventInviteId: UUID?
        let type = userInfo["type"] as? String
        if type == "event_invite" {
            if let payload = userInfo["payload"] as? [String: Any] {
                if let eventIdString = payload["event_id"] as? String {
                    eventInviteId = UUID(uuidString: eventIdString)
                }
            } else if let payloadString = userInfo["payload"] as? String,
                      let data = payloadString.data(using: .utf8),
                      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let eventIdString = payload["event_id"] as? String {
                eventInviteId = UUID(uuidString: eventIdString)
            } else if let eventIdString = userInfo["event_id"] as? String {
                eventInviteId = UUID(uuidString: eventIdString)
            }
        }
        DeepLinkRouter.shared.openNotificationsFromPush(eventInviteId: eventInviteId)
        Task { @MainActor in
            PushNotificationService.shared.clearBadge()
        }
        completionHandler()
    }
}
