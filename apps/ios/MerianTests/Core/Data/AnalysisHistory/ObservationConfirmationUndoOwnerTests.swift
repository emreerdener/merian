import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager), .timeLimit(.minutes(1)))
struct ObservationConfirmationUndoOwnerTests {
    typealias Owner = ObservationConfirmationUndoOwner
    private final class Pause {
        private let stream = AsyncStream<Void>.makeStream()
        private var pending: [CheckedContinuation<Void, Never>] = []
        deinit { stream.continuation.finish() }
        func wait() async { await withCheckedContinuation { pending.append($0); stream.continuation.yield() } }
        func entered() async { for await _ in stream.stream { break } }
        func release() { let saved = pending; pending.removeAll(); saved.forEach { $0.resume() } }
    }
    @Test func joinedLookupRetainsLeaseThroughAuthDrainAndRejectsStaleDispatch() async throws {
        let fixture = try await ConfirmationUndoEligibilityTests().seed()
        let container = fixture.container, ticket = fixture.ticket, operation = fixture.operation
        let gate = Pause(), owner = Owner()
        defer { gate.release(); owner.cancelAll() }
        var calls = 0, exits = 0
        let cloud = ObservationHistorySyncTests().client(fetch: { _ in Data() }, finish: { exits += 1 })
        let service = ObservationConfirmationUndoService(cloud: cloud, fetch: { lookup, _, validate in
            calls += 1; await gate.wait()
            try validate()
            var row = try lookup.object()
            row.merge(["status": "available", "confirmation_operation_id": operation.uuidString.lowercased(), "confirmation_action": "confirm_primary"]) { _, new in new }
            return try .init(data: JSONSerialization.data(withJSONObject: row), request: lookup)
        })
        let session = AuthTransitionSession(userID: ticket.ownerID, isAnonymous: false)
        let first = Task { try await owner.prepare(ticket: ticket, session: session, generation: 1,
            container: container, service: service, isCurrent: { true }) }
        await gate.entered()
        let joined = AsyncStream<Void>.makeStream(); defer { joined.continuation.finish() }
        let second = Task { try await owner.prepare(ticket: ticket, session: session, generation: 1,
            container: container, service: service, isCurrent: { joined.continuation.yield(); return true }) }
        for await _ in joined.stream { break }
        #expect(calls == 1 && owner.activeCount == 1 && exits == 0)
        owner.cancelAll()
        let drain = Task { await owner.cancelAndAwaitAll() }
        #expect(owner.activeCount == 1 && exits == 0)
        gate.release()
        await drain.value
        await #expect(throws: (any Error).self) { try await first.value }
        await #expect(throws: (any Error).self) { try await second.value }
        #expect(owner.activeCount == 0 && exits == 1)
    }
    @Test func capacityAndCancelledEntriesRemainBoundedUntilActualExit() async throws {
        let fixture = try await ConfirmationUndoEligibilityTests().seed()
        let gate = Pause(), owner = Owner()
        defer { gate.release(); owner.cancelAll() }
        let service = ObservationConfirmationUndoService(cloud: ObservationHistorySyncTests().client(fetch: { _ in Data() }),
            fetch: { lookup, _, _ in
                await gate.wait()
                var row = try lookup.object(); row["status"] = "unavailable"; row["reason"] = "receipt_unavailable"
                return try .init(data: JSONSerialization.data(withJSONObject: row), request: lookup)
            })
        let session = AuthTransitionSession(userID: fixture.ticket.ownerID, isAnonymous: false)
        var tasks: [Task<ObservationConfirmationUndoEligibility.Resolution, Error>] = []
        for generation in 1...Owner.maximumActiveLookups {
            tasks.append(Task { try await owner.prepare(ticket: fixture.ticket, session: session, generation: UInt64(generation),
                container: fixture.container, service: service, isCurrent: { true }) })
            await gate.entered()
        }
        #expect(owner.activeCount == 4)
        await #expect(throws: Owner.Failure.capacity) {
            try await owner.prepare(ticket: fixture.ticket, session: session, generation: 5,
                container: fixture.container, service: service, isCurrent: { true })
        }
        owner.cancelAll()
        await #expect(throws: Owner.Failure.busy) {
            try await owner.prepare(ticket: fixture.ticket, session: session, generation: 1,
                container: fixture.container, service: service, isCurrent: { true })
        }
        #expect(owner.activeCount == 4)
        gate.release()
        for task in tasks { await #expect(throws: (any Error).self) { try await task.value } }
        #expect(owner.activeCount == 0)
    }

}
