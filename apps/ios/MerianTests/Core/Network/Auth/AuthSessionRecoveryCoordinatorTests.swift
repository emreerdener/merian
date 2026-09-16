@testable import Merian
import XCTest

@MainActor
final class AuthSessionRecoveryCoordinatorTests: XCTestCase {
    func testOrdinaryRefreshPublishesBeforePurchaseReadiness() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        harness.expectedSession = harness.source
        harness.sdkSession = harness.source
        harness.publishedSession = harness.source
        harness.refreshResult = harness.source

        let refreshed = await harness.makeCoordinator()
            .refreshActiveSessionForRetry()

        XCTAssertTrue(refreshed)
        XCTAssertEqual(harness.beginCount, 1)
        XCTAssertEqual(harness.finishCount, 1)
        assertOrder(
            [
                "begin-recovery",
                "await-quiescence",
                "refresh-sdk-session",
                "adopt-session",
                "publish-session",
                "schedule-public-author-refresh",
                "ensure-purchase-identity",
                "diagnose-ordinaryRefreshSucceeded",
                "finish-recovery"
            ],
            in: harness.events
        )
    }

    func testCancelledOrdinaryRefreshStopsBeforeTransition() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        harness.expectedSession = harness.source

        let refreshed = await Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await harness.makeCoordinator()
                .refreshActiveSessionForRetry()
        }.value

        XCTAssertFalse(refreshed)
        XCTAssertTrue(harness.events.isEmpty)
    }

    func testExpectedSessionDriftDuringQuiescenceStopsBeforeRefresh() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        let gate = AuthSessionRecoveryCoordinatorTestGate()
        harness.expectedSession = harness.source
        harness.sdkSession = harness.source
        harness.refreshResult = harness.source
        harness.quiescenceGate = gate

        let attempt = Task { @MainActor in
            await harness.makeCoordinator().refreshActiveSessionForRetry()
        }
        await gate.waitUntilWaiterCount(1)
        harness.expectedSession = harness.replacement
        await gate.release()

        let refreshed = await attempt.value

        XCTAssertFalse(refreshed)
        XCTAssertEqual(harness.refreshCount, 0)
        XCTAssertEqual(harness.finishCount, 1)
    }

    func testCancellationDuringRefreshStopsBeforePublication() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        let gate = AuthSessionRecoveryCoordinatorTestGate()
        harness.expectedSession = harness.source
        harness.sdkSession = harness.source
        harness.refreshResult = harness.source
        harness.refreshGate = gate

        let attempt = Task { @MainActor in
            await harness.makeCoordinator().refreshActiveSessionForRetry()
        }
        await gate.waitUntilWaiterCount(1)
        attempt.cancel()
        await gate.release()

        let refreshed = await attempt.value

        XCTAssertFalse(refreshed)
        XCTAssertEqual(harness.publishCount, 0)
        XCTAssertEqual(harness.finishCount, 1)
    }

    func testTransitionOwnedRefreshSkipsIdentityFollowUp() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        harness.activeTransition = harness.recovery
        harness.expectedSession = harness.source
        harness.sdkSession = harness.source
        harness.refreshResult = harness.source

        let refreshed = await harness.makeCoordinator()
            .refreshExpectedSessionForAuthenticatedRequest(
                ownedBy: harness.recovery
            )

        XCTAssertTrue(refreshed)
        XCTAssertEqual(harness.beginCount, 0)
        XCTAssertEqual(harness.finishCount, 0)
        XCTAssertEqual(harness.publishCount, 1)
        XCTAssertEqual(harness.scheduleCount, 0)
        XCTAssertEqual(harness.purchaseReadinessCount, 0)
    }

    func testTransitionOwnedRefreshRejectsDifferentIdentity() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        harness.activeTransition = harness.recovery
        harness.expectedSession = harness.source
        harness.sdkSession = harness.source
        harness.refreshResult = harness.replacement

        let refreshed = await harness.makeCoordinator()
            .refreshExpectedSessionForAuthenticatedRequest(
                ownedBy: harness.recovery
            )

        XCTAssertFalse(refreshed)
        XCTAssertEqual(harness.publishCount, 0)
    }

    func testAnonymousResetRejectsPendingPurchaseHandoff() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        harness.expectedSession = harness.source
        harness.purchaseHandoffPending = true

        let reset = await harness.makeCoordinator()
            .resetGhostSessionForRetry()

        XCTAssertFalse(reset)
        XCTAssertFalse(
            harness.events.contains("reset-anonymous-session")
        )
        XCTAssertTrue(
            harness.events.contains(
                "diagnose-anonymousResetBlockedByPurchaseHandoff"
            )
        )
    }

    func testAnonymousResetRestoresPurchaseAndEntitlementReadiness() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        harness.expectedSession = harness.source
        harness.sdkSession = harness.source
        harness.loadedSessions = [harness.anonymous, harness.anonymous]

        let reset = await harness.makeCoordinator()
            .resetGhostSessionForRetry()

        XCTAssertTrue(reset)
        XCTAssertEqual(harness.purchaseReadinessCount, 1)
        XCTAssertEqual(harness.entitlementCount, 1)
        XCTAssertEqual(harness.loadCount, 2)
        assertOrder(
            [
                "reset-anonymous-session",
                "load-sdk-session",
                "ensure-purchase-identity",
                "validate-purchase-identity",
                "begin-entitlement-session",
                "load-sdk-session",
                "validate-published-generation",
                "publish-session",
                "diagnose-anonymousResetSucceeded",
                "finish-recovery"
            ],
            in: harness.events
        )
    }

    func testCancellationDuringPurchaseReadinessStopsBeforeEntitlement() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        let gate = AuthSessionRecoveryCoordinatorTestGate()
        harness.expectedSession = harness.source
        harness.sdkSession = harness.source
        harness.loadedSessions = [harness.anonymous]
        harness.purchaseReadinessGate = gate

        let attempt = Task { @MainActor in
            await harness.makeCoordinator().resetGhostSessionForRetry()
        }
        await gate.waitUntilWaiterCount(1)
        attempt.cancel()
        await gate.release()

        let reset = await attempt.value

        XCTAssertFalse(reset)
        XCTAssertEqual(harness.entitlementCount, 0)
        XCTAssertEqual(harness.finishCount, 1)
    }

    func testAnonymousResetRejectsUnreadyPurchaseIdentity() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        harness.expectedSession = harness.source
        harness.sdkSession = harness.source
        harness.loadedSessions = [harness.anonymous]
        harness.purchaseIdentityReady = false

        let reset = await harness.makeCoordinator()
            .resetGhostSessionForRetry()

        XCTAssertFalse(reset)
        XCTAssertEqual(harness.entitlementCount, 0)
        XCTAssertTrue(
            harness.events.contains(
                "diagnose-anonymousResetPurchaseIdentityNotReady"
            )
        )
    }

    func testAnonymousResetRejectsFinalSessionReplacement() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        harness.expectedSession = harness.source
        harness.sdkSession = harness.source
        harness.loadedSessions = [harness.anonymous, harness.replacement]

        let reset = await harness.makeCoordinator()
            .resetGhostSessionForRetry()

        XCTAssertFalse(reset)
        XCTAssertEqual(harness.publishCount, 0)
        XCTAssertEqual(harness.loadCount, 2)
    }

    func testLocalClearPreservesSessionWhilePurchaseHandoffIsPending() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        harness.expectedSession = harness.source
        harness.sdkSession = harness.source
        harness.publishedSession = harness.source
        harness.purchaseHandoffPending = true

        let outcome = await harness.makeCoordinator()
            .clearLocalSessionAfterAuthFailure()

        XCTAssertEqual(outcome, .blockedByPurchaseHandoff)
        XCTAssertEqual(harness.localStateClearCount, 0)
        XCTAssertEqual(harness.purchaseSignOutCount, 0)
        XCTAssertEqual(harness.publishedSession, harness.source)
        XCTAssertTrue(
            harness.events.contains(
                "diagnose-localClearBlockedByPurchaseHandoff"
            )
        )
    }

    func testLocalClearCompletesAfterSDKSignOutFailure() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        harness.expectedSession = harness.source
        harness.sdkSession = harness.source
        harness.publishedSession = harness.source
        harness.localSignOutError =
            AuthSessionRecoveryCoordinatorTestError.localSignOut

        let outcome = await harness.makeCoordinator()
            .clearLocalSessionAfterAuthFailure()

        XCTAssertEqual(outcome, .cleared)
        XCTAssertEqual(harness.localStateClearCount, 1)
        XCTAssertEqual(harness.purchaseSignOutCount, 1)
        XCTAssertNil(harness.publishedSession)
        assertOrder(
            [
                "phase-installingSession",
                "adopt-signed-out",
                "local-sdk-sign-out",
                "diagnose-localSDKSignOutFailed",
                "clear-local-state",
                "finish-purchase-sign-out",
                "diagnose-localSessionCleared",
                "finish-recovery"
            ],
            in: harness.events
        )
    }

    func testLocalClearCompletesWhenCancelledDuringSDKSignOut() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        let gate = AuthSessionRecoveryCoordinatorTestGate()
        harness.expectedSession = harness.source
        harness.sdkSession = harness.source
        harness.publishedSession = harness.source
        harness.localSignOutGate = gate

        let attempt = Task { @MainActor in
            await harness.makeCoordinator()
                .clearLocalSessionAfterAuthFailure()
        }
        await gate.waitUntilWaiterCount(1)
        attempt.cancel()
        await gate.release()
        let outcome = await attempt.value

        XCTAssertEqual(outcome, .cleared)
        XCTAssertEqual(harness.localStateClearCount, 1)
        XCTAssertEqual(harness.purchaseSignOutCount, 1)
        XCTAssertNil(harness.publishedSession)
        XCTAssertEqual(harness.finishCount, 1)
        assertOrder(
            [
                "local-sdk-sign-out",
                "diagnose-localSDKSignOutFailed",
                "clear-local-state",
                "finish-purchase-sign-out",
                "diagnose-localSessionCleared",
                "finish-recovery"
            ],
            in: harness.events
        )
    }

    func testOwnedLocalClearDoesNotFinishCallersTransition() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        harness.activeTransition = harness.recovery
        harness.expectedSession = harness.source
        harness.sdkSession = harness.source
        harness.publishedSession = harness.source

        let outcome = await harness.makeCoordinator()
            .clearLocalSessionAfterAuthFailure(
                ownedBy: harness.recovery
            )

        XCTAssertEqual(outcome, .cleared)
        XCTAssertEqual(harness.beginCount, 0)
        XCTAssertEqual(harness.finishCount, 0)
        XCTAssertEqual(harness.activeTransition, harness.recovery)
        XCTAssertEqual(harness.localStateClearCount, 1)
    }

    func testMutatedOAuthCleanupStartsForCancelledTransitionOwner() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        harness.activeTransition = harness.recovery
        harness.expectedSession = harness.source
        harness.sdkSession = harness.source
        harness.publishedSession = harness.source

        let outcome = await Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await harness.makeCoordinator()
                .clearLocalSessionAfterAuthFailure(
                    ownedBy: harness.recovery,
                    entryPolicy: .completeMutatedOAuthSession
                )
        }.value

        XCTAssertEqual(outcome, .cleared)
        XCTAssertEqual(harness.localStateClearCount, 1)
        XCTAssertEqual(harness.purchaseSignOutCount, 1)
        XCTAssertNil(harness.sdkSession)
        XCTAssertNil(harness.publishedSession)
        XCTAssertEqual(harness.finishCount, 0)
    }

    func testMutatedOAuthCleanupClearsExactAdoptedReplacement() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        harness.activeTransition = harness.recovery
        harness.expectedSession = harness.replacement
        harness.sdkSession = harness.replacement
        harness.publishedSession = nil

        let outcome = await Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await harness.makeCoordinator()
                .clearLocalSessionAfterAuthFailure(
                    ownedBy: harness.recovery,
                    entryPolicy: .completeMutatedOAuthSession
                )
        }.value

        XCTAssertEqual(outcome, .cleared)
        XCTAssertEqual(harness.localStateClearCount, 1)
        XCTAssertEqual(harness.purchaseSignOutCount, 1)
        XCTAssertNil(harness.sdkSession)
        XCTAssertEqual(harness.finishCount, 0)
    }

    func testLocalClearRejectsSessionReplacementDuringQuiescence() async {
        let harness = AuthSessionRecoveryCoordinatorHarness()
        let gate = AuthSessionRecoveryCoordinatorTestGate()
        harness.expectedSession = harness.source
        harness.sdkSession = harness.source
        harness.publishedSession = harness.source
        harness.quiescenceGate = gate

        let attempt = Task { @MainActor in
            await harness.makeCoordinator()
                .clearLocalSessionAfterAuthFailure()
        }
        await gate.waitUntilWaiterCount(1)
        harness.sdkSession = harness.replacement
        await gate.release()

        let outcome = await attempt.value

        XCTAssertEqual(outcome, .rejected)
        XCTAssertEqual(harness.localStateClearCount, 0)
        XCTAssertEqual(harness.purchaseSignOutCount, 0)
        XCTAssertEqual(harness.publishedSession, harness.source)
        XCTAssertFalse(harness.events.contains("local-sdk-sign-out"))
        XCTAssertEqual(harness.finishCount, 1)
    }

    private func assertOrder(
        _ values: [String],
        in events: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var cursor = events.startIndex
        for value in values {
            guard let index = events[cursor...].firstIndex(of: value) else {
                XCTFail(
                    "Missing \(value) in \(events)",
                    file: file,
                    line: line
                )
                return
            }
            cursor = events.index(after: index)
        }
    }
}
