@testable import Merian
import SwiftUI
import XCTest

private enum RequiredConsentSynchronizationStubError: Error {
    case unavailable
}

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    
    var viewModel: OnboardingViewModel!
    var appSettings: AppSettings!
    var consentManager: ConsentManager!
    var userDefaults: UserDefaults!
    var suiteName: String!
    
    override func setUp() {
        super.setUp()
        suiteName = "merian.tests.onboarding.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        appSettings = AppSettings(userDefaults: userDefaults, observeExternalChanges: false)
        consentManager = ConsentManager(userDefaults: userDefaults)
        appSettings.hasCompletedOnboarding = false
        viewModel = OnboardingViewModel(
            appSettings: appSettings,
            consentManager: consentManager
        )
    }
    
    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        viewModel = nil
        appSettings = nil
        consentManager = nil
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }
    
    func testInitialStateIsWelcome() {
        XCTAssertEqual(viewModel.currentStep, .welcome, "ViewModel should strictly start at the .welcome step on cold boot.")
        XCTAssertFalse(viewModel.hasCompletedOnboarding, "AppStorage bypass flag should explicitly be false initially.")
    }

    func testMissingConsentWaitsForInitialSessionBeforePresentation() {
        XCTAssertEqual(
            consentManager.requiredConsentRestorationState,
            .awaitingInitialSession
        )
        XCTAssertTrue(consentManager.isRestoringRequiredConsent)

        consentManager.observeSession(userId: nil)

        XCTAssertEqual(consentManager.requiredConsentRestorationState, .resolved)
        XCTAssertFalse(consentManager.isRestoringRequiredConsent)
    }

    func testMissingAccountConsentWaitsUntilAuthoritativeMergeCompletes() throws {
        let ownerUserId = UUID()
        let store = FaultInjectingConsentLedgerStore()
        let manager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId },
            analyticsPermissionApplier: { _, _ in }
        )

        manager.observeSession(userId: ownerUserId)

        XCTAssertEqual(
            manager.requiredConsentRestorationState,
            .reconciling(userId: ownerUserId)
        )
        XCTAssertTrue(manager.isRestoringRequiredConsent)

        try manager.merge(
            ConsentManager.RemoteState(
                adultEligibilityReceipt: nil,
                termsReceipt: nil,
                aiConsentEvent: nil,
                analyticsConsentEvent: nil,
                aiConsentStreamHead: nil,
                analyticsConsentStreamHead: nil
            ),
            for: ownerUserId,
            generation: 1
        )

        XCTAssertEqual(manager.requiredConsentRestorationState, .resolved)
        XCTAssertFalse(manager.isRestoringRequiredConsent)
        XCTAssertFalse(manager.hasCurrentRequiredConsent)

        manager.observeSession(userId: ownerUserId)

        XCTAssertEqual(
            manager.requiredConsentRestorationState,
            .resolved,
            "A duplicate auth event must not put a resolved account back behind the launch gate."
        )
        XCTAssertFalse(manager.isRestoringRequiredConsent)
    }

    func testSynchronizationFailureRetainsNeutralRestorationUntilMerge() async throws {
        let ownerUserId = UUID()
        var synchronizationAttempts = 0
        let manager = ConsentManager(
            ledgerStore: FaultInjectingConsentLedgerStore(),
            currentSDKUserIdProvider: { ownerUserId },
            analyticsPermissionApplier: { _, _ in },
            synchronizationOperation: { _, _ in
                synchronizationAttempts += 1
                throw RequiredConsentSynchronizationStubError.unavailable
            }
        )
        manager.observeSession(userId: ownerUserId)

        for attempt in 1...ConsentManager.maximumAutomaticRestorationRetries {
            do {
                try await manager.synchronize(for: ownerUserId)
                XCTFail("A synchronization failure must propagate to its caller.")
            } catch {
                XCTAssertTrue(
                    error is RequiredConsentSynchronizationStubError
                )
            }

            XCTAssertEqual(
                manager.requiredConsentRestorationState,
                .waitingToRetry(userId: ownerUserId, attempt: attempt)
            )
            if attempt == 1 {
                manager.observeSession(userId: ownerUserId)
                XCTAssertEqual(
                    manager.requiredConsentRestorationState,
                    .waitingToRetry(userId: ownerUserId, attempt: attempt),
                    "A repeated auth event must not consume the retry budget."
                )
            }
            XCTAssertTrue(manager.isRestoringRequiredConsent)
            XCTAssertTrue(manager.canRetryRequiredConsentRestoration)
            XCTAssertEqual(
                AppRootPresentationPolicy.presentation(
                    hasCompletedOnboarding: true,
                    hasCurrentRequiredConsent: manager.hasCurrentRequiredConsent,
                    isRestoringRequiredConsent: manager.isRestoringRequiredConsent
                ),
                .restoringConsent
            )
            XCTAssertTrue(manager.beginRequiredConsentRestorationRetry(
                for: ownerUserId,
                generation: 1,
                attempt: attempt
            ))
        }

        do {
            try await manager.synchronize(for: ownerUserId)
            XCTFail("An exhausted synchronization failure must still propagate.")
        } catch {
            XCTAssertTrue(error is RequiredConsentSynchronizationStubError)
        }

        XCTAssertEqual(
            manager.requiredConsentRestorationState,
            .retryRequired(userId: ownerUserId)
        )
        XCTAssertTrue(manager.isRestoringRequiredConsent)
        XCTAssertTrue(manager.canRetryRequiredConsentRestoration)
        XCTAssertEqual(synchronizationAttempts, 4)

        manager.retryRequiredConsentRestoration()

        XCTAssertEqual(
            manager.requiredConsentRestorationState,
            .reconciling(userId: ownerUserId)
        )
        XCTAssertTrue(manager.isRestoringRequiredConsent)
        XCTAssertFalse(manager.canRetryRequiredConsentRestoration)

        try manager.merge(
            ConsentManager.RemoteState(
                adultEligibilityReceipt: nil,
                termsReceipt: nil,
                aiConsentEvent: nil,
                analyticsConsentEvent: nil,
                aiConsentStreamHead: nil,
                analyticsConsentStreamHead: nil
            ),
            for: ownerUserId,
            generation: 1
        )

        XCTAssertEqual(manager.requiredConsentRestorationState, .resolved)
        XCTAssertFalse(manager.isRestoringRequiredConsent)
        XCTAssertEqual(
            AppRootPresentationPolicy.presentation(
                hasCompletedOnboarding: true,
                hasCurrentRequiredConsent: manager.hasCurrentRequiredConsent,
                isRestoringRequiredConsent: manager.isRestoringRequiredConsent
            ),
            .onboarding
        )
    }

    func testPersistenceFailureKeepsConsentRestorationRetryable() async throws {
        let ownerUserId = UUID()
        let store = FaultInjectingConsentLedgerStore()
        weak var weakManager: ConsentManager?
        let manager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId },
            analyticsPermissionApplier: { _, _ in },
            synchronizationOperation: { userId, generation in
                guard let manager = weakManager else {
                    throw RequiredConsentSynchronizationStubError.unavailable
                }
                try manager.merge(
                    ConsentManager.RemoteState(
                        adultEligibilityReceipt: nil,
                        termsReceipt: nil,
                        aiConsentEvent: nil,
                        analyticsConsentEvent: nil,
                        aiConsentStreamHead: nil,
                        analyticsConsentStreamHead: nil
                    ),
                    for: userId,
                    generation: generation
                )
            }
        )
        weakManager = manager
        manager.observeSession(userId: ownerUserId)
        store.failLedgerWrites = true

        do {
            try await manager.synchronize(for: ownerUserId)
            XCTFail("A failed durable merge must propagate to its caller.")
        } catch {
            XCTAssertTrue(error is FaultInjectingConsentLedgerStore.Failure)
        }

        XCTAssertEqual(
            manager.requiredConsentRestorationState,
            .waitingToRetry(userId: ownerUserId, attempt: 1)
        )
        XCTAssertTrue(manager.isRestoringRequiredConsent)

        store.failLedgerWrites = false
        XCTAssertTrue(manager.beginRequiredConsentRestorationRetry(
            for: ownerUserId,
            generation: 1,
            attempt: 1
        ))
        try await manager.synchronize(for: ownerUserId)

        XCTAssertEqual(manager.requiredConsentRestorationState, .resolved)
        XCTAssertFalse(manager.isRestoringRequiredConsent)
    }

    func testRequiredConsentRestorationRetryCannotCrossAccountSwitch() async {
        let firstUserId = UUID()
        let secondUserId = UUID()
        var sdkUserId: UUID? = firstUserId
        let manager = ConsentManager(
            ledgerStore: FaultInjectingConsentLedgerStore(),
            currentSDKUserIdProvider: { sdkUserId },
            analyticsPermissionApplier: { _, _ in },
            synchronizationOperation: { _, _ in
                throw RequiredConsentSynchronizationStubError.unavailable
            }
        )
        manager.observeSession(userId: firstUserId)

        do {
            try await manager.synchronize(for: firstUserId)
            XCTFail("The synchronization stub must fail.")
        } catch {
            XCTAssertTrue(error is RequiredConsentSynchronizationStubError)
        }
        XCTAssertEqual(
            manager.requiredConsentRestorationState,
            .waitingToRetry(userId: firstUserId, attempt: 1)
        )

        sdkUserId = secondUserId
        manager.observeSession(userId: secondUserId)

        XCTAssertFalse(manager.beginRequiredConsentRestorationRetry(
            for: firstUserId,
            generation: 1,
            attempt: 1
        ))
        XCTAssertEqual(
            manager.requiredConsentRestorationState,
            .reconciling(userId: secondUserId)
        )
        XCTAssertTrue(manager.isRestoringRequiredConsent)
    }

    func testSynchronizationInvalidationCannotOrphanAWaitingRetry() async {
        let ownerUserId = UUID()
        let manager = ConsentManager(
            ledgerStore: FaultInjectingConsentLedgerStore(),
            currentSDKUserIdProvider: { ownerUserId },
            analyticsPermissionApplier: { _, _ in },
            synchronizationOperation: { _, _ in
                throw RequiredConsentSynchronizationStubError.unavailable
            }
        )
        manager.observeSession(userId: ownerUserId)

        do {
            try await manager.synchronize(for: ownerUserId)
            XCTFail("The synchronization stub must fail.")
        } catch {
            XCTAssertTrue(error is RequiredConsentSynchronizationStubError)
        }
        XCTAssertEqual(
            manager.requiredConsentRestorationState,
            .waitingToRetry(userId: ownerUserId, attempt: 1)
        )

        let transitionGeneration = manager.beginAnalyticsAccountTransition()

        XCTAssertEqual(
            manager.requiredConsentRestorationState,
            .reconciling(userId: ownerUserId),
            "Invalidation must not leave a waiting state after its timer is cancelled."
        )
        XCTAssertFalse(manager.canRetryRequiredConsentRestoration)
        XCTAssertTrue(manager.resolveAnalyticsAccountTransition(
            generation: transitionGeneration,
            userId: ownerUserId
        ))

        do {
            try await manager.synchronize(for: ownerUserId)
            XCTFail("The synchronization stub must fail.")
        } catch {
            XCTAssertTrue(error is RequiredConsentSynchronizationStubError)
        }
        XCTAssertEqual(
            manager.requiredConsentRestorationState,
            .waitingToRetry(userId: ownerUserId, attempt: 1),
            "The new synchronization generation must receive a fresh retry budget."
        )
    }
    
    func testAdvanceStepProgression() {
        // Initial boundary is welcome
        XCTAssertEqual(viewModel.currentStep, .welcome)
        
        // Sequence: welcome -> camera
        viewModel.advanceStep()
        XCTAssertEqual(viewModel.currentStep, .camera)
        
        // Sequence: camera -> location
        viewModel.advanceStep()
        XCTAssertEqual(viewModel.currentStep, .location)
        
        // Sequence: location -> ready
        viewModel.advanceStep()
        XCTAssertEqual(viewModel.currentStep, .ready)
        
        // Attempting to advance past .ready should securely trap without crashing Swift's Int boundary indices natively.
        viewModel.advanceStep()
        XCTAssertEqual(viewModel.currentStep, .ready, "ViewModel should actively trap progression at .ready boundary without out-of-bounds scalar execution crashes.")
    }
    
    func testCompleteOnboarding() throws {
        // Assume user advanced sequentially to completion
        viewModel.currentStep = .ready
        
        // Fire completion
        try viewModel.completeOnboarding(analyticsEnabled: false)
        
        // Verify AppStorage binding actually triggers the physical override
        XCTAssertTrue(viewModel.hasCompletedOnboarding, "The completeOnboarding physical action MUST explicitly flip the global teardown flag in SwiftUI memory.")
        XCTAssertTrue(userDefaults.bool(forKey: UserDefaultsKeys.hasCompletedOnboarding), "The injected defaults mapping must confirm persistence for WindowGroup reconfiguration on next launch.")
        XCTAssertTrue(consentManager.hasConfirmedCurrentAdultEligibility)
        XCTAssertTrue(consentManager.hasAcceptedCurrentTerms)
        XCTAssertTrue(consentManager.hasGrantedCurrentGeminiProcessing)
        XCTAssertFalse(consentManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertTrue(consentManager.hasCurrentRequiredConsent)
        XCTAssertEqual(consentManager.pendingCloudRecordCount, 3)

        let restoredManager = ConsentManager(userDefaults: userDefaults)
        XCTAssertTrue(restoredManager.hasCurrentRequiredConsent)
        XCTAssertFalse(restoredManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(restoredManager.pendingCloudRecordCount, 3)
    }

    func testOnboardingDoesNotCompleteUntilLedgerWriteIsVerified() throws {
        let store = FaultInjectingConsentLedgerStore()
        store.failLedgerWrites = true
        let manager = ConsentManager(ledgerStore: store)
        let model = OnboardingViewModel(
            appSettings: appSettings,
            consentManager: manager
        )
        model.currentStep = .ready

        XCTAssertThrowsError(
            try model.completeOnboarding(analyticsEnabled: false)
        )
        XCTAssertFalse(model.hasCompletedOnboarding)
        XCTAssertFalse(manager.hasCurrentRequiredConsent)
        XCTAssertNil(store.ledgerData)

        store.failLedgerWrites = false
        try model.completeOnboarding(analyticsEnabled: false)

        XCTAssertTrue(model.hasCompletedOnboarding)
        XCTAssertTrue(manager.hasCurrentRequiredConsent)
        XCTAssertNotNil(store.ledgerData)
    }

    func testFailedAnalyticsRevocationRemainsOffAcrossRestartAndReplaysExactEvent() throws {
        let store = FaultInjectingConsentLedgerStore()
        let ownerUserId = UUID()
        let manager = ConsentManager(ledgerStore: store)
        manager.observeSession(userId: ownerUserId)
        try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )
        XCTAssertTrue(manager.hasGrantedCurrentPostHogAnalytics)

        store.operations.removeAll()
        store.failLedgerWrites = true
        XCTAssertThrowsError(
            try manager.setPostHogAnalyticsEnabled(false)
        )
        XCTAssertFalse(manager.hasGrantedCurrentPostHogAnalytics)
        let intentData = try XCTUnwrap(store.revocationIntentData)
        let journal = try JSONDecoder().decode(
            ConsentManager.AnalyticsRevocationJournal.self,
            from: intentData
        )
        let intent = try XCTUnwrap(journal.intents.last)
        XCTAssertEqual(
            journal.formatVersion,
            ConsentManager.AnalyticsRevocationJournal.currentFormatVersion
        )
        XCTAssertEqual(intent.event.eventKind, .revoked)
        XCTAssertEqual(intent.event.ownerUserId, ownerUserId)
        XCTAssertEqual(store.operations, ["saveIntent", "saveLedger"])

        let restoredWhileStorageFails = ConsentManager(ledgerStore: store)
        restoredWhileStorageFails.observeSession(userId: ownerUserId)
        XCTAssertFalse(
            restoredWhileStorageFails.hasGrantedCurrentPostHogAnalytics
        )
        XCTAssertEqual(store.revocationIntentData, intentData)

        store.failLedgerWrites = false
        try restoredWhileStorageFails.setPostHogAnalyticsEnabled(false)
        XCTAssertFalse(
            restoredWhileStorageFails.hasGrantedCurrentPostHogAnalytics
        )
        XCTAssertNil(store.revocationIntentData)

        let recoveredData = try XCTUnwrap(store.ledgerData)
        let recoveredLedger = try JSONDecoder().decode(
            ConsentManager.LocalLedger.self,
            from: recoveredData
        )
        XCTAssertEqual(
            recoveredLedger.analyticsConsentEvents.last(where: {
                $0.id == intent.event.id
            }),
            intent.event
        )

        let finalRestart = ConsentManager(ledgerStore: store)
        finalRestart.observeSession(userId: ownerUserId)
        XCTAssertFalse(finalRestart.hasGrantedCurrentPostHogAnalytics)
    }

    func testRevocationUsesAtomicLedgerWhenJournalWriteFails() throws {
        let store = FaultInjectingConsentLedgerStore()
        let manager = ConsentManager(ledgerStore: store)
        try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )
        store.failRevocationIntentWrites = true

        XCTAssertNoThrow(
            try manager.setPostHogAnalyticsEnabled(false)
        )
        XCTAssertFalse(manager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertNil(store.revocationIntentData)

        let restored = ConsentManager(ledgerStore: store)
        XCTAssertFalse(restored.hasGrantedCurrentPostHogAnalytics)
    }

    func testRevocationJournalCleanupFailureRemainsOffAcrossRestart() throws {
        let store = FaultInjectingConsentLedgerStore()
        let ownerUserId = UUID()
        let manager = ConsentManager(ledgerStore: store)
        manager.observeSession(userId: ownerUserId)
        try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )
        store.failRevocationIntentClears = true

        XCTAssertNoThrow(
            try manager.setPostHogAnalyticsEnabled(false)
        )
        XCTAssertFalse(manager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertNotNil(store.revocationIntentData)

        let restored = ConsentManager(ledgerStore: store)
        restored.observeSession(userId: ownerUserId)
        XCTAssertFalse(restored.hasGrantedCurrentPostHogAnalytics)
        XCTAssertNotNil(store.revocationIntentData)

        store.failRevocationIntentClears = false
        try restored.setPostHogAnalyticsEnabled(false)

        XCTAssertFalse(restored.hasGrantedCurrentPostHogAnalytics)
        XCTAssertNil(store.revocationIntentData)
    }

    func testRevocationClosesInMemoryGateWhenBothDurableBoundariesFail() throws {
        let store = FaultInjectingConsentLedgerStore()
        let manager = ConsentManager(ledgerStore: store)
        try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )
        store.operations.removeAll()
        store.failRevocationIntentWrites = true
        store.failLedgerWrites = true

        XCTAssertThrowsError(
            try manager.setPostHogAnalyticsEnabled(false)
        )
        XCTAssertFalse(manager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(store.operations, ["saveIntent", "saveLedger"])
    }

    func testRevocationJournalRetainsMultipleAccountsWhenLedgerStaysUnavailable() throws {
        let store = FaultInjectingConsentLedgerStore()
        let firstUserId = UUID()
        let secondUserId = UUID()
        let manager = ConsentManager(ledgerStore: store)
        manager.observeSession(userId: firstUserId)
        try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )
        manager.observeSession(userId: secondUserId)
        try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )

        store.failLedgerWrites = true
        XCTAssertThrowsError(
            try manager.setPostHogAnalyticsEnabled(false)
        )
        manager.observeSession(userId: firstUserId)
        XCTAssertThrowsError(
            try manager.setPostHogAnalyticsEnabled(false)
        )

        let journalData = try XCTUnwrap(store.revocationIntentData)
        let journal = try JSONDecoder().decode(
            ConsentManager.AnalyticsRevocationJournal.self,
            from: journalData
        )
        XCTAssertEqual(journal.intents.count, 2)
        XCTAssertEqual(
            Set(journal.intents.compactMap(\.event.ownerUserId)),
            Set([firstUserId, secondUserId])
        )

        let restored = ConsentManager(ledgerStore: store)
        restored.observeSession(userId: firstUserId)
        XCTAssertFalse(restored.hasGrantedCurrentPostHogAnalytics)
        restored.observeSession(userId: secondUserId)
        XCTAssertFalse(restored.hasGrantedCurrentPostHogAnalytics)

        store.failLedgerWrites = false
        try restored.setPostHogAnalyticsEnabled(false)
        XCTAssertNil(store.revocationIntentData)
        let recoveredData = try XCTUnwrap(store.ledgerData)
        let recoveredLedger = try JSONDecoder().decode(
            ConsentManager.LocalLedger.self,
            from: recoveredData
        )
        let recoveredRevocationOwners = Set(
            recoveredLedger.analyticsConsentEvents
                .filter { $0.eventKind == .revoked }
                .compactMap(\.ownerUserId)
        )
        XCTAssertTrue(recoveredRevocationOwners.contains(firstUserId))
        XCTAssertTrue(recoveredRevocationOwners.contains(secondUserId))
    }

    func testCorruptStoredLedgerCannotBeOverwrittenByOnboarding() {
        let store = FaultInjectingConsentLedgerStore()
        store.ledgerData = Data("not-json".utf8)
        let manager = ConsentManager(ledgerStore: store)
        let originalData = store.ledgerData

        XCTAssertThrowsError(
            try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
                analyticsEnabled: false
            )
        )
        XCTAssertFalse(manager.hasCurrentRequiredConsent)
        XCTAssertFalse(manager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(store.ledgerData, originalData)
    }

    func testDurableStoreAtomicallyMigratesAndVerifiesLegacyLedger() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ConsentLedgerStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyData = Data("legacy-ledger".utf8)
        let replacementData = Data("replacement-ledger".utf8)
        userDefaults.set(
            legacyData,
            forKey: UserDefaultsKeys.legalConsentLedger
        )
        let store = DurableConsentLedgerStore(
            userDefaults: userDefaults,
            applicationSupportDirectory: root
        )

        XCTAssertEqual(try store.loadLedgerData(), legacyData)
        XCTAssertNil(
            userDefaults.data(forKey: UserDefaultsKeys.legalConsentLedger)
        )
        try store.saveLedgerData(replacementData)
        XCTAssertEqual(try store.loadLedgerData(), replacementData)

        let ledgerURL = root
            .appendingPathComponent("Naturebook", isDirectory: true)
            .appendingPathComponent("Consent", isDirectory: true)
            .appendingPathComponent("ledger-v1.json", isDirectory: false)
        XCTAssertEqual(try Data(contentsOf: ledgerURL), replacementData)
    }

    func testPriorDisclosureVersionsReturnCompletedBetaUserToReadyStep() throws {
        let now = Date()
        let priorLedger = ConsentManager.LocalLedger(
            activeUserId: nil,
            termsReceipts: [
                ConsentManager.TermsAcceptanceReceipt(
                    id: UUID(),
                    ownerUserId: nil,
                    syncedUserId: nil,
                    termsVersion: ConsentPolicy.termsVersion,
                    acceptedAt: now,
                    acceptanceText: ConsentPolicy.combinedAcceptanceText,
                    platform: "ios",
                    appVersion: "1.0.3",
                    appBuild: "275",
                    recordedAt: nil
                )
            ],
            aiConsentEvents: [
                ConsentManager.AIConsentEvent(
                    id: UUID(),
                    ownerUserId: nil,
                    syncedUserId: nil,
                    provider: ConsentPolicy.geminiProvider,
                    disclosureVersion: "2026-08-03.1",
                    eventKind: .granted,
                    occurredAt: now,
                    disclosureText: "Prior internal-test disclosure",
                    actionText: ConsentPolicy.combinedAcceptanceText,
                    platform: "ios",
                    appVersion: "1.0.3",
                    appBuild: "275",
                    recordedAt: nil
                )
            ],
            adultEligibilityReceipts: [
                ConsentManager.AdultEligibilityReceipt(
                    id: UUID(),
                    ownerUserId: nil,
                    syncedUserId: nil,
                    policyVersion: ConsentPolicy.adultEligibilityVersion,
                    confirmedAt: now,
                    confirmationMethod: .selfAttestation,
                    confirmationText: ConsentPolicy.adultConfirmationText,
                    platform: "ios",
                    appVersion: "1.0.3",
                    appBuild: "275",
                    recordedAt: nil
                )
            ],
            analyticsConsentEvents: [
                ConsentManager.AnalyticsConsentEvent(
                    id: UUID(),
                    ownerUserId: nil,
                    syncedUserId: nil,
                    provider: ConsentPolicy.analyticsProvider,
                    disclosureVersion: "2026-08-03",
                    eventKind: .granted,
                    occurredAt: now,
                    disclosureText: "Prior internal-test disclosure",
                    actionText: "Prior internal-test grant",
                    platform: "ios",
                    appVersion: "1.0.3",
                    appBuild: "275",
                    recordedAt: nil
                )
            ]
        )
        userDefaults.set(
            try JSONEncoder().encode(priorLedger),
            forKey: UserDefaultsKeys.legalConsentLedger
        )
        appSettings.hasCompletedOnboarding = true

        let restoredManager = ConsentManager(userDefaults: userDefaults)
        let restoredViewModel = OnboardingViewModel(
            appSettings: appSettings,
            consentManager: restoredManager
        )

        XCTAssertTrue(restoredManager.hasConfirmedCurrentAdultEligibility)
        XCTAssertTrue(restoredManager.hasAcceptedCurrentTerms)
        XCTAssertFalse(restoredManager.hasGrantedCurrentGeminiProcessing)
        XCTAssertFalse(restoredManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertFalse(restoredManager.hasCurrentRequiredConsent)
        XCTAssertEqual(restoredViewModel.currentStep, .ready)
    }

    func testReadyStepMatchesStoredConsentCopyAndPurposeBeforeConsent() {
        let disclosure = ReadyStepView.disclosure
        let consent = ReadyStepView.consentStatement
        let adult = ReadyStepView.adultStatement
        let analytics = ReadyStepView.analyticsStatement

        XCTAssertEqual(disclosure, ConsentPolicy.geminiDisclosureText)
        XCTAssertEqual(consent, ConsentPolicy.combinedAcceptanceText)
        XCTAssertEqual(adult, ConsentPolicy.adultConfirmationText)
        XCTAssertEqual(analytics, ConsentPolicy.analyticsDisclosureText)

        let completeSurface = [disclosure, consent, adult, analytics].joined(separator: " ")
        for requiredDisclosure in [
            "observation data",
            "terms",
            "Google Gemini",
            "AI-powered identification",
            "18 or older",
            "usage and diagnostics",
            "improve Naturebook"
        ] {
            XCTAssertTrue(
                completeSurface.contains(requiredDisclosure),
                "Ready-step disclosure must identify its recipient, data, and purpose: \(requiredDisclosure)"
            )
        }
    }

    func testEveryReadySwitchCombinationKeepsAnalyticsOptional() {
        for adultConfirmed in [false, true] {
            for geminiAllowed in [false, true] {
                for analyticsAllowed in [false, true] {
                    XCTAssertEqual(
                        ReadyStepView.canStartScanning(
                            adultConfirmed: adultConfirmed,
                            geminiAllowed: geminiAllowed,
                            analyticsAllowed: analyticsAllowed
                        ),
                        adultConfirmed && geminiAllowed
                    )
                }
            }
        }
    }

    func testReadyTermsLinkTargetsTheFullTermsOfService() throws {
        let statement = ReadyStepView.linkedConsentStatement
        let termsRange = try XCTUnwrap(statement.range(of: "terms"))

        XCTAssertEqual(statement[termsRange].link, ReadyStepView.termsURL)
        XCTAssertTrue(ReadyStepView.termsURL.absoluteString.hasSuffix("/terms"))
    }

    func testReadyRequiredConsentStatementsEndWithRedAsterisk() throws {
        let statements = [
            ReadyStepView.appendingRequiredIndicator(
                to: AttributedString(ReadyStepView.adultStatement)
            ),
            ReadyStepView.linkedConsentStatement
        ]

        for statement in statements {
            XCTAssertTrue(
                String(statement.characters).hasSuffix(ReadyStepView.requiredIndicator)
            )
            let indicatorRange = try XCTUnwrap(statement.range(of: "*"))
            XCTAssertEqual(statement[indicatorRange].foregroundColor, Color.red)
        }

        XCTAssertFalse(ReadyStepView.analyticsStatement.hasSuffix("*"))
    }

    func testLegacyCompletionRoutesDirectlyToCurrentConsentStep() {
        appSettings.hasCompletedOnboarding = true

        let legacyViewModel = OnboardingViewModel(
            appSettings: appSettings,
            consentManager: consentManager
        )

        XCTAssertEqual(legacyViewModel.currentStep, .ready)
    }

    func testGeminiWithdrawalIsPersistedAndClosesConsentGate() throws {
        try consentManager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: false
        )
        try consentManager.withdrawGeminiPermission()

        XCTAssertTrue(consentManager.hasConfirmedCurrentAdultEligibility)
        XCTAssertTrue(consentManager.hasAcceptedCurrentTerms)
        XCTAssertFalse(consentManager.hasGrantedCurrentGeminiProcessing)
        XCTAssertFalse(consentManager.hasCurrentRequiredConsent)
        XCTAssertEqual(consentManager.pendingCloudRecordCount, 4)

        let restoredManager = ConsentManager(userDefaults: userDefaults)
        XCTAssertFalse(restoredManager.hasCurrentRequiredConsent)
        XCTAssertEqual(restoredManager.pendingCloudRecordCount, 4)
    }

    func testOptionalAnalyticsGrantAndWithdrawalNeverCloseRequiredGate() throws {
        viewModel.currentStep = .ready
        try viewModel.completeOnboarding(analyticsEnabled: true)

        XCTAssertTrue(consentManager.hasCurrentRequiredConsent)
        XCTAssertTrue(consentManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(consentManager.pendingCloudRecordCount, 4)

        try consentManager.setPostHogAnalyticsEnabled(false)

        XCTAssertTrue(consentManager.hasCurrentRequiredConsent)
        XCTAssertFalse(consentManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(consentManager.pendingCloudRecordCount, 5)

        let restoredManager = ConsentManager(userDefaults: userDefaults)
        XCTAssertTrue(restoredManager.hasCurrentRequiredConsent)
        XCTAssertFalse(restoredManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(restoredManager.pendingCloudRecordCount, 5)
    }

    func testAccountSwitchNeverInheritsPriorAccountConsent() throws {
        let firstUserId = UUID()
        let secondUserId = UUID()
        consentManager.observeSession(userId: firstUserId)
        try consentManager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )

        XCTAssertTrue(consentManager.hasCurrentRequiredConsent)
        XCTAssertTrue(consentManager.hasGrantedCurrentPostHogAnalytics)

        consentManager.observeSession(userId: secondUserId)

        XCTAssertFalse(consentManager.hasConfirmedCurrentAdultEligibility)
        XCTAssertFalse(consentManager.hasAcceptedCurrentTerms)
        XCTAssertFalse(consentManager.hasGrantedCurrentGeminiProcessing)
        XCTAssertFalse(consentManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertFalse(consentManager.hasCurrentRequiredConsent)

        consentManager.observeSession(userId: nil)
        XCTAssertFalse(consentManager.hasCurrentRequiredConsent)
        XCTAssertFalse(consentManager.hasGrantedCurrentPostHogAnalytics)
    }

    func testOverlappingAccountTransitionsOnlyNewestResolutionReopensAnalytics() throws {
        let originalUserId = UUID()
        let replacementUserId = UUID()
        consentManager.observeSession(userId: originalUserId)
        try consentManager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )

        let firstGeneration = consentManager.beginAnalyticsAccountTransition()
        let secondGeneration = consentManager.beginAnalyticsAccountTransition()
        XCTAssertTrue(consentManager.isAnalyticsSuppressedForAccountTransition)

        XCTAssertFalse(
            consentManager.resolveAnalyticsAccountTransition(
                generation: firstGeneration,
                userId: originalUserId
            )
        )
        XCTAssertTrue(consentManager.isAnalyticsSuppressedForAccountTransition)
        XCTAssertEqual(consentManager.currentSessionUserId, originalUserId)

        XCTAssertTrue(
            consentManager.resolveAnalyticsAccountTransition(
                generation: secondGeneration,
                userId: replacementUserId
            )
        )
        XCTAssertFalse(consentManager.isAnalyticsSuppressedForAccountTransition)
        XCTAssertEqual(consentManager.currentSessionUserId, replacementUserId)
        XCTAssertFalse(consentManager.hasGrantedCurrentPostHogAnalytics)
    }

    func testSynchronizationContextRequiresCurrentUncancelledAccount() {
        let expectedUserId = UUID()
        let otherUserId = UUID()
        let expectedGeneration: UInt = 7

        XCTAssertTrue(
            ConsentManager.isSynchronizationContextCurrent(
                expectedUserId: expectedUserId,
                expectedGeneration: expectedGeneration,
                observedUserId: expectedUserId,
                sdkUserId: expectedUserId,
                currentGeneration: expectedGeneration,
                isCancelled: false
            )
        )

        let invalidContexts: [(UUID?, UUID?, UInt, Bool)] = [
            (otherUserId, expectedUserId, expectedGeneration, false),
            (nil, expectedUserId, expectedGeneration, false),
            (expectedUserId, otherUserId, expectedGeneration, false),
            (expectedUserId, nil, expectedGeneration, false),
            (expectedUserId, expectedUserId, expectedGeneration + 1, false),
            (expectedUserId, expectedUserId, expectedGeneration, true)
        ]

        for (observedUserId, sdkUserId, currentGeneration, isCancelled) in invalidContexts {
            XCTAssertFalse(
                ConsentManager.isSynchronizationContextCurrent(
                    expectedUserId: expectedUserId,
                    expectedGeneration: expectedGeneration,
                    observedUserId: observedUserId,
                    sdkUserId: sdkUserId,
                    currentGeneration: currentGeneration,
                    isCancelled: isCancelled
                )
            )
        }
    }

    func testStaleSynchronizationMergeCannotMutateReplacementAccountLedger() throws {
        let originalUserId = UUID()
        let replacementUserId = UUID()
        consentManager.observeSession(userId: originalUserId)
        try consentManager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )
        consentManager.observeSession(userId: replacementUserId)

        let ledgerBeforeMerge = userDefaults.data(
            forKey: UserDefaultsKeys.legalConsentLedger
        )
        XCTAssertEqual(
            consentManager.analyticsCloudAuthorityState,
            .awaitingRemote(userId: replacementUserId)
        )
        XCTAssertFalse(consentManager.hasGrantedCurrentPostHogAnalytics)

        XCTAssertThrowsError(
            try consentManager.merge(
                ConsentManager.RemoteState(
                    adultEligibilityReceipt: nil,
                    termsReceipt: nil,
                    aiConsentEvent: nil,
                    analyticsConsentEvent: nil,
                    aiConsentStreamHead: nil,
                    analyticsConsentStreamHead: nil
                ),
                for: originalUserId,
                generation: 0
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }

        XCTAssertEqual(consentManager.currentSessionUserId, replacementUserId)
        XCTAssertEqual(
            consentManager.analyticsCloudAuthorityState,
            .awaitingRemote(userId: replacementUserId)
        )
        XCTAssertFalse(consentManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(
            userDefaults.data(forKey: UserDefaultsKeys.legalConsentLedger),
            ledgerBeforeMerge
        )
    }

    func testRestoredCachedAnalyticsGrantStaysClosedUntilRemoteRevocationMerges() throws {
        let store = FaultInjectingConsentLedgerStore()
        let ownerUserId = UUID()
        let localGrant = makeAnalyticsEvent(
            ownerUserId: ownerUserId,
            eventKind: .granted,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_000)
        )
        store.ledgerData = try JSONEncoder().encode(
            ConsentManager.LocalLedger(
                activeUserId: ownerUserId,
                termsReceipts: [],
                aiConsentEvents: [],
                adultEligibilityReceipts: [],
                analyticsConsentEvents: [localGrant]
            )
        )
        var applications: [AppliedAnalyticsPermission] = []
        let manager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId },
            analyticsPermissionApplier: { enabled, userId in
                applications.append(.init(enabled: enabled, userId: userId))
            }
        )

        XCTAssertTrue(manager.hasGrantedCurrentPostHogAnalytics)
        manager.observeSession(userId: ownerUserId)

        XCTAssertEqual(
            manager.analyticsCloudAuthorityState,
            .awaitingRemote(userId: ownerUserId)
        )
        XCTAssertEqual(
            applications,
            [.init(enabled: false, userId: nil)]
        )

        let remoteRevocation = makeAnalyticsEvent(
            ownerUserId: ownerUserId,
            eventKind: .revoked,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_001)
        )
        try manager.merge(
            ConsentManager.RemoteState(
                adultEligibilityReceipt: nil,
                termsReceipt: nil,
                aiConsentEvent: nil,
                analyticsConsentEvent: remoteRevocation,
                aiConsentStreamHead: nil,
                analyticsConsentStreamHead: remoteRevocation
            ),
            for: ownerUserId,
            generation: 1
        )

        XCTAssertEqual(
            manager.analyticsCloudAuthorityState,
            .resolvedRemote(userId: ownerUserId, granted: false)
        )
        XCTAssertFalse(manager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertFalse(applications.contains(where: \.enabled))

        var restartedApplications: [AppliedAnalyticsPermission] = []
        let restarted = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId },
            analyticsPermissionApplier: { enabled, userId in
                restartedApplications.append(
                    .init(enabled: enabled, userId: userId)
                )
            }
        )
        restarted.observeSession(userId: ownerUserId)

        XCTAssertEqual(
            restarted.analyticsCloudAuthorityState,
            .awaitingRemote(userId: ownerUserId)
        )
        XCTAssertEqual(
            restartedApplications,
            [.init(enabled: false, userId: nil)]
        )
    }

    func testRestoredCachedAnalyticsGrantStaysClosedWhenRemoteGrantIsAbsent() throws {
        let store = FaultInjectingConsentLedgerStore()
        let ownerUserId = UUID()
        let localGrant = makeAnalyticsEvent(
            ownerUserId: ownerUserId,
            eventKind: .granted,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_000)
        )
        store.ledgerData = try JSONEncoder().encode(
            ConsentManager.LocalLedger(
                activeUserId: ownerUserId,
                termsReceipts: [],
                aiConsentEvents: [],
                adultEligibilityReceipts: [],
                analyticsConsentEvents: [localGrant]
            )
        )
        var applications: [AppliedAnalyticsPermission] = []
        let manager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId },
            analyticsPermissionApplier: { enabled, userId in
                applications.append(.init(enabled: enabled, userId: userId))
            }
        )

        manager.observeSession(userId: ownerUserId)
        try manager.merge(
            ConsentManager.RemoteState(
                adultEligibilityReceipt: nil,
                termsReceipt: nil,
                aiConsentEvent: nil,
                analyticsConsentEvent: nil,
                aiConsentStreamHead: nil,
                analyticsConsentStreamHead: nil
            ),
            for: ownerUserId,
            generation: 1
        )

        XCTAssertEqual(
            manager.analyticsCloudAuthorityState,
            .resolvedRemote(userId: ownerUserId, granted: false)
        )
        XCTAssertFalse(applications.contains(where: { $0.enabled }))
    }

    func testRestoredAnalyticsGrantOpensOnlyAfterAuthoritativeMerge() throws {
        let store = FaultInjectingConsentLedgerStore()
        let ownerUserId = UUID()
        let remoteGrant = makeAnalyticsEvent(
            ownerUserId: ownerUserId,
            eventKind: .granted,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_000)
        )
        store.ledgerData = try JSONEncoder().encode(
            ConsentManager.LocalLedger(
                activeUserId: ownerUserId,
                termsReceipts: [],
                aiConsentEvents: [],
                adultEligibilityReceipts: [],
                analyticsConsentEvents: [remoteGrant]
            )
        )
        var applications: [AppliedAnalyticsPermission] = []
        let manager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId },
            analyticsPermissionApplier: { enabled, userId in
                applications.append(.init(enabled: enabled, userId: userId))
            }
        )

        manager.observeSession(userId: ownerUserId)
        XCTAssertEqual(applications.map(\.enabled), [false])

        try manager.merge(
            ConsentManager.RemoteState(
                adultEligibilityReceipt: nil,
                termsReceipt: nil,
                aiConsentEvent: nil,
                analyticsConsentEvent: remoteGrant,
                aiConsentStreamHead: nil,
                analyticsConsentStreamHead: remoteGrant
            ),
            for: ownerUserId,
            generation: 1
        )

        XCTAssertEqual(
            manager.analyticsCloudAuthorityState,
            .resolvedRemote(userId: ownerUserId, granted: true)
        )
        XCTAssertEqual(applications.map(\.enabled), [false, true])
        XCTAssertEqual(applications.last?.userId, ownerUserId.uuidString)

        manager.observeSession(userId: ownerUserId)

        XCTAssertEqual(
            manager.analyticsCloudAuthorityState,
            .resolvedRemote(userId: ownerUserId, granted: true)
        )
        XCTAssertEqual(applications.map(\.enabled), [false, true, true])
    }

    func testFailedAuthoritativeMergeKeepsRestoredAnalyticsClosed() throws {
        let store = FaultInjectingConsentLedgerStore()
        let ownerUserId = UUID()
        let localGrant = makeAnalyticsEvent(
            ownerUserId: ownerUserId,
            eventKind: .granted,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_000)
        )
        store.ledgerData = try JSONEncoder().encode(
            ConsentManager.LocalLedger(
                activeUserId: ownerUserId,
                termsReceipts: [],
                aiConsentEvents: [],
                adultEligibilityReceipts: [],
                analyticsConsentEvents: [localGrant]
            )
        )
        var applications: [AppliedAnalyticsPermission] = []
        let manager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId },
            analyticsPermissionApplier: { enabled, userId in
                applications.append(.init(enabled: enabled, userId: userId))
            }
        )
        manager.observeSession(userId: ownerUserId)
        store.failLedgerWrites = true

        XCTAssertThrowsError(
            try manager.merge(
                ConsentManager.RemoteState(
                    adultEligibilityReceipt: nil,
                    termsReceipt: nil,
                    aiConsentEvent: nil,
                    analyticsConsentEvent: localGrant,
                    aiConsentStreamHead: nil,
                    analyticsConsentStreamHead: localGrant
                ),
                for: ownerUserId,
                generation: 1
            )
        )

        XCTAssertEqual(
            manager.analyticsCloudAuthorityState,
            .awaitingRemote(userId: ownerUserId)
        )
        XCTAssertEqual(applications.map(\.enabled), [false])
    }

    func testAnalyticsConsentRealtimeRetryUsesBoundedExponentialBackoff() {
        XCTAssertEqual(ConsentManager.analyticsConsentRetryDelay(attempt: 1), 1)
        XCTAssertEqual(ConsentManager.analyticsConsentRetryDelay(attempt: 2), 2)
        XCTAssertEqual(ConsentManager.analyticsConsentRetryDelay(attempt: 3), 4)
        XCTAssertEqual(ConsentManager.analyticsConsentRetryDelay(attempt: 6), 30)
        XCTAssertEqual(ConsentManager.analyticsConsentRetryDelay(attempt: 100), 30)
    }

    func testRequiredConsentRestorationRetryUsesBoundedBackoff() {
        XCTAssertEqual(
            ConsentManager.maximumAutomaticRestorationRetries,
            3
        )
        XCTAssertEqual(
            ConsentManager.requiredConsentRestorationRetryDelay(attempt: 1),
            5
        )
        XCTAssertEqual(
            ConsentManager.requiredConsentRestorationRetryDelay(attempt: 2),
            10
        )
        XCTAssertEqual(
            ConsentManager.requiredConsentRestorationRetryDelay(attempt: 3),
            20
        )
        XCTAssertEqual(
            ConsentManager.requiredConsentRestorationRetryDelay(attempt: 4),
            30
        )
        XCTAssertEqual(
            ConsentManager.requiredConsentRestorationRetryDelay(attempt: 100),
            30
        )
    }

    private func makeAnalyticsEvent(
        ownerUserId: UUID,
        eventKind: ConsentManager.AnalyticsConsentEventKind,
        recordedAt: Date
    ) -> ConsentManager.AnalyticsConsentEvent {
        ConsentManager.AnalyticsConsentEvent(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            provider: ConsentPolicy.analyticsProvider,
            disclosureVersion: ConsentPolicy.analyticsDisclosureVersion,
            eventKind: eventKind,
            occurredAt: recordedAt.addingTimeInterval(-1),
            disclosureText: ConsentPolicy.analyticsDisclosureText,
            actionText: eventKind == .granted
                ? ConsentPolicy.analyticsDisclosureText
                : ConsentPolicy.analyticsWithdrawalText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: recordedAt
        )
    }
}

