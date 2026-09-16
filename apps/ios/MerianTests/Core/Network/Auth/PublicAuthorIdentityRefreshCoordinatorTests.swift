@testable import Merian
import XCTest

@MainActor
final class PublicAuthorRefreshCoordinatorTests: XCTestCase {
    func testSchedulingGatesRejectTestsTransitionsAndAnonymousSessions() {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()

        harness.isTestExecution = true
        XCTAssertFalse(
            coordinator.scheduleIfNeeded(
                for: harness.session(),
                dependencies: harness.dependencies(label: "test")
            )
        )

        harness.isTestExecution = false
        harness.hasActiveTransition = true
        XCTAssertFalse(
            coordinator.scheduleIfNeeded(
                for: harness.session(),
                dependencies: harness.dependencies(label: "transition")
            )
        )

        harness.hasActiveTransition = false
        XCTAssertFalse(
            coordinator.scheduleIfNeeded(
                for: harness.session(isAnonymous: true),
                dependencies: harness.dependencies(label: "anonymous")
            )
        )
        XCTAssertTrue(harness.events.isEmpty)
    }

    func testScheduledRefreshPreservesMergeLeaseRefreshAndPublishOrder() async {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()
        harness.publishedUserID = harness.firstUserID

        XCTAssertTrue(
            coordinator.scheduleIfNeeded(
                for: harness.session(),
                dependencies: harness.dependencies(label: "first")
            )
        )
        await waitUntil { harness.finishLeaseCount == 2 }

        XCTAssertEqual(harness.beginLeaseCount, 2)
        XCTAssertEqual(harness.finishLeaseCount, 2)
        XCTAssertEqual(harness.remoteRefreshCount, 1)
        XCTAssertEqual(harness.publishedChanges.count, 1)
        XCTAssertNil(harness.publishedChanges.first?.0)
        XCTAssertEqual(
            harness.publishedChanges.first?.1,
            harness.firstUserID.uuidString.lowercased()
        )
        assertOrder(
            [
                "begin-first",
                "merge-first",
                "begin-first",
                "refresh-first",
                "finish-first",
                "publish-first",
                "finish-first"
            ],
            in: harness.events
        )
        XCTAssertFalse(
            coordinator.scheduleIfNeeded(
                for: harness.session(),
                dependencies: harness.dependencies(label: "duplicate")
            )
        )
    }

    func testSameActiveUserSharesTheExistingScheduledAttempt() async {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()
        let gate = PublicAuthorIdentityRefreshTestGate()
        harness.publishedUserID = harness.firstUserID

        XCTAssertTrue(
            coordinator.scheduleIfNeeded(
                for: harness.session(),
                dependencies: harness.dependencies(
                    label: "active",
                    mergeGate: gate
                )
            )
        )
        await gate.waitUntilBlocked()
        XCTAssertFalse(
            coordinator.scheduleIfNeeded(
                for: harness.session(),
                dependencies: harness.dependencies(label: "duplicate")
            )
        )

        await gate.open()
        await waitUntil { harness.finishLeaseCount == 2 }

        XCTAssertEqual(harness.remoteRefreshCount, 1)
        XCTAssertEqual(harness.publishedChanges.count, 1)
        XCTAssertFalse(harness.events.contains("begin-duplicate"))
    }

    func testStaleScheduledUserCannotReplaceCurrentUserRefresh() async {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()
        let gate = PublicAuthorIdentityRefreshTestGate()
        harness.publishedUserID = harness.secondUserID

        XCTAssertTrue(
            coordinator.scheduleIfNeeded(
                for: harness.session(userID: harness.secondUserID),
                dependencies: harness.dependencies(
                    label: "current",
                    mergeGate: gate
                )
            )
        )
        await gate.waitUntilBlocked()

        XCTAssertFalse(
            coordinator.scheduleIfNeeded(
                for: harness.session(userID: harness.firstUserID),
                dependencies: harness.dependencies(label: "stale")
            )
        )
        await gate.open()
        await waitUntil { harness.finishLeaseCount == 2 }

        XCTAssertEqual(harness.remoteRefreshCount, 1)
        XCTAssertEqual(harness.publishedChanges.count, 1)
        XCTAssertEqual(
            harness.publishedChanges.first?.1,
            harness.secondUserID.uuidString.lowercased()
        )
        XCTAssertFalse(harness.events.contains("begin-stale"))
    }

