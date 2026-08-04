import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite(.serialized)
@MainActor
struct AppLifecycleManagerTests {

    @Test("handleActivePhase recovers .staged scans stuck before inference on foreground with stable connectivity")
    func testHandleActivePhasePlaysBackStagedScans() async throws {
        let diContainer = AppDIContainer.preview
        let consentFixture = try makeConsentFixture(granted: true)
        let originalConsentManager = diContainer.consentManager
        diContainer.consentManager = consentFixture.manager
        let manager = AppLifecycleManager(container: diContainer)
        let offlineManager = diContainer.offlineQueueManager

        let originalContext    = offlineManager.modelContext
        let originalOnline     = offlineManager.isOnline
        let originalReconciled = offlineManager.hasReconciledStartupState
        let originalOnboarding = diContainer.appSettings.hasCompletedOnboarding
        defer {
            offlineManager.modelContext              = originalContext
            offlineManager.isOnline                  = originalOnline
            offlineManager.hasReconciledStartupState = originalReconciled
            offlineManager.replayedStagedScanCount   = 0
            diContainer.appSettings.hasCompletedOnboarding = originalOnboarding
            diContainer.consentManager = originalConsentManager
            consentFixture.removePersistentState()
        }

        let context = try makeStagedQueueContext()
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

    @Test("handleActivePhase does not drain staged scans while required consent is closed")
    func testHandleActivePhaseDoesNotPlayBackStagedScansWithoutConsent() async throws {
        let diContainer = AppDIContainer.preview
        let consentFixture = try makeConsentFixture(granted: false)
        let originalConsentManager = diContainer.consentManager
        diContainer.consentManager = consentFixture.manager
        let manager = AppLifecycleManager(container: diContainer)
        let offlineManager = diContainer.offlineQueueManager

        let originalContext = offlineManager.modelContext
        let originalOnline = offlineManager.isOnline
        let originalReconciled = offlineManager.hasReconciledStartupState
        let originalOnboarding = diContainer.appSettings.hasCompletedOnboarding
        defer {
            offlineManager.modelContext = originalContext
            offlineManager.isOnline = originalOnline
            offlineManager.hasReconciledStartupState = originalReconciled
            offlineManager.replayedStagedScanCount = 0
            diContainer.appSettings.hasCompletedOnboarding = originalOnboarding
            diContainer.consentManager = originalConsentManager
            consentFixture.removePersistentState()
        }

        let context = try makeStagedQueueContext()
        offlineManager.modelContext = context
        offlineManager.isOnline = true
        offlineManager.hasReconciledStartupState = true
        offlineManager.replayedStagedScanCount = 0
        diContainer.appSettings.hasCompletedOnboarding = true

        manager.handleActivePhase()
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(
            offlineManager.replayedStagedScanCount == 0,
            "handleActivePhase must not drain provider work before current adult, Terms, and Gemini evidence exists"
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

    @Test("handleActivePhase does not eagerly create anonymous Supabase sessions")
    func testHandleActivePhaseDoesNotEagerlyInitializeGhostSession() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourcePath = testFileURL.path.replacingOccurrences(
            of: "/MerianTests/Core/Utilities/AppLifecycleManagerTests.swift",
            with: "/Merian/Core/Utilities/AppLifecycleManager.swift"
        )
        let source = try String(contentsOfFile: sourcePath, encoding: .utf8)

        #expect(
            !source.contains("initializeGhostSession"),
            "Foreground lifecycle should not create ghost users by itself; authenticated cloud calls can initialize a session on demand."
        )
    }

    private func makeStagedQueueContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let encodedMedia = try JSONEncoder().encode([
            SerializedMediaItem.image("stuck.webp")
        ])

        // Scan fully uploaded to R2 but inference was interrupted before completion.
        context.insert(OfflineQueuedScan(
            capturedMediaJSON: String(bytes: encodedMedia, encoding: .utf8),
            scanState: .staged,
            stagedR2Keys: ["staging/test-user/stuck.webp"]
        ))
        try context.save()
        return context
    }

    private func makeConsentFixture(granted: Bool) throws -> ConsentFixture {
        let suiteName = "AppLifecycleManagerTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let manager = ConsentManager(userDefaults: userDefaults)
        if granted {
            manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
                analyticsEnabled: false
            )
        }
        return ConsentFixture(
            manager: manager,
            userDefaults: userDefaults,
            suiteName: suiteName
        )
    }

    private struct ConsentFixture {
        let manager: ConsentManager
        let userDefaults: UserDefaults
        let suiteName: String

        func removePersistentState() {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
    }
}
