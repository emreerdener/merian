import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoUploadDeliveryTests {
    typealias Store = ObservationVideoUploadLifecycleStore
    typealias Owner = ObservationVideoUploadOwner
    typealias Service = ObservationVideoUploadService
    let fixture = ObservationVideoUploadLifecycleTests()
    func key(_ entry: Store.Snapshot) -> Owner.Key {
        .init(snapshot: entry, session: .init(userID: entry.work.staged.reservation.preparation.identity.ownerID, isAnonymous: false),
            generation: 1, container: entry.containerID)
    }
    func account(_ key: Owner.Key, finish: @escaping () -> Void = {}) -> ObservationHistoryCloudClient {
        .init(begin: { owner in
            #expect(owner == key.session.userID); return .init(id: UUID(), session: key.session)
        }, isCurrent: { $0.session == key.session }, finish: { _ in finish() }, fetch: { _ in
            Issue.record("Upload must not fetch history"); throw MerianError.invalidResponse
        })
    }
    func prepare(_ seed: ObservationVideoDurabilityTests.Seed) -> Service {
        Service.live(files: ObservationReanalysisFileStore(documents: seed.root),
            transport: .init(baseURL: "https://example.invalid", dispatcher: AuthenticatedTransportDispatcher(sessionTransport: PinnedNetworkTransport())))
    }
    func run(_ entry: Store.Snapshot, seed: ObservationVideoDurabilityTests.Seed, owner: Owner, service: Service,
             current: @escaping @MainActor @Sendable () -> Bool = { true },
             dispatch: @escaping @MainActor @Sendable () -> Bool = { true }) async throws -> Service.Outcome? {
        let key = key(entry), proof = try seed.proof
        var released = false
        let cloud = account(key) { released = true }
        return await withCheckedContinuation { continuation in
            var outcome: Service.Outcome?
            let admission = owner.start(key, account: cloud, isCurrent: current, permitsDispatch: dispatch, operation: {
                outcome = await service.run(entry, proof: proof, container: seed.container, scope: $0)
            }, didFinish: { #expect(released && !owner.isRunning); continuation.resume(returning: outcome) })
            if admission != .started { continuation.resume(returning: nil) }
        }
    }
    @Test(arguments: [false, true])
    func uploadsOriginalSavedCohortInOrderAndRetainsFiles(audio: Bool) async throws {
        let (seed, entry) = try await fixture.staged(audio: audio); defer { seed.remove() }
        let bytes = try seed.preparation.files.map { try Data(contentsOf: seed.root.appendingPathComponent($0.path)) }
        var sent: [UUID] = []
        let service = Service(prepare: prepare(seed).prepare, upload: { wire, owner, previous, before, after in
            try before()
            #expect(wire.candidate == entry.work.staged.reservation.request && owner == seed.source.ownerID)
            let current = try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true })
            #expect(previous == current.work.receipt)
            sent.append(wire.mediaID)
            try after(); return try fixture.receipt(current)
        })
        #expect(try await run(entry, seed: seed, owner: Owner(), service: service) == .ready)
        #expect(sent == entry.work.staged.request.inventory.items.map { $0.artifact.mediaID })
        #expect(try seed.preparation.files.map { try Data(contentsOf: seed.root.appendingPathComponent($0.path)) } == bytes)
        let saved = try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(saved.work.receipt?.state == .ready && saved.work.attempts.count == sent.count)
        #expect(try await run(saved, seed: seed, owner: Owner(), service: service) == nil)
    }
    @Test(arguments: ["unknown", "cancel", "account", "dispatch", "erasure"])
    func transportBoundaryNeverRearmsUncertainWork(_ boundary: String) async throws {
        let (seed, entry) = try await fixture.staged(); defer { seed.remove() }
        let owner = Owner(); var current = true, dispatch = true, sends = 0
        let service = Service(prepare: prepare(seed).prepare, upload: { _, _, _, before, after in
            try before(); sends += 1
            let running = try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true })
            let receipt = try fixture.receipt(running)
            if boundary == "unknown" { throw MerianError.invalidResponse }
            if boundary == "cancel" { owner.cancel() }
            if boundary == "account" { current = false }
            if boundary == "dispatch" { dispatch = false }
            if boundary == "erasure" {
                let context = ModelContext(seed.container)
                try ObservationReanalysisErasureReceipt(parentID: seed.source.observationID, childID: seed.preparation.identity.analysisID).record(in: context)
                try context.save()
            }
            try after(); return receipt
        })
        _ = try await run(entry, seed: seed, owner: owner, service: service, current: { current }, dispatch: { dispatch })
        #expect(sends == 1)
        if boundary != "erasure" {
            let saved = try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true })
            #expect(saved.work.attempts.last?.phase == (boundary == "unknown" ? .unknown : (boundary == "account" ? .running : .observed)))
            if ["unknown", "account"].contains(boundary) { #expect(try await run(saved, seed: seed, owner: Owner(), service: service) == nil) }
        }
    }
    @Test(arguments: ["missing", "damage", "cancel", "account", "dispatch"])
    func stalePreparationCannotSend(_ boundary: String) async throws {
        let (seed, entry) = try await fixture.staged(); defer { seed.remove() }
        let owner = Owner(); var current = true, dispatch = true
        if boundary == "missing" { try FileManager.default.removeItem(at: seed.root.appendingPathComponent(seed.preparation.files[0].path)) }
        if boundary == "damage" { try Data([1, 2, 3]).write(to: seed.root.appendingPathComponent(seed.preparation.files[0].path)) }
        let live = prepare(seed)
        let service = Service(prepare: { work, media, validate in
            let wire = try await live.prepare(work, media, validate)
            if boundary == "cancel" { owner.cancel() }
            if boundary == "account" { current = false }
            if boundary == "dispatch" { dispatch = false }
            return wire
        }, upload: { _, _, _, _, _ in Issue.record("Stale preparation dispatched"); throw MerianError.invalidResponse })
        _ = try await run(entry, seed: seed, owner: owner, service: service, current: { current }, dispatch: { dispatch })
        let saved = try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(saved.work.attempts.last?.phase == (["missing", "damage"].contains(boundary) ? .unknown : .running))
    }
    @Test(arguments: [false, true], [false, true])
    func uncertainSaveCannotFallThroughToAnotherUpload(claim: Bool, commits: Bool) async throws {
        let (seed, entry) = try await fixture.staged(); defer { seed.remove() }
        var sends = 0
        var service = Service(prepare: prepare(seed).prepare, upload: { _, _, _, before, after in
            try before(); sends += 1
            let current = try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true })
            try after(); return try fixture.receipt(current)
        })
        let save: (ModelContext) throws -> Void = { if commits { try $0.save() }; throw ObservationVideoUploadLifecycleTests.Simulated.save }
        if claim { service.claimSave = save } else { service.settlementSave = save }
        #expect(try await run(entry, seed: seed, owner: Owner(), service: service) == .unavailable)
        let saved = try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(sends == (claim ? 0 : 1))
        #expect(saved.work.attempts.last?.phase == (claim ? (commits ? .running : nil) : (commits ? .observed : .running)))
    }
    @Test func ownerCoalescesAndDrainsThroughAccountExit() async throws {
        let (seed, entry) = try await fixture.staged(); defer { seed.remove() }
        let key = key(entry), owner = Owner(), entered = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, scope: Owner.Scope?, released = false, drained = false
        let cloud = account(key) { released = true }
        let admission = owner.start(key, account: cloud, isCurrent: { true }, operation: {
            scope = $0; await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
        }, didFinish: { #expect(released && !owner.isRunning) })
        #expect(admission == .started)
        var iterator = entered.stream.makeAsyncIterator(); _ = await iterator.next()
        #expect(owner.start(key, account: cloud, isCurrent: { true }, operation: { _ in Issue.record("Duplicate") }, didFinish: {}) == .coalesced)
        owner.cancel(); #expect(scope?.mayDispatch() == false && scope?.maySettleKnownReceipt() == true)
        owner.invalidate(); #expect(scope?.maySettleKnownReceipt() == false)
        let first = Task { await owner.invalidateAndAwait(); drained = true }
        let second = Task { await owner.invalidateAndAwait() }
        await Task.yield(); #expect(owner.isRunning && !released && !drained)
        #expect(owner.start(key, account: cloud, isCurrent: { true }, operation: { _ in }, didFinish: {}) == .unavailable)
        try #require(release).resume(); await first.value; await second.value
        #expect(released && drained && !owner.isRunning)
    }
    @Test(arguments: ["normal", "offline", "container", "account"])
    func queueRetainsTaskAndSuppressesStaleCompletion(_ boundary: String) async throws {
        let (seed, entry) = try await fixture.staged(); defer { seed.remove() }
        let key = key(entry), proof = try seed.proof
        let queue = OfflineQueueManager.shared, oldContext = queue.modelContext, oldOnline = queue.isOnline
        #expect(!queue.videoUploadOwner.isRunning)
        queue.modelContext = ModelContext(seed.container); queue.isOnline = true
        defer { queue.modelContext = oldContext; queue.isOnline = oldOnline }
        let exited = AsyncStream<Void>.makeStream(); defer { exited.continuation.finish() }
        var released = false, current = true, callbacks = 0
        let cloud = account(key) { released = true; exited.continuation.yield(()) }
        let service = Service(prepare: prepare(seed).prepare, upload: { _, _, _, before, after in
            try before()
            let running = try Store.read(proof: proof, container: seed.container, isCurrent: { true })
            let reply = try fixture.receipt(running, all: true)
            if boundary == "offline" { queue.isOnline = false; queue.videoUploadOwner.cancel() }
            if boundary == "container" { queue.modelContext = nil }
            if boundary == "account" { current = false }
            try after(); return reply
        })
        let valid: @MainActor @Sendable (AuthTransitionSession, UInt64) -> Bool = { current && $0 == key.session && $1 == key.generation }
        let admitted = queue.requestVideoEvidenceUpload(key, proof: proof, account: cloud, service: service,
            isCurrentAccount: valid, didComplete: {
                #expect(released && !queue.videoUploadOwner.isRunning); callbacks += 1
            })
        #expect(admitted == .started)
        #expect(queue.requestVideoEvidenceUpload(key, proof: proof, account: cloud, service: service,
            isCurrentAccount: valid, didComplete: { Issue.record("Coalesced callback") }) == .coalesced)
        var iterator = exited.stream.makeAsyncIterator(); _ = await iterator.next()
        await queue.videoUploadOwner.invalidateAndAwait()
        #expect(released && !queue.videoUploadOwner.isRunning)
        #expect(callbacks == (["normal", "offline"].contains(boundary) ? 1 : 0))
        let saved = try Store.read(proof: proof, container: seed.container, isCurrent: { true })
        #expect(saved.work.attempts.last?.phase == (["normal", "offline"].contains(boundary) ? .observed : .running))
    }

    @Test func queueBarriersAndOrdinaryAccessStayClosed() throws {
        let root = "apps/ios/Merian/Core/Data/OfflineSync/"
        for path in ["Services/OfflineQueueManager+ReanalysisExecution.swift", "Services/BackgroundTransfer/OfflineQueueManager+BackgroundAccountWork.swift"] {
            let source = try DatabaseActorTestSupport.loadRepositorySource(at: root + path)
            #expect(source.contains("videoUploadOwner.invalidate()") && source.contains("await videoUploadOwner.invalidateAndAwait()"))
        }
        let manager = try DatabaseActorTestSupport.loadRepositorySource(at: root + "OfflineQueueManager.swift")
        #expect(manager.components(separatedBy: "videoUploadOwner.cancel()").count == 3)
    }
}
