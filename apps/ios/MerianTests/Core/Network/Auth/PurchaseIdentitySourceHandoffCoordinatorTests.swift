import Foundation
@testable import Merian
import Testing

private actor SourceHandoffSuspensionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func wait() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilBlocked() async {
        while !isReleased && continuation == nil {
            await Task.yield()
        }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}

@Suite("Purchase Identity Source Handoff Coordinator")
@MainActor
struct SourceHandoffCoordinatorTests {
    @Test func unreadableJournalFailsClosedAndPublishesFence() {
        let harness = PurchaseIdentitySourceHandoffHarness()
        harness.legacyJournalError =
            PurchaseIdentitySourceHandoffTestError.journal

        let pending = makeCoordinator(harness)
            .hasPendingHandoffFailClosed()

        #expect(pending)
        #expect(harness.publishedPendingValues == [true])
        #expect(harness.events == [
            "load-legacy",
            "pending-true",
            "diagnose-pending"
        ])
    }

    @Test func journalProjectionPublishesAggregateStateOnce() throws {
        let harness = PurchaseIdentitySourceHandoffHarness()
        harness.installStableRotation()

        let pending = try makeCoordinator(harness)
            .loadAndPublishPendingState()

        #expect(pending)
        #expect(harness.publishedPendingValues == [true])
        #expect(harness.events == [
            "load-legacy",
            "load-stable",
            "pending-true"
        ])
    }

    @Test func stablePreparationRejectsSessionDriftAfterDurableWork() async {
        let harness = PurchaseIdentitySourceHandoffHarness()
        harness.mutateDuringStablePreparation = {
            harness.currentSession = AuthTransitionSession(
                userID: harness.replacementUserID,
                isAnonymous: true
            )
        }

        do {
            try await makeCoordinator(harness).prepareStableRotation(
                source: harness.sourceContext(),
                ownedBy: harness.token
            )
            Issue.record("Expected stable preparation session drift")
        } catch SupabaseAuthTransitionError.signOutSessionChanged {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(harness.events == [
            "load-session",
            "prepare-stable",
            "load-session"
        ])
    }

    @Test func legacyPreparationRejectsSessionDriftAfterDurableWork() async {
        let harness = PurchaseIdentitySourceHandoffHarness()
        harness.mutateDuringLegacyPreparation = {
            harness.currentSession = AuthTransitionSession(
                userID: harness.replacementUserID,
                isAnonymous: true
            )
        }

        do {
            try await makeCoordinator(harness).prepareLegacyHandoff(
                sourceUserID: harness.sourceUserID.uuidString,
                ownedBy: harness.token
            )
            Issue.record("Expected legacy preparation session drift")
        } catch SupabaseAuthTransitionError.signOutSessionChanged {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(harness.events == [
            "load-session",
            "prepare-legacy",
            "load-session"
        ])
    }

    @Test func legacyPreparationCancellationDuringFinalReadStopsCompletion() async {
        let harness = PurchaseIdentitySourceHandoffHarness()
        let gate = SourceHandoffSuspensionGate()
        harness.beforeSDKSessionReturn = { callCount in
            guard callCount == 2 else { return }
            await gate.wait()
        }
        let coordinator = makeCoordinator(harness)
        let task = Task { @MainActor in
            try await coordinator.prepareLegacyHandoff(
                sourceUserID: harness.sourceUserID.uuidString,
                ownedBy: harness.token
            )
        }
        await gate.waitUntilBlocked()

        task.cancel()
        await gate.release()

        do {
            try await task.value
            Issue.record("Expected legacy preparation cancellation")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(harness.events == [
            "load-session",
            "prepare-legacy",
            "load-session"
        ])
    }

    @Test func stableAbandonmentCancelsThenClearsExactSourceProof() async {
        let harness = PurchaseIdentitySourceHandoffHarness()
        harness.installStableRotation()

        await makeCoordinator(harness)
            .abandonStableRotationIfSourceRestored(
                sourceUserID: harness.sourceUserID,
                ownedBy: harness.token
            )

        #expect(harness.pendingStable == nil)
        #expect(harness.publishedPendingValues == [false])
        #expect(harness.events == [
            "load-session",
            "load-stable",
            "cancel-stable",
            "load-session",
            "clear-stable",
            "load-legacy",
            "load-stable",
            "pending-false"
        ])
    }

    @Test func staleStableCancellationRetainsProofAndFailClosedFence() async {
        let harness = PurchaseIdentitySourceHandoffHarness()
        harness.installStableRotation()
        harness.mutateDuringStableCancellation = {
            harness.currentSession = AuthTransitionSession(
                userID: harness.replacementUserID,
                isAnonymous: true
            )
        }

        await makeCoordinator(harness)
            .abandonStableRotationIfSourceRestored(
                sourceUserID: harness.sourceUserID,
                ownedBy: harness.token
            )

        #expect(harness.pendingStable != nil)
        #expect(harness.publishedPendingValues == [true])
        #expect(!harness.events.contains("clear-stable"))
    }

    @Test func unownedStableAbandonmentReleasesAccountWorkLease() async {
        let harness = PurchaseIdentitySourceHandoffHarness()
        harness.installStableRotation()

        await makeCoordinator(harness)
            .abandonStableRotationIfSourceRestored(
                sourceUserID: harness.sourceUserID
            )

        #expect(harness.pendingStable == nil)
        #expect(harness.publishedPendingValues == [false])
        #expect(harness.events == [
            "begin-account-work",
            "load-session",
            "load-stable",
            "cancel-stable",
            "load-session",
            "clear-stable",
            "load-legacy",
            "load-stable",
            "pending-false",
            "finish-account-work"
        ])
    }

    @Test func accountWorkInvalidatedDuringInitialReadSkipsStableCancel() async {
        let harness = PurchaseIdentitySourceHandoffHarness()
        let gate = SourceHandoffSuspensionGate()
        harness.installStableRotation()
        harness.beforeSDKSessionReturn = { callCount in
            guard callCount == 1 else { return }
            await gate.wait()
        }
        let coordinator = makeCoordinator(harness)
        let task = Task { @MainActor in
            await coordinator.abandonStableRotationIfSourceRestored(
                sourceUserID: harness.sourceUserID
            )
        }
        await gate.waitUntilBlocked()

        harness.accountWorkIsCurrent = false
        await gate.release()
        await task.value

        #expect(harness.pendingStable != nil)
        #expect(!harness.events.contains("load-stable"))
        #expect(!harness.events.contains("cancel-stable"))
        #expect(harness.events.first == "begin-account-work")
        #expect(harness.events.last == "finish-account-work")
    }

    @Test func accountWorkInvalidatedDuringFinalReadRetainsStableProof() async {
        let harness = PurchaseIdentitySourceHandoffHarness()
        let gate = SourceHandoffSuspensionGate()
        harness.installStableRotation()
        harness.beforeSDKSessionReturn = { callCount in
            guard callCount == 2 else { return }
            await gate.wait()
        }
        let coordinator = makeCoordinator(harness)
        let task = Task { @MainActor in
            await coordinator.abandonStableRotationIfSourceRestored(
                sourceUserID: harness.sourceUserID
            )
        }
        await gate.waitUntilBlocked()

        harness.accountWorkIsCurrent = false
        await gate.release()
        await task.value

        #expect(harness.pendingStable != nil)
        #expect(harness.publishedPendingValues == [true])
        #expect(!harness.events.contains("clear-stable"))
        #expect(harness.events.first == "begin-account-work")
        #expect(harness.events.last == "finish-account-work")
    }

    @Test func legacyAbandonmentCancelsClearsAndPublishesAggregate() async {
        let harness = PurchaseIdentitySourceHandoffHarness()
        harness.installLegacyHandoff()

        await makeCoordinator(harness)
            .abandonLegacyHandoffIfSourceRestored(
                sourceUserID: harness.sourceUserID.uuidString,
                ownedBy: harness.token
            )

        #expect(harness.pendingLegacy == nil)
        #expect(harness.publishedPendingValues == [false])
        #expect(harness.events == [
            "load-session",
            "load-legacy",
            "cancel-legacy",
            "clear-legacy",
            "load-legacy",
            "load-stable",
            "pending-false",
            "diagnose-abandoned-legacy"
        ])
    }

    @Test func accountWorkInvalidatedDuringInitialReadSkipsLegacyCancel() async {
        let harness = PurchaseIdentitySourceHandoffHarness()
        let gate = SourceHandoffSuspensionGate()
        harness.installLegacyHandoff()
        harness.beforeSDKSessionReturn = { callCount in
            guard callCount == 1 else { return }
            await gate.wait()
        }
        let coordinator = makeCoordinator(harness)
        let task = Task { @MainActor in
            await coordinator.abandonLegacyHandoffIfSourceRestored(
                sourceUserID: harness.sourceUserID.uuidString
            )
        }
        await gate.waitUntilBlocked()

        harness.accountWorkIsCurrent = false
        await gate.release()
        await task.value

        #expect(harness.pendingLegacy != nil)
        #expect(!harness.events.contains("load-legacy"))
        #expect(!harness.events.contains("cancel-legacy"))
        #expect(harness.events.first == "begin-account-work")
        #expect(harness.events.last == "finish-account-work")
    }

    @Test func failedSignOutRestoresSourceInFencedOrder() async {
        let harness = PurchaseIdentitySourceHandoffHarness()

        await makeCoordinator(harness)
            .restoreSourceIdentityAfterFailedSignOut(
                sourceUserID: harness.sourceUserID,
                ownedBy: harness.token
            )

        #expect(harness.publishedPendingValues == [false])
        #expect(harness.events == [
            "load-session",
            "load-legacy",
            "load-stable",
            "adopt-source",
            "pending-false",
            "publish-source",
            "ensure-purchase-identity",
            "begin-entitlement",
            "diagnose-restored-source"
        ])
    }

    @Test func pendingProofPreventsSourceRestorationAndRetainsFence() async {
        let harness = PurchaseIdentitySourceHandoffHarness()
        harness.installLegacyHandoff()

        await makeCoordinator(harness)
            .restoreSourceIdentityAfterFailedSignOut(
                sourceUserID: harness.sourceUserID,
                ownedBy: harness.token
            )

        #expect(harness.publishedPendingValues == [true])
        #expect(!harness.events.contains("adopt-source"))
        #expect(!harness.events.contains("ensure-purchase-identity"))
    }

    @Test func cancellationBeforeEntryProducesNoEffects() async {
        let harness = PurchaseIdentitySourceHandoffHarness()
        harness.installStableRotation()
        let coordinator = makeCoordinator(harness)
        let task = Task { @MainActor in
            await Task.yield()
            await coordinator.abandonStableRotationIfSourceRestored(
                sourceUserID: harness.sourceUserID,
                ownedBy: harness.token
            )
        }
        task.cancel()

        await task.value

        #expect(harness.events.isEmpty)
        #expect(harness.pendingStable != nil)
    }

    private func makeCoordinator(
        _ harness: PurchaseIdentitySourceHandoffHarness
    ) -> PurchaseIdentitySourceHandoffCoordinator {
        PurchaseIdentitySourceHandoffCoordinator(
            dependencies: harness.dependencies()
        )
    }
}
