@testable import Merian
import XCTest

@MainActor
final class GhostProfileMergeCoordinatorTests: XCTestCase {
    func testPreparationPersistsReturnedProofBeforeHonoringCancellation() async {
        let harness = GhostProfileMergeCoordinatorHarness()
        let coordinator = GhostProfileMergeCoordinator()
        let gate = GhostProfileMergeCoordinatorTestGate()
        harness.currentIdentity = harness.source
        harness.activeTransitionID = harness.transition.id
        harness.prepareGate = gate

        let preparation = Task { @MainActor in
            try await coordinator.prepare(
                sourceUserID: harness.source.userID,
                provider: .google,
                providerSubject: "provider-subject",
                ownedBy: harness.transition,
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        preparation.cancel()
        await gate.release()

        do {
            _ = try await preparation.value
            XCTFail("Cancellation should end the OAuth preparation step")
        } catch is CancellationError {
            // Expected after the returned capability becomes durable.
        } catch {
            XCTFail("Unexpected preparation error: \(error)")
        }

        XCTAssertEqual(harness.prepareCount, 1)
        XCTAssertEqual(harness.persistCount, 1)
        XCTAssertEqual(harness.queue.count, 1)
        XCTAssertTrue(harness.analyticsIsSuppressed)
        assertOrder(
            ["prepare-remote", "load-queue", "persist-queue", "suppressed-true"],
            in: harness.events
        )
    }

    func testPreparationReplacesOnlyMatchingSourceProofInStableOrder() async throws {
        let harness = GhostProfileMergeCoordinatorHarness()
        harness.currentIdentity = harness.source
        harness.activeTransitionID = harness.transition.id
        let unrelated = harness.makeHandoff(
            id: "22222222-2222-2222-2222-222222222222",
            sourceUserID: UUID(
                uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"
            )!
        )
        let replaced = harness.makeHandoff(
            id: "33333333-3333-3333-3333-333333333333"
        )
        harness.queue = [unrelated, replaced]

        let prepared = try await GhostProfileMergeCoordinator().prepare(
            sourceUserID: harness.source.userID,
            provider: .google,
            providerSubject: "provider-subject",
            ownedBy: harness.transition,
            dependencies: harness.makeDependencies()
        )

        XCTAssertEqual(harness.queue.map(\.handoffId), [
            unrelated.handoffId,
            prepared.handoffId
        ])
        XCTAssertTrue(harness.analyticsIsSuppressed)
    }

    func testPreparationRejectsProviderTransitionMismatchBeforeRemoteWork() async {
        let harness = GhostProfileMergeCoordinatorHarness()
        harness.currentIdentity = harness.source
        harness.activeTransitionID = harness.transition.id

        do {
            _ = try await GhostProfileMergeCoordinator().prepare(
                sourceUserID: harness.source.userID,
                provider: .apple,
                providerSubject: "provider-subject",
                ownedBy: harness.transition,
                dependencies: harness.makeDependencies()
            )
            XCTFail("A provider-mismatched transition must be rejected")
        } catch SupabaseAuthTransitionError.guestMergeSessionChanged {
            // Expected before the remote preparation request.
        } catch {
            XCTFail("Unexpected preparation error: \(error)")
        }

        XCTAssertEqual(harness.prepareCount, 0)
        XCTAssertEqual(harness.persistCount, 0)
        XCTAssertTrue(harness.queue.isEmpty)
        XCTAssertFalse(harness.analyticsIsSuppressed)
    }

    func testPreparationRejectsChangedSessionBeforePersistingProof() async {
        let harness = GhostProfileMergeCoordinatorHarness()
        let gate = GhostProfileMergeCoordinatorTestGate()
        harness.currentIdentity = harness.source
        harness.activeTransitionID = harness.transition.id
        harness.prepareGate = gate

        let preparation = Task { @MainActor in
            try await GhostProfileMergeCoordinator().prepare(
                sourceUserID: harness.source.userID,
                provider: .google,
                providerSubject: "provider-subject",
                ownedBy: harness.transition,
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        harness.currentIdentity = harness.replacementTarget
        await gate.release()

        do {
            _ = try await preparation.value
            XCTFail("A stale source session must not persist a merge proof")
        } catch SupabaseAuthTransitionError.guestMergeSessionChanged {
            // Expected after the remote response but before local persistence.
        } catch {
            XCTFail("Unexpected preparation error: \(error)")
        }

        XCTAssertEqual(harness.prepareCount, 1)
        XCTAssertEqual(harness.persistCount, 0)
        XCTAssertTrue(harness.queue.isEmpty)
        XCTAssertFalse(harness.analyticsIsSuppressed)
    }

    func testSameTargetAndOwnerShareOneCompletionTask() async {
        let harness = GhostProfileMergeCoordinatorHarness()
        let coordinator = GhostProfileMergeCoordinator()
        let gate = GhostProfileMergeCoordinatorTestGate()
        harness.currentIdentity = harness.target
        harness.activeTransitionID = harness.transition.id
        harness.queue = [harness.makeHandoff()]
        harness.completeGate = gate

        let first = Task { @MainActor in
            await coordinator.completePendingHandoffs(
                expectedTargetUserID: harness.target.userID,
                ownedBy: harness.transition,
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        let second = Task { @MainActor in
            await coordinator.completePendingHandoffs(
                expectedTargetUserID: harness.target.userID,
                ownedBy: harness.transition,
                dependencies: harness.makeDependencies()
            )
        }
        await Task.yield()

        await gate.release()
        let firstResult = await first.value
        let secondResult = await second.value

        XCTAssertTrue(firstResult)
        XCTAssertTrue(secondResult)
        XCTAssertEqual(harness.completeCount, 1)
        XCTAssertEqual(harness.clearCount, 1)
        XCTAssertFalse(harness.analyticsIsSuppressed)
    }

    func testDifferentTargetCancelsStaleTaskBeforeProofRemoval() async {
        let harness = GhostProfileMergeCoordinatorHarness()
        let coordinator = GhostProfileMergeCoordinator()
        let gate = GhostProfileMergeCoordinatorTestGate()
        harness.currentIdentity = harness.target
        harness.queue = [harness.makeHandoff()]
        harness.completeGate = gate

        let stale = Task { @MainActor in
            await coordinator.completePendingHandoffs(
                expectedTargetUserID: harness.target.userID,
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        harness.currentIdentity = harness.replacementTarget

        let current = Task { @MainActor in
            await coordinator.completePendingHandoffs(
                expectedTargetUserID: harness.replacementTarget.userID,
                dependencies: harness.makeDependencies()
            )
        }
        let currentResult = await current.value

        await gate.release()
        let staleResult = await stale.value

        XCTAssertTrue(currentResult)
        XCTAssertFalse(staleResult)
        XCTAssertEqual(harness.completeCount, 2)
        XCTAssertEqual(harness.clearCount, 1)
        XCTAssertTrue(harness.queue.isEmpty)
        XCTAssertFalse(harness.analyticsIsSuppressed)
    }

    func testTransitionOwnerReplacesOwnerlessTaskForSameTarget() async {
        let harness = GhostProfileMergeCoordinatorHarness()
        let coordinator = GhostProfileMergeCoordinator()
        let gate = GhostProfileMergeCoordinatorTestGate()
        harness.currentIdentity = harness.target
        harness.queue = [harness.makeHandoff()]
        harness.completeGate = gate

        let ownerless = Task { @MainActor in
            await coordinator.completePendingHandoffs(
                expectedTargetUserID: harness.target.userID,
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        harness.activeTransitionID = harness.transition.id

        let owned = Task { @MainActor in
            await coordinator.completePendingHandoffs(
                expectedTargetUserID: harness.target.userID,
                ownedBy: harness.transition,
                dependencies: harness.makeDependencies()
            )
        }
        let ownedResult = await owned.value

        await gate.release()
        let ownerlessResult = await ownerless.value

        XCTAssertTrue(ownedResult)
        XCTAssertFalse(ownerlessResult)
        XCTAssertEqual(harness.completeCount, 2)
        XCTAssertEqual(harness.clearCount, 1)
    }

    func testUnreadableQueueFailsClosedBeforeSessionOrRemoteWork() async {
        let harness = GhostProfileMergeCoordinatorHarness()
        harness.currentIdentity = harness.target
        harness.queueLoadError = GhostProfileMergeCoordinatorTestError.queue

        let completed = await GhostProfileMergeCoordinator()
            .completePendingHandoffs(
                expectedTargetUserID: harness.target.userID,
                dependencies: harness.makeDependencies()
            )

        XCTAssertFalse(completed)
        XCTAssertTrue(harness.analyticsIsSuppressed)
        XCTAssertTrue(harness.events.contains("diagnose-queueUnreadable"))
        XCTAssertFalse(harness.events.contains("load-session"))
        XCTAssertEqual(harness.completeCount, 0)
    }

    func testTransientFailureRetainsProofAndSuppression() async {
        let harness = GhostProfileMergeCoordinatorHarness()
        harness.currentIdentity = harness.target
        let pending = harness.makeHandoff()
        harness.queue = [pending]
        harness.completionErrorsByHandoffID[pending.handoffId] =
            GhostProfileMergeCoordinatorTestError.remote

        let completed = await GhostProfileMergeCoordinator()
            .completePendingHandoffs(
                expectedTargetUserID: harness.target.userID,
                dependencies: harness.makeDependencies()
            )

        XCTAssertFalse(completed)
        XCTAssertEqual(harness.queue, [pending])
        XCTAssertEqual(harness.clearCount, 0)
        XCTAssertTrue(harness.analyticsIsSuppressed)
        XCTAssertTrue(harness.events.contains("diagnose-retryPending"))
    }

    func testTerminalFailureSynchronizesTargetBeforeClearingProof() async {
        let harness = GhostProfileMergeCoordinatorHarness()
        harness.currentIdentity = harness.target
        let pending = harness.makeHandoff()
        harness.queue = [pending]
        harness.completionErrorsByHandoffID[pending.handoffId] =
            GhostProfileMergeCoordinatorTestError.terminal

        let completed = await GhostProfileMergeCoordinator()
            .completePendingHandoffs(
                expectedTargetUserID: harness.target.userID,
                dependencies: harness.makeDependencies()
            )

        XCTAssertTrue(completed)
        XCTAssertTrue(harness.queue.isEmpty)
        XCTAssertEqual(harness.targetEvidenceSyncCount, 1)
        XCTAssertEqual(harness.clearCount, 1)
        XCTAssertFalse(harness.analyticsIsSuppressed)
        assertOrder(
            [
                "complete-\(pending.handoffId)",
                "synchronize-target-evidence",
                "clear-\(pending.handoffId)"
            ],
            in: harness.events
        )
    }

    func testCanceledTerminalResponseCannotSynchronizeOrClearProof() async {
        let harness = GhostProfileMergeCoordinatorHarness()
        let coordinator = GhostProfileMergeCoordinator()
        let gate = GhostProfileMergeCoordinatorTestGate()
        harness.currentIdentity = harness.target
        let pending = harness.makeHandoff()
        harness.queue = [pending]
        harness.completeGate = gate
        harness.completionErrorsByHandoffID[pending.handoffId] =
            GhostProfileMergeCoordinatorTestError.terminal

        let attempt = Task { @MainActor in
            await coordinator.completePendingHandoffs(
                expectedTargetUserID: harness.target.userID,
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        coordinator.cancel()
        await gate.release()

        let completed = await attempt.value

        XCTAssertFalse(completed)
        XCTAssertEqual(harness.queue, [pending])
        XCTAssertEqual(harness.targetEvidenceSyncCount, 0)
        XCTAssertEqual(harness.clearCount, 0)
        XCTAssertTrue(harness.analyticsIsSuppressed)
    }

    func testRetryableHandoffDoesNotBlockLaterHandoffCompletion() async {
        let harness = GhostProfileMergeCoordinatorHarness()
        harness.currentIdentity = harness.target
        let retryable = harness.makeHandoff(
            id: "11111111-1111-1111-1111-111111111111"
        )
        let successful = harness.makeHandoff(
            id: "22222222-2222-2222-2222-222222222222"
        )
        harness.queue = [retryable, successful]
        harness.completionErrorsByHandoffID[retryable.handoffId] =
            GhostProfileMergeCoordinatorTestError.remote

        let completed = await GhostProfileMergeCoordinator()
            .completePendingHandoffs(
                expectedTargetUserID: harness.target.userID,
                dependencies: harness.makeDependencies()
            )

        XCTAssertFalse(completed)
        XCTAssertEqual(harness.completeCount, 2)
        XCTAssertEqual(harness.queue, [retryable])
        XCTAssertEqual(harness.clearCount, 1)
        XCTAssertTrue(harness.analyticsIsSuppressed)
    }

    func testEmptyQueueReopensAnalyticsWithoutSessionOrRemoteWork() async {
        let harness = GhostProfileMergeCoordinatorHarness()
        harness.currentIdentity = harness.target

        let completed = await GhostProfileMergeCoordinator()
            .completePendingHandoffs(
                expectedTargetUserID: harness.target.userID,
                dependencies: harness.makeDependencies()
            )

        XCTAssertTrue(completed)
        XCTAssertFalse(harness.analyticsIsSuppressed)
        XCTAssertFalse(harness.events.contains("load-session"))
        XCTAssertEqual(harness.completeCount, 0)
    }

    func testClearingSourcePreservesSuppressionForUnrelatedProofs() throws {
        let harness = GhostProfileMergeCoordinatorHarness()
        let unrelatedSource = UUID(
            uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"
        )!
        harness.queue = [
            harness.makeHandoff(),
            harness.makeHandoff(
                id: "22222222-2222-2222-2222-222222222222",
                sourceUserID: unrelatedSource
            )
        ]

        try GhostProfileMergeCoordinator().clearHandoffs(
            for: harness.source.userID,
            dependencies: harness.makeDependencies()
        )

        XCTAssertEqual(harness.queue.count, 1)
        XCTAssertEqual(harness.queue.first?.ghostUserId, unrelatedSource.uuidString.lowercased())
        XCTAssertTrue(harness.analyticsIsSuppressed)
    }

    private func assertOrder(
        _ expectedPrefixes: [String],
        in events: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var cursor = events.startIndex
        for prefix in expectedPrefixes {
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
