import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("Capture funding account shutdown", .serialized, .timeLimit(.minutes(1)))
struct SharedMediaCaptureFundingLifecycleTests {
    @Test func nativeShutdownJoinsFundingBeforeReleasingTheAccountFence() async throws {
        let store = try SharedMediaNativeAppBootstrapTests.Store(startupEligible: true)
        let (container, admission) = try store.startup()
        let runtime = AuthRuntimeState(), gate = InferenceOperationGate()
        let account = PhotoOriginalPreparationOwner.syntheticAccount(ownerID: store.ownerID, runtime: runtime)
        let lifetime = SharedMediaNativeOriginalDrain(container: container, admission: admission)
        try lifetime.bindPreparedAccount(account)
        var released = 0, closeEntered = false
        let worker = SharedMediaCaptureFundingDrain(dependencies: .init(begin: {
            let lease = try account.begin()
            return .init(ownerID: store.ownerID,
                isCurrent: { !lifetime.isClosed && account.isCurrent(lease) },
                release: { released += 1; account.finish(lease) })
        }, page: { _, _ in
            await gate.wait() // Deliberately ignores cancellation until actual exit.
            return .init(candidates: [.init(scanID: UUID(), generation: UUID(), due: nil)], nextCursor: nil)
        }, recover: { _, _ in Issue.record("Shutdown allowed funding effects") },
        postpone: { _, _, _ in Issue.record("Shutdown allowed retry persistence") },
        isCurrent: { !lifetime.isClosed }))
        let borrow = try lifetime.borrowLocalFence(for: worker, role: .captureFunding, container: container) {
            closeEntered = true
            await worker.close()
            return !worker.isRunning
        }
        let work = Task { await worker.drain() }
        await gate.waitUntilStarted()
        let shutdown = Task { await lifetime.shutdown() }
        while !closeEntered { await Task.yield() }
        #expect(lifetime.isClosed && !lifetime.shutdownFinished && released == 0)
        #expect(throws: (any Error).self) { _ = try borrow.fence(container: container) }
        await gate.release()
        #expect(await shutdown.value)
        await work.value
        await runtime.awaitAccountWorkDrain()
        #expect(lifetime.shutdownFinished && worker.isClosed && released == 1)
        _ = try admission.acquireFence(container: container)
        await worker.drain()
        #expect(released == 1)
    }
}
