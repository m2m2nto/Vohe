import SwiftUI
import UIKit
import UserNotifications

@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()
    var quickSessionRequested: Bool = false
    private init() {}
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    static let reminderIdentifierPrefix = "vohe.reminder."

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let id = response.notification.request.identifier
        guard id.hasPrefix(Self.reminderIdentifierPrefix) else { return }
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        DispatchQueue.main.async {
            NotificationRouter.shared.quickSessionRequested = true
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        return true
    }
}
