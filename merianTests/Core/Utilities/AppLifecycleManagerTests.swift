import Testing
import Foundation
import SwiftData
@testable import Merian

@MainActor
struct AppLifecycleManagerTests {

    @Test("handleActivePhase recovers isUploaded scans stuck before inference on foreground with stable connectivity")
    func testHandleActivePhasePlaysBackUploadedScans() async throws {
        let diContainer = AppDIContainer.preview
        let manager = AppLifecycleManager(container: diContainer)
        let offlineManager = diContainer.offlineQueueManager

        let schema = Schema(CurrentSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let stuck = OfflineQueuedScan(localImagePaths: ["stuck.webp"], isDeleted: false, isUploaded: true)
        context.insert(stuck)
        try context.save()

        let originalContext = offlineManager.modelContext
        let originalOnline  = offlineManager.isOnline
        let originalActive  = offlineManager.activeScanUploadIds
        let originalOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        defer {
            offlineManager.modelContext        = originalContext
            offlineManager.isOnline            = originalOnline
            offlineManager.activeScanUploadIds = originalActive
            UserDefaults.standard.set(originalOnboarding, forKey: "hasCompletedOnboarding")
        }

        offlineManager.modelContext        = context
        offlineManager.isOnline            = true
        offlineManager.activeScanUploadIds = []
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

        manager.handleActivePhase()
        // Allow the inner Task {} in handleActivePhase one scheduling tick.
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(
            offlineManager.activeScanUploadIds.contains(stuck.id),
            "handleActivePhase must call replayInferenceForUploadedScans() so scans stuck mid-inference are recovered on foreground, not just on connectivity change"
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
        #expect(engine.isProcessing == false, "Engine should safely clear the processing state after backgrounding")
    }
}
