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
            localImagePaths: ["stuck.webp"],
            scanState: .staged,
            stagedR2Keys: ["staging/test-user/stuck.webp"]
        )
        context.insert(stuck)
        try context.save()

        let originalContext    = offlineManager.modelContext
        let originalOnline     = offlineManager.isOnline
        let originalReconciled = offlineManager.hasReconciledStartupState
        let originalOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        defer {
            offlineManager.modelContext              = originalContext
            offlineManager.isOnline                  = originalOnline
            offlineManager.hasReconciledStartupState = originalReconciled
            offlineManager.uploadRetryCount.removeValue(forKey: stuck.id)
            UserDefaults.standard.set(originalOnboarding, forKey: "hasCompletedOnboarding")
        }

        offlineManager.modelContext              = context
        offlineManager.isOnline                  = true
        // Bypass startup reconciliation so replayInferenceForUploadedScans queries .staged scans immediately.
        offlineManager.hasReconciledStartupState = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

        manager.handleActivePhase()

        // In the test environment the network call fails immediately and increments
        // uploadRetryCount — a reliable, network-free observable that the pipeline was triggered.
        // Poll up to 5s to avoid a fixed sleep racing the async Task in handleActivePhase().
        let deadline = Date().addingTimeInterval(5)
        while (offlineManager.uploadRetryCount[stuck.id] ?? 0) == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(
            (offlineManager.uploadRetryCount[stuck.id] ?? 0) > 0,
            "handleActivePhase must call replayInferenceForUploadedScans() so .staged scans stuck mid-inference are recovered on foreground, not just on connectivity change"
        )
    }

    @Test("AppLifecycleManager intercepts active UI inference and pushes it to OfflineQueue on backgrounding")
    func testHandleBackgroundPhaseRescuesActiveLiveCapture() async {
        // Arrange
        let diContainer = AppDIContainer.preview
        let manager = AppLifecycleManager(container: diContainer)
        let engine = diContainer.inferenceEngine
        
        // Setup initial state: An active live capture is still processing when the user backgrounds the app
        engine.isProcessing = true
        let dummyImageData = Data("dummy test pixels".utf8)
        engine.activeLiveCaptureDatas = [dummyImageData]
        
        // Assert preconditions
        #expect(engine.isBackgroundRescued == false)
        
        // Act
        manager.handleBackgroundPhase()
        
        // Assert
        // The engine's cancelActiveRequest() should have been called, setting isBackgroundRescued to true
        // and signaling that the in-flight inference was deliberately interrupted by the OS backgrounding
        #expect(engine.isBackgroundRescued == true, "Engine should mark the request as background rescued so it isn't automatically refunded")
        // isProcessing is cleared asynchronously by the task's cancellation catch block —
        // not synchronously inside cancelActiveRequest() — so it cannot be checked here.
    }
}
