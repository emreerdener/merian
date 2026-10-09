import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAudioSourceSubmissionTests {
    typealias Store = ObservationSourceReservationStore
    typealias Service = ObservationAudioSourceSubmissionService
    typealias Seed = ObservationAudioPreparationTests.Seed
    let fixture = ObservationAudioSourceStoreTests()

    func state(_ name: String, seed: Seed) throws -> Store.Snapshot {
        let entry = try fixture.stage(seed)
        if name == "staged" { return entry }
        let claim = try Store.claim(entry, admission: .initial, proof: .audio(seed.proof), container: seed.container, isCurrent: { true })
        if name == "running" { return claim.snapshot }
        if name == "unknown" || name == "conflict" {
            return try Store.hold(claim, proof: .audio(seed.proof), container: seed.container, isCurrent: { true },
                conflict: name == "conflict" ? .init(request: entry.work.request, ownerID: entry.identity.ownerID) : nil)
        }
        return try Store.settle(claim, reply: ObservationSourceStoreTests().reply(entry, state: name),
            proof: .audio(seed.proof), container: seed.container, isCurrent: { true })
    }

    func key(_ entry: Store.Snapshot) -> ObservationSourceReservationOwner.Key {
        .init(snapshot: entry, admission: Service.admission(for: entry) ?? .explicitRecovery,
            session: .init(userID: entry.identity.ownerID, isAnonymous: false), generation: 1, container: entry.containerID)
    }

    func run(_ entry: Store.Snapshot, seed: Seed, owner: ObservationSourceReservationOwner, service: Service,
             current: @escaping @MainActor @Sendable () -> Bool = { true }) async throws -> ObservationAudioExecutionStore.Snapshot? {
        let key = key(entry), proof = try seed.proof
        var leaseExited = false
        let cloud = ObservationSourceReservationOwnerTests().account(key) { leaseExited = true }
        return await withCheckedContinuation { continuation in
            var result: ObservationAudioExecutionStore.Snapshot?
            let admission = owner.start(key, account: cloud, isCurrent: current, operation: { scope in
                result = await service.run(entry, admission: key.admission, proof: proof, container: seed.container, scope: scope)
            }, didFinish: {
                #expect(leaseExited && !owner.isRunning)
                continuation.resume(returning: result)
            })
            if admission != .started { continuation.resume(returning: nil) }
        }
    }

    @Test(arguments: ["staged", "running", "unknown", "reserved", "held", "unavailable", "conflict"])
    func explicitStatesRetainCandidateAndReservedSkipsHTTP(_ state: String) async throws {
        let seed = try await fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let entry = try self.state(state, seed: seed), owner = ObservationSourceReservationOwner()
        var sends = 0, consents = 0
        let response = try ObservationSourceStoreTests().reply(entry, state: "reserved")
        let service = Service(source: .init(reserve: { request, _, before, after in
            try before(); sends += 1
            #expect(request == entry.work.request)
            let saved = try Store.read(entry.identity, container: seed.container, isCurrent: { true })
            #expect(saved.work.state == .running && saved.work.request.input == entry.work.request.input)
            try after(); return response
        }), authorize: { owner, validate in
            try validate(); #expect(owner == entry.identity.ownerID); consents += 1
            return fixture.fixture.authorization
        })
        let bound = try await run(entry, seed: seed, owner: owner, service: service)
        #expect(sends == (state == "reserved" || state == "conflict" ? 0 : 1))
        #expect(consents == (state == "conflict" ? 0 : 1))
        if state == "conflict" { #expect(bound == nil) } else {
            #expect(bound?.work.intent.request.body == entry.work.request.input)
            #expect(bound?.work.state == .idle && bound?.work.consumedAttempt == nil)
        }
    }

    @Test(arguments: ["held", "unavailable", "unknown", "cancel"])
    func nonReservedOrCancelledKnownReplyNeverBinds(_ responseState: String) async throws {
        let seed = try await fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let entry = try state("staged", seed: seed), owner = ObservationSourceReservationOwner()
        let response = try ObservationSourceStoreTests().reply(entry, state: responseState == "cancel" || responseState == "unknown" ? "reserved" : responseState)
        let service = Service(source: .init(reserve: { _, _, before, after in
            try before()
            if responseState == "unknown" { throw URLError(.timedOut) }
            if responseState == "cancel" { owner.cancel() }
            try after(); return response
        }), authorize: { _, _ in Issue.record("Held source requested consent"); throw MerianError.invalidResponse })
        #expect(try await run(entry, seed: seed, owner: owner, service: service) == nil)
        let saved = try Store.read(entry.identity, container: seed.container, isCurrent: { true })
        #expect(saved.work.request == entry.work.request)
        #expect(saved.work.state == (responseState == "unknown" ? .unknown : .observed))
        if responseState == "cancel" { #expect(saved.work.reply?.state == .reserved) }
    }

    @Test(arguments: [false, true])
    func throwingBindingSaveNeverReturnsHandoff(committed: Bool) async throws {
        let seed = try await fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let entry = try state("reserved", seed: seed), owner = ObservationSourceReservationOwner()
        let service = Service(source: .init(reserve: { _, _, _, _ in Issue.record("Reserved replay sent HTTP"); throw MerianError.invalidResponse }),
            authorize: { _, validate in try validate(); return fixture.fixture.authorization }, bindingSave: {
                if committed { try $0.save() }; throw CocoaError(.fileWriteUnknown)
            })
        #expect(try await run(entry, seed: seed, owner: owner, service: service) == nil)
        if committed {
            let saved = try ObservationAudioExecutionStore.read(seed.proof, container: seed.container, isCurrent: { true })
            #expect(saved.work.state == .idle && saved.work.intent.request.body == entry.work.request.input)
        } else { #expect(try Store.read(entry.identity, container: seed.container, isCurrent: { true }) == entry) }
    }

    @Test(arguments: ["cancel", "account", "delete", "cas"])
    func authorityChangeDuringConsentCannotBind(_ change: String) async throws {
        let seed = try await fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let entry = try state("reserved", seed: seed), owner = ObservationSourceReservationOwner()
        var current = true
        let service = Service(source: .init(reserve: { _, _, _, _ in Issue.record("Reserved replay sent HTTP"); throw MerianError.invalidResponse }),
            authorize: { _, validate in
                try validate()
                if change == "cancel" { owner.cancel() }
                if change == "account" { current = false }
                if change == "delete" || change == "cas" {
                    let context = ModelContext(seed.container)
                    if change == "delete" { context.delete(try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)) } else {
                        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
                        let changed = try ObservationSourceReservationWork(preparation: entry.work.preparation, request: entry.work.request,
                            state: .observed, generation: entry.work.generation + 1, reply: entry.work.reply)
                        job.metadataJSON = try #require(String(bytes: changed.storedData(), encoding: .utf8))
                    }
                    try context.save()
                }
                return fixture.fixture.authorization
            })
        #expect(try await run(entry, seed: seed, owner: owner, service: service, current: { current }) == nil)
        #expect(throws: (any Error).self) { try ObservationAudioExecutionStore.read(seed.proof, container: seed.container, isCurrent: { true }) }
    }

    @Test(arguments: ["normal", "cancel", "save", "offline", "auth", "container"])
    func queueHandoffWaitsForSourceLeaseAndRetainsCleanup(_ boundary: String) async throws {
        let seed = try await fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let entry = try state("staged", seed: seed), key = key(entry), proof = try seed.proof
        let queue = OfflineQueueManager.shared, oldContext = queue.modelContext, oldOnline = queue.isOnline
        #expect(!queue.sourceReservationOwner.isRunning && !queue.audioExecutionOwner.isRunning)
        queue.modelContext = ModelContext(seed.container); queue.isOnline = true
        defer { queue.modelContext = oldContext; queue.isOnline = oldOnline }
        let exited = AsyncStream<Int>.makeStream(); defer { exited.continuation.finish() }
        var begins = 0, finishes = 0, callbacks = 0
        let cloud = ObservationHistoryCloudClient(begin: { _ in
            begins += 1
            if begins == 2 { #expect(finishes == 1 && !queue.sourceReservationOwner.isRunning) }
            return .init(id: UUID(), session: key.session)
        }, isCurrent: { $0.session == key.session }, finish: { _ in
            finishes += 1
            if finishes == 1 {
                if boundary == "offline" { queue.isOnline = false }
                if boundary == "auth" { queue.audioExecutionOwner.invalidate() }
                if boundary == "container" { queue.modelContext = nil }
            }
            exited.continuation.yield(finishes)
        }, fetch: { _ in Issue.record("Unexpected history fetch"); throw MerianError.invalidResponse })
        let response = try ObservationSourceStoreTests().reply(entry, state: "reserved")
        let source = Service(source: .init(reserve: { _, _, before, after in
            try before(); #expect(begins == 1 && finishes == 0)
            if boundary == "cancel" { queue.sourceReservationOwner.cancel() }
            try after(); return response
        }), authorize: { _, validate in try validate(); return fixture.fixture.authorization }, bindingSave: {
            try $0.save()
            if boundary == "save" { throw CocoaError(.fileWriteUnknown) }
        })
        let audio = try ObservationAudioExecutionServiceTests.Boundary(seed)
        audio.hook = { _ in #expect(begins == 2 && finishes == 1 && !queue.sourceReservationOwner.isRunning) }
        let erasure = ObservationReanalysisErasureOwner(files: .init(documents: seed.root))
        let admitted = queue.requestAudioSourceSubmission(key, proof: proof, account: cloud, source: source,
            execution: audio.service, erasure: erasure, isCurrentAccount: { $0 == key.session && $1 == key.generation },
            didChange: { callbacks += 1 })
        #expect(admitted == .started)
        #expect(queue.requestAudioSourceSubmission(key, proof: proof, account: cloud, source: source,
            execution: audio.service, erasure: erasure, isCurrentAccount: { $0 == key.session && $1 == key.generation },
            didChange: { Issue.record("Coalesced caller callback") }) == .coalesced)
        var iterator = exited.stream.makeAsyncIterator()
        #expect(await iterator.next() == 1)
        if boundary == "normal" { #expect(await iterator.next() == 2) }
        await queue.sourceReservationOwner.invalidateAndAwait()
        await queue.audioExecutionOwner.invalidateAndAwait()
        #expect(begins == (boundary == "normal" ? 2 : 1) && finishes == begins)
        #expect(callbacks == (boundary == "normal" ? 2 : boundary == "container" ? 0 : 1))
        if boundary == "normal" {
            #expect(audio.events == ["read", "upload", "authorize", "analyze", "outcome"])
            let context = ModelContext(seed.container)
            let receipt = try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(entry.identity.analysisID))
            #expect(receipt?.status == .complete && !FileManager.default.fileExists(atPath: seed.file.path))
        } else { #expect(audio.events.isEmpty && FileManager.default.fileExists(atPath: seed.file.path)) }
    }

}
