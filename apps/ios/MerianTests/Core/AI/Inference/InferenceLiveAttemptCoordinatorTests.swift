import Foundation
import Testing

@testable import Merian

@MainActor
private final class InferenceLiveAttemptQueueHarness {
    enum Event: Equatable {
        case release(String, UUID?, String)
        case retire(String, UUID, Bool, String)
    }

    var durableCurrent = true
    var deleteResult = true
    var foregroundGenerations: [String: UUID] = [:]
    var deleteOperation: (@MainActor () async -> Bool)?
    var onRelease: (@MainActor () -> Void)?
    var onRetire: (@MainActor () -> Void)?
    private(set) var deleteCallCount = 0
    private(set) var events: [Event] = []

    var service: InferenceLiveQueueService {
        InferenceLiveQueueService(dependencies: .init(
            releaseDeferredUpload: { [self] scanId, generation, reason in
                onRelease?()
                events.append(.release(scanId, generation, reason))
            },
            retireForegroundInference: { [self] scanId, generation, resumeBackground, reason in
                onRetire?()
                events.append(
                    .retire(scanId, generation, resumeBackground, reason)
                )
            },
            claimForegroundInferenceStart: { _, _ in true },
            isForegroundInferenceAttemptCurrent: { [self] _, _ in
                durableCurrent
            },
            foregroundInferenceGeneration: { [self] scanId in
                foregroundGenerations[scanId]
            },
            deleteQueuedScan: { [self] _, _, _ in
                deleteCallCount += 1
                if let deleteOperation {
                    return await deleteOperation()
                }
                return deleteResult
            },
            rejectQueuedScan: { _, _, _ in true }
        ))
    }
}

