import Testing

@Suite("Shared Process State Gate", .timeLimit(.minutes(1)))
struct SharedProcessStateGateTests {
    @Test func overlappingResourceSetsAreAcquiredAtomically() async throws {
        let gate = SharedProcessStateGate()
        let network = try await gate.acquire([.networkClientOverrides])
        let both = Task { try await gate.acquire([.offlineQueueManager, .networkClientOverrides]) }
        await waitForWaiters(1, in: gate)
        let queue = Task { try await gate.acquire([.offlineQueueManager]) }
        await waitForWaiters(2, in: gate)

        await gate.release(network)
        let combinedLease = try await both.value
        #expect(await gate.waitingCount == 1)
        await gate.release(combinedLease)
        let queueLease = try await queue.value
        #expect(await gate.waitingCount == 0)
        await gate.release(queueLease)
    }

    @Test func independentResourcesDoNotBlockEachOther() async throws {
        let gate = SharedProcessStateGate()
        let network = try await gate.acquire([.networkClientOverrides])
        let queue = try await gate.acquire([.offlineQueueManager])
        #expect(await gate.waitingCount == 0)
        await gate.release(network)
        await gate.release(queue)
    }

    @Test func cancelledWaiterDoesNotHoldUpTheNextTest() async throws {
        let gate = SharedProcessStateGate()
        let owner = try await gate.acquire([.offlineQueueManager])
        let cancelled = Task { try await gate.acquire([.offlineQueueManager]) }
        await waitForWaiters(1, in: gate)
        let next = Task { try await gate.acquire([.offlineQueueManager]) }
        await waitForWaiters(2, in: gate)
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            Issue.record("A queued cancelled acquisition must throw")
        } catch is CancellationError {
            #expect(await gate.waitingCount == 1)
        }
        await gate.release(owner)
        await gate.release(try await next.value)
    }

    @Test func thrownOperationReleasesItsResources() async throws {
        let gate = SharedProcessStateGate()
        do {
            try await gate.withResources([.offlineQueueManager]) { throw ExpectedFailure.expected }
            Issue.record("Expected the operation to throw")
        } catch is ExpectedFailure {
            let next = try await gate.acquire([.offlineQueueManager])
            await gate.release(next)
        }
    }

    @Test func staleReleaseCannotUnlockANewerOwner() async throws {
        let gate = SharedProcessStateGate()
        let first = try await gate.acquire([.offlineQueueManager])
        await gate.release(first)
        let second = try await gate.acquire([.offlineQueueManager])
        let third = Task { try await gate.acquire([.offlineQueueManager]) }
        await waitForWaiters(1, in: gate)
        await gate.release(first)
        #expect(await gate.waitingCount == 1)
        await gate.release(second)
        await gate.release(try await third.value)
    }

    private enum ExpectedFailure: Error { case expected }

    private func waitForWaiters(_ count: Int, in gate: SharedProcessStateGate) async {
        while await gate.waitingCount != count {
            await Task.yield()
        }
    }
}
