import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
import os
#endif

/// Encapsulates Apple's UNUserNotificationCenter logic natively to handle local inference completion alerts.
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
            DispatchQueue.main.async {
                if UserDefaults.standard.bool(forKey: "isPushNotificationsEnabled") != isGranted {
                    UserDefaults.standard.set(isGranted, forKey: "isPushNotificationsEnabled")
                }
            }
        }
    }
    
    func requestAuthorization(completion: @escaping () -> Void = {}) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    MerianLog.hardware.debug("🚨 Failed to natively request push notification authorization: \(error, privacy: .private)")
                    UserDefaults.standard.set(false, forKey: "isPushNotificationsEnabled")
                } else if granted {
                    MerianLog.hardware.debug("✅ Push notification authorization permanently granted.")
                    UserDefaults.standard.set(true, forKey: "isPushNotificationsEnabled")
                } else {
                    MerianLog.hardware.debug("⚠️ Push notification authorization locally denied.")
                    UserDefaults.standard.set(false, forKey: "isPushNotificationsEnabled")
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
        
        // Inject strictly typed metadata cleanly for explicit tap routing
        content.userInfo = ["scanId": scanId]
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                MerianLog.hardware.debug("🚨 Failed to organically schedule push notification: \(error, privacy: .private)")
            } else {
                MerianLog.hardware.debug("✅ Push notification locally scheduled for \(speciesName, privacy: .private).")
            }
        }
    }
    
    func sendAchievementUnlockedNotification(achievementTitle: String) {
        let content = UNMutableNotificationContent()
        content.title = "Achievement Unlocked!"
        content.body = "You just earned: \(achievementTitle)"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                MerianLog.hardware.debug("🚨 Failed to organically schedule achievement push notification: \(error, privacy: .private)")
            } else {
                MerianLog.hardware.debug("✅ Achievement Push notification locally scheduled for '\(achievementTitle, privacy: .public)'.")
            }
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate Hooks
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        if let scanId = userInfo["scanId"] as? String {
            Task { @MainActor in
                MerianLog.hardware.debug("📱 Push Notification Tapped: Routing cleanly to scanId \(scanId, privacy: .private)")
                NotificationCenter.default.post(name: NSNotification.Name("AppDidEnterActivePhaseWithScan"), object: nil, userInfo: ["scanId": scanId])
            }
        }
        
        completionHandler()
    }
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // CRITICAL FIX: Because Merian keeps the app "running" in the background via `URLSession` and Tasks, 
        // iOS still inherently fires `willPresent` on local pushes!
        // We MUST verify `.active` foreground presence before suppressing the visual banner gracefully.
        Task { @MainActor in
#if canImport(UIKit)
            if UIApplication.shared.applicationState == .active {
                // Suppresses visual banners implicitly if the user is already actively navigating the app natively.
                completionHandler([])
            } else {
                // Explicitly allow iOS to render the notification across the locked screen/notification center!
                completionHandler([.banner, .sound, .list])
            }
#else
            completionHandler([.banner, .sound, .list])
#endif
        }
    }
}
