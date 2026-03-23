import Foundation
import UserNotifications

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
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🚨 Failed to natively request push notification authorization: \(error)")
                    UserDefaults.standard.set(false, forKey: "isPushNotificationsEnabled")
                } else if granted {
                    print("✅ Push notification authorization permanently granted.")
                    UserDefaults.standard.set(true, forKey: "isPushNotificationsEnabled")
                } else {
                    print("⚠️ Push notification authorization locally denied.")
                    UserDefaults.standard.set(false, forKey: "isPushNotificationsEnabled")
                }
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
                print("🚨 Failed to organically schedule push notification: \(error)")
            } else {
                print("✅ Push notification locally scheduled for \(speciesName).")
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
                print("📱 Push Notification Tapped: Routing cleanly to scanId \(scanId)")
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
        // Suppresses visual banners implicitly if the user is already actively navigating the app natively.
        completionHandler([])
    }
}
