import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ProtectedInsightChatDeliveryTests {
    typealias Service = ProtectedInsightChatDeliveryService
    typealias Store = ProtectedInsightChatPersistence
    let fixture = ProtectedInsightChatClaimsTests()
    func cloud(current: @escaping () -> Bool = { true }, finish: @escaping () -> Void = {}) -> ObservationHistoryCloudClient {
        fixture.support.source.support.client(fetch: { _ in Issue.record("Unexpected history read"); throw MerianError.invalidResponse },
                                             current: current, finish: finish)
    }
    func reply(_ intent: ProtectedInsightChatIntent) throws -> ProtectedInsightChatReply {
        try .init(data: fixture.receipt(intent), request: intent.request)
    }
    func complete(_ outcome: Service.Outcome) -> Bool { if case .completed = outcome { return true }; return false }

    @Test func exactSendSettlesAndLocalReceiptNeverDispatchesAgain() async throws {
        let (container, intent) = try await fixture.seed()
        var calls = 0, finishes = 0
        let service = Service(cloud: cloud(finish: { finishes += 1 }), submit: { request, owner, expiry, dispatch, response in
            calls += 1; #expect(request == intent.request && owner == intent.ownerID)
            #expect(expiry == fixture.start.addingTimeInterval(180))
            try dispatch(); try response(); return try reply(intent)
        }, now: { fixture.start })
        #expect(try await complete(service.deliver(intent, admission: .initial, container: container, isCurrent: { true }, permitsDispatch: { true })))
        #expect(try await complete(service.deliver(intent, admission: .initial, container: container, isCurrent: { true }, permitsDispatch: { false })))
        #expect(calls == 1 && finishes == 1)
        #expect(try fixture.job(intent, in: ModelContext(container)).status == .complete)
        let scan = try ObservationHistorySyncService.enrolledScan(intent.request.observationID.uuidString, context: ModelContext(container))
        #expect(scan.selectedAnalysisID == intent.request.selection.analysisID.uuidString.lowercased() && scan.observationStateRevision == 10)
    }

    @Test func unknownHoldsWithoutTimerAndOnlyExplicitReplayCanSend() async throws {
        let (container, intent) = try await fixture.seed()
        var calls = 0, time = fixture.start
        let service = Service(cloud: cloud(), submit: { request, _, _, dispatch, _ in
            try dispatch(); calls += 1; #expect(request == intent.request)
            if calls == 1 { throw URLError(.networkConnectionLost) }
            return try reply(intent)
        }, now: { time })
        if case .held = try await service.deliver(intent, admission: .initial, container: container, isCurrent: { true }, permitsDispatch: { true }) {} else {
            Issue.record("Unknown send was not held")
        }
        let held = try fixture.job(intent, in: ModelContext(container))
        #expect(held.status == .needsAttention && held.nextRunAt == nil)
        if case .notStarted = try await service.deliver(intent, admission: .initial, container: container, isCurrent: { true }, permitsDispatch: { true }) {} else {
            Issue.record("Held work restarted automatically")
        }
        let previous = try #require(try Store.currentAttempt(intent, container: container, isCurrent: { true }))
        time = time.addingTimeInterval(1)
        #expect(try await complete(service.deliver(intent, admission: .explicitReplay(previous), container: container, isCurrent: { true }, permitsDispatch: { true })))
        #expect(calls == 2 && previous.intent.request == intent.request)
    }

    @Test func cancelledTaskStillPersistsKnownLateReceipt() async throws {
        let (container, intent) = try await fixture.seed()
        var time = fixture.start, online = true
        let service = Service(cloud: cloud(), submit: { _, _, expiry, dispatch, response in
            try dispatch(); time = expiry.addingTimeInterval(5); online = false
            withUnsafeCurrentTask { $0?.cancel() }
            try response(); return try reply(intent)
        }, now: { time })
        let task = Task { @MainActor in
            try await service.deliver(intent, admission: .initial, container: container, isCurrent: { true }, permitsDispatch: { online })
        }
        #expect(try await complete(task.value))
        #expect(try Store.read(intent, container: container, isCurrent: { true }).isComplete)
    }

    @Test(arguments: ["account", "container", "deletion", "replacement"])
    func lostScopeOrClaimCannotSettle(change: String) async throws {
        let (container, intent) = try await fixture.seed()
        var current = true, leaseCurrent = true, time = fixture.start, finishes = 0
        let service = Service(cloud: cloud(current: { leaseCurrent }, finish: { finishes += 1 }), submit: { _, _, expiry, dispatch, response in
            try dispatch()
            switch change {
            case "account": leaseCurrent = false
            case "container": current = false
            case "deletion":
                let context = ModelContext(container)
                try Store.removeForDeletion(intent.request.observationID.uuidString, context: context); try context.save()
            default:
                let prior = try #require(try Store.currentAttempt(intent, container: container, isCurrent: { true }))
                time = expiry; _ = try Store.claimExplicitReplay(prior, at: time, container: container, isCurrent: { true })
            }
            try response(); return try reply(intent)
        }, now: { time })
        await #expect(throws: (any Error).self) {
            try await service.deliver(intent, admission: .initial, container: container, isCurrent: { current }, permitsDispatch: { true })
        }
        #expect(finishes == 1)
        if change != "deletion" {
            let row = try fixture.job(intent, in: ModelContext(container))
            #expect(try row.status == .running && !Store.restore(row).isComplete)
        }
    }

    @Test(arguments: [false, true])
    func cancellationBeforeOrDuringTransportCannotAutomaticallyRetry(before: Bool) async throws {
        let (container, intent) = try await fixture.seed()
        var calls = 0
        let service = Service(cloud: cloud(), submit: { _, _, _, _, _ in
            calls += 1; withUnsafeCurrentTask { $0?.cancel() }; throw CancellationError()
        }, now: { fixture.start })
        let task = Task { @MainActor in
            if before { withUnsafeCurrentTask { $0?.cancel() } }
            return try await service.deliver(intent, admission: .initial, container: container, isCurrent: { true }, permitsDispatch: { true })
        }
        if before { await #expect(throws: (any Error).self) { try await task.value } } else { _ = try await task.value }
        let row = try fixture.job(intent, in: ModelContext(container))
        #expect(row.status == (before ? .pending : .needsAttention) && row.nextRunAt == nil)
        #expect(calls == (before ? 0 : 1))
    }

    @Test(arguments: [false, true])
    func acknowledgementSaveFailurePreservesReceiptOrHoldsExactRequest(committed: Bool) async throws {
        let (container, intent) = try await fixture.seed()
        var saves = 0, calls = 0
        let service = Service(cloud: cloud(), submit: { _, _, _, dispatch, _ in
            try dispatch(); calls += 1; return try reply(intent)
        }, now: { fixture.start }, save: { context in
            saves += 1
            if saves == 2 {
                if committed { try context.save() }
                throw Store.IntegrityError.unavailable
            }
            try context.save()
        })
        let outcome = try await service.deliver(intent, admission: .initial, container: container, isCurrent: { true }, permitsDispatch: { true })
        #expect(complete(outcome) == committed && calls == 1)
        let row = try fixture.job(intent, in: ModelContext(container))
        #expect(row.status == (committed ? .complete : .needsAttention) && row.nextRunAt == nil)
    }
}
