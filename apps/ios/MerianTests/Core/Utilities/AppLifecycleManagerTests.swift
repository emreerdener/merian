import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct AppLifecycleManagerTests {

    @Test("Foreground maintenance requires both onboarding and current consent", arguments: [false, true], [false, true])
    func foregroundMaintenanceAdmission(onboarded: Bool, granted: Bool) throws {
        let diContainer = AppDIContainer.preview
        let consentFixture = try makeConsentFixture(granted: granted)
        let originalConsentManager = diContainer.consentManager
        let originalOnboarding = diContainer.appSettings.hasCompletedOnboarding
        defer {
            diContainer.appSettings.hasCompletedOnboarding = originalOnboarding
            diContainer.consentManager = originalConsentManager
            consentFixture.removePersistentState()
        }
        var maintenanceCount = 0
        let manager = AppLifecycleManager(
            container: diContainer,
            retryPurchaseIdentityReadiness: {},
            synchronizeConsent: {},
            authorizedForegroundWork: { maintenanceCount += 1 }
        )
        diContainer.consentManager = consentFixture.manager
        diContainer.appSettings.hasCompletedOnboarding = onboarded

        manager.handleActivePhase()

        #expect(maintenanceCount == (onboarded && granted ? 1 : 0))
    }

    @Test("handleActivePhase retries the exact purchase identity while consent is closed")
    func testHandleActivePhaseRetriesPurchaseIdentityWithoutConsent() async throws {
        let diContainer = AppDIContainer.preview
        let consentFixture = try makeConsentFixture(granted: false)
        let originalConsentManager = diContainer.consentManager
        let originalOnboarding = diContainer.appSettings.hasCompletedOnboarding
        var retryCount = 0
        let manager = AppLifecycleManager(
            container: diContainer,
            retryPurchaseIdentityReadiness: {
                retryCount += 1
            },
            synchronizeConsent: {}
        )
        defer {
            diContainer.appSettings.hasCompletedOnboarding = originalOnboarding
            diContainer.consentManager = originalConsentManager
            consentFixture.removePersistentState()
        }

        diContainer.consentManager = consentFixture.manager
        diContainer.appSettings.hasCompletedOnboarding = true
        manager.handleActivePhase()

        let deadline = Date().addingTimeInterval(1)
        while retryCount == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(retryCount == 1)
    }

    @Test("handleBackgroundPhase is a no-op on the inference engine — scan durability is handled at submission time")
    func testHandleBackgroundPhaseDoesNotMutateEngine() async {
        // Arrange
        let diContainer = AppDIContainer.preview
        let manager = AppLifecycleManager(container: diContainer)
        let engine = diContainer.inferenceEngine
        let timestampKey = UserDefaultsKeys.lastBackgroundedDate
        let previousTimestamp = UserDefaults.standard.object(forKey: timestampKey)
        defer { UserDefaults.standard.set(previousTimestamp, forKey: timestampKey) }

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

    @Test func liveForegroundMaintenanceRoutesToTheDurableQueueScheduler() throws {
        let sourcePath = URL(fileURLWithPath: #filePath).path.replacingOccurrences(
            of: "/MerianTests/Core/Utilities/AppLifecycleManagerTests.swift",
            with: "/Merian/Core/Utilities/AppLifecycleManager.swift"
        )
        let source = try String(contentsOfFile: sourcePath, encoding: .utf8)
        #expect(source.contains("await OfflineJobScheduler.shared.drainRunnableJobs("))
        #expect(source.contains("using: container.offlineQueueManager"))
    }

    private func makeConsentFixture(granted: Bool) throws -> ConsentFixture {
        let suiteName = "AppLifecycleManagerTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let manager = ConsentManager(userDefaults: userDefaults)
        if granted {
            try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
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
