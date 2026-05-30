import Testing
import Foundation
import SwiftData
@testable import Merian

@MainActor
struct AppLifecycleManagerTests {

    @Test("handleActivePhase recovers .staged scans stuck before inference on foreground with stable connectivity")
    func testHandleActivePhasePlaysBackStagedScans() async throws {
        let diContainer = AppDIContainer.preview
        let manager = AppLifecycleManager(container: diContainer)
        let offlineManager = diContainer.offlineQueueManager

        let schema = Schema(CurrentSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // Scan fully uploaded to R2 but inference was interrupted before completion.
        let stuck = OfflineQueuedScan(
            capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("stuck.webp")]), encoding: .utf8),
            scanState: .staged,
            stagedR2Keys: ["staging/test-user/stuck.webp"]
        )
        context.insert(stuck)
        try context.save()

        let originalContext    = offlineManager.modelContext
        let originalOnline     = offlineManager.isOnline
        let originalReconciled = offlineManager.hasReconciledStartupState
        let originalOnboarding = diContainer.appSettings.hasCompletedOnboarding
        defer {
            offlineManager.modelContext              = originalContext
            offlineManager.isOnline                  = originalOnline
            offlineManager.hasReconciledStartupState = originalReconciled
            offlineManager.uploadRetryCount.removeValue(forKey: stuck.id)
            offlineManager.replayedStagedScanCount   = 0
            diContainer.appSettings.hasCompletedOnboarding = originalOnboarding
        }

        offlineManager.modelContext              = context
        offlineManager.isOnline                  = true
        // Bypass startup reconciliation so replayInferenceForUploadedScans queries .staged scans immediately.
        offlineManager.hasReconciledStartupState = true
        // Reset debug counter so a prior test's replay doesn't interfere.
        offlineManager.replayedStagedScanCount   = 0
        diContainer.appSettings.hasCompletedOnboarding = true

        manager.handleActivePhase()

        // replayedStagedScanCount is incremented immediately after tryClaimForInference
        // succeeds — before any network work — so this is a network-free observable that
        // the staged-scan replay pipeline was triggered.
        // Poll up to 5s to allow the nested Tasks in handleActivePhase to be scheduled.
        let deadline = Date().addingTimeInterval(5)
        while offlineManager.replayedStagedScanCount == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(
            offlineManager.replayedStagedScanCount > 0,
            "handleActivePhase must call replayInferenceForUploadedScans() so .staged scans stuck mid-inference are recovered on foreground, not just on connectivity change"
        )
    }

    @Test("handleBackgroundPhase is a no-op on the inference engine — scan durability is handled at submission time")
    func testHandleBackgroundPhaseDoesNotMutateEngine() async {
        // Arrange
        let diContainer = AppDIContainer.preview
        let manager = AppLifecycleManager(container: diContainer)
        let engine = diContainer.inferenceEngine

        // Simulate an active inference (scan was submitted and enqueued before the user backgrounded)
        engine.isProcessing = true

        // Act
        manager.handleBackgroundPhase()

        // Assert: engine state is untouched — the scan is already durable in the offline queue.
        // handleBackgroundPhase no longer performs any rescue or cancellation.
        #expect(engine.isProcessing == true, "handleBackgroundPhase must not cancel or modify an in-flight inference — the offline queue already holds the scan")
    }
}