    func testCancellationBeforeScheduledTaskStartsDoesNotOpenLease() async {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()
        harness.publishedUserID = harness.firstUserID

        XCTAssertTrue(
            coordinator.scheduleIfNeeded(
                for: harness.session(),
                dependencies: harness.dependencies(label: "cancelled")
            )
        )
        coordinator.cancel()
        await Task.yield()

        XCTAssertEqual(harness.beginLeaseCount, 0)
        XCTAssertEqual(harness.finishLeaseCount, 0)
        XCTAssertEqual(harness.remoteRefreshCount, 0)
        XCTAssertTrue(harness.publishedChanges.isEmpty)
    }

    func testCanceledPredecessorCannotClearReplacementTaskState() async {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()
        let predecessorGate = PublicAuthorIdentityRefreshTestGate()
        let replacementGate = PublicAuthorIdentityRefreshTestGate()
        harness.publishedUserID = harness.firstUserID

        XCTAssertTrue(
            coordinator.scheduleIfNeeded(
                for: harness.session(),
                dependencies: harness.dependencies(
                    label: "predecessor",
                    mergeGate: predecessorGate
                )
            )
        )
        await predecessorGate.waitUntilBlocked()

        harness.publishedUserID = harness.secondUserID
        XCTAssertTrue(
            coordinator.scheduleIfNeeded(
                for: harness.session(userID: harness.secondUserID),
                dependencies: harness.dependencies(
                    label: "replacement",
                    mergeGate: replacementGate
                )
            )
        )
        await replacementGate.waitUntilBlocked()

        await predecessorGate.open()
        await waitUntil {
            harness.events.contains("finish-predecessor")
        }
        XCTAssertFalse(
            coordinator.scheduleIfNeeded(
                for: harness.session(userID: harness.secondUserID),
                dependencies: harness.dependencies(label: "duplicate")
            )
        )

        await replacementGate.open()
        await waitUntil { harness.publishedChanges.count == 1 }

        XCTAssertEqual(harness.remoteRefreshCount, 1)
        XCTAssertEqual(
            harness.publishedChanges.first?.1,
            harness.secondUserID.uuidString.lowercased()
        )
        XCTAssertFalse(harness.events.contains("begin-duplicate"))
    }

    func testCancelDuringMergeStopsBeforeRemoteRefreshAndPublication() async {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()
        let gate = PublicAuthorIdentityRefreshTestGate()
        harness.publishedUserID = harness.firstUserID

        XCTAssertTrue(
            coordinator.scheduleIfNeeded(
                for: harness.session(),
                dependencies: harness.dependencies(
                    label: "cancelled",
                    mergeGate: gate
                )
            )
        )
        await gate.waitUntilBlocked()
        coordinator.cancel()
        await gate.open()
        await waitUntil { harness.finishLeaseCount == 1 }

        XCTAssertEqual(harness.remoteRefreshCount, 0)
        XCTAssertTrue(harness.publishedChanges.isEmpty)
    }

    func testStaleOuterLeaseAfterMergeStopsBeforeRemoteRefresh() async {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()
        let gate = PublicAuthorIdentityRefreshTestGate()
        harness.publishedUserID = harness.firstUserID

        XCTAssertTrue(
            coordinator.scheduleIfNeeded(
                for: harness.session(),
                dependencies: harness.dependencies(
                    label: "stale",
                    mergeGate: gate
                )
            )
        )
        await gate.waitUntilBlocked()
        harness.accountWorkIsCurrent = false
        await gate.open()
        await waitUntil { harness.finishLeaseCount == 1 }

        XCTAssertEqual(harness.remoteRefreshCount, 0)
        XCTAssertTrue(harness.publishedChanges.isEmpty)
    }

