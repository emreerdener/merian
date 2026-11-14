import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager), .timeLimit(.minutes(1)))
struct ObservationPublicationPreparationOwnerTests {
    let fixture = ObservationPublicationConsentServiceTests()
    var session: AuthTransitionSession { .init(userID: fixture.owner, isAnonymous: false) }
    typealias Owner = ObservationPublicationPreparationOwner

    @Test func exactScopeJoinsAndCancelledWaiterCannotCancelAnotherCaller() async throws {
        let owner = Owner(), gate = Pause(), (container, snapshot) = try await fixture.seed()
        defer { gate.release(); owner.cancelAll() }
        let ticket = try fixture.ticket(container)
        var calls = 0, finished = 0, service = fixture.service(snapshot)
        service.cloud.finish = { _ in finished += 1 }
        service.fetch = { _, _ in calls += 1; await gate.wait(); return snapshot }
        let first = Task { try await owner.prepare(ticket: ticket, session: session, generation: 1,
            container: container, service: service, isCurrent: { true }) }
        await gate.entered()
        let joined = AsyncStream<Void>.makeStream(); defer { joined.continuation.finish() }
        let second = Task { try await owner.prepare(ticket: ticket, session: session, generation: 1,
            container: container, service: service, isCurrent: { joined.continuation.yield(); return true }) }
        for await _ in joined.stream { break }
        #expect(owner.activeCount == 1 && calls == 1 && finished == 0)
        first.cancel(); gate.release()
        await #expect(throws: CancellationError.self) { try await first.value }
        let prepared = try await second.value
        #expect(prepared.ownerID == fixture.owner && finished == 1 && owner.activeCount == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func capacityRetainsDifferentGenerationsUntilActualExit() async throws {
        let owner = Owner(), gate = Pause(), (container, snapshot) = try await fixture.seed()
        defer { gate.release(); owner.cancelAll() }
        let ticket = try fixture.ticket(container)
        var calls = 0, service = fixture.service(snapshot)
        service.fetch = { _, _ in calls += 1; await gate.wait(); return snapshot }
        var tasks: [Task<ObservationPublicationConsentService.Prepared, Error>] = []
        for generation in 1...Owner.maximumActivePreparations {
            tasks.append(Task { try await owner.prepare(ticket: ticket, session: session, generation: UInt64(generation),
                container: container, service: service, isCurrent: { true }) })
            await gate.entered()
        }
        #expect(calls == 4 && owner.activeCount == 4)
        await #expect(throws: Owner.Failure.capacity) {
            try await owner.prepare(ticket: ticket, session: session, generation: 5, container: container, service: service, isCurrent: { true })
        }
        owner.cancelAll()
        #expect(owner.activeCount == 4)
        await #expect(throws: Owner.Failure.busy) {
            try await owner.prepare(ticket: ticket, session: session, generation: 1, container: container, service: service, isCurrent: { true })
        }
        gate.release()
        for task in tasks { await #expect(throws: (any Error).self) { try await task.value } }
        #expect(owner.activeCount == 0)
    }

    @Test func changedTicketCannotJoinAndWrongSessionNeverFetches() async throws {
        let owner = Owner(), gate = Pause(), (container, snapshot) = try await fixture.seed()
        defer { gate.release(); owner.cancelAll() }
        let ticket = try fixture.ticket(container)
        var calls = 0, service = fixture.service(snapshot)
        service.fetch = { _, _ in calls += 1; await gate.wait(); return snapshot }
        let first = Task { try await owner.prepare(ticket: ticket, session: session, generation: 1,
            container: container, service: service, isCurrent: { true }) }
        await gate.entered()
        let context = ModelContext(container), scan = try #require(try context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let revision = try #require(scan.observationStateRevision)
        let entry = try ObservationHistoryListingService.entry(fixture.analysis, scan: scan, context: context)
        let changed = try ObservationAnalysisReviewTicket(entry: entry,
            context: .init(owner: fixture.owner, selected: ticket.selectedAnalysisID,
                revision: revision + 1, pendingOperation: nil, undoOperation: nil), observationID: fixture.observation)
        scan.observationStateRevision = revision + 1; try context.save()
        #expect(changed != ticket)
        await #expect(throws: (any Error).self) {
            try await owner.prepare(ticket: changed, session: session, generation: 1, container: container, service: service, isCurrent: { true })
        }
        scan.observationStateRevision = revision; try context.save()
        await #expect(throws: ObservationHistoryError.accountChanged) {
            try await owner.prepare(ticket: ticket, session: .init(userID: fixture.owner, isAnonymous: true), generation: 1,
                container: container, service: service, isCurrent: { true })
        }
        await #expect(throws: ObservationHistoryError.accountChanged) {
            try await owner.prepare(ticket: ticket, session: .init(userID: UUID(), isAnonymous: false), generation: 1,
                container: container, service: service, isCurrent: { true })
        }
        #expect(calls == 1 && owner.activeCount == 1)
        gate.release(); _ = try await first.value
    }

    @Test func onlyExactScopeCancellationCanWithholdPrivateResult() async throws {
        let owner = Owner(), gate = Pause(), (container, snapshot) = try await fixture.seed()
        let (other, _) = try await fixture.seed()
        defer { gate.release(); owner.cancelAll() }
        let ticket = try fixture.ticket(container)
        var service = fixture.service(snapshot)
        service.fetch = { _, _ in await gate.wait(); return snapshot }
        let task = Task { try await owner.prepare(ticket: ticket, session: session, generation: 1,
            container: container, service: service, isCurrent: { true }) }
        await gate.entered()
        owner.cancel(ticket: ticket, session: session, generation: 2, in: container)
        owner.cancel(ticket: ticket, session: session, generation: 1, in: other)
        // A wrong cancellation leaves the exact request joinable.
        let joined = AsyncStream<Void>.makeStream(); defer { joined.continuation.finish() }
        let waiter = Task { try await owner.prepare(ticket: ticket, session: session, generation: 1,
            container: container, service: service, isCurrent: { joined.continuation.yield(); return true }) }
        for await _ in joined.stream { break }
        owner.cancel(ticket: ticket, session: session, generation: 1, in: container)
        #expect(owner.activeCount == 1)
        gate.release()
        await #expect(throws: (any Error).self) { try await task.value }
        await #expect(throws: (any Error).self) { try await waiter.value }
        #expect(owner.activeCount == 0)
    }

    @Test(arguments: ["owner", "generation", "container"])
    func staleCommonEnvironmentWithholdsCompletedSnapshot(_ changed: String) async throws {
        let owner = Owner(), (container, snapshot) = try await fixture.seed()
        let (replacement, _) = try await fixture.seed()
        let ticket = try fixture.ticket(container)
        var account = fixture.owner, generation = 1, currentContainer = container
        var service = fixture.service(snapshot)
        service.fetch = { _, _ in
            switch changed {
            case "owner": account = UUID()
            case "generation": generation = 3
            default: currentContainer = replacement
            }
            return snapshot
        }
        await #expect(throws: ObservationHistoryError.accountChanged) {
            try await owner.prepare(ticket: ticket, session: session, generation: 1, container: container, service: service,
                isCurrent: { account == fixture.owner && generation == 1 && currentContainer === container })
        }
        #expect(owner.activeCount == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func staleCommonEnvironmentAlsoWithholdsJoinedWaiter() async throws {
        let owner = Owner(), gate = Pause(), (container, snapshot) = try await fixture.seed()
        defer { gate.release(); owner.cancelAll() }
        let ticket = try fixture.ticket(container)
        var current = true, service = fixture.service(snapshot)
        service.fetch = { _, _ in await gate.wait(); return snapshot }
        let first = Task { try await owner.prepare(ticket: ticket, session: session, generation: 1,
            container: container, service: service, isCurrent: { current }) }
        await gate.entered()
        let joined = AsyncStream<Void>.makeStream(); defer { joined.continuation.finish() }
        let second = Task { try await owner.prepare(ticket: ticket, session: session, generation: 1,
            container: container, service: service, isCurrent: { joined.continuation.yield(); return true }) }
        for await _ in joined.stream { break }
        current = false; gate.release()
        await #expect(throws: ObservationHistoryError.accountChanged) { try await first.value }
        await #expect(throws: ObservationHistoryError.accountChanged) { try await second.value }
        #expect(owner.activeCount == 0)
    }

    @Test func queueAuthDrainWaitsForLeaseAndCoalescedDrainsKeepAdmissionClosed() async throws {
        let manager = OfflineQueueManager.shared, owner = manager.publicationConsentPreparationOwner
        let gate = Pause(), (container, snapshot) = try await fixture.seed(), ticket = try fixture.ticket(container)
        defer { gate.release(); owner.cancelAll() }
        var finished = 0, drained = 0, service = fixture.service(snapshot)
        service.cloud.finish = { _ in finished += 1; #expect(owner.activeCount == 1) }
        service.fetch = { _, _ in await gate.wait(); return snapshot }
        let task = Task { try await owner.prepare(ticket: ticket, session: session, generation: 1,
            container: container, service: service, isCurrent: { true }) }
        await gate.entered()
        let entered = AsyncStream<Void>.makeStream(); defer { entered.continuation.finish() }
        let first = Task { entered.continuation.yield(); await manager.awaitRetainedSyncQuiescenceForAuthTransition(); drained += 1 }
        for await _ in entered.stream { break }
        let second = Task { entered.continuation.yield(); await owner.cancelAndAwaitAll(); drained += 1 }
        for await _ in entered.stream { break }
        #expect(finished == 0 && drained == 0 && owner.activeCount == 1)
        await #expect(throws: Owner.Failure.draining) {
            try await owner.prepare(ticket: ticket, session: session, generation: 2, container: container, service: service, isCurrent: { true })
        }
        gate.release(); await first.value; await second.value
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(finished == 1 && drained == 2 && owner.activeCount == 0)
        _ = try await owner.prepare(ticket: ticket, session: session, generation: 2,
            container: container, service: fixture.service(snapshot), isCurrent: { true })
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
