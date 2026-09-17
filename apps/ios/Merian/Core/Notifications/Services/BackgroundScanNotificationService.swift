import Foundation

/// Shared user-visible effects after a background result and its queue cleanup
/// commit. Callers retain durable ownership validation; the notification manager
/// retains scheduling deduplication across direct and recovered completions.
@MainActor
struct BackgroundScanNotificationService {
    let suppressesInferenceBanners: @MainActor () -> Bool
    let markUnseenScan: @MainActor () -> Void
    let notificationsEnabled: @MainActor () -> Bool
    let sendNotification: @MainActor (_ speciesName: String, _ scanId: String) -> Void

    static var live: Self {
        Self(
            suppressesInferenceBanners: {
                AppSettings.shared.suppressInferenceBanners
            },
            markUnseenScan: {
                AppSettings.shared.hasUnseenScan = true
                AppIconBadgeCoordinator.updateAppIconBadge()
            },
            notificationsEnabled: {
                AppSettings.shared.isPushNotificationsEnabled
            },
            sendNotification: { speciesName, scanId in
                PushNotificationManager.shared.sendInferenceCompleteNotification(
                    speciesName: speciesName,
                    scanId: scanId
                )
            }
        )
    }

    func notify(speciesName: String, scanId: String) {
        if !suppressesInferenceBanners() {
            markUnseenScan()
        }
        // Always schedule enabled alerts, including in the foreground. The
        // notification-center delegate alone decides foreground presentation.
        if notificationsEnabled() {
            sendNotification(speciesName, scanId)
        }
    }
}
