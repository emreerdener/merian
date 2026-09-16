@testable import Merian
import XCTest

@MainActor
final class PurchaseIdentityHandoffCoordinatorTests: XCTestCase {
    func testAlreadyCanceledCallerDoesNotStartCompletion() async {
        let harness = PurchaseHandoffCoordinatorHarness()
        let coordinator = PurchaseIdentityHandoffCoordinator()
        let gate = PurchaseHandoffTestGate()
        harness.currentIdentity = harness.anonymousIdentity
        harness.installStableRotation()

        let attempt = Task { @MainActor in
            await gate.wait()
            return await coordinator.completePendingHandoff(
                expectedDestinationUserID:
                    harness.anonymousIdentity.userID.uuidString,
                expectedAuthGeneration: 7,
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        attempt.cancel()
        await gate.release()

        let completed = await attempt.value

        XCTAssertFalse(completed)
        XCTAssertEqual(harness.stableClaimCount, 0)
        XCTAssertTrue(harness.events.isEmpty)
    }

    func testStableRotationClearsProofAfterExactSessionAndEntitlementChecks() async {
        let harness = PurchaseHandoffCoordinatorHarness()
        harness.currentIdentity = harness.anonymousIdentity
        harness.installStableRotation()

        let completed = await PurchaseIdentityHandoffCoordinator()
            .completePendingHandoff(
                expectedDestinationUserID:
                    harness.anonymousIdentity.userID.uuidString,
                expectedAuthGeneration: 7,
                ownedBy: harness.token,
                dependencies: harness.makeDependencies()
            )

        XCTAssertTrue(completed)
        XCTAssertEqual(harness.stableClearCount, 1)
        assertOrder(
            [
                "claim-stable",
                "apply-stable",
                "verify-provider",
                "refresh-entitlement",
                "load-session",
                "clear-stable",
                "record-user",
                "refresh-customer",
                "stable-complete"
            ],
            in: harness.events
        )
    }

    func testLegacyHandoffPreservesCompatibilityCompletionOrder() async {
        let harness = PurchaseHandoffCoordinatorHarness()
        harness.currentIdentity = harness.anonymousIdentity
        harness.installLegacyHandoff()

        let completed = await PurchaseIdentityHandoffCoordinator()
            .completePendingHandoff(
                expectedDestinationUserID:
                    harness.anonymousIdentity.userID.uuidString,
                expectedAuthGeneration: 7,
                ownedBy: harness.token,
                dependencies: harness.makeDependencies()
            )

        XCTAssertTrue(completed)
        XCTAssertEqual(harness.legacyClearCount, 1)
        assertOrder(
            [
                "bind-legacy",
                "load-session",
                "link-legacy-provider",
                "load-session",
                "synchronize-legacy",
                "complete-legacy",
                "refresh-entitlement",
                "load-session",
                "clear-legacy",
                "link-telemetry",
                "legacy-complete"
            ],
            in: harness.events
        )
    }

    func testSameDestinationGenerationAndOwnerShareOneCompletionTask() async {
        let harness = PurchaseHandoffCoordinatorHarness()
        let coordinator = PurchaseIdentityHandoffCoordinator()
        let gate = PurchaseHandoffTestGate()
        harness.currentIdentity = harness.anonymousIdentity
        harness.installStableRotation()
        harness.stableClaimGate = gate
        let destination = harness.anonymousIdentity.userID.uuidString

        let first = Task { @MainActor in
            await coordinator.completePendingHandoff(
                expectedDestinationUserID: destination,
                expectedAuthGeneration: 7,
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        let second = Task { @MainActor in
            await coordinator.completePendingHandoff(
                expectedDestinationUserID: destination,
                expectedAuthGeneration: 7,
                dependencies: harness.makeDependencies()
            )
        }
        await Task.yield()

        await gate.release()
        let firstResult = await first.value
        let secondResult = await second.value

        XCTAssertTrue(firstResult)
        XCTAssertTrue(secondResult)
        XCTAssertEqual(harness.stableClaimCount, 1)
        XCTAssertEqual(harness.stableClearCount, 1)
    }

    func testNewGenerationCancelsStaleCompletionBeforeProofRemoval() async {
        let harness = PurchaseHandoffCoordinatorHarness()
        let coordinator = PurchaseIdentityHandoffCoordinator()
        let gate = PurchaseHandoffTestGate()
        harness.currentIdentity = harness.anonymousIdentity
        harness.installStableRotation()
        harness.stableClaimGate = gate

        let stale = Task { @MainActor in
            await coordinator.completePendingHandoff(
                expectedDestinationUserID:
                    harness.anonymousIdentity.userID.uuidString,
                expectedAuthGeneration: 7,
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        harness.currentIdentity = harness.replacementIdentity
        harness.currentAuthGeneration = 8
        let current = Task { @MainActor in
            await coordinator.completePendingHandoff(
                expectedDestinationUserID:
                    harness.replacementIdentity.userID.uuidString,
                expectedAuthGeneration: 8,
                dependencies: harness.makeDependencies()
            )
        }
        let currentResult = await current.value
        XCTAssertTrue(currentResult)
        XCTAssertFalse(harness.handoffPending)

        await gate.release()
        let staleResult = await stale.value

        XCTAssertFalse(staleResult)
        XCTAssertEqual(harness.stableClaimCount, 2)
        XCTAssertEqual(harness.stableClearCount, 1)
        XCTAssertFalse(harness.handoffPending)
        XCTAssertTrue(
            harness.events.contains(
                "record-user-\(harness.replacementIdentity.userID.uuidString.lowercased())"
            )
        )
    }

    func testTransitionOwnerReplacesOwnerlessForSameDestinationAndGeneration() async {
        let harness = PurchaseHandoffCoordinatorHarness()
        let coordinator = PurchaseIdentityHandoffCoordinator()
        let gate = PurchaseHandoffTestGate()
        harness.currentIdentity = harness.anonymousIdentity
        harness.installStableRotation()
        harness.stableClaimGate = gate

        let stale = Task { @MainActor in
            await coordinator.completePendingHandoff(
                expectedDestinationUserID:
                    harness.anonymousIdentity.userID.uuidString,
                expectedAuthGeneration: 7,
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        harness.activeTransitionID = harness.token.id

        let release = Task {
            for _ in 0..<10 {
                await Task.yield()
            }
            await gate.release()
        }
        let currentResult = await coordinator.completePendingHandoff(
            expectedDestinationUserID:
                harness.anonymousIdentity.userID.uuidString,
            expectedAuthGeneration: 7,
            ownedBy: harness.token,
            dependencies: harness.makeDependencies()
        )
        await release.value
        let staleResult = await stale.value

        XCTAssertTrue(currentResult)
        XCTAssertFalse(staleResult)
        XCTAssertEqual(harness.stableClaimCount, 2)
        XCTAssertEqual(harness.stableClearCount, 1)
        XCTAssertFalse(harness.handoffPending)
    }

    func testCanceledLegacyCompletionCannotRetireProofAfterReplacement() async {
        let harness = PurchaseHandoffCoordinatorHarness()
        let coordinator = PurchaseIdentityHandoffCoordinator()
        let gate = PurchaseHandoffTestGate()
        harness.currentIdentity = harness.anonymousIdentity
        harness.installLegacyHandoff()
        harness.legacyBindGate = gate
        harness.legacyBindError = PurchaseHandoffTestError.terminal

        let stale = Task { @MainActor in
            await coordinator.completePendingHandoff(
                expectedDestinationUserID:
                    harness.anonymousIdentity.userID.uuidString,
                expectedAuthGeneration: 7,
                dependencies: harness.makeDependencies()
            )
        }
        await gate.waitUntilWaiterCount(1)
        harness.currentIdentity = harness.replacementIdentity
        harness.currentAuthGeneration = 8

        let currentResult = await coordinator.completePendingHandoff(
            expectedDestinationUserID:
                harness.replacementIdentity.userID.uuidString,
            expectedAuthGeneration: 8,
            dependencies: harness.makeDependencies()
        )
        XCTAssertTrue(currentResult)
        XCTAssertEqual(harness.legacyClearCount, 1)
        XCTAssertFalse(harness.handoffPending)

        await gate.release()
        let staleResult = await stale.value

        XCTAssertFalse(staleResult)
        XCTAssertEqual(harness.legacyClearCount, 1)
        XCTAssertFalse(harness.handoffPending)
    }

    func testStaleAnonymousSessionRetainsLegacyProof() async {
        let harness = PurchaseHandoffCoordinatorHarness()
        harness.currentIdentity = harness.anonymousIdentity
        harness.activeSessionMatches = false
        harness.installLegacyHandoff()

        let completed = await PurchaseIdentityHandoffCoordinator()
            .completePendingHandoff(
                expectedDestinationUserID:
                    harness.anonymousIdentity.userID.uuidString,
                expectedAuthGeneration: 7,
                ownedBy: harness.token,
                dependencies: harness.makeDependencies()
            )

        XCTAssertFalse(completed)
        XCTAssertNotNil(harness.pendingLegacyHandoff)
        XCTAssertEqual(harness.legacyClearCount, 0)
        XCTAssertEqual(harness.legacyBindCount, 0)
    }

    func testTerminalLegacyErrorDiscardsProofButTransientErrorRetainsIt() async {
        let terminalHarness = PurchaseHandoffCoordinatorHarness()
        terminalHarness.currentIdentity = terminalHarness.anonymousIdentity
        terminalHarness.installLegacyHandoff()
        terminalHarness.legacyBindError = PurchaseHandoffTestError.terminal

        let terminalResult = await PurchaseIdentityHandoffCoordinator()
            .completePendingHandoff(
                expectedAuthGeneration: 7,
                ownedBy: terminalHarness.token,
                dependencies: terminalHarness.makeDependencies()
            )

        XCTAssertFalse(terminalResult)
        XCTAssertNil(terminalHarness.pendingLegacyHandoff)
        XCTAssertEqual(terminalHarness.legacyClearCount, 1)

        let transientHarness = PurchaseHandoffCoordinatorHarness()
        transientHarness.currentIdentity = transientHarness.anonymousIdentity
        transientHarness.installLegacyHandoff()
        transientHarness.legacyBindError = PurchaseHandoffTestError.operation

        let transientResult = await PurchaseIdentityHandoffCoordinator()
            .completePendingHandoff(
                expectedAuthGeneration: 7,
                ownedBy: transientHarness.token,
                dependencies: transientHarness.makeDependencies()
            )

        XCTAssertFalse(transientResult)
        XCTAssertNotNil(transientHarness.pendingLegacyHandoff)
        XCTAssertEqual(transientHarness.legacyClearCount, 0)
    }

    func testUnreadableSelectionFailsClosedBeforeSessionOrProviderWork() async {
        let harness = PurchaseHandoffCoordinatorHarness()
        harness.currentIdentity = harness.anonymousIdentity
        harness.stableJournalError = PurchaseHandoffTestError.journal

        let completed = await PurchaseIdentityHandoffCoordinator()
            .completePendingHandoff(
                expectedAuthGeneration: 7,
                ownedBy: harness.token,
                dependencies: harness.makeDependencies()
            )

        XCTAssertFalse(completed)
        XCTAssertTrue(harness.events.contains("pending-true"))
        XCTAssertTrue(harness.events.contains("diagnose-selection"))
        XCTAssertFalse(harness.events.contains("load-session"))
        XCTAssertFalse(harness.events.contains("claim-stable"))
    }

    func testRestoredSourceAbandonsLegacyProofWithoutBindingDestination() async {
        let harness = PurchaseHandoffCoordinatorHarness()
        harness.currentIdentity = harness.sourceIdentity
        harness.installLegacyHandoff()

        let completed = await PurchaseIdentityHandoffCoordinator()
            .completePendingHandoff(
                expectedAuthGeneration: 7,
                ownedBy: harness.token,
                dependencies: harness.makeDependencies()
            )

        XCTAssertFalse(completed)
        XCTAssertNil(harness.pendingLegacyHandoff)
        XCTAssertTrue(harness.events.contains("abandon-legacy"))
        XCTAssertEqual(harness.legacyBindCount, 0)
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
                    "Missing \(prefix) after index \(cursor) in \(events)",
                    file: file,
                    line: line
                )
                return
            }
            cursor = events.index(after: index)
        }
    }
}
