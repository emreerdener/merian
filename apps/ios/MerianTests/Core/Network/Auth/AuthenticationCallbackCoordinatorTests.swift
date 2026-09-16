import Foundation
@testable import Merian
import XCTest

@MainActor
final class AuthenticationCallbackCoordinatorTests: XCTestCase {
    func testSuccessfulCallbackPreservesCompletionOrder() async {
        let harness = AuthenticationCallbackCoordinatorHarness()

        await harness.makeCoordinator().handle()

        XCTAssertEqual(harness.beginCount, 1)
        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertEqual(harness.installCount, 1)
        XCTAssertEqual(harness.cleanupCount, 0)
        XCTAssertEqual(harness.entitlementCount, 1)
        XCTAssertEqual(harness.publishedSession, harness.installedSession)
        XCTAssertEqual(harness.authenticatedOAuthMarker, true)
        XCTAssertTrue(harness.diagnostics.isEmpty)
        assertOrder(
            [
                "verify-expected-if-present",
                "phase-installingSession",
                "analytics-generation",
                "install-session",
                "adopt-installed-session",
                "publish-session",
                "publish-session",
                "phase-bindingPurchases",
                "ensure-purchase-identity",
                "validate-purchase-identity",
                "begin-entitlement-session",
                "verify-expected",
                "phase-finalizing",
                "mark-authenticated-oauth",
                "finish-transition"
            ],
            in: harness.events
        )
    }

    func testPendingPurchaseHandoffRejectsBeforeTransition() async {
        let harness = AuthenticationCallbackCoordinatorHarness()
        harness.pendingPurchaseHandoff = true

        await harness.makeCoordinator().handle()

        XCTAssertEqual(harness.beginCount, 0)
        XCTAssertEqual(harness.finishCount, 0)
        XCTAssertEqual(harness.installCount, 0)
        XCTAssertEqual(harness.diagnostics, [.transitionRejected])
    }

    func testActiveTransitionRejectsOverlappingCallback() async {
        let harness = AuthenticationCallbackCoordinatorHarness()
        harness.mayBeginTransition = false

        await harness.makeCoordinator().handle()

        XCTAssertEqual(harness.beginCount, 0)
        XCTAssertEqual(harness.finishCount, 0)
        XCTAssertEqual(harness.installCount, 0)
        XCTAssertEqual(harness.diagnostics, [.transitionRejected])
    }

    func testCancellationAfterPreflightStopsBeforeInstallation() async {
        let gate = AuthCallbackCoordinatorTestGate()
        let harness = AuthenticationCallbackCoordinatorHarness()
        harness.initialVerificationGate = gate

        let attempt = Task { @MainActor in
            await harness.makeCoordinator().handle()
        }
        await gate.waitUntilWaiterCount(1)
        attempt.cancel()
        await gate.release()
        await attempt.value

        XCTAssertEqual(harness.installCount, 0)
        XCTAssertEqual(harness.cleanupCount, 0)
        XCTAssertFalse(harness.events.contains("analytics-generation"))
        XCTAssertFalse(harness.events.contains("phase-installingSession"))
        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertEqual(harness.diagnostics, [.completionFailed])
    }

    func testAnonymousSourceRejectsBeforeSessionVerification() async {
        let source = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: true
        )
        let harness = AuthenticationCallbackCoordinatorHarness(
            sourceSession: source
        )

        await harness.makeCoordinator().handle()

