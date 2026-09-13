import Foundation
@testable import Merian
import XCTest

@MainActor
final class ConsentCloudSessionCoordinatorTests: XCTestCase {
    func testSynchronizationAdoptsLeaseSessionAndFinishesLease() async throws {
        let userId = UUID(
            uuidString: "30000000-0000-4000-8000-000000000001"
        )!
        let lease = AccountBoundWorkLease(
            id: UUID(),
            session: .init(userID: userId, isAnonymous: true)
        )
        var synchronizedUserIds: [UUID] = []
        let cloudSession = CloudSessionDependenciesSpy(
            session: lease.session,
            lease: lease
        )
        let manager = makeManager(
            sdkUserId: userId,
            cloudSessionDependencies: cloudSession.dependencies,
            synchronizationOperation: { synchronizedUserIds.append($0) }
        )

        try await manager.synchronizeWithCurrentSession()

        XCTAssertEqual(manager.currentSessionUserId, userId)
        XCTAssertEqual(synchronizedUserIds, [userId])
        XCTAssertEqual(cloudSession.finishedLeases, [lease])
    }

    func testSynchronizationRejectsLeaseThatExpiresAfterRemoteWork() async {
        let userId = UUID(
            uuidString: "30000000-0000-4000-8000-000000000002"
        )!
        let lease = AccountBoundWorkLease(
            id: UUID(),
            session: .init(userID: userId, isAnonymous: true)
        )
        let cloudSession = CloudSessionDependenciesSpy(
            session: lease.session,
            lease: lease
        )
        cloudSession.isLeaseCurrent = {
            cloudSession.leaseAuthorizationChecks += 1
            return cloudSession.leaseAuthorizationChecks < 3
        }
        let manager = makeManager(
            sdkUserId: userId,
            cloudSessionDependencies: cloudSession.dependencies,
            synchronizationOperation: { _ in }
        )

        do {
            try await manager.synchronizeWithCurrentSession()
            XCTFail("Expected the expired account-work lease to be rejected")
        } catch ConsentHandoffError.activeAccountChanged {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(cloudSession.leaseAuthorizationChecks, 3)
        XCTAssertEqual(cloudSession.finishedLeases, [lease])
    }

    func testSynchronizationRejectsGenerationInvalidatedByRemoteWork() async {
        let userId = UUID(
            uuidString: "30000000-0000-4000-8000-000000000003"
        )!
        let lease = AccountBoundWorkLease(
            id: UUID(),
            session: .init(userID: userId, isAnonymous: true)
        )
        let cloudSession = CloudSessionDependenciesSpy(
            session: lease.session,
            lease: lease
        )
        var manager: ConsentManager!
        manager = makeManager(
            sdkUserId: userId,
            cloudSessionDependencies: cloudSession.dependencies,
            synchronizationOperation: { _ in
                manager.prepareForGhostEvidenceRebind()
            }
        )

        do {
            try await manager.synchronizeWithCurrentSession()
            XCTFail("Expected the invalidated generation to be rejected")
        } catch ConsentHandoffError.activeAccountChanged {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(manager.currentSessionUserId, userId)
        XCTAssertEqual(cloudSession.finishedLeases, [lease])
    }

    func testInferenceSynchronizesBindableUnownedConsentAfterAdoption() async throws {
        let userId = UUID(
            uuidString: "30000000-0000-4000-8000-000000000005"
        )!
        let lease = AccountBoundWorkLease(
            id: UUID(),
            session: .init(userID: userId, isAnonymous: true)
        )
        let cloudSession = CloudSessionDependenciesSpy(
            session: lease.session,
            lease: lease
        )
        cloudSession.isRunningTests = true
        cloudSession.isAuthenticated = false
        cloudSession.initializeGhostSession = {
            cloudSession.initializeGhostSessionCount += 1
            cloudSession.isAuthenticated = true
            return true
        }
        let store = FaultInjectingConsentLedgerStore()
        let remoteService = FirstScanConsentRemoteSpy(userId: userId)
        let manager = makeManager(
            store: store,
            sdkUserId: userId,
            cloudSessionDependencies: cloudSession.dependencies,
            remoteService: remoteService.service
        )
        try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: false
        )

        try await manager.ensureCloudConsentForInference()

        XCTAssertEqual(cloudSession.initializeGhostSessionCount, 1)
        XCTAssertEqual(cloudSession.finishedLeases, [lease])
        XCTAssertEqual(
            remoteService.operations,
            [
                "adult-insert",
                "adult-readback",
                "terms-insert",
                "terms-readback",
                "ai-append",
                "authoritative-fetch"
            ]
        )
        let data = try XCTUnwrap(store.ledgerData)
        let ledger = try JSONDecoder().decode(
            ConsentManager.LocalLedger.self,
            from: data
        )
        XCTAssertEqual(ledger.activeUserId, userId)
        XCTAssertEqual(ledger.adultEligibilityReceipts.count, 1)
        XCTAssertTrue(ledger.adultEligibilityReceipts.allSatisfy {
            $0.ownerUserId == userId && $0.syncedUserId == userId
        })
        XCTAssertEqual(ledger.termsReceipts.count, 1)
        XCTAssertTrue(ledger.termsReceipts.allSatisfy {
            $0.ownerUserId == userId && $0.syncedUserId == userId
        })
        XCTAssertEqual(ledger.aiConsentEvents.count, 1)
        XCTAssertTrue(ledger.aiConsentEvents.allSatisfy {
            $0.ownerUserId == userId && $0.syncedUserId == userId
        })
    }

    func testInferenceDoesNotBindAnotherAccountsPersistedConsent() async throws {
        let firstUserId = UUID(
            uuidString: "30000000-0000-4000-8000-000000000006"
        )!
        let replacementUserId = UUID(
            uuidString: "30000000-0000-4000-8000-000000000007"
        )!
        let store = FaultInjectingConsentLedgerStore()
        let firstLease = AccountBoundWorkLease(
            id: UUID(),
            session: .init(userID: firstUserId, isAnonymous: true)
        )
        let firstCloudSession = CloudSessionDependenciesSpy(
            session: firstLease.session,
            lease: firstLease
        )
        firstCloudSession.isRunningTests = true
        let firstManager = makeManager(
            store: store,
            sdkUserId: firstUserId,
            cloudSessionDependencies: firstCloudSession.dependencies,
            synchronizationOperation: { _ in }
        )
        firstManager.observeSession(userId: firstUserId)
        try firstManager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: false
        )

        let replacementLease = AccountBoundWorkLease(
            id: UUID(),
            session: .init(userID: replacementUserId, isAnonymous: true)
        )
        let replacementCloudSession = CloudSessionDependenciesSpy(
            session: replacementLease.session,
            lease: replacementLease
        )
        replacementCloudSession.isRunningTests = true
        var synchronizedUserIds: [UUID] = []
        let replacementManager = makeManager(
            store: store,
            sdkUserId: replacementUserId,
            cloudSessionDependencies: replacementCloudSession.dependencies,
            synchronizationOperation: { synchronizedUserIds.append($0) }
        )
        XCTAssertTrue(replacementManager.hasCurrentRequiredConsent)

        do {
            try await replacementManager.ensureCloudConsentForInference()
            XCTFail("Expected prior-account consent to remain fenced")
        } catch MerianError.aiConsentRequired {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(synchronizedUserIds.isEmpty)
        XCTAssertEqual(
            replacementCloudSession.finishedLeases,
            [replacementLease]
        )
    }

    func testInferenceRejectsInvalidatedGenerationWithoutReapproval() async throws {
        let userId = UUID(
            uuidString: "30000000-0000-4000-8000-000000000010"
        )!
        let lease = AccountBoundWorkLease(
            id: UUID(),
            session: .init(userID: userId, isAnonymous: true)
        )
        let store = FaultInjectingConsentLedgerStore()
        let cloudSession = CloudSessionDependenciesSpy(
            session: lease.session,
            lease: lease
        )
        cloudSession.isRunningTests = true
        var manager: ConsentManager!
        manager = makeManager(
            store: store,
            sdkUserId: userId,
            cloudSessionDependencies: cloudSession.dependencies,
            synchronizationOperation: { _ in
                manager.prepareForGhostEvidenceRebind()
            }
        )
        try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: false
        )

        do {
            try await manager.ensureCloudConsentForInference()
            XCTFail("Expected the invalidated inference generation to fail")
        } catch ConsentHandoffError.activeAccountChanged {
            // Expected. Account/session invalidation is not proof that the
            // server rejected consent, so it must not create a reapproval fence.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let data = try XCTUnwrap(store.ledgerData)
        let ledger = try JSONDecoder().decode(
            ConsentManager.LocalLedger.self,
            from: data
        )
        XCTAssertTrue(ledger.requiredConsentReapprovalUserIds.isEmpty)
        XCTAssertEqual(cloudSession.finishedLeases, [lease])
    }

    func testGhostRebindUsesRuntimeRepositoryAndVerifiesFinalSession() async throws {
        let ghostUserId = UUID(
            uuidString: "30000000-0000-4000-8000-000000000008"
        )!
        let permanentUserId = UUID(
            uuidString: "30000000-0000-4000-8000-000000000009"
        )!
        let store = FaultInjectingConsentLedgerStore()
        let lease = AccountBoundWorkLease(
            id: UUID(),
            session: .init(userID: permanentUserId, isAnonymous: false)
        )
        let cloudSession = CloudSessionDependenciesSpy(
            session: lease.session,
            lease: lease
        )
        cloudSession.isRunningTests = true
        var synchronizedUserIds: [UUID] = []
        let manager = makeManager(
            store: store,
            sdkUserId: permanentUserId,
            cloudSessionDependencies: cloudSession.dependencies,
            synchronizationOperation: { synchronizedUserIds.append($0) }
        )
        manager.observeSession(userId: ghostUserId)
        try manager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: false
        )
        manager.observeSession(userId: permanentUserId)

        try await manager.rebindAndSynchronizeGhostEvidence(
            from: ghostUserId,
            to: permanentUserId
        )

        let data = try XCTUnwrap(store.ledgerData)
        let ledger = try JSONDecoder().decode(
            ConsentManager.LocalLedger.self,
            from: data
        )
        XCTAssertEqual(ledger.activeUserId, permanentUserId)
        XCTAssertTrue(ledger.adultEligibilityReceipts.allSatisfy {
            $0.ownerUserId == permanentUserId
        })
        XCTAssertTrue(ledger.termsReceipts.allSatisfy {
            $0.ownerUserId == permanentUserId
        })
        XCTAssertTrue(ledger.aiConsentEvents.allSatisfy {
            $0.ownerUserId == permanentUserId
        })
        XCTAssertEqual(synchronizedUserIds, [permanentUserId])
        XCTAssertEqual(cloudSession.currentSessionReadCount, 2)
    }

