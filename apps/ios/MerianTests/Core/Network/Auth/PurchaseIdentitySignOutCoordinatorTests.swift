import Foundation
@testable import Merian
import XCTest

@MainActor
final class PurchaseIdentitySignOutCoordinatorTests: XCTestCase {
    func testStableSourceUsesPreparedRotationBeforeLocalSignOut() async {
        let harness = PurchaseSignOutCoordinatorHarness()
        harness.sdkIdentity = harness.sourceIdentity
        harness.initializedIdentity = harness.anonymousIdentity

        let completed = await harness.makeCoordinator()
            .transitionToGhostSession()

        XCTAssertTrue(completed)
        XCTAssertEqual(
            harness.events,
            [
                "begin-sign-out",
                "quiesce",
                "load-legacy",
                "load-stable",
                "load-sdk-session",
                "resolve-source",
                "link-telemetry",
                "pending-true",
                "prepare-stable",
                "sign-out",
                "initialize-anonymous",
                "complete-current",
                "finish"
            ]
        )
    }

    func testLegacySourceUsesCompatibilityPreparation() async {
        let harness = PurchaseSignOutCoordinatorHarness()
        harness.sdkIdentity = harness.sourceIdentity
        harness.initializedIdentity = harness.anonymousIdentity
        harness.sourceMode = .legacy

        let completed = await harness.makeCoordinator()
            .transitionToGhostSession()

        XCTAssertTrue(completed)
        XCTAssertTrue(harness.events.contains("prepare-legacy"))
        XCTAssertFalse(harness.events.contains("prepare-stable"))
        XCTAssertLessThan(
            harness.events.firstIndex(of: "prepare-legacy")!,
            harness.events.firstIndex(of: "sign-out")!
        )
    }

    func testUnreadableJournalFailsClosedBeforeReadingSession() async {
        let harness = PurchaseSignOutCoordinatorHarness()
        harness.legacyJournalError =
            PurchaseSignOutTestError.journal

        let completed = await harness.makeCoordinator()
            .transitionToGhostSession()

        XCTAssertFalse(completed)
        XCTAssertEqual(
            harness.events,
            [
                "begin-sign-out",
                "quiesce",
                "load-legacy",
                "pending-true",
                "diagnose-unreadable-journal",
                "finish"
            ]
        )
    }

    func testPendingStableRotationCompletesAgainstExistingAnonymousSession() async {
        let harness = PurchaseSignOutCoordinatorHarness()
        harness.installStableRotation()
        harness.sdkIdentity = harness.anonymousIdentity

        let completed = await harness.makeCoordinator()
            .transitionToGhostSession()

        XCTAssertTrue(completed)
        XCTAssertTrue(
            harness.events.contains(
                "complete-\(harness.anonymousIdentity.userID.uuidString.lowercased())"
            )
        )
        XCTAssertFalse(harness.events.contains("sign-out"))
        XCTAssertFalse(harness.events.contains("resolve-source"))
    }

    func testPendingProofCancellationDuringAnonymousInitializationStopsCompletion() async {
        let harness = PurchaseSignOutCoordinatorHarness()
        harness.installStableRotation()
        harness.sdkSessionError = PurchaseSignOutTestError.session
        harness.initializedIdentity = harness.anonymousIdentity
        harness.cancelDuringAnonymousInitialization = true

        let completed = await Task { @MainActor in
            await harness.makeCoordinator().transitionToGhostSession()
        }.value

        XCTAssertFalse(completed)
        XCTAssertTrue(harness.events.contains("initialize-anonymous"))
        XCTAssertFalse(harness.events.contains { event in
            event.hasPrefix("complete-")
        })
        XCTAssertEqual(harness.events.last, "finish")
    }

    func testPendingRotationCannotReplaceAnUnrelatedLinkedSession() async {
        let harness = PurchaseSignOutCoordinatorHarness()
        harness.installStableRotation()
        harness.sdkIdentity = harness.unrelatedIdentity

        let completed = await harness.makeCoordinator()
            .transitionToGhostSession()

        XCTAssertFalse(completed)
        XCTAssertTrue(
            harness.events.contains("diagnose-unrelated-stable")
        )
        XCTAssertFalse(harness.events.contains("abandon-stable"))
        XCTAssertFalse(harness.events.contains("sign-out"))
    }

