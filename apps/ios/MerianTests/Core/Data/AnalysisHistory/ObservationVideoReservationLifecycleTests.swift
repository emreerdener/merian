import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoReservationLifecycleTests {
    typealias Store = ObservationVideoSourceReservationStore
    typealias Work = ObservationVideoSourceReservationWork
    typealias Seed = ObservationVideoDurabilityTests.Seed
    enum Simulated: Error { case save }

    func staged() async throws -> (Seed, Store.Snapshot) {
        let fixture = ObservationVideoDurabilityTests(), seed = try await fixture.seed()
        do {
            _ = try await fixture.producer(seed).prepare(seed.preparation, source: seed.source, cohort: seed.cohort,
                container: seed.container, isCurrent: { true })
            let snapshot = try Store.stage(.init(video: seed.preparation.request), proof: seed.proof,
                container: seed.container, isCurrent: { true })
            return (seed, snapshot)
        } catch { seed.remove(); throw error }
    }

    func reply(_ snapshot: Store.Snapshot, state: String = "reserved", owner: UUID? = nil) throws -> ObservationVideoSourceReservationReply {
        var row = snapshot.work.request.identity.fields
        let owner = owner ?? snapshot.work.preparation.identity.ownerID
        row["owner_id"] = owner.uuidString.lowercased(); row["state"] = state
        if state == "held" { row["reason"] = "source_occupied" }
        return try .init(data: JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
            identity: snapshot.work.request.identity, ownerID: owner)
    }

    @Test func claimIsSavedOnceAndRestartNeverRearms() async throws {
        let (seed, staged) = try await staged(); defer { seed.remove() }
        let originalBytes = Data(staged.metadata.utf8), attempt = UUID()
        #expect(try Work.decode(originalBytes).storedData() == originalBytes)
        let claim = try Store.claim(staged, proof: seed.proof, container: seed.container, isCurrent: { true }, attemptID: attempt)
        #expect(claim.snapshot.work.phase == .running && claim.snapshot.work.attemptID == attempt)
        try Store.validate(claim, proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Store.claim(staged, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
        let saved = try Store.read(proof: seed.proof, container: reopened, isCurrent: { true })
        #expect(saved.work == claim.snapshot.work && saved.work.request == staged.work.request)
        #expect(throws: (any Error).self) { try Store.claim(saved, proof: seed.proof, container: reopened, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try Store.validate(claim, proof: seed.proof, container: reopened, isCurrent: { true }) }
        #expect(try Store.stage(staged.work.request, proof: seed.proof, container: reopened, isCurrent: { true }).work == saved.work)
    }

    @Test(arguments: ["reserved", "held", "unavailable", "conflict"])
    func knownSettlementSurvivesCancellationWithoutAnotherClaim(state: String) async throws {
        let (seed, staged) = try await staged(); defer { seed.remove() }
        let claim = try Store.claim(staged, proof: seed.proof, container: seed.container, isCurrent: { true })
        let held = try Store.hold(claim, proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(held.work.phase == .unknown && held.work.attemptID == claim.snapshot.work.attemptID)
        #expect(throws: (any Error).self) { try Store.validate(claim, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try Store.claim(held, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        let settlement: ObservationVideoReservationSettlement = state == "conflict"
            ? .conflict(.init(request: staged.work.request, ownerID: seed.source.ownerID)) : .reply(try reply(staged, state: state))
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: (any Error).self) { try Store.validate(claim, proof: seed.proof, container: seed.container, isCurrent: { true }) }
            let settled = try Store.settle(claim, settlement: settlement, proof: seed.proof, container: seed.container, isCurrent: { true })
            #expect(try Store.settle(claim, settlement: settlement, proof: seed.proof, container: seed.container,
                isCurrent: { true }, save: { _ in Issue.record("Exact settlement replay attempted save") }) == settled)
            return settled
        }
        let settled = try await task.value
        #expect(settled.work.phase == (state == "conflict" ? .conflict : .observed))
        #expect(settled.work.attemptID == claim.snapshot.work.attemptID && settled.work.request == staged.work.request)
        #expect(try Work.decode(Data(settled.metadata.utf8)) == settled.work)
        #expect(throws: (any Error).self) { try Store.hold(claim, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try Store.claim(settled, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        let different: ObservationVideoReservationSettlement = state == "conflict" ? .reply(try reply(staged))
            : .conflict(.init(request: staged.work.request, ownerID: seed.source.ownerID))
        #expect(throws: (any Error).self) { try Store.settle(claim, settlement: different, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        let context = ModelContext(seed.container)
        let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        #expect(row.queueAttemptCount == 0 && row.queueNeedsAttention && !row.permitsOrdinaryInference)
        #expect(job.attemptCount == 0 && job.statusRaw == OfflineJobStatus.needsAttention.rawValue)
        #expect(throws: (any Error).self) { try ObservationVideoPreparationStore.discard(seed.proof, container: seed.container, isCurrent: { true }) }
    }

    @Test(arguments: [false, true])
    func uncertainClaimSaveNeverRestagesRunningWork(commits: Bool) async throws {
        let (seed, staged) = try await staged(); defer { seed.remove() }
        let attempt = UUID()
        #expect(throws: Simulated.save) { try Store.claim(staged, proof: seed.proof, container: seed.container,
            isCurrent: { true }, attemptID: attempt, save: { if commits { try $0.save() }; throw Simulated.save }) }
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
        let saved = try Store.read(proof: seed.proof, container: reopened, isCurrent: { true })
        #expect(saved.work.phase == (commits ? .running : .staged))
        #expect(saved.work.attemptID == (commits ? attempt : nil))
        if commits {
            #expect(throws: (any Error).self) { try Store.claim(saved, proof: seed.proof, container: reopened, isCurrent: { true }) }
        } else {
            #expect(try Store.claim(saved, proof: seed.proof, container: reopened, isCurrent: { true }, attemptID: attempt).snapshot.work.attemptID == attempt)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func uncertainSettlementSaveReplaysSameKnownAnswer(commits: Bool, conflict: Bool) async throws {
        let (seed, staged) = try await staged(); defer { seed.remove() }
        let claim = try Store.claim(staged, proof: seed.proof, container: seed.container, isCurrent: { true })
        let answer = try reply(staged)
        let settlement: ObservationVideoReservationSettlement = conflict
            ? .conflict(.init(request: staged.work.request, ownerID: seed.source.ownerID)) : .reply(answer)
        #expect(throws: Simulated.save) { try Store.settle(claim, settlement: settlement, proof: seed.proof, container: seed.container,
            isCurrent: { true }, save: { if commits { try $0.save() }; throw Simulated.save }) }
        let settled = try Store.settle(claim, settlement: settlement, proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(settled.work.reply?.data == (conflict ? nil : answer.data) && settled.work.attemptID == claim.snapshot.work.attemptID)
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
        #expect(try Store.read(proof: seed.proof, container: reopened, isCurrent: { true }).work == settled.work)
    }

    @Test(arguments: ["account", "owner", "erasure", "source", "attempt", "container", "metadata", "result"])
    func settlementCannotCrossCurrentScope(reason: String) async throws {
        let (seed, staged) = try await staged(); defer { seed.remove() }
        let claim = try Store.claim(staged, proof: seed.proof, container: seed.container, isCurrent: { true })
        let answer = try reply(staged, owner: reason == "owner" ? UUID() : nil)
        let context = ModelContext(seed.container)
        if reason == "source" { context.delete(try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)) }
        if reason == "erasure" { try ObservationReanalysisErasureReceipt(parentID: seed.source.observationID, childID: seed.preparation.identity.analysisID).record(in: context) }
        if reason == "attempt" {
            let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
            job.metadataJSON = String(data: try Work(preparation: seed.preparation, request: staged.work.request, phase: .running, attemptID: UUID()).storedData(), encoding: .utf8)
        }
        if reason == "metadata" {
            let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
            job.metadataJSON = String(data: try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: Data(claim.snapshot.metadata.utf8)), options: [.prettyPrinted]), encoding: .utf8)
        }
        if reason == "result" {
            context.insert(try LocalAnalysisRecord(analysisID: seed.preparation.identity.analysisID,
                observationID: seed.source.observationID.uuidString.lowercased(), ownerAccountID: seed.source.ownerID,
                completedAt: nil, snapshotVersion: 3, resultSnapshotData: Data("{}".utf8)))
        }
        try context.save()
        let container = reason == "container" ? try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false) : seed.container
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: (any Error).self) { try Store.settle(claim, settlement: .reply(answer), proof: seed.proof,
                container: container, isCurrent: { reason != "account" }) }
        }
        await task.value
    }

    @Test func lifecycleCodecIsClosedAndStagedBytesStayVersionOne() async throws {
        let (seed, staged) = try await staged(); defer { seed.remove() }
        let attempt = UUID()
        let observed = try Work(preparation: seed.preparation, request: staged.work.request,
            phase: .observed, attemptID: attempt, reply: reply(staged))
        #expect(try Work.decode(observed.storedData()) == observed)
        let valid = try #require(JSONSerialization.jsonObject(with: observed.storedData()) as? [String: Any])
        var maximumEnvelope = valid
        maximumEnvelope["staged_base64"] = Data(repeating: 32, count: Work.maximumStagedBytes).base64EncodedString()
        maximumEnvelope["reply_base64"] = Data(repeating: 32, count: ObservationVideoSourceReservationReply.maximumBytes).base64EncodedString()
        #expect(try JSONSerialization.data(withJSONObject: maximumEnvelope).count <= Work.maximumBytes)
        for key in ["version", "phase", "attempt_id", "reply_base64", "extra", "staged_base64"] {
            var altered = valid
            switch key {
            case "version": altered[key] = 1
            case "phase": altered[key] = "staged"
            case "attempt_id": altered[key] = NSNull()
            case "reply_base64": altered[key] = NSNull()
            case "staged_base64": altered[key] = staged.work.stagedData.base64EncodedString() + "\n"
            default: altered[key] = true
            }
            #expect(throws: (any Error).self) { try Work.decode(JSONSerialization.data(withJSONObject: altered)) }
        }
        #expect(throws: (any Error).self) { try Work(preparation: seed.preparation, request: staged.work.request, phase: .running) }
        #expect(throws: (any Error).self) { try Work(preparation: seed.preparation, request: staged.work.request, attemptID: attempt) }
        #expect(throws: (any Error).self) { try Work(preparation: seed.preparation, request: staged.work.request,
            phase: .unknown, attemptID: attempt, reply: reply(staged)) }
        #expect(try Work.decode(Data(staged.metadata.utf8)).storedData() == Data(staged.metadata.utf8))
    }

    @Test func formattedStagedMetadataIsRetainedExactlyInsideClaim() async throws {
        let (seed, staged) = try await staged(); defer { seed.remove() }
        let bytes = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: Data(staged.metadata.utf8)), options: [.prettyPrinted])
        let context = ModelContext(seed.container)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        job.metadataJSON = String(decoding: bytes, as: UTF8.self); try context.save()
        let saved = try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true })
        let claim = try Store.claim(saved, proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(claim.snapshot.work.stagedData == bytes)
        #expect(try Work.decode(Data(claim.snapshot.metadata.utf8)).stagedData == bytes)
    }

    @Test func cancellationCannotClaimOrHoldAndMixedSettlementsCannotMutate() async throws {
        let (seed, staged) = try await staged(); defer { seed.remove() }
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: (any Error).self) { try Store.claim(staged, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        }
        await cancelled.value
        #expect(try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true }) == staged)
        let claim = try Store.claim(staged, proof: seed.proof, container: seed.container, isCurrent: { true })
        let hold = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: (any Error).self) { try Store.hold(claim, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        }
        await hold.value
        #expect(try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true }) == claim.snapshot)
        let legacy = ObservationSourceReservationConflict(request: try ObservationSourceReservationTests.candidate(), ownerID: seed.source.ownerID)
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPersistence.transaction(seed.preparation.identity, container: seed.container, isCurrent: { true },
                save: { _ in Issue.record("Mixed settlement saved") }, settlingSourceConflict: legacy, settlingVideo: .reply(reply(staged))) { _ in
                    Issue.record("Mixed settlement reached transaction body")
                }
        }
    }
}