    private func makeManager(
        store: FaultInjectingConsentLedgerStore =
            FaultInjectingConsentLedgerStore(),
        sdkUserId: UUID,
        cloudSessionDependencies:
            ConsentCloudSessionCoordinator.Dependencies,
        remoteService: ConsentRemoteService? = nil,
        synchronizationOperation: (@MainActor (UUID) async -> Void)? = nil
    ) -> ConsentManager {
        ConsentManager(
            ledgerStore: store,
            remoteService: remoteService,
            currentSDKUserIdProvider: { sdkUserId },
            analyticsPermissionApplier: { _, _ in },
            synchronizationOperation: synchronizationOperation.map { operation in
                { userId, _ in await operation(userId) }
            },
            realtimeCoordinator: disabledRealtimeCoordinator(),
            cloudSessionDependencies: cloudSessionDependencies
        )
    }

    private func disabledRealtimeCoordinator() -> ConsentRealtimeCoordinator {
        ConsentRealtimeCoordinator(
            dependencies: .init(
                isEnabled: { false },
                makeSubscription: { _ in
                    fatalError("Disabled Realtime must not make subscriptions")
                },
                sleep: { _ in },
                reportFailure: { _ in }
            )
        )
    }
}

@MainActor
private final class FirstScanConsentRemoteSpy {
    private let userId: UUID
    private let recordedAt = "2026-09-12T12:00:00.000Z"

