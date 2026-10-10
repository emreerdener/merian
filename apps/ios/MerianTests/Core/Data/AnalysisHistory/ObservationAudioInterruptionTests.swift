import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAudioInterruptionTests {
    typealias Store = ObservationAudioExecutionStore
    typealias Seed = ObservationAudioPreparationTests.Seed
    let fixture = ObservationAudioExecutionStoreTests()

    func owned(_ saved: Store.Snapshot, seed: Seed,
               body: @escaping @MainActor (ObservationAudioExecutionOwner.Scope, ObservationAudioExecutionOwner) async throws -> Void) async throws {
        let owner = ObservationAudioExecutionOwner(), support = ObservationAudioExecutionOwnerTests()
        let key = ObservationAudioExecutionOwner.Key(snapshot: saved, session: .init(userID: seed.source.ownerID, isAnonymous: false),
            generation: 1, container: ObjectIdentifier(seed.container))
        let exit = AsyncStream<Void>.makeStream(); defer { exit.continuation.finish() }
        var result: Result<Void, Error>?
        let admission = owner.start(key, account: support.account(key), isCurrent: { true }, operation: { scope in
            do { try await body(scope, owner); result = .success(()) } catch { result = .failure(error) }
        }, didFinish: { exit.continuation.yield(()) })
        #expect(admission == .started)
        var iterator = exit.stream.makeAsyncIterator(); _ = await iterator.next()
        try #require(result).get()
    }
    func running(_ seed: Seed, consumed: Bool) throws -> Store.Snapshot {
        let claim = try Store.claim(fixture.bind(seed), purpose: .initial, proof: seed.proof, container: seed.container, isCurrent: { true })
        return consumed ? try Store.consume(claim, proof: seed.proof, container: seed.container, isCurrent: { true }).snapshot : claim.snapshot
    }

    @Test(arguments: [false, true])
    func cancelledRetainedTaskPersistsExactHoldAndReplay(consumed: Bool) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try running(seed, consumed: consumed), proof = try seed.proof
        var oldScope: ObservationAudioExecutionOwner.Scope?
        try await owned(saved, seed: seed) { scope, owner in
            oldScope = scope; owner.cancel()
            #expect(Task.isCancelled && !scope.mayDispatch() && scope.maySettleKnownReceipt())
            #expect(try Store.readForInterruption(proof, container: seed.container, scope: scope) == saved)
            let held = try Store.interruptRunning(saved, proof: proof, container: seed.container, scope: scope)
            #expect(held.work.state == .held && held.work.attempt == saved.work.attempt)
            #expect(held.work.consumedAttempt == saved.work.consumedAttempt && held.work.intent == saved.work.intent)
            #expect(try Store.interruptRunning(saved, proof: proof, container: seed.container, scope: scope) == held)
        }
        let held = try Store.read(proof, container: seed.container, isCurrent: { true })
        let expiredScope = try #require(oldScope)
        #expect(throws: (any Error).self) { try Store.interruptRunning(saved, proof: proof, container: seed.container, scope: expiredScope) }
        if consumed {
            let recovery = try Store.claim(held, purpose: .recovery, proof: proof, container: seed.container, isCurrent: { true })
            #expect(throws: (any Error).self) { try Store.consume(recovery, proof: proof, container: seed.container, isCurrent: { true }) }
        } else {
            #expect(throws: (any Error).self) { try Store.claim(held, purpose: .initial, proof: proof, container: seed.container, isCurrent: { true }) }
            let denied = IdentificationDispatchAuthorization(recipient: .gemini, validate: { throw MerianError.aiConsentRequired })
            #expect(throws: (any Error).self) {
                try Store.resumeUndispatched(held, proof: proof, authorization: denied, container: seed.container, isCurrent: { true })
            }
        }
    }

    @Test(arguments: [false, true])
    func ambiguousConsumptionReadsOriginalMarkerWithoutPermission(committed: Bool) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let initial = try fixture.bind(seed), proof = try seed.proof
        try await owned(initial, seed: seed) { scope, owner in
            let claim = try Store.claim(initial, purpose: .initial, proof: proof, container: seed.container, isCurrent: scope.mayDispatch)
            #expect(throws: (any Error).self) {
                try Store.consume(claim, proof: proof, container: seed.container, isCurrent: scope.mayDispatch, save: {
                    if committed { try $0.save() }; throw CocoaError(.fileWriteUnknown)
                })
            }
            owner.cancel()
            let saved = try Store.readForInterruption(proof, container: seed.container, scope: scope)
            #expect(saved.work.consumedAttempt == (committed ? 1 : nil))
            let held = try Store.interruptRunning(saved, proof: proof, container: seed.container, scope: scope)
            #expect(held.work.intent.request.body == initial.work.intent.request.body && held.work.consumedAttempt == saved.work.consumedAttempt)
        }
    }

    @Test(arguments: [false, true])
    func holdSaveAmbiguityHasExactReplay(committed: Bool) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try running(seed, consumed: true), proof = try seed.proof
        try await owned(saved, seed: seed) { scope, owner in
            owner.cancel()
            #expect(throws: (any Error).self) {
                try Store.interruptRunning(saved, proof: proof, container: seed.container, scope: scope, save: {
                    if committed { try $0.save() }; throw CocoaError(.fileWriteUnknown)
                })
            }
            let restored = try Store.readForInterruption(proof, container: seed.container, scope: scope)
            #expect(restored.work.state == (committed ? .held : .running))
            let held = try Store.interruptRunning(saved, proof: proof, container: seed.container, scope: scope)
            #expect(held.work.state == .held && held.work.consumedAttempt == 1 && held.work.attempt == 1)
        }
    }

    @Test func laterGenerationCannotBeInterruptedOrAdoptedByOldScope() async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let first = try running(seed, consumed: true), proof = try seed.proof
        try await owned(first, seed: seed) { scope, _ in
            let held = try Store.interruptRunning(first, proof: proof, container: seed.container, scope: scope)
            let second = try Store.claim(held, purpose: .recovery, proof: proof, container: seed.container, isCurrent: { true })
            #expect(throws: (any Error).self) { try Store.interruptRunning(first, proof: proof, container: seed.container, scope: scope) }
            try Store.hold(second, proof: proof, container: seed.container, isCurrent: { true })
            let third = try Store.claim(Store.read(proof, container: seed.container, isCurrent: { true }), purpose: .recovery,
                proof: proof, container: seed.container, isCurrent: { true })
            #expect(!scope.permitsInterruption(third.snapshot, container: ObjectIdentifier(seed.container)))
            #expect(throws: (any Error).self) { try Store.readForInterruption(proof, container: seed.container, scope: scope) }
            #expect(throws: (any Error).self) { try Store.interruptRunning(third.snapshot, proof: proof, container: seed.container, scope: scope) }
        }
    }

    @Test(arguments: ["auth", "container", "source", "parent", "erasure", "metadata"])
    func invalidatedAuthorityCannotHold(reason: String) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try running(seed, consumed: true), proof = try seed.proof
        try await owned(saved, seed: seed) { scope, owner in
            let context = ModelContext(seed.container)
            if reason == "auth" { owner.invalidate() }
            if reason == "source" {
                let id = seed.source.analysisID.uuidString.lowercased()
                let row = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == id })).first)
                let replacement = try LocalAnalysisRecord(analysisID: seed.source.analysisID, observationID: row.observationID,
                    ownerAccountID: seed.source.ownerID, completedAt: row.completedAt, snapshotVersion: row.snapshotVersion,
                    resultSnapshotData: Data("{}".utf8))
                context.delete(row); try context.save(); context.insert(replacement)
            }
            if reason == "parent" {
                let row = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first); context.delete(row)
            }
            if reason == "erasure" {
                try ObservationReanalysisErasureReceipt(parentID: seed.source.observationID, childID: seed.preparation.identity.analysisID).record(in: context)
            }
            if reason == "metadata" {
                let savedJob = try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: seed.preparation.identity.analysisID.uuidString.lowercased()))
                let row = try #require(savedJob)
                row.metadataJSON = "{}"
            }
            try context.save()
            if reason == "container" {
                let other = try ObservationHistorySyncTests().container()
                #expect(throws: (any Error).self) { try Store.interruptRunning(saved, proof: proof, container: other, scope: scope) }
            } else {
                #expect(throws: (any Error).self) { try Store.readForInterruption(proof, container: seed.container, scope: scope) }
                #expect(throws: (any Error).self) { try Store.interruptRunning(saved, proof: proof, container: seed.container, scope: scope) }
            }
        }
    }
}
