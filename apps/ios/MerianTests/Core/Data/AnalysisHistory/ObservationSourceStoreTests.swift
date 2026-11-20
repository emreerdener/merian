import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationSourceStoreTests {
    typealias Store = ObservationSourceReservationStore
    typealias Work = ObservationSourceReservationWork
    typealias Admission = ObservationReanalysisAdmissionStore
    let fixture = ObservationReanalysisRecoveryTests()
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func prepare(_ seed: ObservationReanalysisRecoveryTests.Seed) async throws -> Admission.Claim {
        try await fixture.publish(seed); _ = try await fixture.recover(seed)
        return try Admission.claim(Admission.read(seed.pending.draft.identity, container: seed.container, isCurrent: { true }),
            admission: .initial, now: now, container: seed.container, isCurrent: { true })
    }
    func request(_ seed: ObservationReanalysisRecoveryTests.Seed) throws -> ObservationSourceReservationRequest {
        try .init(photo: seed.pending.draft.binding(processor: .gemini).request)
    }
    func reply(_ saved: Store.Snapshot, state: String = "reserved") throws -> ObservationSourceReservationReply {
        let identity = saved.identity, request = saved.work.request
        var row: [String: Any] = ["schema_version": 1, "owner_id": identity.ownerID.uuidString.lowercased(),
            "observation_id": identity.observationID.uuidString.lowercased(), "source_analysis_id": identity.sourceAnalysisID.uuidString.lowercased(),
            "state": state]
        if state == "reserved" {
            row["analysis_id"] = identity.analysisID.uuidString.lowercased(); row["request_digest"] = request.requestDigest
            row["fingerprint_version"] = 1; row["fingerprint"] = request.fingerprint
        } else if state == "held" { row["reason"] = "source_occupied" }
        return try .init(data: JSONSerialization.data(withJSONObject: row), request: request, ownerID: identity.ownerID)
    }

    @Test(arguments: ["staged", "running", "unknown", "conflict", "reserved", "held", "unavailable"])
    func allSourcePhasesStayOutsideAdmissionExecutionAndDiscard(_ phase: String) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let admission = try await prepare(seed), proof = try ObservationSourceReservationStore.Proof.photo(seed.pending.verified(source: seed.source))
        let saved = try Store.stage(admission, request: request(seed), proof: proof, container: seed.container, isCurrent: { true })
        if phase != "staged" {
            let claim = try Store.claim(saved, admission: .initial, proof: proof, container: seed.container, isCurrent: { true })
            if phase == "unknown" || phase == "conflict" {
                _ = try Store.hold(claim, proof: proof, container: seed.container, isCurrent: { true },
                    conflict: phase == "conflict" ? .init(request: saved.work.request, ownerID: saved.identity.ownerID) : nil)
            } else if phase != "running" {
                let response = try reply(saved, state: phase)
                let observed = try Store.settle(claim, reply: response, proof: proof, container: seed.container, isCurrent: { true })
                #expect(observed.work.reply?.data == response.data)
            }
        }
        #expect(try Admission.candidates(ownerID: saved.identity.ownerID, canPreflight: true, now: now.addingTimeInterval(1000),
            container: seed.container, isCurrent: { true }).isEmpty)
        #expect(try ObservationReanalysisExecutionStore.candidates(ownerID: saved.identity.ownerID,
            container: seed.container, isCurrent: { true }).isEmpty)
        #expect(throws: (any Error).self) {
            try ObservationReanalysisExecutionStore.bindAndAdmit(seed.pending.draft, processor: .gemini, now: now,
                container: seed.container, isCurrent: { true }, submissionProof: seed.pending.verified(source: seed.source), admissionClaim: admission)
        }
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPersistence.discardPreparation(source: seed.source, analysisID: saved.identity.analysisID,
                container: seed.container, isCurrent: { true })
        }
        let context = ModelContext(seed.container), row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let job = try #require(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: row.id)))
        #expect(row.queueNeedsAttention && !row.permitsOrdinaryInference && row.queueAttemptCount == 0 && row.queueNextRetryAt == nil)
        #expect(job.status == .needsAttention && job.attemptCount == 0 && job.nextRunAt == nil)
        #expect(try context.fetch(FetchDescriptor<LocalScanRecord>()).first?.selectedAnalysisID == saved.identity.sourceAnalysisID.uuidString.lowercased())
    }

    @Test func exactRecoveryAdvancesOnlyLocalGenerationAndRejectsStaleClaims() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let admission = try await prepare(seed), proof = try ObservationSourceReservationStore.Proof.photo(seed.pending.verified(source: seed.source))
        let saved = try Store.stage(admission, request: request(seed), proof: proof, container: seed.container, isCurrent: { true })
        let first = try Store.claim(saved, admission: .initial, proof: proof, container: seed.container, isCurrent: { true })
        let second = try Store.claim(first.snapshot, admission: .explicitRecovery, proof: proof, container: seed.container, isCurrent: { true })
        #expect(second.snapshot.work.generation == 2 && second.snapshot.work.request == saved.work.request)
        #expect(throws: (any Error).self) { try Store.settle(first, reply: reply(saved), proof: proof, container: seed.container, isCurrent: { true }) }
        let result = try Store.settle(second, reply: reply(saved), proof: proof, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Store.claim(result, admission: .explicitRecovery, proof: proof, container: seed.container, isCurrent: { true }) }
        #expect(try Store.stage(admission, request: request(seed), proof: proof, container: seed.container, isCurrent: { true }) == result)
    }

    @Test(arguments: [false, true])
    func uncertainStageSaveRetainsExactCandidateAndNeverCreatesExecution(committed: Bool) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let admission = try await prepare(seed), proof = try ObservationSourceReservationStore.Proof.photo(seed.pending.verified(source: seed.source)), candidate = try request(seed)
        #expect(throws: (any Error).self) {
            try Store.stage(admission, request: candidate, proof: proof, container: seed.container, isCurrent: { true }, save: {
                if committed { try $0.save() }; throw CocoaError(.fileWriteUnknown)
            })
        }
        if committed {
            #expect(try Store.read(candidateIdentity(seed), container: seed.container, isCurrent: { true }).work.request == candidate)
        } else { #expect(try Admission.validate(admission, container: seed.container, isCurrent: { true }) == admission.snapshot) }
        let recovered = try Store.stage(admission, request: candidate, proof: proof, container: seed.container, isCurrent: { true })
        #expect(recovered.work.request.body == candidate.body && recovered.work.generation == 0)
    }

    func candidateIdentity(_ seed: ObservationReanalysisRecoveryTests.Seed) -> OfflineQueueWork.Reanalysis { seed.pending.draft.identity }

    @Test func maximalOriginalPhotoBytesRoundTripAndAudioCannotEnterPhotoStore() throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let original = try request(seed), identity = seed.pending.draft.identity
        let bytes = original.input + Data(repeating: 32, count: 1_044_480 - original.input.count)
        let candidate = try ObservationSourceReservationRequest(photo: .init(savedBody: bytes))
        let work = try Work(preparation: seed.pending, request: candidate)
        let restored = try Work.decode(work.storedData())
        #expect(restored.request.input == bytes && restored.request.body == candidate.body)
        #expect(try work.storedData().count <= Work.maximumBytes)
        let audio = try ObservationSourceReservationRequest(audio: .init(observationID: identity.observationID,
            analysisID: identity.analysisID, sourceAnalysisID: identity.sourceAnalysisID,
            evidence: [.audio(.init(mediaID: UUID(), contentType: "audio/wav", byteCount: 46, sha256: String(repeating: "a", count: 64)))]))
        #expect(throws: (any Error).self) { try Work(preparation: seed.pending, request: audio) }
    }

    @Test(arguments: ["extra", "version", "phase", "generation", "fraction", "state", "reply", "candidate", "input", "preparation", "oversized"])
    func storedEnvelopeRejectsMalformedOrRebasedWork(_ damage: String) throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let work = try Work(preparation: seed.pending, request: request(seed))
        var row = try #require(JSONSerialization.jsonObject(with: work.storedData()) as? [String: Any])
        switch damage {
        case "extra": row["execution_permission"] = true
        case "version": row["version"] = true
        case "phase": row["phase"] = "admission_pending"
        case "generation": row["generation"] = true
        case "fraction": row["generation"] = 0.5
        case "state": row["state"] = "running"
        case "reply": row["reply_base64"] = Data("{}".utf8).base64EncodedString()
        case "candidate": row["candidate_base64"] = Data("{}".utf8).base64EncodedString()
        case "input": row["input_base64"] = try seed.pending.draft.binding(processor: .openAI).request.body.base64EncodedString()
        case "preparation": row["preparation_base64"] = try ObservationReanalysisPreparationIntent(draft: seed.pending.draft,
            source: seed.source, action: .hold).storedData().base64EncodedString()
        default: row["candidate_base64"] = String(repeating: "A", count: Work.maximumBytes)
        }
        #expect(throws: (any Error).self) { try Work.decode(JSONSerialization.data(withJSONObject: row)) }
        #expect(throws: (any Error).self) { try Work.decode(Data(repeating: 32, count: Work.maximumBytes + 1)) }
    }

    @Test func sourceStagingRejectsUnverifiedPhaseAndChangedRequest() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let proof = try ObservationSourceReservationStore.Proof.photo(seed.pending.verified(source: seed.source))
        let pending = try Admission.read(seed.pending.draft.identity, container: seed.container, isCurrent: { true })
        let filesClaim = try Admission.claim(pending, admission: .initial, now: now, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Store.stage(filesClaim, request: request(seed), proof: proof, container: seed.container, isCurrent: { true }) }
        // The complete-cohort callback is the only valid promotion seam.
        try await fixture.publish(seed)
        let files = ObservationReanalysisFileStore(documents: seed.root)
        let ready = try await files.recover(draft: seed.pending.draft, validateBeforeRead: {
            try Admission.validate(filesClaim, container: seed.container, isCurrent: { true }, proof: seed.pending.verified(source: seed.source))
        }, commit: {
            try Admission.promoteVerifiedFiles(filesClaim, proof: seed.pending.verified(source: seed.source), container: seed.container, isCurrent: { true })
        })
        let claim = try Admission.claim(ready, admission: .initial, now: now, container: seed.container, isCurrent: { true })
        let saved = try Store.stage(claim, request: request(seed), proof: proof, container: seed.container, isCurrent: { true })
        let changed = try ObservationSourceReservationRequest(photo: seed.pending.draft.binding(processor: .openAI).request)
        #expect(throws: (any Error).self) { try Store.stage(claim, request: changed, proof: proof, container: seed.container, isCurrent: { true }) }
        #expect(try Store.read(saved.identity, container: seed.container, isCurrent: { true }) == saved)
    }

    @Test(arguments: ["account", "parentDeletion", "childDeletion", "source", "queueResidue", "container"])
    func staleScopeAndMalformedPairCannotAcknowledge(_ change: String) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let admission = try await prepare(seed), proof = try ObservationSourceReservationStore.Proof.photo(seed.pending.verified(source: seed.source))
        let saved = try Store.stage(admission, request: request(seed), proof: proof, container: seed.container, isCurrent: { true })
        let claim = try Store.claim(saved, admission: .initial, proof: proof, container: seed.container, isCurrent: { true })
        let context = ModelContext(seed.container)
        switch change {
        case "parentDeletion": context.insert(PendingCloudDeletionTask(scanId: saved.identity.observationID.uuidString.lowercased()))
        case "childDeletion": context.delete(try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first))
        case "source": context.delete(try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first))
        case "queueResidue": try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first).queueAttemptCount = 1
        default: break
        }
        try context.save()
        let target = try change == "container" ? fixture.sourceFixture.fixture.container() : seed.container
        #expect(throws: (any Error).self) {
            try Store.settle(claim, reply: reply(saved), proof: proof, container: target, isCurrent: { change != "account" })
        }
    }

    @Test func knownReplySurvivesCancellationOnlyForTheUnchangedClaim() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let admission = try await prepare(seed), proof = try ObservationSourceReservationStore.Proof.photo(seed.pending.verified(source: seed.source))
        let saved = try Store.stage(admission, request: request(seed), proof: proof, container: seed.container, isCurrent: { true })
        let claim = try Store.claim(saved, admission: .initial, proof: proof, container: seed.container, isCurrent: { true })
        let response = try reply(saved)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try Store.settle(claim, reply: response, proof: proof, container: seed.container, isCurrent: { true })
        }
        #expect(try await task.value.work.reply == response)
    }

    @Test(arguments: [false, true])
    func parentErasureRetainsItsOwnDurableDeletionAuthority(committed: Bool) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let admission = try await prepare(seed), proof = try ObservationSourceReservationStore.Proof.photo(seed.pending.verified(source: seed.source))
        let saved = try Store.stage(admission, request: request(seed), proof: proof, container: seed.container, isCurrent: { true })
        let claim = try Store.claim(saved, admission: .initial, proof: proof, container: seed.container, isCurrent: { true })
        let observed = try Store.settle(claim, reply: reply(saved), proof: proof, container: seed.container, isCurrent: { true })
        let context = ModelContext(seed.container); context.autosaveEnabled = false
        try ConfirmedSpeciesReviewPersistence.transaction {
            let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
            try context.ensurePendingCloudDeletionTask(scanId: parent.id, requestingAccountID: saved.identity.ownerID, origin: .explicitUserDeletion)
            let cleanup = try ObservationReanalysisErasure.removeChildren(of: parent.id, context: context)
            #expect(cleanup.childIDs == [saved.identity.analysisID.uuidString.lowercased()])
            context.delete(parent)
            if committed { try context.save() } else { context.rollback() }
        }
        if committed {
            let read = ModelContext(seed.container)
            #expect(try read.fetch(FetchDescriptor<PendingCloudDeletionTask>()).map(\.scanId) == [saved.identity.observationID.uuidString.lowercased()])
            #expect(try read.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(saved.identity.analysisID)) != nil)
            #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
            #expect(throws: (any Error).self) { try Store.stage(admission, request: request(seed), proof: proof, container: seed.container, isCurrent: { true }) }
        } else {
            #expect(try Store.read(saved.identity, container: seed.container, isCurrent: { true }) == observed)
        }
    }

    @Test func diskRestartKeepsTheOriginalRequestAndInterruptedClaim() async throws {
        let root = try ObservationReanalysisFileStoreTests().directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("store.sqlite")
        let retained: Work
        do {
            let seed = try fixture.seed(action: .submit, url: url); defer { try? FileManager.default.removeItem(at: seed.root) }
            let admission = try await prepare(seed), proof = try ObservationSourceReservationStore.Proof.photo(seed.pending.verified(source: seed.source))
            let saved = try Store.stage(admission, request: request(seed), proof: proof, container: seed.container, isCurrent: { true })
            retained = try Store.claim(saved, admission: .initial, proof: proof, container: seed.container, isCurrent: { true }).snapshot.work
        }
        let container = try fixture.sourceFixture.fixture.container(url: url, seed: false)
        let saved = try Store.read(retained.identity, container: container, isCurrent: { true })
        #expect(saved.work == retained)
        let source = try ObservationReanalysisSource.capture(observationID: retained.identity.observationID,
            analysisID: retained.identity.sourceAnalysisID, ownerID: retained.identity.ownerID, container: container)
        let resumed = try Store.claim(saved, admission: .explicitRecovery, proof: retained.preparation.verified(source: source),
            container: container, isCurrent: { true })
        #expect(resumed.snapshot.work.request == retained.request && resumed.snapshot.work.generation == 2)
    }
}