    private var adultInsert:
        ConsentRemoteWire.AdultEligibilityReceiptInsert?
    private var termsInsert: ConsentRemoteWire.TermsReceiptInsert?
    private var aiAppend: ConsentRemoteWire.AIConsentEventAppend?

    private(set) var operations: [String] = []

    init(userId: UUID) {
        self.userId = userId
    }

    var service: ConsentRemoteService {
        ConsentRemoteService(dependencies: .init(
            insertAdultEligibilityReceipt: { insert in
                self.operations.append("adult-insert")
                self.adultInsert = insert
            },
            insertTermsReceipt: { insert in
                self.operations.append("terms-insert")
                self.termsInsert = insert
            },
            appendAIConsentEvent: { append in
                self.operations.append("ai-append")
                self.aiAppend = append
                return [.init(
                    accepted: true,
                    event_revision: 1,
                    accepted_parent_id: append.p_causal_parent_id,
                    authoritative_revision: 1,
                    authoritative_event_id: append.p_id,
                    recorded_at: self.recordedAt
                )]
            },
            appendAnalyticsConsentEvent: { _ in
                throw MerianError.invalidResponse
            },
            fetchAdultEligibilityReceipt: { id, receivedUserId in
                self.operations.append("adult-readback")
                guard receivedUserId == self.userId,
                      let row = self.adultRow(),
                      row.id == id else {
                    throw MerianError.invalidResponse
                }
                return [row]
            },
            fetchTermsReceipt: { id, receivedUserId in
                self.operations.append("terms-readback")
                guard receivedUserId == self.userId,
                      let row = self.termsRow(),
                      row.id == id else {
                    throw MerianError.invalidResponse
                }
                return [row]
            },
            fetchAIConsentEvent: { _, _ in
                throw MerianError.invalidResponse
            },
            fetchAnalyticsConsentEvent: { _, _ in
                throw MerianError.invalidResponse
            },
            fetchRemoteRows: { receivedUserId in
                self.operations.append("authoritative-fetch")
                guard receivedUserId == self.userId,
                      let adultRow = self.adultRow(),
                      let termsRow = self.termsRow(),
                      let aiRow = self.aiRow() else {
                    throw MerianError.invalidResponse
                }
                return .init(
                    adultEligibilityReceipts: [adultRow],
                    termsReceipts: [termsRow],
                    aiConsentEvents: [aiRow],
                    analyticsConsentEvents: [],
                    aiConsentStreamHeads: [aiRow],
                    analyticsConsentStreamHeads: []
                )
            }
        ))
    }

