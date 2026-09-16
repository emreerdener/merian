@testable import Merian
import XCTest

@MainActor
final class AuthSessionLifecycleCoordinatorTests: XCTestCase {
    func testDeletionCleanupBarrierStopsBeforeDurableOrSessionEffects() async {
        let harness = AuthSessionLifecycleCoordinatorHarness()
        harness.accountDeletionCleanupPending = true
        let coordinator = AuthSessionLifecycleCoordinator(
            dependencies: harness.dependencies()
        )

        await coordinator.handle(harness.event())

        XCTAssertEqual(
            harness.events,
            [
                "clear-published-session",
                "clear-purchase-binding",
                "begin-purchase-resolution",
                "clear-entitlement"
            ]
        )
        XCTAssertEqual(harness.ghostProfileMergeReadCount, 0)
        XCTAssertEqual(harness.purchaseHandoffReadCount, 0)
        XCTAssertEqual(
            harness.diagnostics,
            [.deferredForAccountDeletionCleanup]
        )
    }

    func testActiveTransitionDefersBeforeDurableRecovery() async {
        let harness = AuthSessionLifecycleCoordinatorHarness()
        harness.hasActiveTransition = true
        let coordinator = AuthSessionLifecycleCoordinator(
            dependencies: harness.dependencies()
        )

        await coordinator.handle(harness.event())

        XCTAssertTrue(harness.events.isEmpty)
        XCTAssertEqual(harness.ghostProfileMergeReadCount, 0)
        XCTAssertEqual(harness.purchaseHandoffReadCount, 0)
        XCTAssertEqual(harness.diagnostics, [.deferredForActiveTransition])
    }

    func testDeferredSignOutReplaysAfterTransitionFinishes() async {
        let harness = AuthSessionLifecycleCoordinatorHarness()
        harness.hasActiveTransition = true
        let coordinator = AuthSessionLifecycleCoordinator(
            dependencies: harness.dependencies()
        )
        let replayCoordinator = AuthLifecycleReplayCoordinator()
        let event = harness.event(adoption: .signedOut)

        replayCoordinator.observeLifecycleEvent(
            deferredByActiveTransition: true
        )
        await coordinator.handle(event)

        // A provider failure can finish the transition without producing a
        // second SDK event. The retained obligation must replay signed-out
        // publication and all dependent cleanup from the current snapshot.
        harness.hasActiveTransition = false
        let scheduled = replayCoordinator.scheduleIfNeeded {
            await coordinator.handle(event)
        }
        while harness.diagnostics.last != .processed {
            await Task.yield()
        }

        XCTAssertTrue(scheduled)
        XCTAssertEqual(
            harness.diagnostics.first,
            .deferredForActiveTransition
        )
        XCTAssertEqual(harness.diagnostics.last, .processed)
        XCTAssertEqual(
            harness.events,
            [
                "clear-published-session",
                "clear-purchase-binding",
                "begin-account-session",
                "observe-consent-session",
                "purchase-sign-out",
                "validate-current-lifecycle",
                "clear-linked-user",
                "clear-author-marker",
                "cancel-author-refresh",
                "cancel-apple-revocation",
                "cancel-ghost-merge"
            ]
        )
    }

    func testDurableFenceReadsFailClosedIndependently() async {
        let ghostFailure = AuthSessionLifecycleCoordinatorHarness()
        ghostFailure.isTestExecution = true
        ghostFailure.ghostProfileMergeReadError =
            AuthSessionLifecycleCoordinatorTestError.unreadable
        let ghostCoordinator = AuthSessionLifecycleCoordinator(
            dependencies: ghostFailure.dependencies()
        )

        await ghostCoordinator.handle(ghostFailure.event())

        XCTAssertEqual(ghostFailure.analyticsSuppressionValues, [true])
        XCTAssertEqual(ghostFailure.purchaseHandoffFenceValues, [false])
        XCTAssertTrue(
            ghostFailure.diagnostics.contains(
                .ghostProfileMergeStateUnreadable
            )
        )

        let purchaseFailure = AuthSessionLifecycleCoordinatorHarness()
        purchaseFailure.isTestExecution = true
        purchaseFailure.purchaseHandoffReadError =
            AuthSessionLifecycleCoordinatorTestError.unreadable
        let purchaseCoordinator = AuthSessionLifecycleCoordinator(
            dependencies: purchaseFailure.dependencies()
        )

        await purchaseCoordinator.handle(purchaseFailure.event())

        XCTAssertEqual(purchaseFailure.analyticsSuppressionValues, [false])
        XCTAssertEqual(purchaseFailure.purchaseHandoffFenceValues, [true])
        XCTAssertTrue(
            purchaseFailure.diagnostics.contains(
                .purchaseHandoffStateUnreadable
            )
        )
    }

