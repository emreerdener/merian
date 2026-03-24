import SwiftUI
import SwiftData

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

        Task {
            await container.supabaseManager.initializeGhostSession()
            container.offlineQueueManager.syncPendingScans()

            let now = Date()

            if let context = container.offlineQueueManager.modelContext {
                // Restore account history on re-install or multi-device login.
                // Throttled to once per 15 minutes to avoid redundant network syncs on every foreground.
                let lastSyncDate = UserDefaults.standard.object(forKey: "lastHistoricalSyncDate") as? Date ?? Date.distantPast
                if now.timeIntervalSince(lastSyncDate) >= 900 {
                    await container.scanRepository.syncHistoricalScansDown(modelContext: context)
                    UserDefaults.standard.set(now, forKey: "lastHistoricalSyncDate")
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
        // Posted as a notification to avoid coupling AppLifecycleManager to CameraViewModel.
        NotificationCenter.default.post(name: .appDidEnterInactivePhase, object: nil)
    }

    /// Handles application transition to background.
    func handleBackgroundPhase() {
        // If a live capture is in progress, re-queue it for background URLSession delivery
        // and cancel the active request. Free users are capped at maxFreeScansPerDay items;
        // Pro users queue without limit.
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
