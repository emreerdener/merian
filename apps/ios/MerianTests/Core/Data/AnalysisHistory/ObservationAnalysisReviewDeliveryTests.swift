import Foundation
@testable import Merian
import Supabase
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct ObservationAnalysisReviewDeliveryTests {
    typealias Service = ObservationAnalysisReviewDeliveryService
    typealias Store = ObservationAnalysisReviewPersistence
    let fixture = ObservationAnalysisReviewReconciliationTests()

    @Test(arguments: ["applied", "revision_conflict", "not_verified"])
    func mutationThenFreshReceiptClaimCompleteInOrder(outcome: String) async throws {
        let (container, intent) = try await fresh(decision: .confirmPrimary)
        var events: [String] = [], finishes = 0
        let cloud = try client(during: { events.append("read\($0)") }, finish: { finishes += 1 })
        let delivery = Service(cloud: cloud, submit: { request, owner, validate in
            #expect(request == intent.request && owner == intent.ownerID)
            events.append("submit"); try validate(); return try receipt(request, outcome: outcome)
        }, now: { fixture.date })
        let result = try await delivery.deliver(intent, container: container, isCurrent: { true })
        #expect(result == .completed && events == ["submit", "read1", "read2"] && finishes == 2)
        let saved = try Store.restore(job(intent, container))
        #expect(try saved.isComplete && saved.receipt?.outcome == receipt(intent.request, outcome: outcome).outcome)
        #expect(try job(intent, container).attemptCount == 2)
        #expect(try fixture.projection.parent(container).selectedAnalysisID == fixture.selected.uuidString.lowercased())
        #expect(try await delivery.deliver(saved, container: container, isCurrent: { true }) == .notDue)
        #expect(events.count == 3)
    }

    @Test func ambiguousReplyRetriesExactIntentBeforeCurrentStateChecks() async throws {
        let (container, intent) = try await fresh()
        var calls = 0, time = fixture.date
        let delivery = Service(cloud: try client(), submit: { request, _, validate in
            try validate(); calls += 1; #expect(request == intent.request)
            if calls == 1 {
                _ = try await fixture.source.service(data: fixture.targetData(revision: 11, selectedID: fixture.target))
                    .syncSelected(observationID: fixture.observation.uuidString, container: container)
                throw URLError(.networkConnectionLost)
            }
            return try receipt(request)
        }, now: { time })
        #expect(try await delivery.deliver(intent, container: container, isCurrent: { true }) == .waiting)
        #expect(try job(intent, container).nextRunAt != nil)
        #expect(try await delivery.deliver(intent, container: container, isCurrent: { true }) == .notDue)
        #expect(calls == 1)
        time = time.addingTimeInterval(301)
        #expect(try await delivery.deliver(intent, container: container, isCurrent: { true }) == .completed)
        #expect(try calls == 2 && Store.restore(job(intent, container)).request == intent.request)
    }

    @Test func acknowledgedReceiptAfterRestartNeverDispatchesAgain() async throws {
        let (container, claim) = try await fixture.seeded()
        let recovered = try ObservationAnalysisReviewIntent.decode(claim.intent.storedData())
        let delivery = Service(cloud: try client(), submit: { _, _, _ in
            Issue.record("Receipt recovery dispatched a mutation"); throw MerianError.invalidResponse
        }, now: { claim.expiresAt })
        #expect(try await delivery.deliver(recovered, container: container, isCurrent: { true }) == .completed)
        #expect(try job(recovered, container).attemptCount == claim.attempt + 1)
    }

    @Test func reconciliationFailureUsesNewClaimAndRetainsReceipt() async throws {
        let (container, intent) = try await fresh()
        #expect(try await service(cloud: client(secondRevision: 13)).deliver(intent, container: container, isCurrent: { true }) == .waiting)
        let received = try Store.restore(job(intent, container))
        #expect(received.hasReceipt && !received.isComplete && received.request == intent.request)
        #expect(try job(intent, container).attemptCount == 2 && job(intent, container).nextRunAt != nil)
        let delivery = Service(cloud: try client(), submit: { _, _, _ in
            Issue.record("Reconciliation retry dispatched"); throw MerianError.invalidResponse
        }, now: { fixture.date.addingTimeInterval(301) })
        #expect(try await delivery.deliver(received, container: container, isCurrent: { true }) == .completed)
    }

    @Test(arguments: [false, true])
    func accountLossNeverAcknowledgesOrRetries(reconciliation: Bool) async throws {
        let (container, intent) = try await fresh()
        var current = true, finishes = 0
        let cloud = try client(current: { current }, during: { _ in if reconciliation { current = false } }, finish: { finishes += 1 })
        let delivery = Service(cloud: cloud, submit: { request, _, validate in
            try validate(); if !reconciliation { current = false }; return try receipt(request)
        }, now: { fixture.date })
        await #expect(throws: (any Error).self) { try await delivery.deliver(intent, container: container, isCurrent: { true }) }
        let saved = try Store.restore(job(intent, container))
        #expect(saved.hasReceipt == reconciliation && !saved.isComplete)
        #expect(try job(intent, container).status == .running && job(intent, container).lastErrorCode == nil)
        #expect(finishes == (reconciliation ? 2 : 1))
    }

    @Test(arguments: ["deletion", "successor", "expiry"])
    func dispatchValidatorRechecksClaimAfterSuspension(change: String) async throws {
        let (container, intent) = try await fresh()
        var time = fixture.date, sent = false
        let delivery = Service(cloud: try client(), submit: { request, _, validate in
            await Task.yield()
            if change == "deletion" {
                let context = ModelContext(container)
                try Store.removeForDeletion(request.observationID.uuidString, context: context); try context.save()
            } else {
                time = time.addingTimeInterval(180)
                if change == "successor" { _ = try Store.claim(intent, at: time, container: container, isCurrent: { true }) }
            }
            try validate(); sent = true; return try receipt(request)
        }, now: { time })
        if change == "expiry" {
            #expect(try await delivery.deliver(intent, container: container, isCurrent: { true }) == .waiting)
        } else {
            await #expect(throws: (any Error).self) { try await delivery.deliver(intent, container: container, isCurrent: { true }) }
        }
        #expect(!sent)
        if change == "deletion" {
            #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        } else if change == "successor" {
            #expect(try job(intent, container).attemptCount == 2 && job(intent, container).status == .running)
        }
    }

    @Test(arguments: [1, 2, 3, 4])
    func saveFailurePreservesTheLastDurablePhase(failingFrom: Int) async throws {
        let (container, intent) = try await fresh()
        var delivery = try service(), writes = 0
        delivery.save = { context in
            writes += 1
            if writes >= failingFrom { throw CocoaError(.fileWriteUnknown) }
            try context.save()
        }
        await #expect(throws: (any Error).self) { try await delivery.deliver(intent, container: container, isCurrent: { true }) }
        let saved = try Store.restore(job(intent, container))
        #expect(saved.hasReceipt == (failingFrom >= 3) && !saved.isComplete)
        #expect(try fixture.projection.parent(container).observationStateRevision == 10)
        #expect(try fixture.source.support.count(container) == 1)
        #expect(try job(intent, container).attemptCount == (failingFrom == 1 ? 0 : failingFrom == 4 ? 2 : 1))
    }

    @Test func malformedReceiptHoldsWithoutInventingAcknowledgementOrDeadline() async throws {
        let (container, intent) = try await fresh()
        let delivery = Service(cloud: try client(), submit: { _, _, validate in try validate(); throw MerianError.invalidResponse }, now: { fixture.date })
        #expect(try await delivery.deliver(intent, container: container, isCurrent: { true }) == .needsAttention)
        #expect(try !Store.restore(job(intent, container)).hasReceipt && job(intent, container).nextRunAt == nil)
        #expect(try await delivery.deliver(intent, container: container, isCurrent: { true }) == .notDue)
    }
    @Test func cancellationRetainsClaimWithoutFailureWrite() async throws {
        let (container, intent) = try await fresh()
        let started = AsyncStream<Void>.makeStream(), release = AsyncStream<Void>.makeStream()
        let delivery = Service(cloud: try client(), submit: { request, _, validate in
            try validate(); started.continuation.yield(())
            var iterator = release.stream.makeAsyncIterator(); _ = await iterator.next()
            try Task.checkCancellation(); return try receipt(request)
        }, now: { fixture.date })
        let task = Task { try await delivery.deliver(intent, container: container, isCurrent: { true }) }
        var iterator = started.stream.makeAsyncIterator(); _ = await iterator.next()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        started.continuation.finish(); release.continuation.finish()
        #expect(try job(intent, container).status == .running && job(intent, container).lastErrorCode == nil)
        #expect(try !Store.restore(job(intent, container)).hasReceipt)
    }

    @Test(arguments: [false, true])
    func sdkStateFailuresRequireExactPermanentIdentity(permanent: Bool) async throws {
        let (container, intent) = try await fresh()
        var cloud = try client()
        cloud.fetchState = { _ in
            let message = permanent ? "analysis_history_not_found" : "unrelated_missing_row"
            let bytes = try JSONSerialization.data(withJSONObject: ["code": "P0002", "message": message])
            throw try JSONDecoder().decode(PostgrestError.self, from: bytes)
        }
        let outcome = try await service(cloud: cloud).deliver(intent, container: container, isCurrent: { true })
        #expect(outcome == (permanent ? .needsAttention : .waiting))
        #expect(try Store.restore(job(intent, container)).hasReceipt)
        #expect(try (job(intent, container).nextRunAt == nil) == permanent)
    }

}