@MainActor
@Suite("Inference Live Attempt Coordinator")
struct InferenceLiveAttemptCoordinatorTests {
    @Test func currentAttemptRequiresExactLocalAndDurableOwners() {
        let queue = InferenceLiveAttemptQueueHarness()
        let coordinator = InferenceLiveAttemptCoordinator(
            queueService: queue.service
        )
        let attempt = UUID()
        let foreground = UUID()
        coordinator.activate(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )

        #expect(coordinator.isAttemptCurrent(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        ))
        #expect(!coordinator.isAttemptCurrent(
            scanId: "scan-b",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        ))
        #expect(!coordinator.isAttemptCurrent(
            scanId: "scan-a",
            attemptGeneration: UUID(),
            foregroundGeneration: foreground
        ))
        #expect(!coordinator.isAttemptCurrent(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: UUID()
        ))

        queue.durableCurrent = false
        #expect(!coordinator.isAttemptCurrent(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        ))
        #expect(throws: CancellationError.self) {
            try coordinator.checkAttempt(
                scanId: "scan-a",
                attemptGeneration: attempt,
                foregroundGeneration: foreground
            )
        }
    }

    @Test func queueLessAttemptUsesOnlyItsExactLocalOwner() throws {
        let queue = InferenceLiveAttemptQueueHarness()
        queue.durableCurrent = false
        let coordinator = InferenceLiveAttemptCoordinator(
            queueService: queue.service
        )
        let attempt = UUID()
        coordinator.activate(
            scanId: nil,
            attemptGeneration: attempt,
            foregroundGeneration: nil
        )

        #expect(coordinator.isAttemptCurrent(
            scanId: nil,
            attemptGeneration: attempt,
            foregroundGeneration: nil
        ))
        try coordinator.checkAttempt(
            scanId: nil,
            attemptGeneration: attempt,
            foregroundGeneration: nil
        )
    }

    @Test func queueFinalizationRejectsPartialDurableIdentity() async {
        let queue = InferenceLiveAttemptQueueHarness()
        let coordinator = InferenceLiveAttemptCoordinator(
            queueService: queue.service
        )
        let attempt = UUID()

        coordinator.activate(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: nil
        )
        #expect(
            await coordinator.completeQueuedInferenceIfNeeded(
                scanId: "scan-a",
                attemptGeneration: attempt,
                foregroundGeneration: nil,
                mediaPathsToKeep: []
            ) == false
        )

        let foreground = UUID()
        coordinator.activate(
            scanId: nil,
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )
        #expect(
            await coordinator.completeQueuedInferenceIfNeeded(
                scanId: nil,
                attemptGeneration: attempt,
                foregroundGeneration: foreground,
                mediaPathsToKeep: []
            ) == false
        )
        #expect(queue.deleteCallCount == 0)
    }

    @Test func invalidationClearsLocalIdentityBeforeQueueCallbacks() {
        let queue = InferenceLiveAttemptQueueHarness()
        let coordinator = InferenceLiveAttemptCoordinator(
            queueService: queue.service
        )
        defer {
            queue.onRelease = nil
            queue.onRetire = nil
        }
        let attempt = UUID()
        let foreground = UUID()
        coordinator.activate(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )
        queue.onRelease = {
            #expect(coordinator.activeScanId == nil)
            #expect(coordinator.activeAttemptGeneration == nil)
            #expect(coordinator.activeForegroundGeneration == nil)
        }
        queue.onRetire = queue.onRelease

        coordinator.invalidateActiveAttempt(
            resumeBackground: true,
            reason: "replacement"
        )

        #expect(queue.events == [
            .release("scan-a", foreground, "replacement"),
            .retire("scan-a", foreground, true, "replacement")
        ])
    }

    @Test func currentRetirementFencesDurableOwnerBeforeCallback() {
        let queue = InferenceLiveAttemptQueueHarness()
        let coordinator = InferenceLiveAttemptCoordinator(
            queueService: queue.service
        )
        defer { queue.onRetire = nil }
        let originalAttempt = UUID()
        let originalForeground = UUID()
        let replacementAttempt = UUID()
        let replacementForeground = UUID()
        coordinator.activate(
            scanId: "scan-a",
            attemptGeneration: originalAttempt,
            foregroundGeneration: originalForeground
        )
        queue.onRetire = {
            #expect(coordinator.activeScanId == "scan-a")
            #expect(
                coordinator.activeAttemptGeneration == originalAttempt
            )
            #expect(coordinator.activeForegroundGeneration == nil)
            coordinator.activate(
                scanId: "scan-a",
                attemptGeneration: replacementAttempt,
                foregroundGeneration: replacementForeground
            )
        }

        coordinator.retireForegroundInferenceIfCurrent(
            scanId: "scan-a",
            attemptGeneration: originalAttempt,
            foregroundGeneration: originalForeground,
            resumeBackground: true,
            reason: "handoff"
        )

        #expect(queue.events == [
            .retire("scan-a", originalForeground, true, "handoff")
        ])
        #expect(coordinator.activeScanId == "scan-a")
        #expect(coordinator.activeAttemptGeneration == replacementAttempt)
        #expect(coordinator.activeForegroundGeneration == replacementForeground)
    }

    @Test func failedFinalizationRetiresOnlyTheStillCurrentAttempt() async {
        let queue = InferenceLiveAttemptQueueHarness()
        queue.deleteResult = false
        let coordinator = InferenceLiveAttemptCoordinator(
            queueService: queue.service
        )
        let attempt = UUID()
        let foreground = UUID()
        coordinator.activate(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )

        let didFinalize = await coordinator.completeQueuedInferenceIfNeeded(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground,
            mediaPathsToKeep: []
        )

        #expect(!didFinalize)
        #expect(queue.events == [
            .retire(
                "scan-a",
                foreground,
                true,
                "live_cleanup_failed_or_replaced"
            )
        ])
        #expect(coordinator.activeForegroundGeneration == nil)
    }

    @Test func staleSuccessfulFinalizationCannotClearOrAuthorizeReplacementOwner() async {
        let gate = InferenceOperationGate()
        let queue = InferenceLiveAttemptQueueHarness()
        queue.deleteOperation = {
            await gate.wait()
            return true
        }
        let coordinator = InferenceLiveAttemptCoordinator(
            queueService: queue.service
        )
        let originalAttempt = UUID()
        let originalForeground = UUID()
        let replacementAttempt = UUID()
        let replacementForeground = UUID()
        coordinator.activate(
            scanId: "scan-a",
            attemptGeneration: originalAttempt,
            foregroundGeneration: originalForeground
        )

        let finalization = Task { @MainActor in
            await coordinator.completeQueuedInferenceIfNeeded(
                scanId: "scan-a",
                attemptGeneration: originalAttempt,
                foregroundGeneration: originalForeground,
                mediaPathsToKeep: ["adopted.jpg"]
            )
        }
        await gate.waitUntilStarted()
        coordinator.activate(
            scanId: "scan-a",
            attemptGeneration: replacementAttempt,
            foregroundGeneration: replacementForeground
        )
        await gate.release()

        #expect(await finalization.value == false)
        #expect(coordinator.activeScanId == "scan-a")
        #expect(coordinator.activeAttemptGeneration == replacementAttempt)
        #expect(coordinator.activeForegroundGeneration == replacementForeground)
        #expect(queue.events.isEmpty)
    }

    @Test func staleFailedFinalizationCannotRetireReplacementOwner() async {
        let gate = InferenceOperationGate()
        let queue = InferenceLiveAttemptQueueHarness()
        queue.deleteOperation = {
            await gate.wait()
            return false
        }
        let coordinator = InferenceLiveAttemptCoordinator(
            queueService: queue.service
        )
        let originalAttempt = UUID()
        let originalForeground = UUID()
        let replacementAttempt = UUID()
        let replacementForeground = UUID()
        coordinator.activate(
            scanId: "scan-a",
            attemptGeneration: originalAttempt,
            foregroundGeneration: originalForeground
        )

        let finalization = Task { @MainActor in
            await coordinator.completeQueuedInferenceIfNeeded(
                scanId: "scan-a",
                attemptGeneration: originalAttempt,
                foregroundGeneration: originalForeground,
                mediaPathsToKeep: []
            )
        }
        await gate.waitUntilStarted()
        coordinator.activate(
            scanId: "scan-a",
            attemptGeneration: replacementAttempt,
            foregroundGeneration: replacementForeground
        )
        await gate.release()

        #expect(await finalization.value == false)
        #expect(coordinator.activeAttemptGeneration == replacementAttempt)
        #expect(coordinator.activeForegroundGeneration == replacementForeground)
        #expect(queue.events.isEmpty)
    }

    @Test func recoveredBackgroundResultWaitsForDurableOwnerRelease() {
        let queue = InferenceLiveAttemptQueueHarness()
        let coordinator = InferenceLiveAttemptCoordinator(
            queueService: queue.service
        )
        let attempt = UUID()
        let foreground = UUID()
        coordinator.activate(
            scanId: "scan-a",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )
        queue.foregroundGenerations["scan-a"] = foreground

        #expect(!coordinator.canCommitRecoveredBackgroundResult(
            scanId: "scan-a",
            replacingAttemptGeneration: attempt,
            expectedForegroundGeneration: foreground
        ))

        queue.foregroundGenerations["scan-a"] = nil
        #expect(coordinator.canCommitRecoveredBackgroundResult(
            scanId: "scan-a",
            replacingAttemptGeneration: attempt,
            expectedForegroundGeneration: foreground
        ))
    }
}
