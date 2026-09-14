import Foundation
import Testing

@testable import Merian

@MainActor
private final class InferenceFundingReconciliationHarness {
    let firstGate = InferenceOperationGate()
    let secondGate = InferenceOperationGate()
    var leasesAreCurrent = true
    var cancellationStarted = false
    private(set) var reconcileLeaseIDs: [UUID] = []
    private(set) var resumedQueueWorkCount = 0
    private(set) var finishedLeaseIDs: [UUID] = []

    func makeOwner() -> InferenceFundingReconciliationOwner {
        InferenceFundingReconciliationOwner(
            dependencies: .init(
                reconcile: { [self] lease in
                    reconcileLeaseIDs.append(lease.id)
                    if reconcileLeaseIDs.count == 1 {
                        await firstGate.wait()
                    } else {
                        await secondGate.wait()
                    }
                },
                isLeaseCurrent: { [self] _ in leasesAreCurrent },
                resumeQueueWork: { [self] in
                    resumedQueueWorkCount += 1
                },
                finishLease: { [self] lease in
                    finishedLeaseIDs.append(lease.id)
                }
            )
        )
    }
}

@MainActor
@Suite("Inference Funding Reconciliation Owner")
struct InferenceFundingReconciliationOwnerTests {
    @Test func concurrentRequestsCoalesceAndReleaseEveryLease() async {
        let harness = InferenceFundingReconciliationHarness()
        let owner = harness.makeOwner()
        let first = lease()
        let second = lease()
        let third = lease()

        owner.enqueue(lease: first)
        await harness.firstGate.waitUntilStarted()
        owner.enqueue(lease: second)
        owner.enqueue(lease: third)
        await harness.firstGate.release()
        await harness.secondGate.waitUntilStarted()
        await harness.secondGate.release()
        await owner.awaitCompletion()

        #expect(harness.reconcileLeaseIDs == [first.id, first.id])
        #expect(harness.resumedQueueWorkCount == 2)
        #expect(
            harness.finishedLeaseIDs == [first.id, second.id, third.id]
        )
    }

    @Test func cancellationIgnoringWorkCannotResumeQueueAndCanRestart() async {
        let harness = InferenceFundingReconciliationHarness()
        let owner = harness.makeOwner()
        let cancelledLease = lease()

        owner.enqueue(lease: cancelledLease)
        await harness.firstGate.waitUntilStarted()
        let cancellation = Task { @MainActor in
            harness.cancellationStarted = true
            await owner.cancelAndAwait()
        }
        while !harness.cancellationStarted {
            await Task.yield()
        }
        await harness.firstGate.release()
        await cancellation.value

        #expect(harness.resumedQueueWorkCount == 0)
        #expect(harness.finishedLeaseIDs == [cancelledLease.id])

        let replacementLease = lease()
        owner.enqueue(lease: replacementLease)
        await harness.secondGate.waitUntilStarted()
        await harness.secondGate.release()
        await owner.awaitCompletion()

        #expect(harness.resumedQueueWorkCount == 1)
        #expect(
            harness.finishedLeaseIDs == [
                cancelledLease.id,
                replacementLease.id
            ]
        )
    }

    private func lease() -> AccountBoundWorkLease {
        AccountBoundWorkLease(
            id: UUID(),
            session: AuthTransitionSession(
                userID: UUID(),
                isAnonymous: false
            )
        )
    }
}
