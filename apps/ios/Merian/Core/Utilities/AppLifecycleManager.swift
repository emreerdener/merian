import SwiftData
import SwiftUI

/// Handles app lifecycle transitions (active, inactive, background),
/// dispatching to the relevant core services.
/// Decouples lifecycle logic from the primary dependency injection container.
@MainActor
final class AppLifecycleManager {

    private let container: AppDIContainer

    init(container: AppDIContainer) {
        self.container = container
    }

    /// Handles application transition to active foreground.
    func handleActivePhase() {
        // Skip setup until onboarding is complete.
        guard container.appSettings.hasCompletedOnboarding else { return }

        container.usageManager.evaluateDailyRefresh()
        container.pushNotificationManager.setupDelegate()
        container.pushNotificationManager.syncPermissionState()
        container.pushNotificationManager.registerForRemoteNotificationsIfAuthorized()
        
        // Evaluate session timeout: if the app has been in the background for more than 5 minutes,
        // snap the UI back to a clean camera state.
        let lastBackgrounded = UserDefaults.standard.double(forKey: UserDefaultsKeys.lastBackgroundedDate)
        if lastBackgrounded > 0 {
            let elapsed = Date().timeIntervalSince1970 - lastBackgrounded
            if elapsed > 300 { // 5 minutes
                container.appEventPublisher.send(.appDidResumeAfterTimeout)
            }
            UserDefaults.standard.set(0.0, forKey: UserDefaultsKeys.lastBackgroundedDate)
        }
        
        // Force cross-process settings reconciliation. UserDefaults updates made by
        // background delegates while suspended are not always observed by SwiftUI on resume.
        container.appSettings.refreshFromDefaults()
        container.hardwareOrchestrator.evaluateConstraints()

        Task {
            await AppIconBadgeCoordinator.refreshExploreUnreadNotificationCount()
            await container.pushNotificationManager.syncRemotePushRegistrationIfPossible(reason: "app_active")
            container.offlineQueueManager.purgeSoftDeletedRecords()

            let now = Date()

            if let context = container.offlineQueueManager.modelContext {
                await SpeciesPreferredNameRepository.syncCloudPreferences(modelContext: context)
                await container.scanRepository.purgeExpiredNonBiologicalScans(
                    modelContainer: context.container,
                    referenceDate: now
                )

                // Restore account history on re-install or multi-device login.
                // Throttled to once per 15 minutes to avoid redundant network syncs on every foreground.
                let lastSyncDate = UserDefaults.standard.object(forKey: UserDefaultsKeys.lastHistoricalSyncDate) as? Date ?? Date.distantPast
                if now.timeIntervalSince(lastSyncDate) >= 900 {
                    // Stamp before starting the sync, not after. Without this, two concurrent
                    // callers (auth listener + foreground handler) both check the timestamp
                    // before either writes it and both proceed — doubling the network load.
                    UserDefaults.standard.set(now, forKey: UserDefaultsKeys.lastHistoricalSyncDate)
                    await container.scanRepository.syncHistoricalScansDown(modelContext: context)
                }
            }

            container.offlineQueueManager.syncPendingScans()
            // Recover scans whose upload completed but inference was interrupted
            // (e.g. app killed or suspended mid-inference). NWPathMonitor only fires
            // on connectivity *changes*, so this must also run on every foreground.
            container.offlineQueueManager.replayInferenceForUploadedScans()
        }
    }

    /// Handles application transition to inactive (e.g. app switcher, system overlays).
    func handleInactivePhase() {
        guard container.appSettings.hasCompletedOnboarding else { return }

        // Stop the camera session immediately — the viewfinder should freeze during any
        // interruption (app switcher, system alerts, limited photo library prompt, etc.).
        container.cameraManager.stopSession()

        // Sheet dismissal is intentionally deferred to handleBackgroundPhase.
        // System overlays — including the iOS limited photo library access prompt — transition
        // the scene to .inactive without ever reaching .background, and must not close sheets.
    }

    /// Handles application transition to background.
    func handleBackgroundPhase() {
        // Record the exact time the app entered the background to evaluate session timeouts upon wake.
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UserDefaultsKeys.lastBackgroundedDate)
    }
}
