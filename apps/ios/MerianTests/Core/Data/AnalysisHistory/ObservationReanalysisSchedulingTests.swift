import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager), .timeLimit(.minutes(1)))
struct ObservationReanalysisSchedulingTests {
    let fixture = ObservationReanalysisAdmissionTests()
    @Test func cancelledOwnerKeepsSlotUntilActualTaskExitAndCannotAffectSuccessor() async throws {
        let owner = ObservationReanalysisExecutionOwner(), started = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, valid: (@MainActor @Sendable () -> Bool)?
        var finishes = 0, drained = false
        let firstStarted = owner.start(operation: { current in
            valid = current
            await withCheckedContinuation { continuation in
                release = continuation; started.continuation.yield(())
            }
            #expect(!current())
        }, didFinish: { finishes += 1 })
        #expect(firstStarted)
        var iterator = started.stream.makeAsyncIterator(); _ = await iterator.next()
        #expect(valid?() == true)
        #expect(!owner.start(operation: { _ in Issue.record("Duplicate execution") }, didFinish: {}))
        owner.cancel()
        let draining = Task { await owner.cancelAndAwait(); drained = true }
        await Task.yield()
        #expect(valid?() == false && owner.isRunning && !drained)
        #expect(!owner.start(operation: { _ in Issue.record("Overlapped cancelled task") }, didFinish: {}))
        try #require(release).resume(); await draining.value
        #expect(drained && finishes == 1 && !owner.isRunning)
        let completed = AsyncStream<Void>.makeStream()
        defer { completed.continuation.finish() }
        let secondStarted = owner.start(operation: { current in #expect(current()) },
            didFinish: { finishes += 1; completed.continuation.yield(()) })
        #expect(secondStarted && valid?() == false)
        var completion = completed.stream.makeAsyncIterator(); _ = await completion.next()
        #expect(finishes == 2 && !owner.isRunning)
    }
    @Test func schedulerUsesOnlyAdmittedOwnerQualifiedWorkAndHonorsFailureFloor() throws {
        let container = try fixture.fixture.fixture.fixture.container(), draft = try fixture.stage(container)
        let manager = OfflineQueueManager.shared, previous = manager.modelContext
        manager.modelContext = ModelContext(container)
        defer { manager.modelContext = previous }
        var owner: UUID? = draft.identity.ownerID
        let scheduler = OfflineJobScheduler(drainOperations: .init(reconcileFunding: { _ in }, syncPendingScans: { _ in },
            replayInference: { _ in }, replayFieldTripProgress: { _ in }, syncPendingDeletions: { _ in }, syncCollections: { _ in }),
            deletionAccountID: { owner })
        defer { scheduler.cancelScheduledWake(using: manager) }
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
        let pending = try fixture.admit(draft, container)
        #expect(scheduler.nextPersistedWakeDate(using: manager) == pending.nextRun)
        owner = UUID(); #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
        owner = draft.identity.ownerID
        let clock = fixture.fixture.now.addingTimeInterval(30)
        scheduler.scheduleReanalysisRetry(using: manager, now: clock)
        #expect(scheduler.nextPersistedWakeDate(using: manager) == clock.addingTimeInterval(5))
        scheduler.reanalysisDrainDidStart(using: manager)
        #expect(scheduler.nextPersistedWakeDate(using: manager) == pending.nextRun)
        let claim = try ObservationReanalysisExecutionStore.claim(pending, admission: .initial,
            now: fixture.fixture.now, container: container, isCurrent: { true })
        #expect(scheduler.nextPersistedWakeDate(using: manager) == claim.snapshot.lastAttempt)
        try ObservationReanalysisExecutionStore.settle(claim, as: .held(.consentRequired), now: clock,
            container: container, isCurrent: { true })
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
    }
    @Test(arguments: ["success", "future", "query-error", "commit-error", "account", "offline"])
    func boundedServiceUsesFallbackOnlyForCurrentOwnerAndCleansOnlyCompletion(_ state: String) async throws {
        let container = try fixture.fixture.fixture.fixture.container(), draft = try fixture.stage(container)
        let pending = try fixture.admit(draft, container)
        var current = true, began = 0, retries = 0, cleaned = 0, finished = 0, executed = 0, notified = 0
        let service = ObservationReanalysisExecutionService(account: ObservationReanalysisProducerTests().account(
            current: { current }, finish: { finished += 1 }), candidates: { _, _, _ in
                if state == "query-error" { throw CocoaError(.fileReadUnknown) }
                return [.init(snapshot: pending, admission: .initial,
                    due: fixture.fixture.now.addingTimeInterval(state == "future" ? 60 : 0))]
            }, execute: { _, _, validate in
                #expect(validate()); executed += 1
                if state == "account" { current = false }
                if state == "commit-error" { throw CocoaError(.fileWriteUnknown) }
                return .completed(.init(parentID: draft.identity.observationID, childID: draft.identity.analysisID))
            }, now: { fixture.fixture.now })
        await service.drain(ownerID: draft.identity.ownerID, container: container,
            isCurrent: { state != "offline" }, didStart: { began += 1 }, requestRetry: { retries += 1 }, cleanup: { #expect(notified == 1); cleaned += 1 }, didComplete: { notified += 1 })
        #expect(began == (state == "offline" ? 0 : 1) && finished == began)
        #expect(executed == (["offline", "future", "query-error"].contains(state) ? 0 : 1))
        #expect(retries == (["query-error", "commit-error"].contains(state) ? 1 : 0))
        #expect(cleaned == (state == "success" ? 1 : 0))
        #expect(notified == cleaned)
    }

    @Test(arguments: [false, true])
    func leaseAcquisitionFailureGetsBoundedRetryOnlyWhileOwnerCurrent(stale: Bool) async throws {
        let container = try fixture.fixture.fixture.fixture.container()
        var current = true, retries = 0
        var account = ObservationReanalysisProducerTests().account()
        account.begin = { _ in current = !stale; throw ObservationHistoryError.accountChanged }
        let service = ObservationReanalysisExecutionService(account: account, candidates: { _, _, _ in
            Issue.record("Lease failure read private candidates"); return []
        }, execute: { _, _, _ in Issue.record("Lease failure executed"); return .waiting })
        await service.drain(ownerID: fixture.fixture.fixture.fixture.owner, container: container,
            isCurrent: { current }, didStart: { Issue.record("Lease failure started pass") },
            requestRetry: { retries += 1 }, cleanup: { Issue.record("Lease failure cleaned evidence") })
        #expect(retries == (stale ? 0 : 1))
    }

    @Test func pendingReanalysisCannotBecomeLegacyFundingOrJobWake() throws {
        let container = try fixture.fixture.fixture.fixture.container(), draft = try fixture.stage(container)
        _ = try fixture.admit(draft, container)
        let (context, row, job) = try fixture.fixture.fixture.stored(container)
        #expect(!row.permitsOrdinaryInference)
        job.kind = .scanIngestion; try context.save()
        #expect(try ObservationReanalysisExecutionStore.candidates(ownerID: draft.identity.ownerID,
            container: container, isCurrent: { true }).isEmpty)
        let manager = OfflineQueueManager.shared, previous = manager.modelContext
        manager.modelContext = context
        defer { manager.modelContext = previous }
        let scheduler = OfflineJobScheduler(drainOperations: .init(reconcileFunding: { _ in }, syncPendingScans: { _ in },
            replayInference: { _ in }, replayFieldTripProgress: { _ in }, syncPendingDeletions: { _ in }, syncCollections: { _ in }),
            deletionAccountID: { draft.identity.ownerID })
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
    }
}
