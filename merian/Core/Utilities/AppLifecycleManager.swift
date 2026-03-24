import SwiftUI
import SwiftData

/// Dedicated orchestrator specifically managing logic when the App transitions across Active, Inactive, and Background states.
/// This cleanly decouples all routing and recovery logic off the primary dependency injection container natively.
@MainActor
final class AppLifecycleManager {
    
    private let container: AppDIContainer
    
    init(container: AppDIContainer) {
        self.container = container
    }
    
    /// Handles application transition to active foreground
    func handleActivePhase() {
        // Structurally prevent the OS from booting camera sessions implicitly or hitting API quotas actively natively during the Onboarding flow securely.
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        guard hasCompletedOnboarding else { return }
        
        container.cameraManager.startSession()
        container.usageManager.evaluateDailyRefresh()
        container.pushNotificationManager.setupDelegate()
        container.pushNotificationManager.syncPermissionState()
        
        Task {
            await container.supabaseManager.initializeGhostSession()
            container.offlineQueueManager.syncPendingScans()

            let now = Date()

            if let context = container.offlineQueueManager.modelContext {
                // Restore account history for re-installs or multi-device login seamlessly
                // Throttled to once per 15 minutes to avoid redundant full-table network syncs on every foreground
                let lastSyncDate = UserDefaults.standard.object(forKey: "lastHistoricalSyncDate") as? Date ?? Date.distantPast
                if now.timeIntervalSince(lastSyncDate) >= 900 {
                    await container.scanRepository.syncHistoricalScansDown(modelContext: context)
                    UserDefaults.standard.set(now, forKey: "lastHistoricalSyncDate")
                }
            }

            // Trigger Archive Safety Protocol natively once per 24 hours
            let lastRescueDate = UserDefaults.standard.object(forKey: "lastArchiveRescueDate") as? Date ?? Date.distantPast
            if now.timeIntervalSince(lastRescueDate) >= 86400 {
                if let context = container.offlineQueueManager.modelContext {
                    container.archiveManager.evaluateAndRescueAgingScans(modelContext: context)
                    UserDefaults.standard.set(now, forKey: "lastArchiveRescueDate")
                }
            }
        }
    }
    
    /// Handles application transition to inactive (like app switcher)
    func handleInactivePhase() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        guard hasCompletedOnboarding else { return }
        
        container.cameraManager.stopSession()
        
        // Ensure the UI gracefully defaults back to the ready-to-scan state
        // if the user drops out of the app while viewing a sheet natively.
        // It's imperative that this is dispatched globally because we do not want
        // to directly couple `AppLifecycleManager` tightly to `CameraViewModel`.
        NotificationCenter.default.post(name: NSNotification.Name("AppDidEnterInactivePhase"), object: nil)
    }
    
    /// Handles application transition to background gracefully
    func handleBackgroundPhase() {
        // Cancel the live request and re-queue via the background URLSession for all users.
        // Free users are capped at maxFreeScansPerDay queue items (enforced in enqueueCapture),
        // so they cannot hoard scans. Pro users queue without limit.
        if container.inferenceEngine.isProcessing, !container.inferenceEngine.activeLiveCaptureDatas.isEmpty {
            container.offlineQueueManager.enqueueCapture(
                imageDatas: container.inferenceEngine.activeLiveCaptureDatas,
                telemetry: CaptureTelemetry(from: container.inferenceEngine),
                blurScore: nil
            )
            container.inferenceEngine.cancelActiveRequest()
        }
    }
}
