import Foundation
import UserNotifications
#if canImport(UIKit)
import os
import UIKit
#endif

/// Manages UNUserNotificationCenter delegation for local inference completion alerts.
@MainActor
@Observable
final class PushNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationManager()

    private override init() {
        super.init()
    }

    func setupDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    func syncPermissionState() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let isGranted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            Task { @MainActor in
                if UserDefaults.standard.bool(forKey: UserDefaultsKeys.isPushNotificationsEnabled) != isGranted {
                    UserDefaults.standard.set(isGranted, forKey: UserDefaultsKeys.isPushNotificationsEnabled)
                }
            }
        }
    }

    func requestAuthorization(completion: @escaping () -> Void = {}) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            Task { @MainActor in
                if let error = error {
                    MerianLog.hardware.debug("Failed to request push notification authorization: \(error, privacy: .private)")
                    UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isPushNotificationsEnabled)
                } else if granted {
                    MerianLog.hardware.debug("Push notification authorization granted.")
                    UserDefaults.standard.set(true, forKey: UserDefaultsKeys.isPushNotificationsEnabled)
                } else {
                    MerianLog.hardware.debug("Push notification authorization denied.")
                    UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isPushNotificationsEnabled)
                }
                completion()
            }
        }
    }

    func sendInferenceCompleteNotification(speciesName: String, scanId: String) {
        let content = UNMutableNotificationContent()
        content.title = "Analysis complete"
        content.body = "You discovered \(speciesName)."
        content.sound = .default
        content.userInfo = ["scanId": scanId]

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                MerianLog.hardware.debug("Failed to schedule inference notification: \(error, privacy: .private)")
            } else {
                MerianLog.hardware.debug("Inference notification scheduled for \(speciesName, privacy: .private).")
            }
        }
    }

    func sendAchievementUnlockedNotification(achievementTitle: String) {
        let content = UNMutableNotificationContent()
        content.title = "Achievement Unlocked!"
        content.body = "You just earned: \(achievementTitle)"
        content.sound = .default
        content.userInfo = ["type": "achievement"]

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                MerianLog.hardware.debug("Failed to schedule achievement notification: \(error, privacy: .private)")
            } else {
                MerianLog.hardware.debug("Achievement notification scheduled for '\(achievementTitle, privacy: .public)'.")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let scanId = userInfo["scanId"] as? String {
            Task { @MainActor in
                MerianLog.hardware.debug("Push notification tapped — routing to scanId \(scanId, privacy: .private)")
                AppEventPublisher.shared.send(.appDidEnterActivePhaseWithScan(scanId: scanId))
            }
        }

        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let type = notification.request.content.userInfo["type"] as? String
        
        if type != "achievement", UserDefaults.standard.bool(forKey: "suppressInferenceBanners") {
            completionHandler([])
        } else {
            completionHandler([.banner, .sound, .list])
        }
    }
}
