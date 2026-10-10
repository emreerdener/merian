import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAudioSourceStoreTests {
    typealias Store = ObservationSourceReservationStore
    typealias Work = ObservationSourceReservationWork
    let fixture = ObservationAudioExecutionStoreTests()

    func candidate(_ seed: ObservationAudioPreparationTests.Seed) throws -> ObservationSourceReservationRequest {
        try .init(audio: ObservationAudioExecutionIntent(preparation: seed.preparation).request)
    }
    func stage(_ seed: ObservationAudioPreparationTests.Seed) throws -> Store.Snapshot {
        try Store.stageAudio(request: candidate(seed), proof: .audio(seed.proof), container: seed.container, isCurrent: { true })
    }

    @Test(arguments: ["staged", "running", "unknown", "conflict", "reserved", "held", "unavailable"])
    func sourceWorkNeverBecomesExecutionOrPreparation(_ state: String) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        var saved = try stage(seed)
        if state != "staged" {
            let claim = try Store.claim(saved, admission: .initial, proof: .audio(seed.proof), container: seed.container, isCurrent: { true })
            saved = claim.snapshot
            if ["unknown", "conflict"].contains(state) {
                saved = try Store.hold(claim, proof: .audio(seed.proof), container: seed.container, isCurrent: { true },
                    conflict: state == "conflict" ? .init(request: saved.work.request, ownerID: saved.identity.ownerID) : nil)
            } else if state != "running" {
                saved = try Store.settle(claim, reply: ObservationSourceStoreTests().reply(saved, state: state),
                    proof: .audio(seed.proof), container: seed.container, isCurrent: { true })
            }
        }
        if state != "reserved" {
            #expect(throws: (any Error).self) { try ObservationAudioExecutionIntent(reserved: saved.work) }
            #expect(throws: (any Error).self) {
                try ObservationAudioExecutionStore.bindReserved(.init(preparation: seed.preparation), source: saved,
                    proof: seed.proof, authorization: fixture.authorization, container: seed.container, isCurrent: { true })
            }
        }
        #expect(try stage(seed) == saved)
        #expect(try Work.decode(saved.work.storedData()) == saved.work)
        #expect(saved.work.preparation.version == 10)
        #expect(throws: (any Error).self) { try fixture.bind(seed) }
        #expect(throws: (any Error).self) { try ObservationAudioExecutionStore.admissionState(seed.proof, container: seed.container, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try ObservationAudioPreparationStore.read(seed.proof, container: seed.container, isCurrent: { true }) }
        #expect(try ObservationReanalysisAdmissionStore.candidates(ownerID: saved.identity.ownerID, canPreflight: true,
            now: Date(), container: seed.container, isCurrent: { true }).isEmpty)
        #expect(try ObservationReanalysisExecutionStore.candidates(ownerID: saved.identity.ownerID,
            container: seed.container, isCurrent: { true }).isEmpty)
        let context = ModelContext(seed.container)
        #expect(try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first).permitsOrdinaryInference == false)
        await #expect(throws: (any Error).self) {
            try await ObservationAudioResumeStore.read(saved.identity, container: seed.container, isCurrent: { true })
        }
        #expect(try Data(contentsOf: seed.file) == seed.bytes)
    }

    @Test(arguments: [false, true])
    func stageSaveFailureRecoversOnlyOriginalCandidate(committed: Bool) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let request = try candidate(seed)
        #expect(throws: (any Error).self) {
            try Store.stageAudio(request: request, proof: .audio(seed.proof), container: seed.container, isCurrent: { true }, save: {
                if committed { try $0.save() }; throw CocoaError(.fileWriteUnknown)
            })
        }
        let saved = try stage(seed)
        #expect(saved.work.request == request && saved.work.generation == 0)
    }

    @Test func onlyReadyUnboundExactAudioCanStage() async throws {
        let seed = try fixture.fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        #expect(throws: (any Error).self) { try stage(seed) }
        _ = try fixture.fixture.phase(seed)
        #expect(throws: (any Error).self) { try stage(seed) }
        _ = try await fixture.fixture.producer(seed).prepare(seed.preparation, source: seed.source, bytes: seed.bytes,
            container: seed.container, isCurrent: { true })
        _ = try fixture.bind(seed)
        #expect(throws: (any Error).self) { try stage(seed) }
    }

    @Test(arguments: ["version", "phase", "preparation", "request", "child", "extra"])
    func taggedAudioEnvelopeRejectsCrossVariantAndForgedEvidence(_ damage: String) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try stage(seed)
        var row = try #require(JSONSerialization.jsonObject(with: saved.work.storedData()) as? [String: Any])
        switch damage {
        case "version": row["version"] = 9
        case "phase": row["phase"] = "audio_execution"
        case "preparation": row["preparation_base64"] = try seed.preparation.storedData(phase: .pending).base64EncodedString()
        case "request": row["input_base64"] = Data("{}".utf8).base64EncodedString()
        case "child":
            var preparation = try #require(JSONSerialization.jsonObject(with: seed.preparation.storedData(phase: .admissionPending)) as? [String: Any])
            preparation["analysis_id"] = UUID().uuidString.lowercased()
            row["preparation_base64"] = try JSONSerialization.data(withJSONObject: preparation).base64EncodedString()
        default: row["dispatch"] = true
        }
        #expect(throws: (any Error).self) { try Work.decode(JSONSerialization.data(withJSONObject: row)) }
    }

    @Test func cancelledKnownReplyUsesExactClaimAndOriginalBytes() async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try stage(seed), proof = try Store.Proof.audio(seed.proof)
        let old = try Store.claim(saved, admission: .initial, proof: proof, container: seed.container, isCurrent: { true })
        let current = try Store.claim(old.snapshot, admission: .explicitRecovery, proof: proof, container: seed.container, isCurrent: { true })
        let reply = try ObservationSourceStoreTests().reply(saved)
        #expect(throws: (any Error).self) { try Store.settle(old, reply: reply, proof: proof, container: seed.container, isCurrent: { true }) }
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try Store.settle(current, reply: reply, proof: proof, container: seed.container, isCurrent: { true })
        }
        let observed = try await task.value
        #expect(observed.work.reply?.data == reply.data && observed.work.request == saved.work.request)
        #expect(throws: (any Error).self) { try Store.claim(observed, admission: .explicitRecovery, proof: proof, container: seed.container, isCurrent: { true }) }
    }

    @Test(arguments: ["account", "source", "parent", "child", "row", "container"])
    func staleAudioAuthorityCannotSettle(_ damage: String) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try stage(seed), proof = try Store.Proof.audio(seed.proof)
        let claim = try Store.claim(saved, admission: .initial, proof: proof, container: seed.container, isCurrent: { true })
        let context = ModelContext(seed.container)
        switch damage {
        case "source": context.delete(try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first))
        case "parent": context.insert(PendingCloudDeletionTask(scanId: saved.identity.observationID.uuidString.lowercased()))
        case "child": context.delete(try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first))
        case "row": try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first).queueAttemptCount = 1
        default: break
        }
        try context.save()
        let container = try damage == "container" ? ObservationReanalysisSourceTests().fixture.container() : seed.container
        #expect(throws: (any Error).self) {
            try Store.settle(claim, reply: ObservationSourceStoreTests().reply(saved), proof: proof,
                container: container, isCurrent: { damage != "account" })
        }
    }

    @Test func retainedServiceUsesOriginalAudioCandidateAndSettlesAfterCancellation() async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try stage(seed), owner = ObservationSourceReservationOwner(), proof = try Store.Proof.audio(seed.proof)
        let key = ObservationSourceReservationOwner.Key(snapshot: saved, admission: .initial,
            session: .init(userID: saved.identity.ownerID, isAnonymous: false), generation: 1, container: ObjectIdentifier(seed.container))
        var exited = false
        let account = ObservationSourceReservationOwnerTests().account(key) { exited = true }
        let response = try ObservationSourceStoreTests().reply(saved)
        let service = ObservationSourceReservationService(reserve: { request, account, before, after in
            #expect(request == saved.work.request && account == saved.identity.ownerID)
            try before(); owner.cancel(); try after(); return response
        })
        let outcome: ObservationSourceReservationService.Outcome = await withCheckedContinuation { continuation in
            var result = ObservationSourceReservationService.Outcome.unavailable
            let admitted = owner.start(key, account: account, isCurrent: { true }, operation: { scope in
                result = await service.run(saved, admission: .initial, proof: proof, container: seed.container, scope: scope)
            }, didFinish: {
                #expect(exited && !owner.isRunning)
                continuation.resume(returning: result)
            })
            if admitted != .started { continuation.resume(returning: .unavailable) }
        }
        #expect(outcome == .observed)
        #expect(try Store.read(saved.identity, container: seed.container, isCurrent: { true }).work.reply?.data == response.data)
    }

    @Test func photoEnvelopeRemainsByteCompatible() throws {
        let photo = ObservationSourceStoreTests(), seed = try photo.fixture.seed(action: .submit)
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let request = try photo.request(seed), work = try Work(preparation: seed.pending, request: request)
        let original: [String: Any] = ["version": 9, "phase": "source_reservation",
            "preparation_base64": try seed.pending.storedData().base64EncodedString(),
            "input_base64": request.input.base64EncodedString(), "candidate_base64": request.body.base64EncodedString(),
            "state": "staged", "generation": 0, "reply_base64": NSNull()]
        let originalBytes = try JSONSerialization.data(withJSONObject: original, options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(try work.storedData() == originalBytes)
        #expect(try Work.decode(originalBytes) == work)
    }

    @Test func durableRestartRecoversExactAudioWithoutRebinding() async throws {
        let root = try ObservationReanalysisFileStoreTests().directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("store.sqlite")
        let retained: Work
        do {
            let seed = try fixture.fixture.seed(action: .submit, url: url); defer { try? FileManager.default.removeItem(at: seed.root) }
            _ = try await fixture.fixture.producer(seed).prepare(seed.preparation, source: seed.source, bytes: seed.bytes,
                container: seed.container, isCurrent: { true })
            let saved = try stage(seed)
            retained = try Store.claim(saved, admission: .initial, proof: .audio(seed.proof), container: seed.container, isCurrent: { true }).snapshot.work
        }
        let container = try ObservationReanalysisSourceTests().fixture.container(url: url, seed: false)
        let saved = try Store.read(retained.identity, container: container, isCurrent: { true })
        #expect(saved.work == retained)
        let source = try ObservationReanalysisSource.captureForAudio(observationID: retained.identity.observationID,
            analysisID: retained.identity.sourceAnalysisID, ownerID: retained.identity.ownerID, container: container)
        let claim = try Store.claim(saved, admission: .explicitRecovery, proof: retained.preparation.verified(source: source),
            container: container, isCurrent: { true })
        #expect(claim.snapshot.work.request == retained.request && claim.snapshot.work.generation == 2)
    }

    func reserved(_ seed: ObservationAudioPreparationTests.Seed, exactBytes: Bool = false) throws -> Store.Snapshot {
        let original = try candidate(seed)
        let request = exactBytes
            ? try ObservationSourceReservationRequest(audio: .init(savedBody: Data("\n".utf8) + original.input + Data(" ".utf8)))
            : original
        let staged = try Store.stageAudio(request: request, proof: .audio(seed.proof), container: seed.container, isCurrent: { true })
        let claim = try Store.claim(staged, admission: .initial, proof: .audio(seed.proof), container: seed.container, isCurrent: { true })
        return try Store.settle(claim, reply: ObservationSourceStoreTests().reply(claim.snapshot, state: "reserved"),
            proof: .audio(seed.proof), container: seed.container, isCurrent: { true })
    }

    @Test func explicitReservedBindingPreservesBytesAndConsumedReplay() async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let source = try reserved(seed, exactBytes: true)
        let intent = try ObservationAudioExecutionIntent(reserved: source.work)
        #expect(intent.request.body == source.work.request.input)
        #expect(intent.request.body != (try candidate(seed).input))
        let bound = try ObservationAudioExecutionStore.bindReserved(intent, source: source, proof: seed.proof,
            authorization: fixture.authorization, container: seed.container, isCurrent: { true })
        let claim = try ObservationAudioExecutionStore.claim(bound, purpose: .initial, proof: seed.proof,
            container: seed.container, isCurrent: { true })
        let permit = try ObservationAudioExecutionStore.consume(claim, proof: seed.proof, container: seed.container, isCurrent: { true })
        let revoked = IdentificationDispatchAuthorization(recipient: .recoveryOnly, validate: { throw MerianError.aiConsentRequired })
        let replay = try ObservationAudioExecutionStore.bindReserved(intent, source: source, proof: seed.proof,
            authorization: revoked, container: seed.container, isCurrent: { true })
        #expect(replay == permit.snapshot && replay.work.consumedAttempt == 1)
        #expect(try Data(contentsOf: seed.file) == seed.bytes)
        #expect(throws: (any Error).self) {
            try ObservationAudioExecutionStore.bindReserved(.init(preparation: seed.preparation), source: source, proof: seed.proof,
                authorization: fixture.authorization, container: seed.container, isCurrent: { true })
        }
    }

    @Test(arguments: [false, true])
    func reservedBindingSaveUncertaintyRetainsOriginalBytes(committed: Bool) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let source = try reserved(seed, exactBytes: true), intent = try ObservationAudioExecutionIntent(reserved: source.work)
        #expect(throws: (any Error).self) {
            try ObservationAudioExecutionStore.bindReserved(intent, source: source, proof: seed.proof,
                authorization: fixture.authorization, container: seed.container, isCurrent: { true }, save: {
                    if committed { try $0.save() }; throw CocoaError(.fileWriteUnknown)
                })
        }
        if !committed { #expect(try Store.read(source.identity, container: seed.container, isCurrent: { true }) == source) }
        let saved = try ObservationAudioExecutionStore.bindReserved(intent, source: source, proof: seed.proof,
            authorization: fixture.authorization, container: seed.container, isCurrent: { true })
        #expect(saved.work.intent == intent && saved.work.state == .idle && saved.work.consumedAttempt == nil)
    }

    @Test(arguments: ["consent", "account", "container", "cas"])
    func reservedBindingRevalidatesBeforeReplacingSource(_ reason: String) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let source = try reserved(seed), intent = try ObservationAudioExecutionIntent(reserved: source.work)
        var current = true
        let authorization = IdentificationDispatchAuthorization(recipient: .gemini, validate: {
            if reason == "consent" { throw MerianError.aiConsentRequired }
            if reason == "account" { current = false }
            if reason == "cas" {
                let context = ModelContext(seed.container)
                let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
                let changed = try Work(preparation: source.work.preparation, request: source.work.request,
                    state: .observed, generation: source.work.generation + 1, reply: source.work.reply)
                job.metadataJSON = try #require(String(bytes: changed.storedData(), encoding: .utf8))
                try context.save()
            }
        })
        let container = reason == "container" ? try ObservationReanalysisSourceTests().fixture.container() : seed.container
        #expect(throws: (any Error).self) {
            try ObservationAudioExecutionStore.bindReserved(intent, source: source, proof: seed.proof,
                authorization: authorization, container: container, isCurrent: { current })
        }
        #expect(try Store.read(source.identity, container: seed.container, isCurrent: { true }).work.request == source.work.request)
    }

}
