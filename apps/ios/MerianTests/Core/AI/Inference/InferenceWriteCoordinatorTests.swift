import Foundation
import Testing

@testable import Merian

private actor InferenceWriteTestGate {
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [(
        count: Int,
        continuation: CheckedContinuation<Void, Never>
    )] = []
    private var startedCount = 0
    private var isReleased = false

    func wait() async {
        startedCount += 1
        resumeSatisfiedStartWaiters()
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }
    }

    func waitUntilStarted(count: Int) async {
        guard startedCount < count else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((count, continuation))
        }
    }

    func release() {
        isReleased = true
        let continuations = releaseContinuations
        releaseContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    private func resumeSatisfiedStartWaiters() {
        var remaining: [(
            count: Int,
            continuation: CheckedContinuation<Void, Never>
        )] = []
        for waiter in startWaiters {
            if startedCount >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        startWaiters = remaining
    }
}

private actor InferenceWriteTestRecorder {
    private var values: [Int] = []
    private var waiters: [(
        count: Int,
        continuation: CheckedContinuation<Void, Never>
    )] = []

    func append(_ value: Int) {
        values.append(value)
        var remaining: [(
            count: Int,
            continuation: CheckedContinuation<Void, Never>
        )] = []
        for waiter in waiters {
            if values.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        waiters = remaining
    }

    func waitForCount(_ count: Int) async {
        guard values.count < count else { return }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    func snapshot() -> [Int] {
        values
    }
}

@MainActor
@Suite("Inference Write Coordinator")
struct InferenceWriteCoordinatorTests {
    @Test func enforcesDefaultActivePendingAndOverflowBounds() async {
        let coordinator = InferenceWriteCoordinator()
        let gate = InferenceWriteTestGate()
        let recorder = InferenceWriteTestRecorder()
        let acceptedWriteCount =
            InferenceResourceLimits.activeBackgroundWriteCapacity +
            InferenceResourceLimits.pendingBackgroundWriteCapacity

        for value in 0...acceptedWriteCount {
            coordinator.enqueueBackgroundWrite {
                await recorder.append(value)
                await gate.wait()
            }
        }

        await gate.waitUntilStarted(
            count: InferenceResourceLimits.activeBackgroundWriteCapacity
        )
        #expect(
            coordinator.snapshot == .init(
                active: InferenceResourceLimits.activeBackgroundWriteCapacity,
                pending: InferenceResourceLimits.pendingBackgroundWriteCapacity,
                generation: 0
            )
        )

        await gate.release()
        await recorder.waitForCount(acceptedWriteCount)
        #expect(coordinator.beginAuthTransitionFence())
        coordinator.resetPresentationWrites()
        await coordinator.awaitQuiescence()

        let executedValues = await recorder.snapshot()
        #expect(executedValues.count == acceptedWriteCount)
        #expect(Set(executedValues) == Set(0..<acceptedWriteCount))
        #expect(
            coordinator.snapshot == .init(
                active: 0,
                pending: 0,
                generation: 1
            )
        )
    }

    @Test func authFenceWaitsForCancellationIgnoringWriteAndRejectsNewWork() async {
        let coordinator = InferenceWriteCoordinator()
        let gate = InferenceWriteTestGate()
        let recorder = InferenceWriteTestRecorder()

        coordinator.enqueueBackgroundWrite {
            await gate.wait()
            await recorder.append(1)
        }
        await gate.waitUntilStarted(count: 1)

        #expect(coordinator.beginAuthTransitionFence())
        coordinator.resetPresentationWrites()
        coordinator.enqueueBackgroundWrite {
            await recorder.append(2)
        }

        let drain = Task { @MainActor in
            await coordinator.awaitQuiescence()
            await recorder.append(3)
        }
        await Task.yield()
        #expect(await recorder.snapshot().isEmpty)

        await gate.release()
        await drain.value
        #expect(await recorder.snapshot() == [1, 3])
    }

    @Test func reviewWritesPreserveStartedActionOrder() async {
        let coordinator = InferenceWriteCoordinator()
        let gate = InferenceWriteTestGate()
        let recorder = InferenceWriteTestRecorder()
        let scanId = "SCAN-A"

        let firstGeneration = coordinator.beginIdentificationAction(
            scanId: scanId,
            channel: .review
        )
        coordinator.enqueueIdentificationWrite(
            scanId: scanId,
            actionGeneration: firstGeneration,
            channel: .review
        ) {
            await gate.wait()
            await recorder.append(1)
        }
        await gate.waitUntilStarted(count: 1)

        let secondGeneration = coordinator.beginIdentificationAction(
            scanId: scanId,
            channel: .review
        )
        coordinator.enqueueIdentificationWrite(
            scanId: scanId,
            actionGeneration: secondGeneration,
            channel: .review
        ) {
            await recorder.append(2)
        }

        await gate.release()
        await recorder.waitForCount(2)
        #expect(await recorder.snapshot() == [1, 2])
    }

    @Test func newPresentationWaitsForCancellationIgnoringReviewWrite() async {
        let coordinator = InferenceWriteCoordinator()
        let gate = InferenceWriteTestGate()
        let recorder = InferenceWriteTestRecorder()
        let scanId = "scan-a"

        let firstGeneration = coordinator.beginIdentificationAction(
            scanId: scanId,
            channel: .review
        )
        coordinator.enqueueIdentificationWrite(
            scanId: scanId,
            actionGeneration: firstGeneration,
            channel: .review
        ) {
            await gate.wait()
            await recorder.append(1)
        }
        await gate.waitUntilStarted(count: 1)

        coordinator.resetPresentationWrites()
        let replacementGeneration = coordinator.beginIdentificationAction(
            scanId: scanId,
            channel: .review
        )
        coordinator.enqueueIdentificationWrite(
            scanId: scanId,
            actionGeneration: replacementGeneration,
            channel: .review
        ) {
            await recorder.append(2)
        }

        await Task.yield()
        #expect(await recorder.snapshot().isEmpty)

        await gate.release()
        await recorder.waitForCount(2)
        #expect(await recorder.snapshot() == [1, 2])
    }

    @Test func staleReviewWriteIsRejectedBeforeItStarts() async {
        let coordinator = InferenceWriteCoordinator()
        let recorder = InferenceWriteTestRecorder()
        let scanId = "scan-a"

        let staleGeneration = coordinator.beginIdentificationAction(
            scanId: scanId,
            channel: .review
        )
        coordinator.enqueueIdentificationWrite(
            scanId: scanId,
            actionGeneration: staleGeneration,
            channel: .review
        ) {
            await recorder.append(1)
        }

        let currentGeneration = coordinator.beginIdentificationAction(
            scanId: scanId,
            channel: .review
        )
        coordinator.enqueueIdentificationWrite(
            scanId: scanId,
            actionGeneration: currentGeneration,
            channel: .review
        ) {
            await recorder.append(2)
        }

        await recorder.waitForCount(1)
        #expect(await recorder.snapshot() == [2])
    }

    @Test func confirmationDoesNotInvalidateSameSpeciesHydration() {
        let coordinator = InferenceWriteCoordinator()
        let scanId = "scan-a"

        let hydrationGeneration = coordinator.beginIdentificationAction(
            scanId: scanId,
            channel: .review
        )
        let confirmationGeneration = coordinator.beginIdentificationAction(
            scanId: scanId,
            channel: .confirmation
        )

        #expect(coordinator.isIdentificationActionCurrent(
            scanId: scanId,
            generation: hydrationGeneration,
            channel: .review
        ))
        #expect(coordinator.isIdentificationActionCurrent(
            scanId: scanId,
            generation: confirmationGeneration,
            channel: .confirmation
        ))
    }

    @Test func confirmationSharesTheIdentificationFinalWriterTail() async {
        let coordinator = InferenceWriteCoordinator()
        let gate = InferenceWriteTestGate()
        let recorder = InferenceWriteTestRecorder()
        let scanId = "scan-a"

        let reviewGeneration = coordinator.beginIdentificationAction(
            scanId: scanId,
            channel: .review
        )
        coordinator.enqueueIdentificationWrite(
            scanId: scanId,
            actionGeneration: reviewGeneration,
            channel: .review
        ) {
            await gate.wait()
            await recorder.append(1)
        }
        await gate.waitUntilStarted(count: 1)

        let confirmationGeneration = coordinator.beginIdentificationAction(
            scanId: scanId,
            channel: .confirmation
        )
        coordinator.enqueueIdentificationWrite(
            scanId: scanId,
            actionGeneration: confirmationGeneration,
            channel: .confirmation
        ) {
            await recorder.append(2)
        }

        await Task.yield()
        #expect(await recorder.snapshot().isEmpty)
        await gate.release()
        await recorder.waitForCount(2)
        #expect(await recorder.snapshot() == [1, 2])
    }

    @Test func presentationResetCancelsAQueuedReviewWrite() async {
        let coordinator = InferenceWriteCoordinator()
        let gate = InferenceWriteTestGate()
        let recorder = InferenceWriteTestRecorder()

        let firstGeneration = coordinator.beginIdentificationAction(
            scanId: "scan-a",
            channel: .review
        )
        coordinator.enqueueIdentificationWrite(
            scanId: "scan-a",
            actionGeneration: firstGeneration,
            channel: .review
        ) {
            await gate.wait()
            await recorder.append(1)
        }
        await gate.waitUntilStarted(count: 1)

        let queuedGeneration = coordinator.beginIdentificationAction(
            scanId: "scan-b",
            channel: .review
        )
        coordinator.enqueueIdentificationWrite(
            scanId: "scan-b",
            actionGeneration: queuedGeneration,
            channel: .review
        ) {
            await recorder.append(2)
        }

        coordinator.resetPresentationWrites()
        #expect(coordinator.beginAuthTransitionFence())
        await gate.release()
        await coordinator.awaitQuiescence()

        #expect(await recorder.snapshot() == [1])
    }

    @Test func identificationActionHistoryRemainsBounded() {
        let coordinator = InferenceWriteCoordinator(
            identificationActionCapacity: 2
        )
        let firstGeneration = coordinator.beginIdentificationAction(
            scanId: "scan-a",
            channel: .review
        )
        _ = coordinator.beginIdentificationAction(
            scanId: "scan-b",
            channel: .review
        )
        _ = coordinator.beginIdentificationAction(
            scanId: "scan-c",
            channel: .review
        )

        #expect(!coordinator.isIdentificationActionCurrent(
            scanId: "scan-a",
            generation: firstGeneration,
            channel: .review
        ))
    }
}
