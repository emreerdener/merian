import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoExecutionStoreTests {
    typealias Store = ObservationVideoExecutionStore
    typealias Work = ObservationVideoExecutionWork
    enum Simulated: Error { case save }
    var authorization: IdentificationDispatchAuthorization { .init(recipient: .gemini, validate: {}) }
    func ready(audio: Bool = true) async throws -> (ObservationVideoDurabilityTests.Seed, ObservationVideoUploadLifecycleStore.Snapshot) {
        let helper = ObservationVideoUploadLifecycleTests()
        let (seed, upload) = try await helper.staged(audio: audio)
        do {
            let claim = try ObservationVideoUploadLifecycleStore.claim(upload, proof: seed.proof, container: seed.container, isCurrent: { true })
            let receipt = try helper.receipt(claim, all: true)
            return (seed, try ObservationVideoUploadLifecycleStore.settle(claim, receipt: receipt, proof: seed.proof,
                container: seed.container, isCurrent: { true }))
        } catch { seed.remove(); throw error }
    }
    func stage(_ seed: ObservationVideoDurabilityTests.Seed, _ uploaded: ObservationVideoUploadLifecycleStore.Snapshot) throws -> Store.Snapshot {
        try Store.stage(uploaded, proof: seed.proof, authorization: authorization, container: seed.container, isCurrent: { true })
    }

    @Test(arguments: [false, true])
    func exactReadyHandoffReopensWithoutConsentReplayOrLegacyRouting(audio: Bool) async throws {
        let (seed, uploaded) = try await ready(audio: audio); defer { seed.remove() }
        let saved = try stage(seed, uploaded)
        #expect(saved.work.request.body == uploaded.work.staged.reservation.request.input)
        #expect(saved.work.uploadData == Data(uploaded.metadata.utf8))
        #expect(saved.work.upload.receipt?.data == uploaded.work.receipt?.data)
        let replay = try Store.stage(uploaded, proof: seed.proof,
            authorization: .init(recipient: .recoveryOnly, validate: { Issue.record("Replay asked for consent") }),
            container: seed.container, isCurrent: { true }, now: .distantFuture, save: { _ in Issue.record("Replay saved") })
        #expect(replay == saved)
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
        #expect(try Store.read(proof: seed.proof, container: reopened, isCurrent: { true }).work == saved.work)
        let context = ModelContext(reopened)
        let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        #expect(!row.permitsOrdinaryInference && row.queueAttemptCount == 0 && job.attemptCount == 0)
        #expect(throws: (any Error).self) { try ObservationReanalysisPersistence.restore(row: row, job: job) }
        #expect(throws: (any Error).self) { try ObservationReanalysisPersistence.preparation(seed.preparation.identity, container: reopened, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try ObservationVideoUploadStore.read(proof: seed.proof, container: reopened, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try ObservationVideoUploadLifecycleStore.read(proof: seed.proof, container: reopened, isCurrent: { true }) }
        #expect(try ObservationReanalysisAdmissionStore.candidates(ownerID: seed.source.ownerID, canPreflight: true, now: Date(), container: reopened, isCurrent: { true }).isEmpty)
        #expect(try ObservationReanalysisExecutionStore.candidates(ownerID: seed.source.ownerID, container: reopened, isCurrent: { true }).isEmpty)
        for file in seed.preparation.files { #expect(FileManager.default.fileExists(atPath: seed.root.appendingPathComponent(file.path).path)) }
    }

    @Test func consumptionIsDurableAndHeldWorkNeverClaimsAgain() async throws {
        let (seed, uploaded) = try await ready(); defer { seed.remove() }
        let original = try stage(seed, uploaded)
        #expect(throws: (any Error).self) { try Store.claim(original, proof: seed.proof, container: seed.container, isCurrent: { true }, now: .distantFuture) }
        #expect(try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true }) == original)
        let claim = try Store.claim(original, proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Store.claim(original, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        let permit = try Store.consume(claim, proof: seed.proof, authorization: authorization, container: seed.container, isCurrent: { true })
        try Store.validateDispatch(permit, proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Store.validateDispatch(permit, proof: seed.proof, container: seed.container, isCurrent: { true }, now: .distantFuture) }
        #expect(permit.snapshot.work.consumed && permit.snapshot.work.attemptID == claim.snapshot.work.attemptID)
        #expect(throws: (any Error).self) { try Store.consume(claim, proof: seed.proof, authorization: authorization, container: seed.container, isCurrent: { true }) }
        let held = try Store.hold(permit.snapshot, proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(held.work.phase == .held && held.work.consumed)
        #expect(throws: (any Error).self) { try Store.claim(held, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try Store.validateDispatch(permit, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        #expect(try stage(seed, uploaded) == held)
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
        #expect(try Store.read(proof: seed.proof, container: reopened, isCurrent: { true }).work == held.work)
    }

    @Test(arguments: ["stage", "claim", "consume", "hold"], [false, true])
    func uncertainSavesNeverResetCommittedAuthority(operation: String, commits: Bool) async throws {
        let (seed, uploaded) = try await ready(); defer { seed.remove() }
        let fail: (ModelContext) throws -> Void = { if commits { try $0.save() }; throw Simulated.save }
        if operation == "stage" {
            #expect(throws: Simulated.save) { try Store.stage(uploaded, proof: seed.proof, authorization: authorization, container: seed.container, isCurrent: { true }, save: fail) }
            let saved = try stage(seed, uploaded)
            #expect(saved.work.phase == .idle && !saved.work.consumed)
            return
        }
        let original = try stage(seed, uploaded), id = UUID()
        if operation == "claim" {
            #expect(throws: Simulated.save) { try Store.claim(original, proof: seed.proof, container: seed.container, isCurrent: { true }, attemptID: id, save: fail) }
            let saved = try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true })
            #expect(saved.work.phase == (commits ? .running : .idle))
            #expect(saved.work.attemptID == (commits ? id : nil))
            if commits { #expect(throws: (any Error).self) { try Store.claim(saved, proof: seed.proof, container: seed.container, isCurrent: { true }) } }
            return
        }
        let claim = try Store.claim(original, proof: seed.proof, container: seed.container, isCurrent: { true }, attemptID: id)
        if operation == "consume" {
            #expect(throws: Simulated.save) { try Store.consume(claim, proof: seed.proof, authorization: authorization, container: seed.container, isCurrent: { true }, save: fail) }
            let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
            let saved = try Store.read(proof: seed.proof, container: reopened, isCurrent: { true })
            #expect(saved.work.consumed == commits && saved.work.attemptID == id)
            if commits { #expect(throws: (any Error).self) { try Store.consume(claim, proof: seed.proof, authorization: authorization, container: seed.container, isCurrent: { true }) } }
            return
        }
        let permit = try Store.consume(claim, proof: seed.proof, authorization: authorization, container: seed.container, isCurrent: { true })
        #expect(throws: Simulated.save) { try Store.hold(permit.snapshot, proof: seed.proof, container: seed.container, isCurrent: { true }, save: fail) }
        let saved = try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(saved.work.consumed && saved.work.phase == (commits ? .held : .running))
        #expect(throws: (any Error).self) { try Store.claim(saved, proof: seed.proof, container: seed.container, isCurrent: { true }) }
    }

    @Test(arguments: ["account", "container", "source", "job", "erasure", "row", "metadata", "consent", "recipient", "expired", "result"])
    func dispatchConsumptionRequiresCurrentExactScope(boundary: String) async throws {
        let (seed, uploaded) = try await ready(); defer { seed.remove() }
        let claim = try Store.claim(stage(seed, uploaded), proof: seed.proof, container: seed.container, isCurrent: { true })
        let context = ModelContext(seed.container)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        if boundary == "result" {
            let source = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
            context.insert(try LocalAnalysisRecord(analysisID: seed.preparation.identity.analysisID,
                observationID: source.observationID, ownerAccountID: seed.source.ownerID,
                completedAt: source.completedAt, snapshotVersion: source.snapshotVersion, resultSnapshotData: source.resultSnapshotData))
        }
        if boundary == "job" { context.delete(job) }
        if boundary == "erasure" { try ObservationReanalysisErasureReceipt(parentID: seed.source.observationID, childID: seed.preparation.identity.analysisID).record(in: context) }
        if boundary == "source" { context.delete(try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)) }
        if boundary == "row" { try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first).queueAttemptCount = 1 }
        if boundary == "metadata" { job.metadataJSON = claim.snapshot.metadata + " " }
        try context.save()
        let container = boundary == "container" ? try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false) : seed.container
        #expect(throws: (any Error).self) {
            try Store.consume(claim, proof: seed.proof,
                authorization: .init(recipient: boundary == "recipient" ? .recoveryOnly : .gemini, validate: {
                    if boundary == "consent" { throw MerianError.aiConsentRequired }
                }), container: container, isCurrent: { boundary != "account" }, now: boundary == "expired" ? .distantFuture : Date())
        }
    }

    @Test func partialUnknownExpiredAndCancelledWorkCannotBecomeDispatchable() async throws {
        let helper = ObservationVideoUploadLifecycleTests()
        let (seed, upload) = try await helper.staged(); defer { seed.remove() }
        #expect(throws: (any Error).self) { try stage(seed, upload) }
        let claim = try ObservationVideoUploadLifecycleStore.claim(upload, proof: seed.proof, container: seed.container, isCurrent: { true })
        let held = try ObservationVideoUploadLifecycleStore.hold(claim, proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) { try stage(seed, held) }
        let partial = try ObservationVideoUploadLifecycleStore.settle(claim, receipt: helper.receipt(claim), proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) { try stage(seed, partial) }
        let (readySeed, readyUpload) = try await ready(); defer { readySeed.remove() }
        #expect(throws: (any Error).self) { try Store.stage(readyUpload, proof: readySeed.proof, authorization: authorization, container: readySeed.container, isCurrent: { true }, now: .distantFuture) }
        let original = try stage(readySeed, readyUpload)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: (any Error).self) { try Store.claim(original, proof: readySeed.proof, container: readySeed.container, isCurrent: { true }) }
        }
        await task.value
        #expect(try Store.read(proof: readySeed.proof, container: readySeed.container, isCurrent: { true }) == original)
    }

    @Test func codecRejectsForgedStatesAndExecutionKindCannotFallThroughLegacyParsing() async throws {
        #expect(throws: (any Error).self) { try ObservationVideoPreparation.requireNonVideo(Data("{\"kind\":\"video_execution\"}".utf8)) }
        let (seed, uploaded) = try await ready(); defer { seed.remove() }
        let work = try Work(uploadData: Data(uploaded.metadata.utf8))
        #expect(try Work.decode(work.storedData()) == work)
        let row = try #require(JSONSerialization.jsonObject(with: work.storedData()) as? [String: Any])
        for (key, value) in [("version", 2 as Any), ("kind", "audio_execution"), ("extra", true), ("phase", "other"), ("consumed", 1), ("consumed", true), ("attempt_id", UUID().uuidString.lowercased()), ("upload_base64", "invalid")] {
            var changed = row; changed[key] = value
            #expect(throws: (any Error).self) { try Work.decode(JSONSerialization.data(withJSONObject: changed)) }
        }
        for collision in [seed.source.ownerID, seed.source.observationID, seed.preparation.identity.analysisID, uploaded.work.attempts[0].id] {
            #expect(throws: (any Error).self) { try Work(uploadData: work.uploadData, phase: .running, attemptID: collision) }
        }
    }
}
