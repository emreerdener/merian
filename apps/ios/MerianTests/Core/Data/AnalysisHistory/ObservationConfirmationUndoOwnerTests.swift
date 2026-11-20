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
    @Test(arguments: [false, true])
    func uiSeedRetainsAcknowledgedReviewAndExactSelectedTicket(named: Bool) throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let fixture = try PublicationConsentUIFixture(container: container, namedReview: named, confirmationUndo: true)
        let context = ModelContext(container)
        try fixture.seed(context: context)
        try context.save()
        let scan = try ObservationHistorySyncService.enrolledScan(PublicationConsentUIFixture.observation, context: ModelContext(container))
        #expect(scan.analysisRecords?.count == 2)
        #expect(scan.observationStateRevision == 11)
        #expect(scan.userReviewState == (named ? .userOverridden : .aiConfirmed))
        #expect(scan.selectedAnalysisID == PublicationConsentUIFixture.selected)
        let selected = try ObservationHistoryPage.uuid(PublicationConsentUIFixture.selected)
        let entry = try ObservationHistoryListingService.entry(selected, scan: scan, context: ModelContext(container))
        let ticket = try ObservationAnalysisReviewTicket(entry: entry,
            context: .init(owner: PublicationConsentUIFixture.owner, selected: selected, revision: 11, pendingOperation: nil, undoOperation: nil),
            observationID: ObservationHistoryPage.uuid(scan.id))
        #expect(ticket.confirmationAction == (named ? .name : .primary))
        #expect(ticket.confirmationOperationID != nil)
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
    @Test func cancelledPresentationCannotPublishWhileJoinedPresentationCompletes() async throws {
        let fixture = try await ConfirmationUndoEligibilityTests().seed()
        let gate = Pause(), owner = Owner()
        defer { gate.release(); owner.cancelAll() }
        var calls = 0, exits = 0, firstPublished = false, secondPublished = false
        let cloud = ObservationHistorySyncTests().client(fetch: { _ in Data() }, finish: { exits += 1 })
        let service = ObservationConfirmationUndoService(cloud: cloud, fetch: { lookup, _, validate in
            calls += 1; await gate.wait(); try validate()
            var row = try lookup.object()
            row.merge(["status": "available", "confirmation_operation_id": fixture.operation.uuidString.lowercased(),
                       "confirmation_action": "confirm_primary"]) { _, new in new }
            return try .init(data: JSONSerialization.data(withJSONObject: row), request: lookup)
        })
        let session = AuthTransitionSession(userID: fixture.ticket.ownerID, isAnonymous: false)
        let first = Task {
            let result = try await owner.prepare(ticket: fixture.ticket, session: session, generation: 1,
                container: fixture.container, service: service, isCurrent: { true })
            firstPublished = true
            return result
        }
        await gate.entered()
        let joined = AsyncStream<Void>.makeStream(); defer { joined.continuation.finish() }
        let second = Task {
            let result = try await owner.prepare(ticket: fixture.ticket, session: session, generation: 1,
                container: fixture.container, service: service, isCurrent: { joined.continuation.yield(); return true })
            secondPublished = true
            return result
        }
        for await _ in joined.stream { break }
        first.cancel()
        #expect(calls == 1 && exits == 0 && owner.activeCount == 1)
        #expect(!firstPublished && !secondPublished)
        gate.release()
        await #expect(throws: CancellationError.self) { try await first.value }
        let result = try await second.value
        guard case let .available(eligibility) = result else { Issue.record("Joined presentation lost eligibility"); return }
        #expect(eligibility.operationID == fixture.operation)
        #expect(!firstPublished && secondPublished && calls == 1 && exits == 1 && owner.activeCount == 0)
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
