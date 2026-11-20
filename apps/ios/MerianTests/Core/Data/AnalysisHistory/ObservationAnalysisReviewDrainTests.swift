import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager), .timeLimit(.minutes(1)))
struct ObservationAnalysisReviewDrainTests {
    let fixture = ObservationAnalysisReviewPersistenceTests()

    @Test func boundedPassPreservesEveryIntentAndContinuesAfterDurableOutcomes() async throws {
        let container = try fixture.container()
        let intents = try (0..<10).map { _ in try ObservationAnalysisReviewIntent(request: fixture.request(operationID: UUID()), ownerID: fixture.owner) }
        var sent: [UUID] = [], began = 0, finished = 0
        let cloud = ObservationReanalysisProducerTests().account(finish: { finished += 1 })
        let drain = ObservationAnalysisReviewDrain(cloud: cloud, deliver: { intent, received, current in
            #expect(current() && received === container); sent.append(intent.request.operationID)
            return [.waiting, .needsAttention, .completed, .notDue][sent.count % 4]
        }, candidates: { _, owner in
            #expect(owner == fixture.owner)
            return intents.enumerated().map { ($0.element, fixture.now.addingTimeInterval($0.offset == 9 ? 10 : -1)) }
        }, now: { fixture.now })
        await drain.run(ownerID: fixture.owner, container: container, isCurrent: { true },
                        didStart: { began += 1 }, requestRetry: { Issue.record("Durable result requested fallback") })
        #expect(sent == intents.prefix(8).map(\.request.operationID))
        #expect(began == 1 && finished == 1)
    }

    @Test(arguments: ["query", "save", "account", "context", "claim", "cancel", "future"])
    func failuresUseFallbackOnlyForCurrentStorageUncertainty(_ failure: String) async throws {
        let container = try fixture.container(), intent = try fixture.stage(container)
        var current = true, finished = 0, retries = 0, calls = 0
        let cloud = ObservationReanalysisProducerTests().account(current: { current }, finish: { finished += 1 })
        let drain = ObservationAnalysisReviewDrain(cloud: cloud, deliver: { _, _, valid in
            #expect(valid()); calls += 1
            if failure == "account" || failure == "context" { current = false }
            if failure == "save" { throw CocoaError(.fileWriteUnknown) }
            if failure == "claim" { throw ObservationAnalysisReviewPersistence.IntegrityError.conflict }
            if failure == "cancel" { throw CancellationError() }
            return .completed
        }, candidates: { _, _ in
            if failure == "query" { throw CocoaError(.fileReadUnknown) }
            return [(intent, fixture.now.addingTimeInterval(failure == "future" ? 1 : 0)), (intent, fixture.now.addingTimeInterval(1))]
        }, now: { fixture.now })
        await drain.run(ownerID: fixture.owner, container: container, isCurrent: { current }, didStart: {}, requestRetry: { retries += 1 })
        #expect(retries == (["query", "save"].contains(failure) ? 1 : 0))
        #expect(calls == (["query", "future"].contains(failure) ? 0 : 1) && finished == 1)
    }

    @Test func cancellationRetainsTaskAndLeaseUntilActualExit() async throws {
        let owner = ObservationAnalysisReviewDeliveryOwner(), container = try fixture.container(), intent = try fixture.stage(container)
        let started = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, valid: (@MainActor @Sendable () -> Bool)?
        var finished = 0, drained = false
        let cloud = ObservationReanalysisProducerTests().account(finish: { finished += 1 })
        let drain = ObservationAnalysisReviewDrain(cloud: cloud, deliver: { _, _, current in
            valid = current
            await withCheckedContinuation { release = $0; started.continuation.yield(()) }
            #expect(!current()); return .waiting
        }, candidates: { _, _ in [(intent, fixture.now)] }, now: { fixture.now })
        #expect(owner.start(operation: { current in
            await drain.run(ownerID: fixture.owner, container: container, isCurrent: current,
                            didStart: {}, requestRetry: { Issue.record("Cancelled work requested retry") })
        }, didFinish: {}))
        var iterator = started.stream.makeAsyncIterator(); _ = await iterator.next()
        #expect(valid?() == true)
        let teardown = Task { await owner.cancelAndAwait(); drained = true }
        await Task.yield()
        #expect(owner.isRunning && !drained && finished == 0 && valid?() == false)
        #expect(!owner.start(operation: { _ in Issue.record("Overlapped retained task") }, didFinish: {}))
        try #require(release).resume(); await teardown.value
        #expect(!owner.isRunning && drained && finished == 1 && valid?() == false)
    }

    @Test(arguments: ["conflict", "deleted", "unavailable", "account", "cancel", "storage"])
    func firstFailureCannotStarveIndependentDueReview(_ failure: String) async throws {
        let container = try fixture.container(), first = try fixture.stage(container)
        let second = try ObservationAnalysisReviewIntent(request: fixture.request(operationID: UUID()), ownerID: fixture.owner)
        var calls: [UUID] = [], retries = 0
        let drain = ObservationAnalysisReviewDrain(cloud: ObservationReanalysisProducerTests().account(), deliver: { intent, _, _ in
            calls.append(intent.request.operationID)
            if calls.count == 1 {
                switch failure {
                case "conflict": throw ObservationAnalysisReviewPersistence.IntegrityError.conflict
                case "deleted": throw ObservationHistoryError.deleted
                case "unavailable": throw ObservationHistoryError.unavailable
                case "account": throw ObservationAnalysisReviewPersistence.IntegrityError.accountChanged
                case "cancel": throw CancellationError()
                default: throw CocoaError(.fileWriteUnknown)
                }
            }
            return .waiting
        }, candidates: { _, _ in [(first, fixture.now), (second, fixture.now)] }, now: { fixture.now })
        await drain.run(ownerID: fixture.owner, container: container, isCurrent: { true }, didStart: {}, requestRetry: { retries += 1 })
        #expect(calls == (["conflict", "deleted", "unavailable"].contains(failure) ? [first.request.operationID, second.request.operationID] : [first.request.operationID]))
        #expect(retries == (failure == "storage" ? 1 : 0))
    }
}
