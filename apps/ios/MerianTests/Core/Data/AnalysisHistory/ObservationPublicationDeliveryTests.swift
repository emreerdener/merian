import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationPublicationDeliveryTests {
    let fixture = ObservationPublicationPersistenceTests()
    func missing(_ code: String = "analysis_history_not_found") -> MerianError {
        .httpError(statusCode: 404, message: "{\"code\":\"\(code)\"}")
    }
    func service() -> ObservationPublicationDeliveryService {
        var dependencies = ObservationPublicationDeliveryService.Dependencies()
        dependencies.ownerID = { fixture.owner }
        dependencies.begin = { owner in .init(id: UUID(), session: .init(userID: owner, isAnonymous: false)) }
        dependencies.finish = { _ in }
        dependencies.current = { _ in true }
        dependencies.now = { fixture.now }
        return .init(dependencies: dependencies)
    }
    func job(_ container: ModelContainer) throws -> OfflineJobRecord {
        try #require(try ModelContext(container).fetchOfflineJob(id: ObservationPublicationPersistence.jobID(fixture.operation, observationID: fixture.observation)))
    }
    func seed(_ container: ModelContainer) throws -> ObservationPublicationIntent {
        let result = try fixture.stage(container)
        let context = ModelContext(container)
        let job = try #require(try context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        job.createdAt = fixture.now.addingTimeInterval(-1); try context.save()
        return result
    }
    func run(_ service: ObservationPublicationDeliveryService, _ container: ModelContainer) async {
        await service.drain(container: container, isAvailable: { true }, didStart: {}, requestRetry: {})
    }

    @Test(arguments: [ObservationPublicationStatus.admitted, .needsAction])
    func recoveredTerminalNeverAdmitsOrReopens(_ status: ObservationPublicationStatus) async throws {
        let container = try fixture.container(); _ = try seed(container)
        var service = service(), calls = 0
        service.dependencies.status = { _, owner in
            #expect(owner == fixture.owner); calls += 1; return try fixture.receipt(status)
        }
        service.dependencies.admit = { _, _ in Issue.record("Unexpected admission"); throw missing() }
        await run(service, container); await run(service, container)
        #expect(calls == 1)
        let saved = try ObservationPublicationPersistence.restore(job(container))
        #expect(saved.isTerminal && saved.request == nil)
    }

    @Test func lostAdmissionReplyRecoversStatusWithoutResubmission() async throws {
        let container = try fixture.container(), original = try seed(container)
        var service = service(), submitted = false, admissions = 0, time = fixture.now
        service.dependencies.now = { time }
        service.dependencies.status = { _, _ in
            if submitted { return try fixture.receipt(.accepted) }
            throw missing()
        }
        service.dependencies.admit = { request, _ in
            #expect(try ObservationPublicationIntent.fingerprint(request) == original.requestSHA256)
            admissions += 1; submitted = true; throw URLError(.networkConnectionLost)
        }
        await run(service, container)
        #expect(try ObservationPublicationPersistence.restore(job(container)).request != nil)
        time = time.addingTimeInterval(301)
        await run(service, container)
        #expect(admissions == 1)
        #expect(try ObservationPublicationPersistence.restore(job(container)).request == nil)
        service.dependencies.status = { _, _ in throw missing() }
        time = time.addingTimeInterval(301); await run(service, container)
        #expect(admissions == 1)
        #expect(try job(container).status == .needsAttention)
    }

    @Test func arbitrary404NeverPermitsAdmission() async throws {
        let container = try fixture.container(); _ = try seed(container)
        var service = service()
        service.dependencies.status = { _, _ in throw missing("unrelated_route_missing") }
        service.dependencies.admit = { _, _ in Issue.record("Unexpected admission"); throw missing() }
        await run(service, container)
        #expect(try job(container).status == .waiting)
        #expect(try ObservationPublicationPersistence.restore(job(container)).request != nil)
    }

    @Test(arguments: [false, true])
    func accountLossAfterEitherAwaitCannotAcknowledge(admission: Bool) async throws {
        let container = try fixture.container(); _ = try seed(container)
        var service = service(), current = true, finished = 0
        service.dependencies.current = { _ in current }
        service.dependencies.finish = { _ in finished += 1 }
        service.dependencies.status = { _, _ in
            if admission { throw missing() }
            current = false; return try fixture.receipt(.admitted)
        }
        service.dependencies.admit = { _, _ in current = false; return try fixture.receipt(.accepted) }
        await run(service, container)
        #expect(finished == 1)
        #expect(try job(container).status == .running)
        #expect(try ObservationPublicationPersistence.restore(job(container)).request != nil)
    }

    @Test func deletionDuringStatusPreventsAdmissionAndRecreation() async throws {
        let container = try fixture.container(); _ = try seed(container)
        var service = service()
        service.dependencies.status = { _, _ in
            let context = ModelContext(container)
            try ObservationPublicationPersistence.removeForDeletion(fixture.observation.uuidString, context: context)
            try context.save(); throw missing()
        }
        service.dependencies.admit = { _, _ in Issue.record("Deleted operation admitted"); throw missing() }
        await run(service, container)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func newerClaimDefeatsStaleAcknowledgementRetryAndDispatch() throws {
        let container = try fixture.container(), intent = try seed(container)
        let first = try #require(try ObservationPublicationPersistence.claim(intent, at: fixture.now, container: container, isCurrent: { true }))
        #expect(try ObservationPublicationPersistence.claim(intent, at: fixture.now, container: container, isCurrent: { true }) == nil)
        let second = try #require(try ObservationPublicationPersistence.claim(intent, at: first.expiresAt, container: container, isCurrent: { true }))
        #expect(second.attempt == first.attempt + 1)
        #expect(throws: (any Error).self) {
            try ObservationPublicationPersistence.acknowledge(fixture.receipt(.admitted), expected: intent, at: first.expiresAt,
                container: container, isCurrent: { true }, claim: first)
        }
        #expect(throws: (any Error).self) {
            try ObservationPublicationPersistence.retry(first, at: first.expiresAt, needsAttention: false, container: container, isCurrent: { true })
        }
        #expect(throws: (any Error).self) {
            try ObservationPublicationPersistence.requireDispatch(first, at: first.expiresAt, container: container, isCurrent: { true })
        }
        _ = try ObservationPublicationPersistence.acknowledge(fixture.receipt(.admitted), expected: intent,
            at: second.expiresAt.addingTimeInterval(1), container: container, isCurrent: { true }, claim: second)
        #expect(try job(container).status == .complete)
    }

    @Test(arguments: [1, 2])
    func saveFailureDoesNotLoseWorkAndRequestsFallback(failingFrom: Int) async throws {
        let container = try fixture.container(); _ = try seed(container)
        var service = service(), saves = 0, statusCalls = 0, fallback = 0
        service.dependencies.save = { context in
            saves += 1
            if saves >= failingFrom { throw CocoaError(.fileWriteUnknown) }
            try context.save()
        }
        service.dependencies.status = { _, _ in statusCalls += 1; return try fixture.receipt(.admitted) }
        await service.drain(container: container, isAvailable: { true }, didStart: {}, requestRetry: { fallback += 1 })
        #expect(fallback == 1 && statusCalls == failingFrom - 1)
        #expect(try ObservationPublicationPersistence.restore(job(container)).request != nil)
    }

    @Test func ownerCoalescesAndAwaitsCancellation() async {
        let joined = AsyncStream<Void>.makeStream()
        let owner = ObservationPublicationDeliveryOwner(didJoin: { joined.continuation.yield(()) })
        let started = AsyncStream<Void>.makeStream(), release = AsyncStream<Void>.makeStream()
        var calls = 0, exited = false
        let first = Task { await owner.run {
            calls += 1; started.continuation.yield(())
            var iterator = release.stream.makeAsyncIterator(); _ = await iterator.next()
            exited = true
        } }
        var iterator = started.stream.makeAsyncIterator(); _ = await iterator.next()
        let second = Task { await owner.run { calls += 1 } }
        var joinedIterator = joined.stream.makeAsyncIterator(); _ = await joinedIterator.next()
        await owner.cancelAndAwait()
        await first.value; await second.value
        #expect(calls == 1 && exited && !owner.isRunning)
        await owner.run { calls += 1 }
        #expect(calls == 2 && !owner.isRunning)
        started.continuation.finish(); release.continuation.finish(); joined.continuation.finish()
    }

    @Test func passExitEmitsOnceAfterActualLeaseReleaseNotForJoiners() async {
        let entered = AsyncStream<Void>.makeStream(), joined = AsyncStream<Void>.makeStream()
        let owner = ObservationPublicationDeliveryOwner(didJoin: { joined.continuation.yield(()) })
        var release: CheckedContinuation<Void, Never>?
        var leaseReleased = false, exits = 0, joinerExits = 0
        let first = Task {
            await owner.run(didFinish: {
                #expect(leaseReleased && !owner.isRunning)
                exits += 1
            }) {
                await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
                leaseReleased = true
            }
        }
        var iterator = entered.stream.makeAsyncIterator(); _ = await iterator.next()
        let second = Task { await owner.run(didFinish: { joinerExits += 1 }) { Issue.record("Duplicate pass") } }
        var joinedIterator = joined.stream.makeAsyncIterator(); _ = await joinedIterator.next()
        owner.cancel()
        #expect(owner.isRunning && exits == 0 && !leaseReleased)
        release?.resume()
        await owner.cancelAndAwait(); await first.value; await second.value
        #expect(exits == 1 && joinerExits == 0 && !owner.isRunning)
        await owner.run(didFinish: { exits += 1 }) {}
        #expect(exits == 2)
        entered.continuation.finish(); joined.continuation.finish()
    }

    @Test func publicationPassExitRejectsReplacedOwnerOrContext() throws {
        let manager = OfflineQueueManager.shared, previous = manager.modelContext
        let context = ModelContext(try fixture.container()), replacement = ModelContext(try fixture.container())
        manager.modelContext = context
        defer { manager.modelContext = previous }
        let generation = manager.publicationDeliveryGeneration
        manager.publicationDeliveryDidFinish(ownerID: fixture.owner, context: context, currentOwnerID: UUID())
        manager.publicationDeliveryDidFinish(ownerID: fixture.owner, context: context, currentOwnerID: nil)
        manager.modelContext = replacement
        manager.publicationDeliveryDidFinish(ownerID: fixture.owner, context: context, currentOwnerID: fixture.owner)
        #expect(manager.publicationDeliveryGeneration == generation)
        manager.modelContext = context
        manager.publicationDeliveryDidFinish(ownerID: fixture.owner, context: context, currentOwnerID: fixture.owner)
        #expect(manager.publicationDeliveryGeneration == generation &+ 1)
    }

    @Test func schedulerUsesOnlyCurrentOwnerAndRecoversClaimDeadline() throws {
        let container = try fixture.container(), intent = try seed(container)
        let manager = OfflineQueueManager.shared, original = manager.modelContext
        manager.modelContext = ModelContext(container)
        defer { manager.modelContext = original }
        var owner: UUID? = fixture.owner
        let scheduler = OfflineJobScheduler(drainOperations: .init(
            reconcileFunding: { _ in }, syncPendingScans: { _ in }, replayInference: { _ in },
            replayFieldTripProgress: { _ in }, syncPendingDeletions: { _ in }, syncCollections: { _ in }
        ), deletionAccountID: { owner })
        #expect(scheduler.nextPersistedWakeDate(using: manager) == fixture.now.addingTimeInterval(-1))
        let claim = try #require(try ObservationPublicationPersistence.claim(intent, at: fixture.now, container: container, isCurrent: { true }))
        #expect(scheduler.nextPersistedWakeDate(using: manager) == claim.expiresAt)
        owner = UUID(); #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
        owner = nil; #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
        owner = fixture.owner
        try ObservationPublicationPersistence.retry(claim, at: fixture.now, needsAttention: true, container: container, isCurrent: { true })
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
        #expect(try fixture.stage(container).request != nil)
    }

    @Test func persistenceFallbackDoesNotSpinOnDuePendingJob() throws {
        let container = try fixture.container(); _ = try seed(container)
        let manager = OfflineQueueManager.shared, original = manager.modelContext, online = manager.isOnline
        manager.modelContext = ModelContext(container); manager.isOnline = true
        var owner: UUID? = fixture.owner
        let scheduler = OfflineJobScheduler(drainOperations: .init(
            reconcileFunding: { _ in }, syncPendingScans: { _ in }, replayInference: { _ in },
            replayFieldTripProgress: { _ in }, syncPendingDeletions: { _ in }, syncCollections: { _ in }
        ), deletionAccountID: { owner })
        defer { scheduler.cancelScheduledWake(); manager.modelContext = original; manager.isOnline = online }
        let now = Date()
        scheduler.schedulePublicationRetry(using: manager, now: now)
        #expect(scheduler.scheduledWakeDate == now.addingTimeInterval(5))
        #expect(scheduler.nextPersistedWakeDate(using: manager) == now.addingTimeInterval(5))
        owner = UUID()
        scheduler.publicationDrainDidStart(using: manager)
        scheduler.scheduleNextPersistedWake(using: manager, now: now)
        #expect(scheduler.scheduledWakeDate == nil)
        owner = fixture.owner
        scheduler.scheduleNextPersistedWake(using: manager, now: now)
        #expect(scheduler.scheduledWakeDate == now.addingTimeInterval(5))
        scheduler.publicationDrainDidStart(using: manager)
        #expect(scheduler.nextPersistedWakeDate(using: manager) == fixture.now.addingTimeInterval(-1))
    }
}
