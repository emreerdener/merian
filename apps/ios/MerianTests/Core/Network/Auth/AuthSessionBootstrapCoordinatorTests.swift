@testable import Merian
import XCTest

@MainActor
final class AuthSessionBootstrapCoordinatorTests: XCTestCase {
    func testTestAndDeletionGatesStopBeforeSignOutOrSessionWork() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        let coordinator = AuthSessionBootstrapCoordinator()
        harness.isTestExecution = true

        let testResult = await coordinator.initialize(
            dependencies: harness.makeDependencies()
        )

        harness.isTestExecution = false
        harness.accountDeletionCleanupPending = true
        let deletionResult = await coordinator.initialize(
            dependencies: harness.makeDependencies()
        )

        XCTAssertNil(testResult)
        XCTAssertNil(deletionResult)
        XCTAssertTrue(harness.events.isEmpty)
        XCTAssertEqual(harness.transitionBeginCount, 0)
        XCTAssertEqual(harness.loadCount, 0)
    }

    func testAlreadyCancelledCallerStopsBeforeSignOutOrSessionWork() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        let coordinator = AuthSessionBootstrapCoordinator()
        let gate = AuthSessionBootstrapCoordinatorTestGate()
        harness.loadedSession = harness.existing

        let attempt = Task { @MainActor in
            await gate.wait()
            return await coordinator.initialize(
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        attempt.cancel()
        await gate.release()

        let result = await attempt.value

        XCTAssertNil(result)
        XCTAssertTrue(harness.events.isEmpty)
        XCTAssertEqual(harness.transitionBeginCount, 0)
        XCTAssertEqual(harness.loadCount, 0)
    }

    func testSignOutCompletesBeforeTransitionOrSessionResolution() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        let coordinator = AuthSessionBootstrapCoordinator()
        let gate = AuthSessionBootstrapCoordinatorTestGate()
        harness.signOutGate = gate
        harness.loadedSession = harness.existing

        let attempt = Task { @MainActor in
            await coordinator.initialize(
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)

        XCTAssertEqual(harness.transitionBeginCount, 0)
        XCTAssertEqual(harness.loadCount, 0)

        await gate.release()
        let result = await attempt.value

        XCTAssertEqual(result, harness.existing)
        XCTAssertEqual(harness.transitionBeginCount, 1)
        XCTAssertEqual(harness.loadCount, 1)
    }

    func testCallerCancellationWhileAwaitingSignOutStopsBeforeSessionWork() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        let coordinator = AuthSessionBootstrapCoordinator()
        let gate = AuthSessionBootstrapCoordinatorTestGate()
        harness.signOutGate = gate
        harness.loadedSession = harness.existing

        let attempt = Task { @MainActor in
            await coordinator.initialize(
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        attempt.cancel()
        await gate.release()

        let result = await attempt.value

        XCTAssertNil(result)
        XCTAssertEqual(harness.transitionBeginCount, 0)
        XCTAssertEqual(harness.loadCount, 0)
    }

    func testQuiescenceFailureStopsBeforeSessionResolution() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        harness.accountWorkQuiescenceSucceeds = false

        let result = await AuthSessionBootstrapCoordinator().initialize(
            dependencies: harness.makeDependencies()
        )

        XCTAssertNil(result)
        XCTAssertEqual(harness.transitionBeginCount, 1)
        XCTAssertEqual(harness.transitionFinishCount, 1)
        XCTAssertEqual(harness.loadCount, 0)
    }

    func testPublishedSessionReusesAccountWorkLeaseWithoutTransition() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        harness.currentSDKSession = harness.existing
        harness.currentPublishedSession = harness.existing
        harness.isAuthenticated = true

        let result = await AuthSessionBootstrapCoordinator().initialize(
            dependencies: harness.makeDependencies()
        )

        XCTAssertEqual(result, harness.existing)
        XCTAssertEqual(harness.accountWorkBeginCount, 1)
        XCTAssertEqual(harness.accountWorkFinishCount, 1)
        XCTAssertEqual(harness.readinessCount, 1)
        XCTAssertEqual(harness.transitionBeginCount, 0)
        XCTAssertEqual(harness.loadCount, 0)
        XCTAssertEqual(harness.publishCount, 0)
    }

    func testStaleAccountWorkLeaseRejectsPublishedSessionAfterReadiness() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        harness.currentSDKSession = harness.existing
        harness.currentPublishedSession = harness.existing
        harness.isAuthenticated = true
        harness.accountWorkIsCurrent = false

        let result = await AuthSessionBootstrapCoordinator().initialize(
            dependencies: harness.makeDependencies()
        )

        XCTAssertNil(result)
        XCTAssertEqual(harness.readinessCount, 1)
        XCTAssertEqual(harness.accountWorkFinishCount, 1)
    }

    func testOwnerlessCallersShareOneAnonymousBootstrapTask() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        let coordinator = AuthSessionBootstrapCoordinator()
        let gate = AuthSessionBootstrapCoordinatorTestGate()
        harness.loadError =
            AuthSessionBootstrapCoordinatorTestError.missingSession
        harness.createGate = gate

        let first = Task { @MainActor in
            await coordinator.initialize(
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        let second = Task { @MainActor in
            await coordinator.initialize(
                dependencies: harness.makeDependencies()
            )
        }
        await Task.yield()
        await gate.release()

        let firstResult = await first.value
        let secondResult = await second.value

        XCTAssertEqual(firstResult, harness.anonymous)
        XCTAssertEqual(secondResult, harness.anonymous)
        XCTAssertEqual(harness.transitionBeginCount, 1)
        XCTAssertEqual(harness.loadCount, 1)
        XCTAssertEqual(harness.createCount, 1)
        XCTAssertEqual(harness.transitionFinishCount, 1)
    }

    func testDifferentTransitionCannotJoinActiveBootstrap() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        let coordinator = AuthSessionBootstrapCoordinator()
        let gate = AuthSessionBootstrapCoordinatorTestGate()
        harness.activeTransition = harness.firstTransition
        harness.loadedSession = harness.existing
        harness.loadGate = gate

        let first = Task { @MainActor in
            await coordinator.initialize(
                ownedBy: harness.firstTransition,
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)

        let unrelated = await coordinator.initialize(
            ownedBy: harness.secondTransition,
            dependencies: harness.makeDependencies()
        )
        await gate.release()
        let firstResult = await first.value

        XCTAssertNil(unrelated)
        XCTAssertEqual(firstResult, harness.existing)
        XCTAssertEqual(harness.loadCount, 1)
        XCTAssertEqual(harness.transitionFinishCount, 0)
    }

    func testOwnerlessCallerRejectsReplacedAnonymousTransitionTask() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        let coordinator = AuthSessionBootstrapCoordinator()
        let gate = AuthSessionBootstrapCoordinatorTestGate()
        let rejected = expectation(
            description: "ownerless stale task admission rejected"
        )
        harness.activeTransition = harness.firstTransition
        harness.loadedSession = harness.existing
        harness.loadGate = gate

        let first = Task { @MainActor in
            await coordinator.initialize(
                ownedBy: harness.firstTransition,
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        harness.activeTransition = harness.secondTransition

        let ownerless = Task { @MainActor in
            let result = await coordinator.initialize(
                dependencies: harness.makeDependencies()
            )
            rejected.fulfill()
            return result
        }
        await fulfillment(of: [rejected], timeout: 1)
        await gate.release()

        let firstResult = await first.value
        let ownerlessResult = await ownerless.value

        XCTAssertNil(firstResult)
        XCTAssertNil(ownerlessResult)
        XCTAssertEqual(harness.loadCount, 1)
    }

    func testSessionMissingCreatesAndPublishesAnonymousIdentity() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        harness.loadError =
            AuthSessionBootstrapCoordinatorTestError.missingSession

        let result = await AuthSessionBootstrapCoordinator().initialize(
            dependencies: harness.makeDependencies()
        )

        XCTAssertEqual(result, harness.anonymous)
        XCTAssertEqual(harness.createCount, 1)
        XCTAssertEqual(harness.adoptionCount, 1)
        XCTAssertEqual(harness.publishCount, 1)
        XCTAssertEqual(harness.readinessCount, 1)
        XCTAssertEqual(harness.publicAuthorRefreshCount, 0)
        assertOrder(
            [
                "load-sdk-session",
                "create-anonymous-session",
                "adopt-",
                "publish-",
                "diagnose-anonymousSessionEstablished",
                "ensure-purchase-identity",
                "validate-published-session"
            ],
            in: harness.events
        )
    }

    func testNetworkSessionFailurePreservesIdentityWithoutAnonymousSignIn() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        harness.loadError = AuthSessionBootstrapCoordinatorTestError.network

        let result = await AuthSessionBootstrapCoordinator().initialize(
            dependencies: harness.makeDependencies()
        )

        XCTAssertNil(result)
        XCTAssertEqual(harness.createCount, 0)
        XCTAssertEqual(harness.publishCount, 0)
        XCTAssertTrue(
            harness.events.contains("diagnose-existingIdentityPreserved")
        )
    }

    func testAnonymousCreationFailureReportsWithoutPublishing() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        harness.loadError =
            AuthSessionBootstrapCoordinatorTestError.missingSession
        harness.createError =
            AuthSessionBootstrapCoordinatorTestError.anonymousCreation

        let result = await AuthSessionBootstrapCoordinator().initialize(
            dependencies: harness.makeDependencies()
        )

        XCTAssertNil(result)
        XCTAssertEqual(harness.createCount, 1)
        XCTAssertEqual(harness.publishCount, 0)
        XCTAssertTrue(
            harness.events.contains(
                "diagnose-anonymousSessionCreationFailed"
            )
        )
    }

    func testCancellationAfterSessionLoadStopsBeforeAnonymousCreation() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        let coordinator = AuthSessionBootstrapCoordinator()
        let gate = AuthSessionBootstrapCoordinatorTestGate()
        harness.loadError =
            AuthSessionBootstrapCoordinatorTestError.missingSession
        harness.loadGate = gate

        let attempt = Task { @MainActor in
            await coordinator.initialize(
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        let cancelledTask = coordinator.cancel()
        await gate.release()

        let result = await attempt.value
        _ = await cancelledTask?.value

        XCTAssertNil(result)
        XCTAssertEqual(harness.createCount, 0)
        XCTAssertEqual(harness.publishCount, 0)
    }

    func testTransitionChangeAfterSessionLoadStopsBeforePublication() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        let coordinator = AuthSessionBootstrapCoordinator()
        let gate = AuthSessionBootstrapCoordinatorTestGate()
        harness.activeTransition = harness.firstTransition
        harness.loadedSession = harness.existing
        harness.loadGate = gate

        let attempt = Task { @MainActor in
            await coordinator.initialize(
                ownedBy: harness.firstTransition,
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        harness.activeTransition = harness.secondTransition
        await gate.release()

        let result = await attempt.value

        XCTAssertNil(result)
        XCTAssertEqual(harness.adoptionCount, 0)
        XCTAssertEqual(harness.publishCount, 0)
    }

    func testCanceledPredecessorCannotClearReplacementTaskState() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        let coordinator = AuthSessionBootstrapCoordinator()
        let firstGate = AuthSessionBootstrapCoordinatorTestGate()
        let secondGate = AuthSessionBootstrapCoordinatorTestGate()
        harness.activeTransition = harness.firstTransition
        harness.loadedSession = harness.existing
        harness.loadGate = firstGate

        let first = Task { @MainActor in
            await coordinator.initialize(
                ownedBy: harness.firstTransition,
                dependencies: harness.makeDependencies()
            )
        }
        await firstGate.waitUntilWaiterCount(1)
        coordinator.cancel()
        harness.activeTransition = harness.secondTransition
        harness.loadedSession = harness.replacement
        harness.loadGate = secondGate

        let replacement = Task { @MainActor in
            await coordinator.initialize(
                ownedBy: harness.secondTransition,
                dependencies: harness.makeDependencies()
            )
        }
        await secondGate.waitUntilWaiterCount(1)
        await firstGate.release()
        _ = await first.value

        let joinedReplacement = Task { @MainActor in
            await coordinator.initialize(
                ownedBy: harness.secondTransition,
                dependencies: harness.makeDependencies()
            )
        }
        await Task.yield()
        XCTAssertEqual(harness.loadCount, 2)
        await secondGate.release()

        let replacementResult = await replacement.value
        let joinedResult = await joinedReplacement.value

        XCTAssertEqual(replacementResult, harness.replacement)
        XCTAssertEqual(joinedResult, harness.replacement)
        XCTAssertEqual(harness.loadCount, 2)
    }

    func testResolvedSessionSchedulesRefreshBeforePurchaseReadiness() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        harness.loadedSession = harness.existing

        let result = await AuthSessionBootstrapCoordinator().initialize(
            dependencies: harness.makeDependencies()
        )

        XCTAssertEqual(result, harness.existing)
        XCTAssertEqual(harness.publicAuthorRefreshCount, 1)
        assertOrder(
            [
                "publish-",
                "diagnose-existingSessionResolved",
                "schedule-public-author-refresh",
                "ensure-purchase-identity",
                "validate-published-session"
            ],
            in: harness.events
        )
    }

    func testCancellationDuringExistingSessionReadinessRejectsCompletion()
        async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        let coordinator = AuthSessionBootstrapCoordinator()
        let gate = AuthSessionBootstrapCoordinatorTestGate()
        harness.loadedSession = harness.existing
        harness.readinessGate = gate

        let attempt = Task { @MainActor in
            await coordinator.initialize(
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        let cancelledTask = coordinator.cancel()
        await gate.release()

        let result = await attempt.value
        _ = await cancelledTask?.value

        XCTAssertNil(result)
        XCTAssertEqual(harness.publishCount, 1)
        XCTAssertEqual(harness.readinessCount, 1)
        XCTAssertFalse(harness.events.contains("validate-published-session"))
    }

    func testCancellationDuringAnonymousReadinessRejectsCompletion() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        let coordinator = AuthSessionBootstrapCoordinator()
        let gate = AuthSessionBootstrapCoordinatorTestGate()
        harness.loadError =
            AuthSessionBootstrapCoordinatorTestError.missingSession
        harness.readinessGate = gate

        let attempt = Task { @MainActor in
            await coordinator.initialize(
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        let cancelledTask = coordinator.cancel()
        await gate.release()

        let result = await attempt.value
        _ = await cancelledTask?.value

        XCTAssertNil(result)
        XCTAssertEqual(harness.createCount, 1)
        XCTAssertEqual(harness.publishCount, 1)
        XCTAssertEqual(harness.readinessCount, 1)
        XCTAssertFalse(harness.events.contains("validate-published-session"))
    }

    func testSessionReplacementDuringPurchaseReadinessRejectsCompletion() async {
        let harness = AuthSessionBootstrapCoordinatorHarness()
        harness.loadedSession = harness.existing
        harness.readinessReplacement = harness.replacement

        let result = await AuthSessionBootstrapCoordinator().initialize(
            dependencies: harness.makeDependencies()
        )

        XCTAssertNil(result)
        XCTAssertEqual(harness.publishCount, 1)
        XCTAssertEqual(harness.readinessCount, 1)
        XCTAssertTrue(harness.events.contains("validate-published-session"))
    }

    private func assertOrder(
        _ prefixes: [String],
        in events: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var cursor = events.startIndex
        for prefix in prefixes {
            guard let index = events[cursor...].firstIndex(where: {
                $0.hasPrefix(prefix)
            }) else {
                XCTFail(
                    "Missing event prefix \(prefix) in \(events)",
                    file: file,
                    line: line
                )
                return
            }
            cursor = events.index(after: index)
        }
    }
}
