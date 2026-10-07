import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAudioExecutionStoreTests {
    typealias Store = ObservationAudioExecutionStore
    let fixture = ObservationAudioPreparationTests()
    let authorization = IdentificationDispatchAuthorization(recipient: .gemini, validate: {})

    func ready() async throws -> ObservationAudioPreparationTests.Seed {
        let seed = try fixture.seed(action: .submit)
        _ = try await fixture.producer(seed).prepare(seed.preparation, source: seed.source, bytes: seed.bytes,
            container: seed.container, isCurrent: { true })
        return seed
    }
    func bind(_ seed: ObservationAudioPreparationTests.Seed) throws -> Store.Snapshot {
        try Store.bind(.init(preparation: seed.preparation), proof: seed.proof, authorization: authorization,
            container: seed.container, isCurrent: { true })
    }

    @Test func exactBindingAndRecoveryNeverResetConsumedAuthority() async throws {
        let seed = try await ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let proof = try seed.proof, initial = try bind(seed)
        let first = try Store.claim(initial, purpose: .initial, proof: proof, container: seed.container, isCurrent: { true })
        let consumed = try Store.consume(first, proof: proof, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Store.validate(first, proof: proof, container: seed.container, isCurrent: { true }) }
        try Store.validateDispatch(consumed, proof: proof, container: seed.container, isCurrent: { true })
        #expect(try bind(seed) == consumed.snapshot)
        let revoked = IdentificationDispatchAuthorization(recipient: .recoveryOnly, validate: { throw MerianError.aiConsentRequired })
        #expect(try Store.bind(initial.work.intent, proof: proof, authorization: revoked,
            container: seed.container, isCurrent: { true }) == consumed.snapshot)
        #expect(throws: (any Error).self) {
            try Store.claim(consumed.snapshot, purpose: .recovery, proof: proof, container: seed.container, isCurrent: { true })
        }
        try Store.hold(consumed.claim, proof: proof, container: seed.container, isCurrent: { true })
        let held = try Store.read(proof, container: seed.container, isCurrent: { true })
        #expect(held.work.state == .held && held.work.consumedAttempt == 1)
        #expect(throws: (any Error).self) {
            try Store.claim(held, purpose: .initial, proof: proof, container: seed.container, isCurrent: { true })
        }
        #expect(throws: (any Error).self) {
            try Store.validateDispatch(consumed, proof: proof, container: seed.container, isCurrent: { true })
        }
        let recovery = try Store.claim(held, purpose: .recovery, proof: proof, container: seed.container, isCurrent: { true })
        #expect(recovery.snapshot.work.attempt == 2 && recovery.snapshot.work.consumedAttempt == 1)
        #expect(recovery.snapshot.work.intent.request.body == initial.work.intent.request.body)
        #expect(throws: (any Error).self) { try Store.consume(recovery, proof: proof, container: seed.container, isCurrent: { true }) }
        #expect(try ObservationReanalysisExecutionStore.candidates(ownerID: seed.source.ownerID,
            container: seed.container, isCurrent: { true }).isEmpty)
        #expect(try ObservationReanalysisAdmissionStore.candidates(ownerID: seed.source.ownerID, canPreflight: true,
            now: Date(), container: seed.container, isCurrent: { true }).isEmpty)
        let parent = try #require(ModelContext(seed.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == seed.source.analysisID.uuidString.lowercased())
    }

    @Test func replacementBeforeConsumptionInvalidatesTheOldClaim() async throws {
        let seed = try await ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let proof = try seed.proof, initial = try bind(seed)
        let first = try Store.claim(initial, purpose: .initial, proof: proof, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) {
            try Store.claim(first.snapshot, purpose: .initial, proof: proof, container: seed.container, isCurrent: { true })
        }
        try Store.hold(first, proof: proof, container: seed.container, isCurrent: { true })
        let held = try Store.read(proof, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) {
            try Store.claim(held, purpose: .initial, proof: proof, container: seed.container, isCurrent: { true })
        }
        let replacement = try Store.resumeUndispatched(held, proof: proof, authorization: authorization,
            container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Store.consume(first, proof: proof, container: seed.container, isCurrent: { true }) }
        let consumed = try Store.consume(replacement, proof: proof, container: seed.container, isCurrent: { true })
        #expect(consumed.snapshot.work.consumedAttempt == 2)
        #expect(throws: (any Error).self) { try Store.consume(consumed.claim, proof: proof, container: seed.container, isCurrent: { true }) }
    }

    @Test(arguments: [false, true])
    func consumedSaveAmbiguityNeverReturnsPermission(committed: Bool) async throws {
        let seed = try await ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let proof = try seed.proof
        let claim = try Store.claim(bind(seed), purpose: .initial, proof: proof, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) {
            try Store.consume(claim, proof: proof, container: seed.container, isCurrent: { true }, save: { context in
                if committed { try context.save() }
                throw CocoaError(.fileWriteUnknown)
            })
        }
        let saved = try Store.read(proof, container: seed.container, isCurrent: { true })
        #expect(saved.work.consumedAttempt == (committed ? 1 : nil))
        if committed {
            #expect(throws: (any Error).self) { try Store.consume(claim, proof: proof, container: seed.container, isCurrent: { true }) }
            #expect(throws: (any Error).self) {
                try Store.claim(saved, purpose: .initial, proof: proof, container: seed.container, isCurrent: { true })
            }
        }
    }

    @Test func bindingCommitThenThrowRecoversExactSavedRequest() async throws {
        let seed = try await ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let candidate = try ObservationAudioExecutionIntent(preparation: seed.preparation), proof = try seed.proof
        #expect(throws: (any Error).self) {
            try Store.bind(candidate, proof: proof, authorization: authorization, container: seed.container, isCurrent: { true }, save: { context in
                try context.save(); throw CocoaError(.fileWriteUnknown)
            })
        }
        let saved = try Store.read(proof, container: seed.container, isCurrent: { true })
        #expect(saved.work.intent == candidate && saved.work.state == .idle && saved.work.attempt == 0)
        #expect(try bind(seed) == saved)
    }

    @Test(arguments: ["pending", "recipient", "consent", "account", "source", "deletion"])
    func bindingRequiresSubmittedReadySourceAndCurrentAuthority(denial: String) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.phase(seed)
        if denial != "pending" {
            _ = try await fixture.producer(seed).prepare(seed.preparation, source: seed.source, bytes: seed.bytes,
                container: seed.container, isCurrent: { true })
        }
        if denial == "source" || denial == "deletion" {
            let context = ModelContext(seed.container)
            if denial == "source" {
                let record = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
                context.delete(record)
            } else { _ = try ObservationReanalysisErasure.removeChildren(of: seed.source.observationID.uuidString.lowercased(), context: context) }
            try context.save()
        }
        let grant = IdentificationDispatchAuthorization(recipient: denial == "recipient" ? .openAI : .gemini, validate: {
            if denial == "consent" { throw MerianError.invalidResponse }
        })
        #expect(throws: (any Error).self) {
            try Store.bind(.init(preparation: seed.preparation), proof: seed.proof, authorization: grant,
                container: seed.container, isCurrent: { denial != "account" })
        }
    }

    @Test(arguments: ["owner_id", "source_snapshot_sha256", "state", "attempt", "consumed_attempt", "request_base64", "extra"])
    func damagedBindingNeverClaims(key: String) async throws {
        let seed = try await ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try bind(seed), proof = try seed.proof
        var row = try #require(JSONSerialization.jsonObject(with: Data(saved.metadata.utf8)) as? [String: Any])
        switch key {
        case "owner_id": row[key] = UUID().uuidString.lowercased()
        case "source_snapshot_sha256": row[key] = String(repeating: "0", count: 64)
        case "attempt": row[key] = true
        case "consumed_attempt": row[key] = 1
        default: row[key] = "invalid"
        }
        let context = ModelContext(seed.container), job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        job.metadataJSON = String(data: try JSONSerialization.data(withJSONObject: row), encoding: .utf8)
        try context.save()
        #expect(throws: (any Error).self) { try Store.read(proof, container: seed.container, isCurrent: { true }) }
        #expect(throws: (any Error).self) {
            try Store.claim(saved, purpose: .initial, proof: proof, container: seed.container, isCurrent: { true })
        }
    }

    @Test(arguments: ["rowError", "rowHTTP", "rowServer", "rowRetry", "jobError", "jobHTTP", "jobServer", "jobRetry"])
    func genericExecutionResidueDeniesBindingAndClaims(field: String) async throws {
        let seed = try await ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try bind(seed), proof = try seed.proof
        let context = ModelContext(seed.container)
        let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        switch field {
        case "rowError": row.queueLastErrorCode = "unknown"
        case "rowHTTP": row.queueLastHTTPStatus = 503
        case "rowServer": row.queueLastServerStage = "running"
        case "rowRetry": row.queueLastServerRetryAfter = Date()
        case "jobError": job.lastErrorMessage = "unknown"
        case "jobHTTP": job.lastHTTPStatus = 503
        case "jobServer": job.serverStatus = "running"
        default: job.serverRetryAfter = Date()
        }
        try context.save()
        #expect(throws: (any Error).self) { try bind(seed) }
        #expect(throws: (any Error).self) {
            try Store.claim(saved, purpose: .initial, proof: proof, container: seed.container, isCurrent: { true })
        }
    }

    @Test func diskReopenPreservesConsumedRequestAndDeniesFreshDispatch() throws {
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("queue.store")
        let saved: (ObservationReanalysisSource, ObservationAudioPreparation, Data) = try autoreleasepool {
            let database = ObservationReanalysisSourceTests(), original = try database.seed(version: 3, url: url)
            let source = try ObservationReanalysisProducerTests().source(original)
            let bytes = makeInferenceTestPCM16WAVData(sampleRate: 44_100, frameCount: 16, sampleAt: { Int16($0) })
            let child = UUID()
            let upload = try ObservationAudioEvidenceUpload(observationID: source.observationID, analysisID: child,
                mediaID: UUID(), bytes: bytes).prepare()
            let preparation = try ObservationAudioPreparation(identity: .init(observationID: source.observationID,
                sourceAnalysisID: source.analysisID, analysisID: child, ownerID: source.ownerID),
                evidence: [.audio(upload.reference)], source: source, action: .submit)
            let proof = try preparation.verified(source: source)
            _ = try ObservationAudioPreparationStore.begin(proof, container: original.container, isCurrent: { true })
            // Seed the verified-file boundary; production file-lock behavior has its own integration suite.
            try ObservationAudioPreparationStore.validate(proof, container: original.container, isCurrent: { true }, makeReady: true)
            let initial = try Store.bind(.init(preparation: preparation), proof: proof, authorization: authorization,
                container: original.container, isCurrent: { true })
            let claim = try Store.claim(initial, purpose: .initial, proof: proof, container: original.container, isCurrent: { true })
            let consumed = try Store.consume(claim, proof: proof, container: original.container, isCurrent: { true })
            try Store.hold(consumed.claim, proof: proof, container: original.container, isCurrent: { true })
            return (source, preparation, initial.work.intent.request.body)
        }
        let container = try ObservationReanalysisSourceTests().fixture.container(url: url, seed: false)
        let proof = try saved.1.verified(source: saved.0)
        let reopened = try Store.read(proof, container: container, isCurrent: { true })
        #expect(reopened.work.intent.request.body == saved.2 && reopened.work.consumedAttempt == 1)
        #expect(throws: (any Error).self) { try Store.claim(reopened, purpose: .initial, proof: proof, container: container, isCurrent: { true }) }
        #expect(throws: (any Error).self) {
            try Store.resumeUndispatched(reopened, proof: proof, authorization: authorization, container: container, isCurrent: { true })
        }
        let recovery = try Store.claim(reopened, purpose: .recovery, proof: proof, container: container, isCurrent: { true })
        #expect(recovery.snapshot.work.consumedAttempt == 1)
    }
}
