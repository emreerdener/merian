import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoReservationDeliveryTests {
    typealias Store = ObservationVideoSourceReservationStore
    typealias Owner = ObservationVideoReservationOwner
    typealias Service = ObservationVideoReservationService
    let fixture = ObservationVideoReservationLifecycleTests()

    func key(_ entry: Store.Snapshot) -> Owner.Key {
        .init(snapshot: entry, session: .init(userID: entry.work.preparation.identity.ownerID, isAnonymous: false),
            generation: 1, container: entry.containerID)
    }
    func account(_ key: Owner.Key, finish: @escaping () -> Void = {}) -> ObservationHistoryCloudClient {
        .init(begin: { owner in
            #expect(owner == key.session.userID)
            return .init(id: UUID(), session: key.session)
        }, isCurrent: { $0.session == key.session }, finish: { _ in finish() }, fetch: { _ in
            Issue.record("Reservation must not fetch history"); throw MerianError.invalidResponse
        })
    }
    func run(_ entry: Store.Snapshot, seed: ObservationVideoDurabilityTests.Seed, owner: Owner, service: Service,
             current: @escaping @MainActor @Sendable () -> Bool = { true },
             permitsDispatch: @escaping @MainActor @Sendable () -> Bool = { true }) async throws -> Service.Outcome? {
        let key = key(entry), proof = try seed.proof
        var released = false
        let cloud = account(key) { released = true }
        return await withCheckedContinuation { continuation in
            var outcome: Service.Outcome?
            let admission = owner.start(key, account: cloud, isCurrent: current, permitsDispatch: permitsDispatch, operation: { scope in
                outcome = await service.run(entry, proof: proof, container: seed.container, scope: scope)
            }, didFinish: {
                #expect(released && !owner.isRunning)
                continuation.resume(returning: outcome)
            })
            if admission != .started { continuation.resume(returning: nil) }
        }
    }

    @Test(arguments: ["reserved", "held", "unavailable", "conflict", "unknown", "cancel", "account"])
    func oneSavedAttemptSettlesOnlyKnownCurrentAnswers(_ boundary: String) async throws {
        let (seed, entry) = try await fixture.staged(); defer { seed.remove() }
        let owner = Owner(), files = ObservationReanalysisFileStore(documents: seed.root)
        var sends = 0, reads = 0, current = true
        let reply = try fixture.reply(entry, state: ["held", "unavailable"].contains(boundary) ? boundary : "reserved")
        let service = Service(verifyFiles: { preparation, validate in
            _ = try await files.readVideo(preparation: preparation, validateBeforeRead: validate, validateBeforeReturn: validate)
            reads += 1
        }, reserve: { candidate, ownerID, before, after in
            try before(); sends += 1
            #expect(candidate.body == entry.work.request.body && ownerID == seed.source.ownerID)
            #expect(try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true }).work.phase == .running)
            if boundary == "unknown" { throw URLError(.timedOut) }
            if boundary == "cancel" || boundary == "conflict" { owner.cancel() }
            if boundary == "account" { current = false }
            try after()
            if boundary == "conflict" { throw ObservationVideoSourceReservationConflict(request: candidate, ownerID: ownerID) }
            return reply
        })
        _ = try await run(entry, seed: seed, owner: owner, service: service, current: { current })
        #expect(sends == 1 && reads == 1)
        let saved = try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true })
        let expected: ObservationVideoSourceReservationWork.Phase = boundary == "account" ? .running
            : boundary == "unknown" ? .unknown : boundary == "conflict" ? .conflict : .observed
        #expect(saved.work.phase == expected && saved.work.request == entry.work.request)
        #expect(try await run(saved, seed: seed, owner: owner, service: service) == nil)
        #expect(sends == 1)
    }

    @Test(arguments: ["missing", "cancel", "account", "erasure", "dispatch"])
    func failureDuringSavedFileVerificationNeverDispatches(_ boundary: String) async throws {
        let (seed, entry) = try await fixture.staged(); defer { seed.remove() }
        let owner = Owner(), files = ObservationReanalysisFileStore(documents: seed.root)
        var current = true, dispatch = true
        if boundary == "missing" { try FileManager.default.removeItem(at: seed.root.appendingPathComponent(seed.preparation.files[0].path)) }
        let service = Service(verifyFiles: { preparation, validate in
            _ = try await files.readVideo(preparation: preparation, validateBeforeRead: validate, validateBeforeReturn: validate)
            if boundary == "cancel" { owner.cancel() }
            if boundary == "account" { current = false }
            if boundary == "dispatch" { dispatch = false }
            if boundary == "erasure" {
                let context = ModelContext(seed.container)
                try ObservationReanalysisErasureReceipt(parentID: seed.source.observationID, childID: preparation.identity.analysisID).record(in: context)
                try context.save()
            }
        }, reserve: { _, _, _, _ in Issue.record("Stale or incomplete cohort dispatched"); throw MerianError.invalidResponse })
        _ = try await run(entry, seed: seed, owner: owner, service: service, current: { current }, permitsDispatch: { dispatch })
        if boundary != "erasure" {
            let saved = try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true })
            #expect(saved.work.phase == (boundary == "missing" ? .unknown : .running))
        }
    }

    @Test(arguments: [false, true], [false, true])
    func uncertainSaveDoesNotAuthorizeAnotherDispatch(claim: Bool, commits: Bool) async throws {
        let (seed, entry) = try await fixture.staged(); defer { seed.remove() }
        let owner = Owner(), reply = try fixture.reply(entry)
        var sends = 0
        var service = Service(verifyFiles: { _, validate in try validate() }, reserve: { _, _, before, after in
            try before(); sends += 1; try after(); return reply
        })
        let save: (ModelContext) throws -> Void = { if commits { try $0.save() }; throw ObservationVideoReservationLifecycleTests.Simulated.save }
        if claim { service.claimSave = save } else { service.settlementSave = save }
        #expect(try await run(entry, seed: seed, owner: owner, service: service) == .unavailable)
        let saved = try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(sends == (claim ? 0 : 1))
        #expect(saved.work.phase == (claim ? (commits ? .running : .staged) : (commits ? .observed : .running)))
        if saved.work.phase != .staged { #expect(try await run(saved, seed: seed, owner: owner, service: service) == nil) }
    }

    @Test func retainedOwnerCoalescesAndDrainsThroughActualLeaseExit() async throws {
        let (seed, entry) = try await fixture.staged(); defer { seed.remove() }
        let key = key(entry), owner = Owner(), entered = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, scope: Owner.Scope?, released = false, drained = false
        let cloud = account(key) { released = true }
        let admitted = owner.start(key, account: cloud, isCurrent: { true }, operation: {
            scope = $0; await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
        }, didFinish: { #expect(released && !owner.isRunning) })
        #expect(admitted == .started)
        var iterator = entered.stream.makeAsyncIterator(); _ = await iterator.next()
        #expect(owner.start(key, account: cloud, isCurrent: { true }, operation: { _ in Issue.record("Duplicate") }, didFinish: {}) == .coalesced)
        let changed = Owner.Key(snapshot: entry, session: key.session, generation: 2, container: key.container)
        #expect(owner.start(changed, account: cloud, isCurrent: { true }, operation: { _ in }, didFinish: {}) == .unavailable)
        owner.cancel()
        #expect(scope?.mayDispatch() == false && scope?.maySettleKnownReceipt() == true)
        owner.invalidate()
        #expect(scope?.maySettleKnownReceipt() == false)
        let first = Task { await owner.invalidateAndAwait(); drained = true }
        let second = Task { await owner.invalidateAndAwait() }
        await Task.yield()
        #expect(owner.isRunning && !released && !drained)
        #expect(owner.start(key, account: cloud, isCurrent: { true }, operation: { _ in }, didFinish: {}) == .unavailable)
        try #require(release).resume(); await first.value; await second.value
        #expect(released && drained && !owner.isRunning && scope?.maySettleKnownReceipt() == false)
    }

    @Test(arguments: ["normal", "offline", "container", "account"])
    func queueRetainsTaskAndSuppressesStaleCompletion(_ boundary: String) async throws {
        let (seed, entry) = try await fixture.staged(); defer { seed.remove() }
        let key = key(entry), proof = try seed.proof, reply = try fixture.reply(entry)
        let queue = OfflineQueueManager.shared, oldContext = queue.modelContext, oldOnline = queue.isOnline
        #expect(!queue.videoReservationOwner.isRunning)
        queue.modelContext = ModelContext(seed.container); queue.isOnline = true
        defer { queue.modelContext = oldContext; queue.isOnline = oldOnline }
        let exited = AsyncStream<Void>.makeStream(); defer { exited.continuation.finish() }
        var released = false, current = true, callbacks = 0
        let cloud = account(key) { released = true; exited.continuation.yield(()) }
        let service = Service(verifyFiles: { _, validate in try validate() }, reserve: { _, _, before, after in
            try before()
            if boundary == "offline" { queue.isOnline = false; queue.videoReservationOwner.cancel() }
            if boundary == "container" { queue.modelContext = nil }
            if boundary == "account" { current = false }
            try after(); return reply
        })
        let valid: @MainActor @Sendable (AuthTransitionSession, UInt64) -> Bool = { current && $0 == key.session && $1 == key.generation }
        let admitted = queue.requestVideoSourceReservation(key, proof: proof, account: cloud, service: service,
            isCurrentAccount: valid, didComplete: {
                #expect(released && !queue.videoReservationOwner.isRunning); callbacks += 1
            })
        #expect(admitted == .started)
        #expect(queue.requestVideoSourceReservation(key, proof: proof, account: cloud, service: service,
            isCurrentAccount: valid, didComplete: { Issue.record("Coalesced callback") }) == .coalesced)
        var iterator = exited.stream.makeAsyncIterator(); _ = await iterator.next()
        await queue.videoReservationOwner.invalidateAndAwait()
        #expect(released && !queue.videoReservationOwner.isRunning)
        #expect(callbacks == (["normal", "offline"].contains(boundary) ? 1 : 0))
        let saved = try Store.read(proof: proof, container: seed.container, isCurrent: { true })
        #expect(saved.work.phase == (["normal", "offline"].contains(boundary) ? .observed : .running))
    }

    @Test func queueBarriersCoverVideoWithoutSchedulerAdmission() throws {
        let root = "apps/ios/Merian/Core/Data/OfflineSync/"
        for path in ["Services/OfflineQueueManager+ReanalysisExecution.swift", "Services/BackgroundTransfer/OfflineQueueManager+BackgroundAccountWork.swift"] {
            let source = try DatabaseActorTestSupport.loadRepositorySource(at: root + path)
            let invalidate = try #require(source.range(of: "videoReservationOwner.invalidate()"))
            let drain = try #require(source.range(of: "await videoReservationOwner.invalidateAndAwait()"))
            #expect(invalidate.lowerBound < drain.lowerBound)
        }
        let manager = try DatabaseActorTestSupport.loadRepositorySource(at: root + "OfflineQueueManager.swift")
        #expect(manager.components(separatedBy: "self.videoReservationOwner.cancel()").count == 3)
        let scheduler = try DatabaseActorTestSupport.loadRepositorySource(at: root + "OfflineJobScheduler.swift")
        #expect(!scheduler.contains("videoReservationOwner"))
    }
}