    func testStableJournalRereadFailureRestoresFailClosedReadiness() async {
        let harness = PurchaseSignOutCoordinatorHarness()
        harness.installStableRotation()
        harness.sdkIdentity = harness.sourceIdentity
        harness.stableJournalErrorOnRead = 2

        let completed = await harness.makeCoordinator()
            .transitionToGhostSession()

        XCTAssertFalse(completed)
        XCTAssertEqual(harness.stableJournalReadCount, 2)
        XCTAssertEqual(
            harness.events.filter { $0 == "pending-true" }.count,
            2
        )
        XCTAssertTrue(
            harness.events.contains("diagnose-unreadable-journal")
        )
        XCTAssertFalse(harness.events.contains("sign-out"))
    }

    func testPendingLegacySourceIsAbandonedBeforePreparingReplacement() async {
        let harness = PurchaseSignOutCoordinatorHarness()
        harness.installLegacyHandoff()
        harness.sdkIdentity = harness.sourceIdentity
        harness.initializedIdentity = harness.anonymousIdentity
        harness.sourceMode = .legacy

        let completed = await harness.makeCoordinator()
            .transitionToGhostSession()

        XCTAssertTrue(completed)
        XCTAssertLessThan(
            harness.events.firstIndex(of: "abandon-legacy")!,
            harness.events.firstIndex(of: "prepare-legacy")!
        )
        XCTAssertLessThan(
            harness.events.firstIndex(of: "prepare-legacy")!,
            harness.events.firstIndex(of: "sign-out")!
        )
    }

    func testPendingLegacyHandoffCannotReplaceUnrelatedLinkedSession() async {
        let harness = PurchaseSignOutCoordinatorHarness()
        harness.installLegacyHandoff()
        harness.sdkIdentity = harness.unrelatedIdentity

        let completed = await harness.makeCoordinator()
            .transitionToGhostSession()

        XCTAssertFalse(completed)
        XCTAssertTrue(
            harness.events.contains("diagnose-unrelated-legacy")
        )
        XCTAssertFalse(harness.events.contains("abandon-legacy"))
        XCTAssertFalse(harness.events.contains("sign-out"))
    }

    func testFailedStablePreparationRestoresOnlyItsSourceSession() async {
        let harness = PurchaseSignOutCoordinatorHarness()
        harness.sdkIdentity = harness.sourceIdentity
        harness.initializedIdentity = harness.anonymousIdentity
        harness.preparationError =
            PurchaseSignOutTestError.preparation

        let completed = await harness.makeCoordinator()
            .transitionToGhostSession()

        XCTAssertFalse(completed)
        XCTAssertEqual(
            Array(harness.events.suffix(4)),
            [
                "diagnose-transition-failure",
                "abandon-stable",
                "restore-source",
                "finish"
            ]
        )
        XCTAssertFalse(harness.events.contains("sign-out"))
    }

    func testKnownLinkedIdentityRefusesUnverifiedSDKSession() async {
        let harness = PurchaseSignOutCoordinatorHarness()
        harness.sdkSessionError =
            PurchaseSignOutTestError.session
        harness.hasKnownLinkedIdentity = true
        harness.fallbackIdentity = harness.sourceIdentity

        let completed = await harness.makeCoordinator()
            .transitionToGhostSession()

        XCTAssertFalse(completed)
        XCTAssertTrue(
            harness.events.contains("diagnose-unverified-session")
        )
        XCTAssertFalse(harness.events.contains("load-fallback-session"))
        XCTAssertFalse(harness.events.contains("sign-out"))
    }

    func testAnonymousSessionUsesOrdinaryReplacementWithoutPurchaseProof() async {
        let harness = PurchaseSignOutCoordinatorHarness()
        harness.sdkIdentity = harness.anonymousIdentity
        harness.initializedIdentity = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: true
        )

