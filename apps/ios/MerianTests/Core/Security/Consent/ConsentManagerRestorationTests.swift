import Foundation
@testable import Merian
import XCTest

@MainActor
final class ConsentManagerRestorationTests: ConsentManagerTestCase {
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

    func testExpiredCachedSessionKeepsCompletedUserOffApprovalScreenWhileRefreshing() {
        let ownerUserId = UUID()
        let manager = ConsentManager(
            ledgerStore: FaultInjectingConsentLedgerStore(),
            currentSDKUserIdProvider: { ownerUserId },
            analyticsPermissionApplier: { _, _ in }
        )

        let adoption = AuthTransitionPolicy.authSessionAdoption(
            userId: ownerUserId,
            isExpired: true
        )
        guard case .awaitingRefresh(let observedUserId) = adoption else {
            XCTFail("An expired cached session must remain a pending restoration.")
            return
        }
        manager.observeSession(userId: observedUserId)

        XCTAssertEqual(
            manager.requiredConsentRestorationState,
            .reconciling(userId: ownerUserId)
        )
        XCTAssertTrue(manager.isRestoringRequiredConsent)
        XCTAssertEqual(
            AppRootPresentationPolicy.presentation(
                hasCompletedOnboarding: true,
                hasCurrentRequiredConsent: manager.hasCurrentRequiredConsent,
                isRestoringRequiredConsent: manager.isRestoringRequiredConsent
            ),
            .restoringConsent
        )
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

}
