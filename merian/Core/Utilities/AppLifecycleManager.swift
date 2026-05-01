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
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasCompletedOnboarding)
        guard hasCompletedOnboarding else { return }

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
        
        // Force cross-process AppStorage reconciliation. 
        // UserDefaults updates made by the BackgroundDatabaseActor while suspended
        // are not always natively observed by SwiftUI @AppStorage properties upon resume.
        let unseen = UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasUnseenScan)
        UserDefaults.standard.set(unseen, forKey: UserDefaultsKeys.hasUnseenScan)

        Task {
            await container.supabaseManager.initializeGhostSession()
            await container.pushNotificationManager.syncRemotePushRegistrationIfPossible(reason: "app_active")
            container.offlineQueueManager.purgeSoftDeletedRecords()
            container.offlineQueueManager.syncPendingScans()
            // Recover scans whose upload completed but inference was interrupted
            // (e.g. app killed or suspended mid-inference). NWPathMonitor only fires
            // on connectivity *changes*, so this must also run on every foreground.
            container.offlineQueueManager.replayInferenceForUploadedScans()

            let now = Date()

            if let context = container.offlineQueueManager.modelContext {
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

            // Evaluate archive rescue once per 24 hours.
            let lastRescueDate = UserDefaults.standard.object(forKey: UserDefaultsKeys.lastArchiveRescueDate) as? Date ?? Date.distantPast
            if now.timeIntervalSince(lastRescueDate) >= 86400 {
                if let context = container.offlineQueueManager.modelContext {
                    container.archiveManager.evaluateAndRescueAgingScans(modelContext: context)
                    UserDefaults.standard.set(now, forKey: UserDefaultsKeys.lastArchiveRescueDate)
                }
            }
        }
    }

    /// Handles application transition to inactive (e.g. app switcher, system overlays).
    func handleInactivePhase() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasCompletedOnboarding)
        guard hasCompletedOnboarding else { return }

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
