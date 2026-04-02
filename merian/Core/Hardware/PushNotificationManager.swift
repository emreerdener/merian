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
        setupCategories()
    }

    /// Registers custom notification categories and interactive actions for the app's push notifications.
    ///
    /// This enables rich, interactive notifications on the iOS lock screen, allowing users to
    /// trigger common actions (like viewing details or sharing a discovery) without needing to
    /// manually open the app first.
    private func setupCategories() {
        let viewAction = UNNotificationAction(identifier: "VIEW_ACTION", title: "View Details", options: [.foreground])
        let shareAction = UNNotificationAction(identifier: "SHARE_ACTION", title: "Share Discovery", options: [.foreground])
        
        let category = UNNotificationCategory(
            identifier: "INFERENCE_COMPLETE",
            actions: [viewAction, shareAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
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

    /// Schedules a local notification to alert the user that the AI has finished analyzing their scan.
    ///
    /// This notification utilizes several premium UX features:
    /// - **Rich Media**: Attaches an image thumbnail if `imageURL` is provided.
    /// - **Time Sensitive**: Escalates priority to bypass focus modes (requires the Time Sensitive capability).
    /// - **Thread Grouping**: Groups all inference completion notifications neatly under a single stack.
    /// - **Interactive Actions**: Provides quick actions to view or share the discovery straight from the lock screen.
    ///
    /// - Parameters:
    ///   - speciesName: The resolved name of the discovered species.
    ///   - scanId: The unique identifier for the scan, used for internal routing when the notification is tapped.
    ///   - imageURL: An optional local file URL pointing to the scan's captured image for the lock screen thumbnail.
    func sendInferenceCompleteNotification(speciesName: String, scanId: String, imageURL: URL? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "Analysis complete"
        content.body = "New discovery: \(speciesName)!"
        content.sound = .default
        content.userInfo = ["scanId": scanId]
        content.categoryIdentifier = "INFERENCE_COMPLETE"
        content.threadIdentifier = "inference_complete_thread"
        
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        
        if let imageURL = imageURL {
            do {
                let attachment = try UNNotificationAttachment(identifier: "image", url: imageURL, options: nil)
                content.attachments = [attachment]
            } catch {
                MerianLog.hardware.debug("Failed to create notification attachment: \(error, privacy: .private)")
            }
        }

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
        handleNotificationAction(userInfo: userInfo, actionIdentifier: response.actionIdentifier)
        completionHandler()
    }

    /// Extracted for testability since `UNNotificationResponse` cannot be cleanly mocked in XCTest.
    nonisolated func handleNotificationAction(userInfo: [AnyHashable: Any], actionIdentifier: String) {
        if let scanId = userInfo["scanId"] as? String {
            if actionIdentifier != UNNotificationDismissActionIdentifier {
                Task { @MainActor in
                    if actionIdentifier == "SHARE_ACTION" {
                        MerianLog.hardware.debug("Share action tapped for scanId \(scanId, privacy: .private)")
                    } else {
                        MerianLog.hardware.debug("Push notification tapped — routing to scanId \(scanId, privacy: .private)")
                    }
                    // For now, route to the scan regardless of which action was tapped
                    // We can handle specific share intent dynamically within the insight sheet later.
                    AppEventPublisher.shared.send(.appDidEnterActivePhaseWithScan(scanId: scanId))
                }
            }
        }
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
