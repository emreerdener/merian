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
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        guard hasCompletedOnboarding else { return }

        container.cameraManager.startSession()
        container.usageManager.evaluateDailyRefresh()
        container.pushNotificationManager.setupDelegate()
        container.pushNotificationManager.syncPermissionState()
        
        // Force cross-process AppStorage reconciliation. 
        // UserDefaults updates made by the BackgroundDatabaseActor while suspended
        // are not always natively observed by SwiftUI @AppStorage properties upon resume.
        let unseen = UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasUnseenScan)
        UserDefaults.standard.set(unseen, forKey: UserDefaultsKeys.hasUnseenScan)

        Task {
            await container.supabaseManager.initializeGhostSession()
            container.offlineQueueManager.syncPendingScans()
            // Recover scans whose upload completed but inference was interrupted
            // (e.g. app killed or suspended mid-inference). NWPathMonitor only fires
            // on connectivity *changes*, so this must also run on every foreground.
            container.offlineQueueManager.replayInferenceForUploadedScans()

            let now = Date()

            if let context = container.offlineQueueManager.modelContext {
                // Restore account history on re-install or multi-device login.
                // Throttled to once per 15 minutes to avoid redundant network syncs on every foreground.
                let lastSyncDate = UserDefaults.standard.object(forKey: "lastHistoricalSyncDate") as? Date ?? Date.distantPast
                if now.timeIntervalSince(lastSyncDate) >= 900 {
                    // Stamp before starting the sync, not after. Without this, two concurrent
                    // callers (auth listener + foreground handler) both check the timestamp
                    // before either writes it and both proceed — doubling the network load.
                    UserDefaults.standard.set(now, forKey: "lastHistoricalSyncDate")
                    await container.scanRepository.syncHistoricalScansDown(modelContext: context)
                }
            }

            // Evaluate archive rescue once per 24 hours.
            let lastRescueDate = UserDefaults.standard.object(forKey: "lastArchiveRescueDate") as? Date ?? Date.distantPast
            if now.timeIntervalSince(lastRescueDate) >= 86400 {
                if let context = container.offlineQueueManager.modelContext {
                    container.archiveManager.evaluateAndRescueAgingScans(modelContext: context)
                    UserDefaults.standard.set(now, forKey: "lastArchiveRescueDate")
                }
            }
        }
    }

    /// Handles application transition to inactive (e.g. app switcher).
    func handleInactivePhase() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        guard hasCompletedOnboarding else { return }

        container.cameraManager.stopSession()

        // Notify observers (e.g. CameraViewModel) to reset modal state.
        // Posted via AppEventPublisher to safely broadcast cross-module states back to @MainActor observers.
        container.appEventPublisher.send(.appDidEnterInactivePhase)
    }

    /// Handles application transition to background.
    func handleBackgroundPhase() {
        // No-op: scans are enqueued to the offline queue immediately at submission time
        // (in CameraViewModel.submitActiveScan), so no rescue is needed here. The background
        // URLSession upload was already dispatched while the app was in the foreground.
    }
}
