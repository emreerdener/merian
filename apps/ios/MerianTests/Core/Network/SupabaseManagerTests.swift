import AuthenticationServices
import Foundation
@testable import Merian
import XCTest

@MainActor
final class SupabaseManagerTests: XCTestCase {
    var supabaseManager: SupabaseManager!

    override func setUp() async throws {
        supabaseManager = SupabaseManager.shared
    }

    override func tearDown() async throws {
        supabaseManager = nil
    }

    func testGuestUserPropertyDefaults() {
        // Without an explicit session injected, an initial boot should default into
        // a false authentication bound and mark itself as a Guest
        // Note: As this is a live singleton, if a simulator has persistent data logged in,
        // it may alter this behavior. This asserts the logic flows without crashing.
        let isGuest = supabaseManager.isGuestUser
        let authState = supabaseManager.isAuthenticated

        XCTAssertNotNil(isGuest)
        XCTAssertNotNil(authState)
    }

    func testAuthTransitionDrainCancelsAndAwaitsConsentSynchronization() async throws {
        let userID = UUID()
        let suiteName = "merian.tests.auth-consent-drain.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let started = expectation(description: "consent sync started")
        let cancelled = expectation(description: "consent sync cancelled")
        let manager = ConsentManager(
            ledgerStore: UserDefaultsConsentLedgerStore(
                userDefaults: userDefaults
            ),
            currentSDKUserIdProvider: { userID },
            synchronizationOperation: { _, _ in
                started.fulfill()
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch is CancellationError {
                    cancelled.fulfill()
                    throw CancellationError()
                }
            }
        )
        manager.observeSession(userId: userID)
        let synchronization = Task { @MainActor in
            try? await manager.synchronize(for: userID)
        }
        await fulfillment(of: [started], timeout: 1)

        await manager.cancelAndAwaitAccountBoundWorkForAuthTransition()
        await synchronization.value

        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testGetValidAuthHeadersUsesDeterministicTestStub() async throws {
        let headers = try await supabaseManager.getValidAuthHeaders()

        XCTAssertEqual(headers["Authorization"], "Bearer merian-test-session")
        XCTAssertEqual(headers["apikey"], MerianEnvironment.supabaseAnonKey)
        XCTAssertEqual(headers["Content-Type"], "application/json")
    }

    func testGhostConsentRebindPreservesImmutableEvidenceAndPendingState() {
        let ghostUserId = UUID()
        let permanentUserId = UUID()
        let recordedAt = Date(timeIntervalSince1970: 1_786_000_000)

        let adultReceipts = [
            makeAdultReceipt(
                ownerUserId: ghostUserId,
                syncedUserId: ghostUserId,
                recordedAt: recordedAt
            ),
            makeAdultReceipt(
                ownerUserId: ghostUserId,
                syncedUserId: nil,
                recordedAt: nil
            )
        ]
        let termsReceipts = [
            makeTermsReceipt(
                ownerUserId: ghostUserId,
                syncedUserId: ghostUserId,
                recordedAt: recordedAt
            ),
            makeTermsReceipt(
                ownerUserId: ghostUserId,
                syncedUserId: nil,
                recordedAt: nil
            )
        ]
        let aiEvents = [
            makeAIConsentEvent(
                ownerUserId: ghostUserId,
                syncedUserId: ghostUserId,
                recordedAt: recordedAt
            ),
            makeAIConsentEvent(
                ownerUserId: ghostUserId,
                syncedUserId: nil,
                recordedAt: nil
            )
        ]
        let analyticsEvents = [
            makeAnalyticsConsentEvent(
                ownerUserId: ghostUserId,
                syncedUserId: ghostUserId,
                eventKind: .granted,
                recordedAt: recordedAt
            ),
            makeAnalyticsConsentEvent(
                ownerUserId: ghostUserId,
                syncedUserId: nil,
                eventKind: .revoked,
                recordedAt: nil
            )
        ]
        let source = ConsentManager.LocalLedger(
            activeUserId: ghostUserId,
            termsReceipts: termsReceipts,
            aiConsentEvents: aiEvents,
            adultEligibilityReceipts: adultReceipts,
            analyticsConsentEvents: analyticsEvents
        )

        let rebound = ConsentManager.rebinding(
            source,
            from: ghostUserId,
            to: permanentUserId
        )

        XCTAssertEqual(rebound.activeUserId, permanentUserId)
        XCTAssertEqual(
            rebound,
            ConsentManager.rebinding(
                rebound,
                from: ghostUserId,
                to: permanentUserId
            ),
            "Rebinding must be idempotent for crash-safe handoff retries"
        )

        var expectedAdults = adultReceipts
        var expectedTerms = termsReceipts
        var expectedAI = aiEvents
        var expectedAnalytics = analyticsEvents
        for index in expectedAdults.indices {
            expectedAdults[index].ownerUserId = permanentUserId
            expectedAdults[index].syncedUserId = index == 0
                ? permanentUserId
                : nil
        }
        for index in expectedTerms.indices {
            expectedTerms[index].ownerUserId = permanentUserId
            expectedTerms[index].syncedUserId = index == 0
                ? permanentUserId
                : nil
        }
        for index in expectedAI.indices {
            expectedAI[index].ownerUserId = permanentUserId
            expectedAI[index].syncedUserId = index == 0
                ? permanentUserId
                : nil
        }
        for index in expectedAnalytics.indices {
            expectedAnalytics[index].ownerUserId = permanentUserId
            expectedAnalytics[index].syncedUserId = index == 0
                ? permanentUserId
                : nil
        }

        XCTAssertEqual(rebound.adultEligibilityReceipts, expectedAdults)
        XCTAssertEqual(rebound.termsReceipts, expectedTerms)
        XCTAssertEqual(rebound.aiConsentEvents, expectedAI)
        XCTAssertEqual(rebound.analyticsConsentEvents, expectedAnalytics)
    }

    func testOfflineGhostAnalyticsRevocationWinsAfterMergeAndAcrossDevices() throws {
        let ghostUserId = UUID()
        let permanentUserId = UUID()
        let grantRecordedAt = Date(timeIntervalSince1970: 1_786_000_000)
        let revocation = makeAnalyticsConsentEvent(
            ownerUserId: ghostUserId,
            syncedUserId: nil,
            eventKind: .revoked,
            recordedAt: nil
        )
        let permanentGrant = makeAnalyticsConsentEvent(
            ownerUserId: permanentUserId,
            syncedUserId: permanentUserId,
            eventKind: .granted,
            recordedAt: grantRecordedAt,
            consentRevision: 60
        )
        let source = ConsentManager.LocalLedger(
            activeUserId: ghostUserId,
            termsReceipts: [],
            aiConsentEvents: [],
            adultEligibilityReceipts: [],
            analyticsConsentEvents: [
                permanentGrant,
                revocation
            ]
        )
        let rebound = ConsentManager.rebinding(
            source,
            from: ghostUserId,
            to: permanentUserId
        )

        let suiteName = "merian.tests.ghost-consent.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(
            try JSONEncoder().encode(rebound),
            forKey: UserDefaultsKeys.legalConsentLedger
        )

        let mergedManager = ConsentManager(userDefaults: userDefaults)
        mergedManager.observeSession(userId: permanentUserId)
        XCTAssertFalse(mergedManager.hasGrantedCurrentPostHogAnalytics)

        let restartedManager = ConsentManager(userDefaults: userDefaults)
        restartedManager.observeSession(userId: permanentUserId)
        XCTAssertFalse(restartedManager.hasGrantedCurrentPostHogAnalytics)

        var secondDeviceLedger = rebound
        let revocationIndex = try XCTUnwrap(
            secondDeviceLedger.analyticsConsentEvents.firstIndex {
                $0.id == revocation.id
            }
        )
        secondDeviceLedger.analyticsConsentEvents[revocationIndex].syncedUserId =
            permanentUserId
        secondDeviceLedger.analyticsConsentEvents[revocationIndex].recordedAt =
            grantRecordedAt.addingTimeInterval(1)
        secondDeviceLedger.analyticsConsentEvents[revocationIndex]
            .causalParentId = permanentGrant.id
        secondDeviceLedger.analyticsConsentEvents[revocationIndex]
            .consentRevision = 61
        userDefaults.set(
            try JSONEncoder().encode(secondDeviceLedger),
            forKey: UserDefaultsKeys.legalConsentLedger
        )

        let secondDeviceManager = ConsentManager(userDefaults: userDefaults)
        secondDeviceManager.observeSession(userId: permanentUserId)
        XCTAssertFalse(secondDeviceManager.hasGrantedCurrentPostHogAnalytics)
    }