        let completed = await harness.makeCoordinator()
            .transitionToGhostSession()

        XCTAssertTrue(completed)
        XCTAssertLessThan(
            harness.events.firstIndex(of: "sign-out")!,
            harness.events.firstIndex(of: "initialize-anonymous")!
        )
        XCTAssertFalse(harness.events.contains("resolve-source"))
        XCTAssertFalse(harness.events.contains("pending-true"))
    }

    func testRetryRequiresExactAnonymousRecoverySession() async {
        let harness = PurchaseSignOutCoordinatorHarness()
        harness.sdkIdentity = harness.anonymousIdentity

        let completed = await harness.makeCoordinator()
            .retryPendingHandoff()

        XCTAssertTrue(completed)
        XCTAssertEqual(
            harness.events,
            [
                "begin-recovery",
                "quiesce",
                "load-sdk-session",
                "phase-bindingPurchases",
                "complete-\(harness.anonymousIdentity.userID.uuidString.lowercased())",
                "finish"
            ]
        )
    }

    func testRetryStopsBeforeSessionLoadWhenQuiescenceFails() async {
        let harness = PurchaseSignOutCoordinatorHarness()
        harness.sdkIdentity = harness.anonymousIdentity
        harness.quiescenceSucceeds = false

        let completed = await harness.makeCoordinator()
            .retryPendingHandoff()

        XCTAssertFalse(completed)
        XCTAssertEqual(
            harness.events,
            ["begin-recovery", "quiesce", "finish"]
        )
    }

    func testCanceledTransitionDoesNotBegin() async {
        let harness = PurchaseSignOutCoordinatorHarness()

        let completed = await Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await harness.makeCoordinator()
                .transitionToGhostSession()
        }.value

        XCTAssertFalse(completed)
        XCTAssertTrue(harness.events.isEmpty)
    }

    func testRetryRejectsLinkedOrStaleRecoverySession() async {
        let linkedHarness = PurchaseSignOutCoordinatorHarness()
        linkedHarness.sdkIdentity = linkedHarness.sourceIdentity

        let linkedCompleted = await linkedHarness.makeCoordinator()
            .retryPendingHandoff()
        XCTAssertFalse(linkedCompleted)
        XCTAssertFalse(linkedHarness.events.contains { event in
            event.hasPrefix("complete-")
        })

        let staleHarness = PurchaseSignOutCoordinatorHarness()
        staleHarness.sdkIdentity = staleHarness.anonymousIdentity
        staleHarness.transitionMatches = false

        let staleCompleted = await staleHarness.makeCoordinator()
            .retryPendingHandoff()
        XCTAssertFalse(staleCompleted)
        XCTAssertFalse(staleHarness.events.contains { event in
            event.hasPrefix("complete-")
        })
    }

    func testRecoveryOwnedResetRequiresRecoveryTokenAndPreservesOwnership() async {
        let wrongKindHarness = PurchaseSignOutCoordinatorHarness()
        wrongKindHarness.transitionIsOwned = true

        let wrongKindCompleted = await wrongKindHarness.makeCoordinator()
            .resetGhostSessionForRetry(ownedBy: wrongKindHarness.token)

        XCTAssertFalse(wrongKindCompleted)
        XCTAssertTrue(wrongKindHarness.events.isEmpty)

        let recoveryHarness = PurchaseSignOutCoordinatorHarness()
        recoveryHarness.transitionIsOwned = true
        recoveryHarness.sdkIdentity = recoveryHarness.anonymousIdentity
        recoveryHarness.initializedIdentity = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: true
        )
        let recovery = AuthTransitionToken(
            id: recoveryHarness.token.id,
            kind: .recovery
        )

        let recoveryCompleted = await recoveryHarness.makeCoordinator()
            .resetGhostSessionForRetry(ownedBy: recovery)

        XCTAssertTrue(recoveryCompleted)
        XCTAssertTrue(recoveryHarness.transitionIsOwned)
        XCTAssertFalse(recoveryHarness.events.contains("begin-recovery"))
        XCTAssertFalse(recoveryHarness.events.contains("finish"))
    }
}
