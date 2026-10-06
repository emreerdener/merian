import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager), .timeLimit(.minutes(1)))
struct ObservationPublicationRecoveryOwnerTests {
    let fixture = ObservationPublicationConsentServiceTests()
    typealias Owner = ObservationPublicationRecoveryOwner
    var session: AuthTransitionSession { .init(userID: fixture.owner, isAnonymous: false) }

    @Test func joinedWaiterCancellationPreservesOtherCallerAndLease() async throws {
        let owner = Owner(), gate = Pause(), (container, snapshot) = try await fixture.seed()
        defer { gate.release(); owner.cancelAll() }
        var calls = 0, finishes = 0
        var cloud = fixture.service(snapshot).cloud
        cloud.finish = { _ in finishes += 1; #expect(owner.activeCount == 1) }
        let service = ObservationPublicationRecoveryService(cloud: cloud, fetch: { _, _ in
            calls += 1; await gate.wait(); return nil
        })
        let first = Task { try await owner.recover(ownerID: fixture.owner, observationID: fixture.observation,
            session: session, generation: 1, container: container, service: service, isCurrent: { true }) }
        await gate.entered()
        let joined = AsyncStream<Void>.makeStream(); defer { joined.continuation.finish() }
        let second = Task { try await owner.recover(ownerID: fixture.owner, observationID: fixture.observation,
            session: session, generation: 1, container: container, service: service,
            isCurrent: { joined.continuation.yield(); return true }) }
        for await _ in joined.stream { break }
        first.cancel()
        #expect(calls == 1 && finishes == 0 && owner.activeCount == 1)
        gate.release()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(try await second.value == nil)
        #expect(finishes == 1 && owner.activeCount == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func capacityAndCancelledScopesStayOccupiedUntilExit() async throws {
        let owner = Owner(), gate = Pause(), (container, snapshot) = try await fixture.seed()
        defer { gate.release(); owner.cancelAll() }
        let service = ObservationPublicationRecoveryService(cloud: fixture.service(snapshot).cloud,
            fetch: { _, _ in await gate.wait(); return nil })
        var tasks: [Task<ObservationPublicationReceipt?, Error>] = []
        for generation in 1...Owner.maximumActiveRecoveries {
            tasks.append(Task { try await owner.recover(ownerID: fixture.owner, observationID: fixture.observation,
                session: session, generation: UInt64(generation), container: container, service: service, isCurrent: { true }) })
            await gate.entered()
        }
        await #expect(throws: Owner.Failure.capacity) {
            try await owner.recover(ownerID: fixture.owner, observationID: fixture.observation,
                session: session, generation: 5, container: container, service: service, isCurrent: { true })
        }
        owner.cancelAll(); #expect(owner.activeCount == 4)
        await #expect(throws: Owner.Failure.busy) {
            try await owner.recover(ownerID: fixture.owner, observationID: fixture.observation,
                session: session, generation: 1, container: container, service: service, isCurrent: { true })
        }
        gate.release()
        for task in tasks { await #expect(throws: (any Error).self) { try await task.value } }
        #expect(owner.activeCount == 0)
    }

    @Test func onlyExactCancellationCanStopRecovery() async throws {
        let owner = Owner(), gate = Pause(), (container, snapshot) = try await fixture.seed()
        let (other, _) = try await fixture.seed()
        defer { gate.release(); owner.cancelAll() }
        let service = ObservationPublicationRecoveryService(cloud: fixture.service(snapshot).cloud,
            fetch: { _, _ in await gate.wait(); return nil })
        let task = Task { try await owner.recover(ownerID: fixture.owner, observationID: fixture.observation,
            session: session, generation: 1, container: container, service: service, isCurrent: { true }) }
        await gate.entered()
        owner.cancel(ownerID: fixture.owner, observationID: UUID(), session: session, generation: 1, in: container)
        owner.cancel(ownerID: fixture.owner, observationID: fixture.observation, session: session, generation: 2, in: container)
        owner.cancel(ownerID: fixture.owner, observationID: fixture.observation, session: session, generation: 1, in: other)
        let joined = AsyncStream<Void>.makeStream(); defer { joined.continuation.finish() }
        let second = Task { try await owner.recover(ownerID: fixture.owner, observationID: fixture.observation,
            session: session, generation: 1, container: container, service: service,
            isCurrent: { joined.continuation.yield(); return true }) }
        for await _ in joined.stream { break }
        owner.cancel(ownerID: fixture.owner, observationID: fixture.observation, session: session, generation: 1, in: container)
        gate.release()
        await #expect(throws: (any Error).self) { try await task.value }
        await #expect(throws: (any Error).self) { try await second.value }
    }