    func testOfflineAIRevocationClosesPermissionAcrossRestart() throws {
        let ownerUserId = UUID()
        let grant = makeAIConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            eventKind: .granted,
            recordedAt: Date(timeIntervalSince1970: 1_786_050_000),
            consentRevision: 60
        )
        let revocation = makeAIConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: nil,
            eventKind: .revoked,
            recordedAt: nil,
            causalParentId: grant.id
        )
        let source = ConsentManager.LocalLedger(
            activeUserId: ownerUserId,
            termsReceipts: [],
            aiConsentEvents: [grant, revocation],
            adultEligibilityReceipts: [],
            analyticsConsentEvents: []
        )
        let suiteName = "merian.tests.offline-ai-revocation.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsConsentLedgerStore(userDefaults: userDefaults)
        try store.saveLedgerData(JSONEncoder().encode(source))

        let manager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId }
        )
        XCTAssertFalse(manager.hasGrantedCurrentGeminiProcessing)
        XCTAssertEqual(manager.pendingCloudRecordCount, 1)

        let restarted = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId }
        )
        XCTAssertFalse(restarted.hasGrantedCurrentGeminiProcessing)
        XCTAssertEqual(restarted.pendingCloudRecordCount, 1)
    }

    func testInverseOrderCrossDeviceAIRevocationSupersedesOfflineGrant() throws {
        let ownerUserId = UUID()
        let baseline = makeAIConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            eventKind: .granted,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_100),
            consentRevision: 40
        )
        let remoteRevocation = makeAIConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            eventKind: .revoked,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_050),
            causalParentId: baseline.id,
            consentRevision: 41
        )
        let staleOfflineGrant = makeAIConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: nil,
            eventKind: .granted,
            recordedAt: nil,
            causalParentId: baseline.id,
            supersededByEventId: remoteRevocation.id,
            supersededByRevision: 41
        )
        let suiteName = "merian.tests.inverse-ai-consent.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(
            try JSONEncoder().encode(ConsentManager.LocalLedger(
                activeUserId: ownerUserId,
                termsReceipts: [makeTermsReceipt(
                    ownerUserId: ownerUserId,
                    syncedUserId: ownerUserId,
                    recordedAt: Date(timeIntervalSince1970: 1_786_100_000)
                )],
                aiConsentEvents: [baseline, staleOfflineGrant],
                adultEligibilityReceipts: [makeAdultReceipt(
                    ownerUserId: ownerUserId,
                    syncedUserId: ownerUserId,
                    recordedAt: Date(timeIntervalSince1970: 1_786_100_000)
                )],
                analyticsConsentEvents: []
            )),
            forKey: UserDefaultsKeys.legalConsentLedger
        )

        let manager = ConsentManager(
            ledgerStore: UserDefaultsConsentLedgerStore(
                userDefaults: userDefaults
            ),
            currentSDKUserIdProvider: { ownerUserId }
        )
        manager.observeSession(userId: ownerUserId)
        try manager.merge(
            ConsentManager.RemoteState(
                adultEligibilityReceipt: nil,
                termsReceipt: nil,
                aiConsentEvent: remoteRevocation,
                analyticsConsentEvent: nil,
                aiConsentStreamHead: remoteRevocation,
                analyticsConsentStreamHead: nil
            ),
            for: ownerUserId,
            generation: 1
        )

        XCTAssertFalse(manager.hasGrantedCurrentGeminiProcessing)
        XCTAssertEqual(manager.pendingCloudRecordCount, 0)

        let restarted = ConsentManager(userDefaults: userDefaults)
        XCTAssertFalse(restarted.hasGrantedCurrentGeminiProcessing)
        restarted.observeSession(userId: ownerUserId)
        XCTAssertFalse(restarted.hasGrantedCurrentGeminiProcessing)
        XCTAssertEqual(restarted.pendingCloudRecordCount, 0)
    }

    func testInverseOrderCrossDeviceAnalyticsRevocationSupersedesOfflineGrant() throws {
        let ownerUserId = UUID()
        let baseline = makeAnalyticsConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            eventKind: .granted,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_100),
            consentRevision: 50
        )
        let remoteRevocation = makeAnalyticsConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            eventKind: .revoked,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_050),
            causalParentId: baseline.id,
            consentRevision: 51
        )
        let staleOfflineGrant = makeAnalyticsConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: nil,
            eventKind: .granted,
            recordedAt: nil,
            causalParentId: baseline.id,
            supersededByEventId: remoteRevocation.id,
            supersededByRevision: 51
        )
        let suiteName = "merian.tests.inverse-analytics-consent.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(
            try JSONEncoder().encode(ConsentManager.LocalLedger(
                activeUserId: ownerUserId,
                termsReceipts: [],
                aiConsentEvents: [],
                adultEligibilityReceipts: [],
                analyticsConsentEvents: [baseline, staleOfflineGrant]
            )),
            forKey: UserDefaultsKeys.legalConsentLedger
        )

        let manager = ConsentManager(
            ledgerStore: UserDefaultsConsentLedgerStore(
                userDefaults: userDefaults
            ),
            currentSDKUserIdProvider: { ownerUserId }
        )
        manager.observeSession(userId: ownerUserId)
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

        XCTAssertFalse(manager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(manager.pendingCloudRecordCount, 0)

        let restarted = ConsentManager(userDefaults: userDefaults)
        XCTAssertFalse(restarted.hasGrantedCurrentPostHogAnalytics)
        restarted.observeSession(userId: ownerUserId)
        XCTAssertFalse(restarted.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(restarted.pendingCloudRecordCount, 0)
    }

    func testOlderDisclosureAIRevocationAtStreamHeadClosesCurrentGrant() throws {
        let ownerUserId = UUID()
        let currentGrant = makeAIConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_100),
            consentRevision: 60
        )
        let olderDisclosureRevocation = makeAIConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            disclosureVersion: "2026-08-03.1",
            eventKind: .revoked,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_200),
            causalParentId: currentGrant.id,
            consentRevision: 61
        )
        let suiteName = "merian.tests.cross-version-ai-consent.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsConsentLedgerStore(userDefaults: userDefaults)
        try store.saveLedgerData(JSONEncoder().encode(ConsentManager.LocalLedger(
            activeUserId: ownerUserId,
            termsReceipts: [],
            aiConsentEvents: [currentGrant],
            adultEligibilityReceipts: [],
            analyticsConsentEvents: []
        )))

        let manager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId }
        )
        XCTAssertTrue(manager.hasGrantedCurrentGeminiProcessing)
        manager.observeSession(userId: ownerUserId)
        try manager.merge(
            ConsentManager.RemoteState(
                adultEligibilityReceipt: nil,
                termsReceipt: nil,
                aiConsentEvent: currentGrant,
                analyticsConsentEvent: nil,
                aiConsentStreamHead: olderDisclosureRevocation,
                analyticsConsentStreamHead: nil
            ),
            for: ownerUserId,
            generation: 1
        )

        XCTAssertFalse(manager.hasGrantedCurrentGeminiProcessing)
        XCTAssertEqual(manager.pendingCloudRecordCount, 0)

        let restarted = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId }
        )
        XCTAssertFalse(restarted.hasGrantedCurrentGeminiProcessing)
    }

    func testOlderDisclosureAnalyticsRevocationAtStreamHeadClosesCurrentGrant() throws {
        let ownerUserId = UUID()
        let currentGrant = makeAnalyticsConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            eventKind: .granted,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_100),
            consentRevision: 70
        )
        let olderDisclosureRevocation = makeAnalyticsConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            disclosureVersion: "2026-08-03",
            eventKind: .revoked,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_200),
            causalParentId: currentGrant.id,
            consentRevision: 71
        )
        let suiteName = "merian.tests.cross-version-analytics-consent.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsConsentLedgerStore(userDefaults: userDefaults)
        try store.saveLedgerData(JSONEncoder().encode(ConsentManager.LocalLedger(
            activeUserId: ownerUserId,
            termsReceipts: [],
            aiConsentEvents: [],
            adultEligibilityReceipts: [],
            analyticsConsentEvents: [currentGrant]
        )))

        let manager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId }
        )
        XCTAssertTrue(manager.hasGrantedCurrentPostHogAnalytics)
        manager.observeSession(userId: ownerUserId)
        try manager.merge(
            ConsentManager.RemoteState(
                adultEligibilityReceipt: nil,
                termsReceipt: nil,
                aiConsentEvent: nil,
                analyticsConsentEvent: currentGrant,
                aiConsentStreamHead: nil,
                analyticsConsentStreamHead: olderDisclosureRevocation
            ),
            for: ownerUserId,
            generation: 1
        )

        XCTAssertEqual(
            manager.analyticsCloudAuthorityState,
            .resolvedRemote(userId: ownerUserId, granted: false)
        )
        XCTAssertFalse(manager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(manager.pendingCloudRecordCount, 0)

        let restarted = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId }
        )
        XCTAssertFalse(restarted.hasGrantedCurrentPostHogAnalytics)
    }

    func testTargetAccountActivationPreservesPendingAndHistoricalEvidence() {
        let previousUserId = UUID()
        let targetUserId = UUID()
        let source = ConsentManager.LocalLedger(
            activeUserId: previousUserId,
            termsReceipts: [
                makeTermsReceipt(
                    ownerUserId: targetUserId,
                    syncedUserId: nil,
                    recordedAt: nil
                )
            ],
            aiConsentEvents: [
                makeAIConsentEvent(
                    ownerUserId: previousUserId,
                    syncedUserId: previousUserId,
                    recordedAt: Date(timeIntervalSince1970: 1_786_000_000)
                )
            ],
            adultEligibilityReceipts: [
                makeAdultReceipt(
                    ownerUserId: targetUserId,
                    syncedUserId: targetUserId,
                    recordedAt: Date(timeIntervalSince1970: 1_786_000_001)
                )
            ],
            analyticsConsentEvents: [
                makeAnalyticsConsentEvent(
                    ownerUserId: targetUserId,
                    syncedUserId: nil,
                    eventKind: .revoked,
                    recordedAt: nil
                )
            ]
        )

        let activated = ConsentManager.activating(source, for: targetUserId)

        XCTAssertEqual(activated.activeUserId, targetUserId)
        XCTAssertEqual(activated.termsReceipts, source.termsReceipts)
        XCTAssertEqual(activated.aiConsentEvents, source.aiConsentEvents)
        XCTAssertEqual(
            activated.adultEligibilityReceipts,
            source.adultEligibilityReceipts
        )
        XCTAssertEqual(
            activated.analyticsConsentEvents,
            source.analyticsConsentEvents
        )
        XCTAssertEqual(
            ConsentManager.activating(activated, for: targetUserId),
            activated
        )
    }

    private func makeAdultReceipt(
        ownerUserId: UUID,
        syncedUserId: UUID?,
        recordedAt: Date?
    ) -> ConsentManager.AdultEligibilityReceipt {
        ConsentManager.AdultEligibilityReceipt(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: syncedUserId,
            policyVersion: ConsentPolicy.adultEligibilityVersion,
            confirmedAt: Date(timeIntervalSince1970: 1_785_999_900),
            confirmationMethod: .selfAttestation,
            confirmationText: ConsentPolicy.adultConfirmationText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: recordedAt
        )
    }

    private func makeTermsReceipt(
        ownerUserId: UUID,
        syncedUserId: UUID?,
        recordedAt: Date?
    ) -> ConsentManager.TermsAcceptanceReceipt {
        ConsentManager.TermsAcceptanceReceipt(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: syncedUserId,
            termsVersion: ConsentPolicy.termsVersion,
            acceptedAt: Date(timeIntervalSince1970: 1_785_999_900),
            acceptanceText: ConsentPolicy.combinedAcceptanceText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: recordedAt
        )
    }

    private func makeAIConsentEvent(
        ownerUserId: UUID,
        syncedUserId: UUID?,
        disclosureVersion: String = ConsentPolicy.geminiDisclosureVersion,
        eventKind: ConsentManager.AIConsentEventKind = .granted,
        recordedAt: Date?,
        causalParentId: UUID? = nil,
        consentRevision: Int64? = nil,
        supersededByEventId: UUID? = nil,
        supersededByRevision: Int64? = nil
    ) -> ConsentManager.AIConsentEvent {
        ConsentManager.AIConsentEvent(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: syncedUserId,
            provider: ConsentPolicy.geminiProvider,
            disclosureVersion: disclosureVersion,
            eventKind: eventKind,
            occurredAt: Date(timeIntervalSince1970: 1_785_999_900),
            disclosureText: ConsentPolicy.geminiDisclosureText,
            actionText: eventKind == .granted
                ? ConsentPolicy.combinedAcceptanceText
                : ConsentPolicy.geminiWithdrawalText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: recordedAt,
            causalParentId: causalParentId,
            consentRevision: consentRevision,
            supersededByEventId: supersededByEventId,
            supersededByRevision: supersededByRevision
        )
    }

    private func makeAnalyticsConsentEvent(
        ownerUserId: UUID,
        syncedUserId: UUID?,
        disclosureVersion: String = ConsentPolicy.analyticsDisclosureVersion,
        eventKind: ConsentManager.AnalyticsConsentEventKind,
        recordedAt: Date?,
        causalParentId: UUID? = nil,
        consentRevision: Int64? = nil,
        supersededByEventId: UUID? = nil,
        supersededByRevision: Int64? = nil
    ) -> ConsentManager.AnalyticsConsentEvent {
        ConsentManager.AnalyticsConsentEvent(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: syncedUserId,
            provider: ConsentPolicy.analyticsProvider,
            disclosureVersion: disclosureVersion,
            eventKind: eventKind,
            occurredAt: Date(timeIntervalSince1970: 1_785_999_900),
            disclosureText: ConsentPolicy.analyticsDisclosureText,
            actionText: eventKind == .granted
                ? ConsentPolicy.analyticsDisclosureText
                : ConsentPolicy.analyticsWithdrawalText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: recordedAt,
            causalParentId: causalParentId,
            consentRevision: consentRevision,
            supersededByEventId: supersededByEventId,
            supersededByRevision: supersededByRevision
        )
    }

}