        XCTAssertEqual(harness.beginCount, 1)
        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertEqual(harness.installCount, 0)
        XCTAssertFalse(
            harness.events.contains("verify-expected-if-present")
        )
        XCTAssertEqual(harness.diagnostics, [.sourceSessionRejected])
    }

    func testDifferentLinkedTargetClearsMutatedSession() async {
        let source = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: false
        )
        let harness = AuthenticationCallbackCoordinatorHarness(
            sourceSession: source
        )

        await harness.makeCoordinator().handle()

        XCTAssertEqual(harness.cleanupCount, 1)
        XCTAssertNil(harness.currentSession)
        XCTAssertNil(harness.publishedSession)
        XCTAssertNil(harness.authenticatedOAuthMarker)
        XCTAssertEqual(harness.diagnostics, [.completionFailed])
        XCTAssertFalse(
            harness.events.contains("ensure-purchase-identity")
        )
    }

    func testExactLinkedSourceMayRefreshTheSameAccount() async {
        let source = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: false
        )
        let harness = AuthenticationCallbackCoordinatorHarness(
            sourceSession: source,
            installedSession: source
        )

        await harness.makeCoordinator().handle()

        XCTAssertEqual(harness.cleanupCount, 0)
        XCTAssertEqual(harness.publishedSession, source)
        XCTAssertEqual(harness.authenticatedOAuthMarker, true)
        XCTAssertTrue(harness.diagnostics.isEmpty)
    }

    func testInstallationFailurePreservesExactSourceSession() async {
        let source = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: false
        )
        let harness = AuthenticationCallbackCoordinatorHarness(
            sourceSession: source
        )
        harness.installError = AuthCallbackCoordinatorTestError
            .install

        await harness.makeCoordinator().handle()

        XCTAssertEqual(harness.cleanupCount, 0)
        XCTAssertEqual(harness.currentSession, source)
        XCTAssertEqual(harness.publishedSession, source)
        XCTAssertEqual(harness.diagnostics, [.completionFailed])
        assertOrder(
            [
                "install-session",
                "publish-session",
                "diagnose-completionFailed",
                "finish-transition"
            ],
            in: harness.events
        )
    }

    func testInstallationFailureAfterMutationClearsChangedSession() async {
        let source = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: false
        )
        let harness = AuthenticationCallbackCoordinatorHarness(
            sourceSession: source
        )
        harness.mutateSessionBeforeInstallFailure = true
        harness.installError = AuthCallbackCoordinatorTestError.install

        await harness.makeCoordinator().handle()

        XCTAssertEqual(harness.installCount, 1)
        XCTAssertEqual(harness.cleanupCount, 1)
        XCTAssertNil(harness.currentSession)
        XCTAssertNil(harness.publishedSession)
        XCTAssertNil(harness.authenticatedOAuthMarker)
        XCTAssertEqual(harness.diagnostics, [.completionFailed])
    }

    func testSignOutDuringInstallationCannotRepublishSession() async {
        let gate = AuthCallbackCoordinatorTestGate()
        let harness = AuthenticationCallbackCoordinatorHarness()
        harness.installGate = gate

        let attempt = Task { @MainActor in
            await harness.makeCoordinator().handle()
        }
        await gate.waitUntilWaiterCount(1)
        harness.isSigningOut = true
        await gate.release()
        await attempt.value

        XCTAssertEqual(harness.cleanupCount, 1)
        XCTAssertNil(harness.publishedSession)
        XCTAssertTrue(harness.events.contains("clear-published-session"))
        XCTAssertFalse(harness.events.contains("ensure-purchase-identity"))
        XCTAssertNil(harness.authenticatedOAuthMarker)
    }

    func testCancellationDuringInstallationClearsMutatedSession() async {
        let source = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: false
        )
        let gate = AuthCallbackCoordinatorTestGate()
        let harness = AuthenticationCallbackCoordinatorHarness(
            sourceSession: source
        )
        harness.installGate = gate

        let attempt = Task { @MainActor in
            await harness.makeCoordinator().handle()
        }
        await gate.waitUntilWaiterCount(1)
        attempt.cancel()
        await gate.release()
        await attempt.value

        XCTAssertEqual(harness.cleanupCount, 1)
        XCTAssertNil(harness.currentSession)
        XCTAssertNil(harness.authenticatedOAuthMarker)
        XCTAssertTrue(
            harness.events.contains("adopt-installed-session")
        )
        XCTAssertFalse(
            harness.events.contains("ensure-purchase-identity")
        )
        XCTAssertEqual(harness.finishCount, 1)
    }

    func testCancellationDuringPurchaseReadinessStopsEntitlement()
        async {
        let gate = AuthCallbackCoordinatorTestGate()
        let harness = AuthenticationCallbackCoordinatorHarness()
        harness.purchaseGate = gate

        let attempt = Task { @MainActor in
            await harness.makeCoordinator().handle()
        }
        await gate.waitUntilWaiterCount(1)
        attempt.cancel()
        await gate.release()
        await attempt.value

        XCTAssertEqual(harness.cleanupCount, 1)
        XCTAssertEqual(harness.entitlementCount, 0)
        XCTAssertNil(harness.authenticatedOAuthMarker)
        XCTAssertEqual(harness.finishCount, 1)
    }

    func testCancellationDuringEntitlementStopsFinalCommit() async {
        let gate = AuthCallbackCoordinatorTestGate()
        let harness = AuthenticationCallbackCoordinatorHarness()
        harness.entitlementGate = gate

        let attempt = Task { @MainActor in
            await harness.makeCoordinator().handle()
        }
        await gate.waitUntilWaiterCount(1)
        attempt.cancel()
        await gate.release()
        await attempt.value

        XCTAssertEqual(harness.cleanupCount, 1)
        XCTAssertEqual(harness.entitlementCount, 1)
        XCTAssertFalse(harness.events.contains("verify-expected"))
        XCTAssertNil(harness.authenticatedOAuthMarker)
        XCTAssertEqual(harness.finishCount, 1)
    }

    func testUnreadyPurchaseIdentityStopsEntitlementAndFinalCommit() async {
        let harness = AuthenticationCallbackCoordinatorHarness()
        harness.purchaseIdentityIsReady = false

        await harness.makeCoordinator().handle()

        XCTAssertEqual(harness.cleanupCount, 1)
        XCTAssertEqual(harness.entitlementCount, 0)
        XCTAssertNil(harness.authenticatedOAuthMarker)
        XCTAssertEqual(harness.diagnostics, [.completionFailed])
    }

    func testFinalSessionDriftClearsMutatedSession() async {
        let gate = AuthCallbackCoordinatorTestGate()
        let harness = AuthenticationCallbackCoordinatorHarness()
        harness.finalVerificationGate = gate

        let attempt = Task { @MainActor in
            await harness.makeCoordinator().handle()
        }
        await gate.waitUntilWaiterCount(1)
        harness.transitionMatches = false
        await gate.release()
        await attempt.value

        XCTAssertEqual(harness.cleanupCount, 1)
        XCTAssertNil(harness.authenticatedOAuthMarker)
        XCTAssertEqual(harness.diagnostics, [.completionFailed])
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