    @Test(arguments: ["owner", "generation", "container"])
    func changedCommonScopeWithholdsResult(_ change: String) async throws {
        let owner = Owner(), (container, snapshot) = try await fixture.seed(), (other, _) = try await fixture.seed()
        var account = fixture.owner, generation = 1, currentContainer = container
        let service = ObservationPublicationRecoveryService(cloud: fixture.service(snapshot).cloud, fetch: { _, _ in
            if change == "owner" { account = UUID() } else if change == "generation" { generation = 2 } else { currentContainer = other }
            return nil
        })
        await #expect(throws: ObservationHistoryError.accountChanged) {
            try await owner.recover(ownerID: fixture.owner, observationID: fixture.observation, session: session,
                generation: 1, container: container, service: service,
                isCurrent: { account == fixture.owner && generation == 1 && currentContainer === container })
        }
        #expect(owner.activeCount == 0)
    }

    @Test func mismatchedSessionCannotFetch() async throws {
        let owner = Owner(), (container, snapshot) = try await fixture.seed()
        let service = ObservationPublicationRecoveryService(cloud: fixture.service(snapshot).cloud,
            fetch: { _, _ in Issue.record("Wrong session dispatched"); return nil })
        for wrong in [AuthTransitionSession(userID: UUID(), isAnonymous: false), .init(userID: fixture.owner, isAnonymous: true)] {
            await #expect(throws: ObservationHistoryError.accountChanged) {
                try await owner.recover(ownerID: fixture.owner, observationID: fixture.observation,
                    session: wrong, generation: 1, container: container, service: service, isCurrent: { true })
            }
        }
    }

    @Test func authDrainWaitsForLeaseAndOverlappingDrainsBlockNewReads() async throws {
        let queue = OfflineQueueManager.shared, owner = queue.publicationTargetRecoveryOwner
        let gate = Pause(), (container, snapshot) = try await fixture.seed()
        defer { gate.release(); owner.cancelAll() }
        var finished = 0, drained = 0, cloud = fixture.service(snapshot).cloud
        cloud.finish = { _ in finished += 1; #expect(owner.activeCount == 1) }
        let service = ObservationPublicationRecoveryService(cloud: cloud, fetch: { _, _ in await gate.wait(); return nil })
        let task = Task { try await owner.recover(ownerID: fixture.owner, observationID: fixture.observation,
            session: session, generation: 1, container: container, service: service, isCurrent: { true }) }
        await gate.entered()
        let entered = AsyncStream<Void>.makeStream(); defer { entered.continuation.finish() }
        let first = Task { entered.continuation.yield(); await queue.awaitRetainedSyncQuiescenceForAuthTransition(); drained += 1 }
        for await _ in entered.stream { break }
        let second = Task { entered.continuation.yield(); await owner.cancelAndAwaitAll(); drained += 1 }
        for await _ in entered.stream { break }
        #expect(finished == 0 && drained == 0 && owner.activeCount == 1)
        await #expect(throws: Owner.Failure.draining) {
            try await owner.recover(ownerID: fixture.owner, observationID: fixture.observation, session: session,
                generation: 2, container: container, service: service, isCurrent: { true })
        }
        gate.release(); await first.value; await second.value
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(finished == 1 && drained == 2 && owner.activeCount == 0)
        let fresh = ObservationPublicationRecoveryService(cloud: cloud, fetch: { _, _ in nil })
        #expect(try await owner.recover(ownerID: fixture.owner, observationID: fixture.observation, session: session,
            generation: 2, container: container, service: fresh, isCurrent: { true }) == nil)
    }

    private final class Pause {
        private let stream = AsyncStream<Void>.makeStream()
        private var pending: [CheckedContinuation<Void, Never>] = []
        deinit { stream.continuation.finish() }
        func wait() async { await withCheckedContinuation { pending.append($0); stream.continuation.yield() } }
        func entered() async { for await _ in stream.stream { break } }
        func release() { let saved = pending; pending.removeAll(); saved.forEach { $0.resume() } }
    }
}