    func testRemoteFailureRollsBackBothLeasesAndReportsWithoutPublishing() async {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()
        harness.publishedUserID = harness.firstUserID
        harness.remoteError = PublicAuthorIdentityRefreshTestError.remote

        XCTAssertTrue(
            coordinator.scheduleIfNeeded(
                for: harness.session(),
                dependencies: harness.dependencies(label: "failure")
            )
        )
        await waitUntil { harness.finishLeaseCount == 2 }

        XCTAssertEqual(harness.reportedFailureCount, 1)
        XCTAssertEqual(harness.beginLeaseCount, 2)
        XCTAssertEqual(harness.finishLeaseCount, 2)
        XCTAssertTrue(harness.publishedChanges.isEmpty)
    }

    func testStaleLeaseAfterRemoteRefreshStopsBeforePublication() async {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()
        let gate = PublicAuthorIdentityRefreshTestGate()
        harness.publishedUserID = harness.firstUserID

        XCTAssertTrue(
            coordinator.scheduleIfNeeded(
                for: harness.session(),
                dependencies: harness.dependencies(
                    label: "stale",
                    refreshGate: gate
                )
            )
        )
        await gate.waitUntilBlocked()
        harness.accountWorkIsCurrent = false
        await gate.open()
        await waitUntil { harness.finishLeaseCount == 2 }

        XCTAssertEqual(harness.remoteRefreshCount, 1)
        XCTAssertTrue(harness.publishedChanges.isEmpty)
    }

    func testPublishedUserDriftAfterRemoteRefreshStopsPublication() async {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()
        let gate = PublicAuthorIdentityRefreshTestGate()
        harness.publishedUserID = harness.firstUserID

        XCTAssertTrue(
            coordinator.scheduleIfNeeded(
                for: harness.session(),
                dependencies: harness.dependencies(
                    label: "drift",
                    refreshGate: gate
                )
            )
        )
        await gate.waitUntilBlocked()
        harness.publishedUserID = harness.secondUserID
        await gate.open()
        await waitUntil { harness.finishLeaseCount == 2 }

        XCTAssertEqual(harness.remoteRefreshCount, 1)
        XCTAssertTrue(harness.publishedChanges.isEmpty)
    }

    func testTransitionOwnedRefreshUsesExactSessionWithoutAccountLease() async {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()
        let gate = PublicAuthorIdentityRefreshTestGate()
        harness.publishedUserID = harness.firstUserID

        let refresh = Task { @MainActor in
            await coordinator.refresh(
                expectedUserID: harness.firstUserID,
                ownedBy: harness.transition,
                dependencies: harness.dependencies(
                    label: "owned",
                    refreshGate: gate
                )
            )
        }
        await gate.waitUntilBlocked()
        harness.transitionMatches = false
        await gate.open()
        let result = await refresh.value

        XCTAssertFalse(result)
        XCTAssertEqual(harness.beginLeaseCount, 0)
        XCTAssertEqual(harness.finishLeaseCount, 0)
        XCTAssertEqual(harness.remoteRefreshCount, 1)
    }

    func testTransitionOwnedRefreshRejectsStaleSessionBeforeRemoteWork() async {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()
        harness.publishedUserID = harness.firstUserID
        harness.transitionMatches = false

        let result = await coordinator.refresh(
            expectedUserID: harness.firstUserID,
            ownedBy: harness.transition,
            dependencies: harness.dependencies(label: "stale")
        )

        XCTAssertFalse(result)
        XCTAssertEqual(harness.beginLeaseCount, 0)
        XCTAssertEqual(harness.finishLeaseCount, 0)
        XCTAssertEqual(harness.remoteRefreshCount, 0)
        XCTAssertTrue(harness.events.isEmpty)
    }

    func testAlreadyCancelledDirectRefreshDoesNotOpenLease() async {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()
        harness.publishedUserID = harness.firstUserID

        let refresh = Task { @MainActor in
            await coordinator.refresh(
                expectedUserID: harness.firstUserID,
                dependencies: harness.dependencies(label: "cancelled")
            )
        }
        refresh.cancel()
        let result = await refresh.value

        XCTAssertFalse(result)
        XCTAssertEqual(harness.beginLeaseCount, 0)
        XCTAssertEqual(harness.finishLeaseCount, 0)
        XCTAssertEqual(harness.remoteRefreshCount, 0)
        XCTAssertTrue(harness.events.isEmpty)
    }