    private func adultRow()
        -> ConsentRemoteWire.AdultEligibilityReceipt? {
        guard let insert = adultInsert else { return nil }
        return .init(
            id: insert.id,
            user_id: userId,
            policy_version: insert.policy_version,
            confirmed_at: insert.confirmed_at,
            confirmation_method: insert.confirmation_method,
            confirmation_text: insert.confirmation_text,
            platform: insert.platform,
            app_version: insert.app_version,
            app_build: insert.app_build,
            recorded_at: recordedAt
        )
    }

    private func termsRow() -> ConsentRemoteWire.TermsReceipt? {
        guard let insert = termsInsert else { return nil }
        return .init(
            id: insert.id,
            user_id: userId,
            terms_version: insert.terms_version,
            accepted_at: insert.accepted_at,
            acceptance_text: insert.acceptance_text,
            platform: insert.platform,
            app_version: insert.app_version,
            app_build: insert.app_build,
            recorded_at: recordedAt
        )
    }

    private func aiRow() -> ConsentRemoteWire.AIConsentEvent? {
        guard let append = aiAppend else { return nil }
        return .init(
            id: append.p_id,
            user_id: userId,
            provider: ConsentPolicy.geminiProvider,
            disclosure_version: append.p_disclosure_version,
            event_kind: append.p_event_kind,
            occurred_at: append.p_occurred_at,
            disclosure_text: append.p_disclosure_text,
            action_text: append.p_action_text,
            platform: append.p_platform,
            app_version: append.p_app_version,
            app_build: append.p_app_build,
            recorded_at: recordedAt,
            causal_parent_id: append.p_causal_parent_id,
            consent_revision: 1
        )
    }
}

@MainActor
private final class CloudSessionDependenciesSpy {
    var isRunningTests = false
    var isAuthenticated = true
    var isAuthTransitionInProgress = false
    var isAccountDeletionCleanupPending = false
    var initializeGhostSessionCount = 0
    var leaseAuthorizationChecks = 0
    var currentSessionReadCount = 0
    var finishedLeases: [AccountBoundWorkLease] = []
    var reportedReapprovalErrors: [Error] = []
    var initializeGhostSession: () async -> Bool = { true }
    var isLeaseCurrent: () -> Bool = { true }
    var transitionIsCurrent: (AuthTransitionToken) -> Bool = { _ in true }

    private let session: AuthTransitionSession
    private let lease: AccountBoundWorkLease

    init(
        session: AuthTransitionSession,
        lease: AccountBoundWorkLease
    ) {
        self.session = session
        self.lease = lease
    }

    var dependencies: ConsentCloudSessionCoordinator.Dependencies {
        .init(
            isRunningTests: { self.isRunningTests },
            isAuthenticated: { self.isAuthenticated },
            initializeGhostSession: {
                await self.initializeGhostSession()
            },
            beginUnownedAccountBoundWork: { self.lease },
            finishAccountBoundWork: { self.finishedLeases.append($0) },
            isAccountBoundWorkLeaseCurrent: { _ in
                self.isLeaseCurrent()
            },
            currentSession: {
                self.currentSessionReadCount += 1
                return self.session
            },
            currentSDKUserId: { self.session.userID },
            currentObservedUserId: { self.session.userID },
            isAuthTransitionInProgress: {
                self.isAuthTransitionInProgress
            },
            isAccountDeletionCleanupPending: {
                self.isAccountDeletionCleanupPending
            },
            currentSessionMatchesAuthTransition: {
                self.transitionIsCurrent($0)
            },
            reportReapprovalPersistenceFailure: {
                self.reportedReapprovalErrors.append($0)
            }
        )
    }
}