private struct AppliedAnalyticsPermission: Equatable {
    let enabled: Bool
    let userId: String?
}

private final class FaultInjectingConsentLedgerStore: ConsentLedgerStoring {
    enum Failure: Error {
        case injected
    }

    var ledgerData: Data?
    var revocationIntentData: Data?
    var failLedgerReads = false
    var failLedgerWrites = false
    var failRevocationIntentReads = false
    var failRevocationIntentWrites = false
    var failRevocationIntentClears = false
    var operations: [String] = []

    func loadLedgerData() throws -> Data? {
        if failLedgerReads { throw Failure.injected }
        return ledgerData
    }

    func saveLedgerData(_ data: Data) throws {
        operations.append("saveLedger")
        if failLedgerWrites { throw Failure.injected }
        ledgerData = data
        guard ledgerData == data else { throw Failure.injected }
    }

    func loadAnalyticsRevocationIntentData() throws -> Data? {
        if failRevocationIntentReads { throw Failure.injected }
        return revocationIntentData
    }

    func saveAnalyticsRevocationIntentData(_ data: Data) throws {
        operations.append("saveIntent")
        if failRevocationIntentWrites { throw Failure.injected }
        revocationIntentData = data
        guard revocationIntentData == data else { throw Failure.injected }
    }

    func clearAnalyticsRevocationIntentData() throws {
        operations.append("clearIntent")
        if failRevocationIntentClears { throw Failure.injected }
        revocationIntentData = nil
        guard revocationIntentData == nil else { throw Failure.injected }
    }
}
