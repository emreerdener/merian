import CryptoKit
import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAudioPreparationTests {
    let fixture = ObservationReanalysisProducerTests()
    struct Seed {
        let container: ModelContainer
        let source: ObservationReanalysisSource
        let preparation: ObservationAudioPreparation
        let bytes: Data
        let root: URL
        var file: URL { root.appendingPathComponent(preparation.path) }
        var proof: ObservationAudioPreparation.Verified { get throws { try preparation.verified(source: source) } }
    }
    func seed() throws -> Seed {
        let original = try fixture.fixture.seed(version: 3), source = try fixture.source(original)
        let bytes = makeInferenceTestPCM16WAVData(sampleRate: 44_100, frameCount: 16, sampleAt: { Int16($0) })
        let child = UUID(), media = UUID()
        let uploaded = try ObservationAudioEvidenceUpload(observationID: source.observationID, analysisID: child, mediaID: media, bytes: bytes).prepare()
        let preparation = try ObservationAudioPreparation(identity: .init(observationID: source.observationID,
            sourceAnalysisID: source.analysisID, analysisID: child, ownerID: source.ownerID),
            evidence: [.description("Before"), .audio(uploaded.reference), .description("After")], source: source)
        return try Seed(container: original.container, source: source, preparation: preparation, bytes: bytes,
            root: ObservationReanalysisFileStoreTests().directory())
    }
    func phase(_ seed: Seed) throws -> ObservationAudioPreparation.Phase {
        try ObservationAudioPreparationStore.begin(seed.proof, container: seed.container, isCurrent: { true })
    }
    func producer(_ seed: Seed) -> ObservationAudioPreparationProducer {
        .init(files: .init(documents: seed.root), ownership: .init(), account: fixture.account())
    }

    @Test func preparationOwnsExactWAVAndDoesNotEnterPhotoOrLegacyExecution() async throws {
        let seed = try seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let result = try await producer(seed).prepare(seed.preparation, source: seed.source, bytes: seed.bytes,
            container: seed.container, isCurrent: { true })
        #expect(result == .ready)
        #expect(try Data(contentsOf: seed.file) == seed.bytes)
        let context = ModelContext(seed.container)
        let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        #expect(row.inferenceImagePaths == nil && row.serializedCapturedMediaItems == seed.preparation.media)
        #expect(!row.permitsOrdinaryInference)
        #expect(try ObservationReanalysisAdmissionStore.candidates(ownerID: seed.source.ownerID, canPreflight: true,
            now: Date(), container: seed.container, isCurrent: { true }).isEmpty)
        #expect(try ObservationReanalysisExecutionStore.candidates(ownerID: seed.source.ownerID,
            container: seed.container, isCurrent: { true }).isEmpty)
        #expect(throws: (any Error).self) { try ObservationReanalysisPersistence.restore(row: row, job: job) }
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == seed.source.analysisID.uuidString.lowercased() && parent.observationStateRevision == 10)
        // A new owner models reopening; it recovers the same held child without reminting.
        #expect(try await producer(seed).prepare(seed.preparation, source: seed.source, bytes: nil,
            container: seed.container, isCurrent: { true }) == .ready)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
    }

    @Test(arguments: ["missing", "changed", "extra", "symlink", "complete"], [false, true])
    func interruptedPreparationOnlyAdoptsExactCompleteCohort(change: String, alreadyReady: Bool) async throws {
        let seed = try seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        #expect(try phase(seed) == .pending)
        try FileManager.default.createDirectory(at: seed.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if change != "missing" { try seed.bytes.write(to: seed.file) }
        if alreadyReady {
            try seed.bytes.write(to: seed.file)
            _ = try await producer(seed).prepare(seed.preparation, source: seed.source, bytes: nil,
                container: seed.container, isCurrent: { true })
            if change == "missing" { try FileManager.default.removeItem(at: seed.file) }
        }
        if change == "changed" { try (seed.bytes + Data([0])).write(to: seed.file) }
        if change == "extra" { try Data([1]).write(to: seed.file.deletingLastPathComponent().appendingPathComponent("extra.wav")) }
        if change == "symlink" {
            try FileManager.default.removeItem(at: seed.file)
            let outside = seed.root.appendingPathComponent("outside.wav"); try seed.bytes.write(to: outside)
            try FileManager.default.createSymbolicLink(at: seed.file, withDestinationURL: outside)
        }
        if change == "complete" {
            #expect(try await producer(seed).prepare(seed.preparation, source: seed.source, bytes: nil,
                container: seed.container, isCurrent: { true }) == .ready)
            #expect(try Data(contentsOf: seed.file) == seed.bytes)
        } else {
            await #expect(throws: (any Error).self) {
                try await producer(seed).prepare(seed.preparation, source: seed.source, bytes: nil,
                    container: seed.container, isCurrent: { true })
            }
            #expect(try phase(seed) == (alreadyReady ? .ready : .pending))
        }
    }

    @Test func failedPromotionRollsBackNewFileButRetainsPendingIdentity() async throws {
        let seed = try seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        #expect(try phase(seed) == .pending)
        let proof = try seed.proof
        await #expect(throws: (any Error).self) {
            try await ObservationReanalysisFileStore(documents: seed.root).persistAudio(preparation: seed.preparation, bytes: seed.bytes,
                validateBeforeWrite: { try ObservationAudioPreparationStore.validate(proof, container: seed.container, isCurrent: { true }) }) {
                try ObservationAudioPreparationStore.validate(proof, container: seed.container, isCurrent: { true }, makeReady: true,
                    save: { _ in throw CocoaError(.fileWriteUnknown) })
            }
        }
        #expect(!FileManager.default.fileExists(atPath: seed.file.path))
        #expect(try phase(seed) == .pending)
        #expect(try await producer(seed).prepare(seed.preparation, source: seed.source, bytes: seed.bytes,
            container: seed.container, isCurrent: { true }) == .ready)
    }

    @Test func parentErasureDeletesAudioWithDamagedMetadataAndPermanentlyFencesLateProducer() async throws {
        let seed = try seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try await producer(seed).prepare(seed.preparation, source: seed.source, bytes: seed.bytes,
            container: seed.container, isCurrent: { true })
        let context = ModelContext(seed.container)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first); job.metadataJSON = "damaged"
        _ = try ObservationReanalysisErasure.removeChildren(of: seed.source.observationID.uuidString.lowercased(), context: context)
        try context.save()
        await #expect(throws: (any Error).self) {
            try await producer(seed).prepare(seed.preparation, source: seed.source, bytes: seed.bytes,
                container: seed.container, isCurrent: { true })
        }
        let receipt = try #require(try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(seed.preparation.identity.analysisID)))
        #expect(try ObservationReanalysisErasureReceipt.restore(receipt).parentID == seed.source.observationID)
        try await ObservationReanalysisFileStore(documents: seed.root).erase(child: seed.preparation.identity.analysisID,
            authorize: { true }, acknowledge: {})
        #expect(!FileManager.default.fileExists(atPath: seed.file.path))
    }

    @Test(arguments: ["version", "kind", "requested_action", "source_snapshot_sha256", "extra"])
    func malformedEnvelopeCannotBecomeReadyOrExecutable(key: String) throws {
        let seed = try seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        var row = try #require(JSONSerialization.jsonObject(with: seed.preparation.storedData(phase: .pending)) as? [String: Any])
        row[key] = key == "version" ? true : "invalid"
        #expect(throws: (any Error).self) { try ObservationAudioPreparation.decode(JSONSerialization.data(withJSONObject: row)) }
    }

    @Test func accountLossWithholdsReadyResultAndReleasesLeaseWithoutDiscard() async throws {
        let seed = try seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        var released = 0
        let current: @MainActor @Sendable () -> Bool = {
            let context = ModelContext(seed.container)
            guard let job = try? context.fetch(FetchDescriptor<OfflineJobRecord>()).first,
                  let text = job.metadataJSON, let decoded = try? ObservationAudioPreparation.decode(Data(text.utf8)) else { return true }
            return decoded.phase == .pending
        }
        let producer = ObservationAudioPreparationProducer(files: .init(documents: seed.root), ownership: .init(),
            account: fixture.account(current: current, finish: { released += 1 }))
        await #expect(throws: ObservationHistoryError.accountChanged) {
            try await producer.prepare(seed.preparation, source: seed.source, bytes: seed.bytes, container: seed.container, isCurrent: { true })
        }
        #expect(released == 1)
        #expect(try phase(seed) == .ready)
        #expect(try Data(contentsOf: seed.file) == seed.bytes)
    }

    @Test func diskRestartRecoversTheSamePendingChildAndOrderedEvidence() async throws {
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("queue.store")
        let saved: (ObservationReanalysisSource, ObservationAudioPreparation, Data) = try autoreleasepool {
            let original = try fixture.fixture.seed(version: 3, url: url), source = try fixture.source(original)
            let bytes = makeInferenceTestPCM16WAVData(sampleRate: 44_100, frameCount: 16, sampleAt: { Int16($0) })
            let child = UUID()
            let upload = try ObservationAudioEvidenceUpload(observationID: source.observationID, analysisID: child, mediaID: UUID(), bytes: bytes).prepare()
            let preparation = try ObservationAudioPreparation(identity: .init(observationID: source.observationID,
                sourceAnalysisID: source.analysisID, analysisID: child, ownerID: source.ownerID),
                evidence: [.description("Before"), .audio(upload.reference), .description("After")], source: source)
            _ = try ObservationAudioPreparationStore.begin(preparation.verified(source: source), container: original.container, isCurrent: { true })
            let file = root.appendingPathComponent(preparation.path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: file)
            return (source, preparation, bytes)
        }
        let container = try fixture.fixture.fixture.container(url: url, seed: false)
        let reopened = Seed(container: container, source: saved.0, preparation: saved.1, bytes: saved.2, root: root)
        #expect(try await producer(reopened).prepare(saved.1, source: saved.0, bytes: nil, container: container, isCurrent: { true }) == .ready)
        let context = ModelContext(container)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        let data = Data(try #require(job.metadataJSON).utf8)
        let decoded = try ObservationAudioPreparation.decode(data)
        #expect(decoded.preparation == saved.1 && decoded.phase == .ready)
        #expect(try Data(contentsOf: reopened.file) == saved.2)
    }

    @Test(arguments: ["json", "entries", "image", "attempt", "owner", "digest"])
    func damagedPersistedOwnershipNeverReplays(field: String) throws {
        let seed = try seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try phase(seed)
        let context = ModelContext(seed.container)
        let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        switch field {
        case "json": row.capturedMediaJSON = "damaged"
        case "entries": row.capturedMediaEntries = []
        case "image": row.inferenceImagePaths = [seed.preparation.path]
        case "attempt": job.attemptCount = 1
        case "owner": row.reanalysisOwnerAccountID = UUID().uuidString.lowercased()
        default:
            let data = try seed.preparation.storedData(phase: .pending)
            var body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            body["source_snapshot_sha256"] = String(repeating: "0", count: 64)
            job.metadataJSON = String(bytes: try JSONSerialization.data(withJSONObject: body), encoding: .utf8)
        }
        try context.save()
        #expect(throws: (any Error).self) { try phase(seed) }
    }


    @Test func childAudioCannotReuseHistoricalPhotoIdentity() throws {
        let original = try fixture.fixture.seed(version: 2), source = try fixture.source(original)
        let media = try #require(source.photos.first).mediaID
        let child = UUID(), bytes = makeInferenceTestPCM16WAVData(sampleRate: 44_100, frameCount: 1, sampleAt: { _ in 0 })
        let upload = try ObservationAudioEvidenceUpload(observationID: source.observationID, analysisID: child, mediaID: media, bytes: bytes).prepare()
        #expect(throws: (any Error).self) {
            try ObservationAudioPreparation(identity: .init(observationID: source.observationID, sourceAnalysisID: source.analysisID,
                analysisID: child, ownerID: source.ownerID), evidence: [.audio(upload.reference)], source: source)
        }
    }

}
