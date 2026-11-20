import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager), .timeLimit(.minutes(1)))
struct ProtectedInsightChatRefreshOwnerTests {
    let support = ProtectedInsightChatPersistenceTests()
    typealias Owner = ProtectedInsightChatRefreshOwner
    func cloud(_ fetch: @escaping (ObservationHistoryStateRequest) async throws -> Data,
               finish: @escaping () -> Void = {}) -> ObservationHistoryCloudClient {
        var cloud = support.source.service(data: Data()).cloud
        cloud.begin = { owner in .init(id: UUID(), session: .init(userID: owner, isAnonymous: false)) }
        cloud.finish = { _ in finish() }; cloud.fetchState = fetch
        return cloud
    }
    func session(_ ticket: ProtectedInsightChatTicket) -> AuthTransitionSession { .init(userID: ticket.ownerID, isAnonymous: false) }

    @Test func exactJoinSharesLeaseAndCancelledWaiterDoesNotCancelRefresh() async throws {
        let owner = Owner(), gate = Pause(), (container, ticket) = try await support.seed()
        defer { gate.release(); owner.cancelAll() }
        var calls = 0, finishes = 0
        let client = cloud({ _ in calls += 1; await gate.wait(); return try support.source.fixture(revision: 11) },
            finish: { finishes += 1 })
        let first = Task { try await owner.refresh(ticket: ticket, session: session(ticket), generation: 1,
            container: container, cloud: client, isCurrent: { true }) }
        await gate.entered()
        let joining = AsyncStream<Void>.makeStream(); defer { joining.continuation.finish() }
        let second = Task { try await owner.refresh(ticket: ticket, session: session(ticket), generation: 1,
            container: container, cloud: client, isCurrent: { joining.continuation.yield(); return true }) }
        for await _ in joining.stream { break }
        #expect(calls == 1 && owner.activeCount == 1)
        first.cancel(); gate.release()
        await #expect(throws: CancellationError.self) { try await first.value }
        let fresh = try await second.value
        #expect(fresh.selection.stateRevision == 11 && ticket.selection.stateRevision == 10)
        #expect(owner.activeCount == 0 && finishes > 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func unchangedAuthorityCannotClearTheStaleTicketBar() async throws {
        let owner = Owner(), (container, ticket) = try await support.seed()
        await #expect(throws: Owner.Failure.unchanged) {
            try await owner.refresh(ticket: ticket, session: session(ticket), generation: 1,
                container: container, cloud: cloud({ _ in try support.source.fixture(revision: 10) }), isCurrent: { true })
        }
        #expect(owner.activeCount == 0)
    }

    @Test func generationsAndContainersDoNotCoalesceAndCapacityIsBounded() async throws {
        let owner = Owner(), gate = Pause(), (container, ticket) = try await support.seed()
        let (other, otherTicket) = try await support.seed()
        defer { gate.release(); owner.cancelAll() }
        let client = cloud { _ in await gate.wait(); return try support.source.fixture(revision: 11) }
        var tasks: [Task<ProtectedInsightChatTicket, Error>] = []
        for index in 0..<Owner.maximumActiveRefreshes {
            tasks.append(Task { try await owner.refresh(ticket: index == 3 ? otherTicket : ticket,
                session: session(ticket), generation: UInt64(index == 3 ? 0 : index),
                container: index == 3 ? other : container, cloud: client, isCurrent: { true }) })
            await gate.entered()
        }
        #expect(owner.activeCount == 4)
        await #expect(throws: Owner.Failure.capacity) {
            try await owner.refresh(ticket: ticket, session: session(ticket), generation: 9,
                container: container, cloud: client, isCurrent: { true })
        }
        owner.cancelAll()
        await #expect(throws: Owner.Failure.busy) {
            try await owner.refresh(ticket: ticket, session: session(ticket), generation: 0,
                container: container, cloud: client, isCurrent: { true })
        }
        gate.release()
        for task in tasks { await #expect(throws: (any Error).self) { try await task.value } }
        #expect(owner.activeCount == 0)
    }

    @Test(arguments: ["account", "generation", "container", "delete", "review"])
    func changedScopeOrPendingReviewCannotCommit(_ change: String) async throws {
        let owner = Owner(), (container, ticket) = try await support.seed()
        var current = true
        let client = cloud { _ in
            if ["account", "generation", "container"].contains(change) { current = false } else if change == "delete" {
                try support.source.update(container) { scan, context in context.delete(scan) }
            } else {
                let context = ModelContext(container)
                context.insert(OfflineJobRecord(id: ObservationAnalysisReviewPersistence.observationPrefix(ticket.observationID) + UUID().uuidString.lowercased(),
                    kind: .observationAnalysisReviewSync, subjectId: ticket.observationID.uuidString.lowercased(), metadataJSON: "damaged"))
                try context.save()
            }
            return try support.source.fixture(revision: 11)
        }
        await #expect(throws: (any Error).self) {
            try await owner.refresh(ticket: ticket, session: session(ticket), generation: 1,
                container: container, cloud: client, isCurrent: { current })
        }
        if change != "delete" {
            let parent = try ObservationHistorySyncService.enrolledScan(ticket.observationID.uuidString, context: ModelContext(container))
            #expect(parent.observationStateRevision == 10)
        }
    }

    @Test func authDrainRetainsLeaseAndBlocksAdmissionUntilActualExit() async throws {
        let queue = OfflineQueueManager.shared, owner = queue.protectedChatRefreshOwner
        let gate = Pause(), (container, ticket) = try await support.seed()
        defer { gate.release(); owner.cancelAll() }
        var released = false, drained = false
        let client = cloud({ _ in released = false; await gate.wait(); return try support.source.fixture(revision: 11) }, finish: { released = true })
        let task = Task { try await owner.refresh(ticket: ticket, session: session(ticket), generation: 1,
            container: container, cloud: client, isCurrent: { true }) }
        await gate.entered()
        let started = AsyncStream<Void>.makeStream(); defer { started.continuation.finish() }
        let drain = Task { started.continuation.yield(); await queue.awaitRetainedSyncQuiescenceForAuthTransition(); drained = true }
        for await _ in started.stream { break }
        #expect(!released && !drained && owner.activeCount == 1)
        await #expect(throws: Owner.Failure.draining) {
            try await owner.refresh(ticket: ticket, session: session(ticket), generation: 2,
                container: container, cloud: client, isCurrent: { true })
        }
        gate.release(); await drain.value
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(released && drained && owner.activeCount == 0)
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