    func testCancellationDuringDirectRefreshRejectsSuccessfulPostflight()
        async {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()
        let gate = PublicAuthorIdentityRefreshTestGate()
        harness.publishedUserID = harness.firstUserID

        let refresh = Task { @MainActor in
            await coordinator.refresh(
                expectedUserID: harness.firstUserID,
                ownedBy: harness.transition,
                dependencies: harness.dependencies(
                    label: "cancelled",
                    refreshGate: gate
                )
            )
        }
        await gate.waitUntilBlocked()
        refresh.cancel()
        await gate.open()
        let result = await refresh.value

        XCTAssertFalse(result)
        XCTAssertEqual(harness.remoteRefreshCount, 1)
        XCTAssertEqual(harness.reportedFailureCount, 0)
        XCTAssertEqual(harness.beginLeaseCount, 0)
        XCTAssertEqual(harness.finishLeaseCount, 0)
    }

    func testCancelledRemoteFailureDoesNotReportDiagnostic() async {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()
        let gate = PublicAuthorIdentityRefreshTestGate()
        harness.publishedUserID = harness.firstUserID
        harness.remoteError = CancellationError()

        let refresh = Task { @MainActor in
            await coordinator.refresh(
                expectedUserID: harness.firstUserID,
                ownedBy: harness.transition,
                dependencies: harness.dependencies(
                    label: "cancelled-error",
                    refreshGate: gate
                )
            )
        }
        await gate.waitUntilBlocked()
        refresh.cancel()
        await gate.open()
        let result = await refresh.value

        XCTAssertFalse(result)
        XCTAssertEqual(harness.remoteRefreshCount, 1)
        XCTAssertEqual(harness.reportedFailureCount, 0)
        XCTAssertFalse(harness.events.contains("diagnose-cancelled-error"))
    }

    func testOwnerlessRefreshUsesOneLeaseAndRevalidatesIt() async {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()
        harness.publishedUserID = harness.firstUserID

        let result = await coordinator.refresh(
            expectedUserID: harness.firstUserID,
            dependencies: harness.dependencies(label: "ownerless")
        )

        XCTAssertTrue(result)
        XCTAssertEqual(harness.beginLeaseCount, 1)
        XCTAssertEqual(harness.finishLeaseCount, 1)
        XCTAssertEqual(harness.remoteRefreshCount, 1)
    }

    func testClearingCompletedUserAllowsTheSameUserToRefreshAgain() async {
        let harness = PublicAuthorIdentityRefreshHarness()
        let coordinator = PublicAuthorIdentityRefreshCoordinator()
        harness.publishedUserID = harness.firstUserID

        XCTAssertTrue(
            coordinator.scheduleIfNeeded(
                for: harness.session(),
                dependencies: harness.dependencies(label: "first")
            )
        )
        await waitUntil { harness.finishLeaseCount == 2 }
        coordinator.clearCompletedUser()
        XCTAssertTrue(
            coordinator.scheduleIfNeeded(
                for: harness.session(),
                dependencies: harness.dependencies(label: "second")
            )
        )
        await waitUntil { harness.finishLeaseCount == 4 }

        XCTAssertEqual(harness.remoteRefreshCount, 2)
        XCTAssertEqual(harness.publishedChanges.count, 2)
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for coordinator state", file: file, line: line)
    }

    private func assertOrder(
        _ fragments: [String],
        in events: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var searchStart = events.startIndex
        for fragment in fragments {
            guard let index = events[searchStart...].firstIndex(where: {
                $0.contains(fragment)
            }) else {
                XCTFail(
                    "Missing ordered event containing \(fragment): \(events)",
                    file: file,
                    line: line
                )
                return
            }
            searchStart = events.index(after: index)
        }
    }
}