    func testAnonymousHandoffCompletesBeforeEntitlement() async {
        let harness = AuthSessionLifecycleCoordinatorHarness(
            isAnonymous: true
        )
        harness.pendingPurchaseIdentityHandoff = true
        harness.clearHandoffOnCompletion = true
        let coordinator = AuthSessionLifecycleCoordinator(
            dependencies: harness.dependencies()
        )

        await coordinator.handle(harness.event())

        XCTAssertEqual(
            harness.events,
            [
                "publish-authenticated",
                "begin-account-session",
                "observe-consent-session",
                "schedule-author-refresh",
                "complete-purchase-handoff",
                "validate-current-session",
                "begin-entitlement",
                "validate-current-session"
            ]
        )
        XCTAssertEqual(harness.diagnostics.last, .processed)
    }

    func testIdentityChangeResetsIdentityStateBeforePublication() async {
        let harness = AuthSessionLifecycleCoordinatorHarness()
        harness.publishedSession = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: false
        )
        harness.isTestExecution = true
        let coordinator = AuthSessionLifecycleCoordinator(
            dependencies: harness.dependencies()
        )

        await coordinator.handle(harness.event())

        XCTAssertEqual(
            Array(harness.events.prefix(8)),
            [
                "clear-purchase-binding",
                "clear-linked-user",
                "begin-purchase-resolution",
                "clear-entitlement",
                "publish-authenticated",
                "begin-account-session",
                "observe-consent-session",
                "schedule-author-refresh"
            ]
        )
    }

    func testRestoredSourceAbandonsHandoffBeforeRelinkingAndSyncing() async {
        let harness = AuthSessionLifecycleCoordinatorHarness()
        harness.pendingPurchaseIdentityHandoff = true
        harness.clearHandoffOnAbandonment = true
        harness.telemetryResults = [false, true]
        let coordinator = AuthSessionLifecycleCoordinator(
            dependencies: harness.dependencies()
        )

        await coordinator.handle(harness.event())

        XCTAssertEqual(
            harness.events,
            [
                "publish-authenticated",
                "begin-account-session",
                "observe-consent-session",
                "schedule-author-refresh",
                "ensure-telemetry",
                "abandon-source-handoffs",
                "ensure-telemetry",
                "validate-current-session",
                "begin-entitlement",
                "validate-current-session",
                "schedule-historical-sync"
            ]
        )
        XCTAssertEqual(harness.diagnostics.last, .processed)
    }

    func testStaleSessionAfterTelemetryStopsBeforeEntitlementAndSync() async {
        let harness = AuthSessionLifecycleCoordinatorHarness()
        harness.telemetryResults = [true]
        harness.advanceGenerationAfterTelemetry = true
        let coordinator = AuthSessionLifecycleCoordinator(
            dependencies: harness.dependencies()
        )

        await coordinator.handle(harness.event())

        XCTAssertEqual(
            harness.events,
            [
                "publish-authenticated",
                "begin-account-session",
                "observe-consent-session",
                "schedule-author-refresh",
                "ensure-telemetry",
                "validate-current-session"
            ]
        )
        XCTAssertFalse(harness.diagnostics.contains(.processed))
    }

    func testTransitionOverlapAfterTelemetryStopsBeforeEntitlement() async {
        let harness = AuthSessionLifecycleCoordinatorHarness()
        harness.telemetryResults = [true]
        harness.openTransitionAfterTelemetry = true
        let coordinator = AuthSessionLifecycleCoordinator(
            dependencies: harness.dependencies()
        )

        await coordinator.handle(harness.event())

        XCTAssertEqual(
            Array(harness.events.suffix(2)),
            ["ensure-telemetry", "validate-current-session"]
        )
        XCTAssertFalse(harness.events.contains("begin-entitlement"))
        XCTAssertFalse(harness.events.contains("schedule-historical-sync"))
        XCTAssertFalse(harness.diagnostics.contains(.processed))
    }

    func testStaleSessionAfterEntitlementStopsBeforeHistoricalSync() async {
        let harness = AuthSessionLifecycleCoordinatorHarness()
        harness.telemetryResults = [true]
        harness.advanceGenerationAfterEntitlement = true
        let coordinator = AuthSessionLifecycleCoordinator(
            dependencies: harness.dependencies()
        )

        await coordinator.handle(harness.event())

        XCTAssertEqual(
            Array(harness.events.suffix(3)),
            [
                "validate-current-session",
                "begin-entitlement",
                "validate-current-session"
            ]
        )
        XCTAssertFalse(harness.events.contains("schedule-historical-sync"))
        XCTAssertFalse(harness.diagnostics.contains(.processed))
    }

    func testAwaitingRefreshPublishesKnownAccountWithoutIdentityWork() async {
        let userID = UUID()
        let harness = AuthSessionLifecycleCoordinatorHarness(userID: userID)
        let coordinator = AuthSessionLifecycleCoordinator(
            dependencies: harness.dependencies()
        )

        await coordinator.handle(
            harness.event(adoption: .awaitingRefresh(userId: userID))
        )

        XCTAssertEqual(
            harness.events,
            [
                "clear-published-session",
                "clear-purchase-binding",
                "begin-purchase-resolution",
                "begin-account-session",
                "observe-consent-session"
            ]
        )
        XCTAssertEqual(
            Array(harness.diagnostics.suffix(2)),
            [.cachedSessionAwaitingRefresh, .processed]
        )
    }

    func testSigningOutIgnoresAuthenticatedAndRefreshEvents() async {
        let userID = UUID()
        let harness = AuthSessionLifecycleCoordinatorHarness(userID: userID)
        harness.isSigningOut = true
        let coordinator = AuthSessionLifecycleCoordinator(
            dependencies: harness.dependencies()
        )

        await coordinator.handle(harness.event())
        await coordinator.handle(
            harness.event(adoption: .awaitingRefresh(userId: userID))
        )

        XCTAssertTrue(harness.events.isEmpty)
        XCTAssertEqual(
            harness.diagnostics.filter {
                $0 == .authenticatedEventIgnoredDuringSignOut
                    || $0 == .refreshEventIgnoredDuringSignOut
            },
            [
                .authenticatedEventIgnoredDuringSignOut,
                .refreshEventIgnoredDuringSignOut
            ]
        )
        XCTAssertFalse(harness.diagnostics.contains(.processed))
    }

    func testSignedOutFinishesPublicationAfterPurchaseSignOut() async {
        let harness = AuthSessionLifecycleCoordinatorHarness()
        let coordinator = AuthSessionLifecycleCoordinator(
            dependencies: harness.dependencies()
        )

        await coordinator.handle(harness.event(adoption: .signedOut))

        XCTAssertEqual(
            harness.events,
            [
                "clear-published-session",
                "clear-purchase-binding",
                "begin-account-session",
                "observe-consent-session",
                "purchase-sign-out",
                "validate-current-lifecycle",
                "clear-linked-user",
                "clear-author-marker",
                "cancel-author-refresh",
                "cancel-apple-revocation",
                "cancel-ghost-merge"
            ]
        )
        XCTAssertEqual(harness.diagnostics.last, .processed)
    }

    func testStaleSignOutPostflightCannotCancelNewSessionWork() async {
        let harness = AuthSessionLifecycleCoordinatorHarness()
        harness.advanceGenerationAfterSignOut = true
        let coordinator = AuthSessionLifecycleCoordinator(
            dependencies: harness.dependencies()
        )

        await coordinator.handle(harness.event(adoption: .signedOut))

        XCTAssertEqual(
            Array(harness.events.suffix(2)),
            ["purchase-sign-out", "validate-current-lifecycle"]
        )
        XCTAssertFalse(harness.events.contains("clear-linked-user"))
        XCTAssertFalse(harness.events.contains("cancel-author-refresh"))
        XCTAssertFalse(harness.events.contains("cancel-apple-revocation"))
        XCTAssertFalse(harness.events.contains("cancel-ghost-merge"))
        XCTAssertFalse(harness.diagnostics.contains(.processed))
    }

    func testInconsistentEventFailsClosedBeforeSessionPublication() async {
        let harness = AuthSessionLifecycleCoordinatorHarness()
        let otherUserID = UUID()
        let coordinator = AuthSessionLifecycleCoordinator(
            dependencies: harness.dependencies()
        )
        let event = AuthSessionLifecycleEvent(
            adoption: .authenticated(userId: otherUserID),
            session: harness.session,
            authGeneration: 7,
            origin: .runtimeTransition
        )

        await coordinator.handle(event)

        XCTAssertTrue(harness.events.isEmpty)
        XCTAssertEqual(harness.diagnostics.last, .invalidEvent)
        XCTAssertFalse(harness.diagnostics.contains(.processed))
    }
}
