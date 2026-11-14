import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoUploadStagingTests {
    typealias Store = ObservationVideoUploadStore
    typealias Work = ObservationVideoUploadWork
    typealias Reservation = ObservationVideoSourceReservationStore
    let fixture = ObservationVideoReservationLifecycleTests()

    func reserved(audio: Bool = true) async throws -> (ObservationVideoDurabilityTests.Seed, Reservation.Snapshot) {
        let (seed, staged) = try await fixture.staged(audio: audio)
        do {
            let claim = try Reservation.claim(staged, proof: seed.proof, container: seed.container, isCurrent: { true })
            return (seed, try Reservation.settle(claim, settlement: .reply(fixture.reply(staged)),
                proof: seed.proof, container: seed.container, isCurrent: { true }))
        } catch { seed.remove(); throw error }
    }

    @Test(arguments: [false, true])
    func reservedHandoffRetainsExactBytesAndReopensHeld(audio: Bool) async throws {
        let (seed, original) = try await reserved(audio: audio); defer { seed.remove() }
        let pretty = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: Data(original.metadata.utf8)), options: [.prettyPrinted])
        let context = ModelContext(seed.container)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        job.metadataJSON = String(decoding: pretty, as: UTF8.self); try context.save()
        let saved = try Reservation.read(proof: seed.proof, container: seed.container, isCurrent: { true })
        let request = try ObservationVideoEvidenceUploadRequest(input: saved.work.request.input)
        let bytes = try seed.preparation.files.map { try Data(contentsOf: seed.root.appendingPathComponent($0.path)) }
        let staged = try Store.stage(saved, proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(staged.work.reservationData == pretty && staged.work.request.body == request.body)
        #expect(staged.work.reservation.reply?.data == original.work.reply?.data)
        #expect(staged.work.request.inventory.items.count == (audio ? 7 : 6))
        #expect(try Store.stage(saved, proof: seed.proof, container: seed.container,
            isCurrent: { true }, save: { _ in Issue.record("Exact replay saved") }) == staged)
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
        #expect(try Store.read(proof: seed.proof, container: reopened, isCurrent: { true }).work == staged.work)
        #expect(try seed.preparation.files.map { try Data(contentsOf: seed.root.appendingPathComponent($0.path)) } == bytes)
        let current = ModelContext(reopened)
        let row = try #require(current.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let persisted = try #require(current.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        #expect(row.queueAttemptCount == 0 && row.queueNeedsAttention && !row.permitsOrdinaryInference)
        #expect(persisted.attemptCount == 0 && persisted.statusRaw == OfflineJobStatus.needsAttention.rawValue)
        #expect(throws: (any Error).self) { try Reservation.read(proof: seed.proof, container: reopened, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try ObservationVideoPreparationStore.discard(seed.proof, container: reopened, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try ObservationReanalysisPersistence.restore(row: row, job: persisted) }
        #expect(throws: (any Error).self) { try ObservationVideoPreparation.requireNonVideo(Data("{\"kind\":\"video_evidence_upload\"}".utf8)) }
    }

    @Test(arguments: [false, true])
    func uncertainSaveRecoversExistingStateOnly(commits: Bool) async throws {
        let (seed, saved) = try await reserved(); defer { seed.remove() }
        let request = try ObservationVideoEvidenceUploadRequest(input: saved.work.request.input)
        #expect(throws: ObservationVideoReservationLifecycleTests.Simulated.save) {
            try Store.stage(saved, proof: seed.proof, container: seed.container,
                isCurrent: { true }, save: { if commits { try $0.save() }; throw ObservationVideoReservationLifecycleTests.Simulated.save })
        }
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
        if commits {
            #expect(try Store.read(proof: seed.proof, container: reopened, isCurrent: { true }).work.request == request)
        } else {
            #expect(throws: (any Error).self) { try Store.read(proof: seed.proof, container: reopened, isCurrent: { true }) }
            #expect(try Reservation.read(proof: seed.proof, container: reopened, isCurrent: { true }).work == saved.work)
        }
        let retry = try Store.stage(saved, proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(retry.work.reservationData == Data(saved.metadata.utf8) && retry.work.request == request)
    }

    @Test(arguments: ["account", "container", "job", "attempt", "source", "erasure", "metadata", "result"])
    func stagingRequiresExactCurrentReservedPair(_ boundary: String) async throws {
        let (seed, saved) = try await reserved(); defer { seed.remove() }
        let context = ModelContext(seed.container)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        if boundary == "job" { context.delete(job) }
        if boundary == "attempt" { job.attemptCount = 1 }
        if boundary == "source" { context.delete(try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)) }
        if boundary == "erasure" {
            try ObservationReanalysisErasureReceipt(parentID: seed.source.observationID, childID: seed.preparation.identity.analysisID).record(in: context)
        }
        if boundary == "metadata" { job.metadataJSON = saved.metadata + " " }
        if boundary == "result" {
            context.insert(try LocalAnalysisRecord(analysisID: seed.preparation.identity.analysisID,
                observationID: seed.source.observationID.uuidString.lowercased(), ownerAccountID: seed.source.ownerID,
                completedAt: nil, snapshotVersion: 3, resultSnapshotData: Data("{}".utf8)))
        }
        try context.save()
        let container = boundary == "container" ? try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false) : seed.container
        #expect(throws: (any Error).self) { try Store.stage(saved, proof: seed.proof, container: container, isCurrent: { boundary != "account" }) }
    }

    @Test func semanticallyEquivalentUploadBytesCannotReplaceDerivedRequest() async throws {
        let (seed, saved) = try await reserved(); defer { seed.remove() }
        let staged = try Store.stage(saved, proof: seed.proof, container: seed.container, isCurrent: { true })
        let pretty = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: staged.work.request.body), options: [.prettyPrinted])
        let equivalent = try ObservationVideoEvidenceUploadRequest(savedBody: pretty, input: saved.work.request.input)
        #expect(equivalent.identity == staged.work.request.identity && equivalent.body != staged.work.request.body)
        var row = try #require(JSONSerialization.jsonObject(with: Data(staged.metadata.utf8)) as? [String: Any])
        row["request_base64"] = pretty.base64EncodedString()
        let altered = try JSONSerialization.data(withJSONObject: row)
        #expect(throws: (any Error).self) { try Work.decode(altered) }
        let context = ModelContext(seed.container)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        job.metadataJSON = String(decoding: altered, as: UTF8.self); try context.save()
        #expect(throws: (any Error).self) { try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try Store.stage(saved, proof: seed.proof, container: seed.container, isCurrent: { true }) }
    }

    @Test func crossAnalysisRequestAndForgedOwnerCannotEnterHandoff() async throws {
        let (seed, saved) = try await reserved(); defer { seed.remove() }
        let (other, different) = try await reserved(); defer { other.remove() }
        let wrongRequest = try ObservationVideoEvidenceUploadRequest(input: different.work.request.input)
        #expect(throws: (any Error).self) { try Work(reservationData: Data(saved.metadata.utf8), request: wrongRequest) }
        #expect(throws: (any Error).self) { try Store.stage(saved, proof: other.proof, container: seed.container, isCurrent: { true }) }
        var outer = try #require(JSONSerialization.jsonObject(with: Data(saved.metadata.utf8)) as? [String: Any])
        let originalReply = try #require(saved.work.reply)
        var reply = try #require(JSONSerialization.jsonObject(with: originalReply.data) as? [String: Any])
        reply["owner_id"] = UUID().uuidString.lowercased()
        outer["reply_base64"] = try JSONSerialization.data(withJSONObject: reply).base64EncodedString()
        let forged = Reservation.Snapshot(work: saved.work,
            metadata: String(decoding: try JSONSerialization.data(withJSONObject: outer), as: UTF8.self), containerID: saved.containerID)
        #expect(throws: (any Error).self) { try Store.stage(forged, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        #expect(try Reservation.read(proof: seed.proof, container: seed.container, isCurrent: { true }) == saved)
    }

    @Test func codecRejectsNonReservedSubstitutionAndUnsupportedWork() async throws {
        let (seed, saved) = try await reserved(); defer { seed.remove() }
        let request = try ObservationVideoEvidenceUploadRequest(input: saved.work.request.input)
        let work = try Work(reservationData: Data(saved.metadata.utf8), request: request)
        #expect(try Work.decode(work.storedData()) == work)
        for phase in [ObservationVideoSourceReservationWork.Phase.staged, .running, .unknown, .conflict] {
            let other = try ObservationVideoSourceReservationWork(preparation: seed.preparation, request: saved.work.request,
                phase: phase, attemptID: phase == .staged ? nil : UUID())
            #expect(throws: (any Error).self) { try Work(reservationData: other.storedData(), request: request) }
        }
        for state in ["held", "unavailable"] {
            let other = try ObservationVideoSourceReservationWork(preparation: seed.preparation, request: saved.work.request,
                phase: .observed, attemptID: UUID(), reply: fixture.reply(saved, state: state))
            #expect(throws: (any Error).self) { try Work(reservationData: other.storedData(), request: request) }
        }
        let row = try #require(JSONSerialization.jsonObject(with: work.storedData()) as? [String: Any])
        for field in ["version", "kind", "phase", "receipt", "request_base64", "reservation_base64"] {
            var changed = row
            if field == "version" { changed[field] = 2 }
            else if field == "request_base64" || field == "reservation_base64" { changed[field] = try #require(changed[field] as? String) + "\n" }
            else { changed[field] = "unsupported" }
            #expect(throws: (any Error).self) { try Work.decode(JSONSerialization.data(withJSONObject: changed)) }
        }
        var maximum = row
        maximum["reservation_base64"] = Data(repeating: 32, count: ObservationVideoSourceReservationWork.maximumBytes).base64EncodedString()
        maximum["request_base64"] = Data(repeating: 32, count: ObservationVideoEvidenceUploadRequest.maximumBytes).base64EncodedString()
        #expect(try JSONSerialization.data(withJSONObject: maximum).count <= Work.maximumBytes)
        #expect(throws: (any Error).self) { try Work.decode(Data(repeating: 32, count: Work.maximumBytes + 1)) }
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: (any Error).self) { try Store.stage(saved, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        }
        await cancelled.value
    }
}
