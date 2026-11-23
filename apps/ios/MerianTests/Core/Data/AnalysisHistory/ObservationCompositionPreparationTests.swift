import CryptoKit
import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationCompositionPreparationTests {
    struct Seed {
        let root: URL
        let database: URL
        let container: ModelContainer
        let source: ObservationReanalysisSource
        let preparation: ObservationCompositionPreparation
        let payloads: [Data]
        var payload: ObservationCompositionPayload { get throws {
            try .prepare(request: preparation.request, standalone: Dictionary(uniqueKeysWithValues:
                zip(preparation.files.map(\.artifact.mediaID), payloads)))
        } }
        var proof: ObservationCompositionPreparation.Verified { get throws { try preparation.verified(source: source) } }
        func removeFiles() { try? FileManager.default.removeItem(at: root.appendingPathComponent("ReanalysisQueue")) }
    }
    func seed(version: Int = 5) throws -> Seed {
        let root = try ObservationReanalysisFileStoreTests().directory(), url = root.appendingPathComponent("history.store")
        let fixture = ObservationReanalysisSourceTests(), history = try fixture.seed(version: version, url: url)
        let source = try ObservationReanalysisSource.capture(observationID: history.observationID,
            ownerID: fixture.fixture.owner, container: history.container)
        let photo = try ObservationReanalysisProducerTests().image()
        let audio = makeInferenceTestPCM16WAVData(sampleRate: 44_100, frameCount: 32, sampleAt: { Int16($0) })
        func item(_ data: Data, kind: String, type: String) -> [String: Any] {
            ["kind": kind, "artifact": ["media_id": UUID().uuidString.lowercased(), "content_type": type,
                "byte_count": data.count, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]]
        }
        let manifest: [String: Any] = ["schema_version": 5, "items": [
            item(photo, kind: "image", type: "image/png"), ["kind": "description", "text": "  Exact e\u{301} 🐾\n"],
            item(audio, kind: "audio", type: "audio/wav")
        ]]
        let request = try ObservationCompositionReanalysisRequest(observationID: source.observationID,
            analysisID: UUID(), sourceAnalysisID: source.analysisID, manifestBytes: JSONSerialization.data(withJSONObject: manifest))
        return Seed(root: root, database: url, container: history.container, source: source,
            preparation: try .init(request: request, source: source), payloads: [photo, audio])
    }
    func producer(_ seed: Seed) -> ObservationCompositionProducer {
        .init(files: .init(documents: seed.root), ownership: .init(), account: ObservationReanalysisProducerTests().account())
    }

    @Test(arguments: [1, 2, 3, 4, 5]) func completeCompositionReopensAsOneHeldChild(version: Int) async throws {
        let seed = try seed(version: version); defer { seed.removeFiles() }
        #expect(try await producer(seed).prepare(seed.preparation, source: seed.source, payload: seed.payload,
            container: seed.container, isCurrent: { true }) == .ready)
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.database, seed: false)
        #expect(try await producer(seed).prepare(seed.preparation, source: seed.source, payload: nil,
            container: reopened, isCurrent: { true }) == .ready)
        let context = ModelContext(reopened)
        let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(!row.permitsOrdinaryInference && row.queueAttemptCount == 0 && row.queueNeedsAttention)
        #expect(row.serializedCapturedMediaItems == seed.preparation.media)
        #expect(try ObservationCompositionPreparation.decode(Data(#require(job.metadataJSON).utf8)).preparation == seed.preparation)
        #expect(throws: (any Error).self) { try ObservationReanalysisPersistence.restore(row: row, job: job) }
        #expect(try ObservationReanalysisAdmissionStore.candidates(ownerID: seed.source.ownerID, canPreflight: true,
            now: Date(), container: reopened, isCurrent: { true }).isEmpty)
        await #expect(throws: (any Error).self) {
            try await ObservationAudioResumeStore.read(seed.preparation.identity, container: reopened, isCurrent: { true })
        }
        await #expect(throws: (any Error).self) {
            try await ObservationVideoResumeStore().read(seed.preparation.identity, container: reopened, isCurrent: { true })
        }
        for (file, bytes) in zip(seed.preparation.files, seed.payloads) {
            #expect(try Data(contentsOf: seed.root.appendingPathComponent(file.path)) == bytes)
        }
        try seed.source.validate(container: reopened)
    }

    @Test func uncertainPromotionPreservesExactCohortAndDoesNotCreateAnotherChild() async throws {
        let seed = try seed(); defer { seed.removeFiles() }
        let proof = try seed.proof, files = ObservationReanalysisFileStore(documents: seed.root)
        #expect(try ObservationCompositionPreparationStore.begin(proof, container: seed.container, isCurrent: { true }) == .pending)
        await #expect(throws: CocoaError.self) {
            let _: Void = try await files.persistComposition(preparation: seed.preparation, payload: seed.payload,
                validateBeforeWrite: { try ObservationCompositionPreparationStore.validate(proof, container: seed.container, isCurrent: { true }) },
                commit: {
                    try ObservationCompositionPreparationStore.validate(proof, container: seed.container, isCurrent: { true }, makeReady: true)
                    throw CocoaError(.fileWriteUnknown)
                })
        }
        #expect(try await producer(seed).prepare(seed.preparation, source: seed.source, payload: nil,
            container: seed.container, isCurrent: { true }) == .ready)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        let decoded = try ObservationCompositionPreparation.decode(seed.preparation.storedData(phase: .ready))
        #expect(decoded.preparation.request.body == seed.preparation.request.body)
    }

    @Test func missingMemberAndChangedAccountCannotRegenerateOrPromote() async throws {
        let seed = try seed(); defer { seed.removeFiles() }
        _ = try await producer(seed).prepare(seed.preparation, source: seed.source, payload: seed.payload,
            container: seed.container, isCurrent: { true })
        let photo = seed.root.appendingPathComponent(seed.preparation.files[0].path)
        try FileManager.default.removeItem(at: photo)
        await #expect(throws: (any Error).self) {
            try await producer(seed).prepare(seed.preparation, source: seed.source, payload: nil, container: seed.container, isCurrent: { true })
        }
        // A ready replay cannot repair missing evidence even if a caller retained buffers.
        await #expect(throws: (any Error).self) {
            try await producer(seed).prepare(seed.preparation, source: seed.source, payload: seed.payload, container: seed.container, isCurrent: { true })
        }
        await #expect(throws: (any Error).self) {
            try await producer(seed).prepare(seed.preparation, source: seed.source, payload: nil, container: seed.container, isCurrent: { false })
        }
        #expect(!FileManager.default.fileExists(atPath: photo.path))
        #expect(try Data(contentsOf: seed.root.appendingPathComponent(seed.preparation.files[1].path)) == seed.payloads[1])
    }

    @Test func changedFileInventoryAndSourceCannotFabricatePreparationProof() throws {
        let seed = try seed(); defer { seed.removeFiles() }
        var row = try #require(JSONSerialization.jsonObject(with: seed.preparation.storedData(phase: .ready)) as? [String: Any])
        var files = try #require(row["files"] as? [[String: Any]])
        files[0]["path"] = "ReanalysisQueue/another-child/input.png"; row["files"] = files
        #expect(throws: (any Error).self) { try ObservationCompositionPreparation.decode(JSONSerialization.data(withJSONObject: row)) }
        let forged = try ObservationCompositionPreparation(ownerID: seed.source.ownerID, request: seed.preparation.request,
            sourceSnapshotSHA256: String(repeating: "0", count: 64))
        #expect(throws: (any Error).self) { try forged.verified(source: seed.source) }
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }
}

extension ObservationCompositionPreparationTests {
    @Test func retainedVideoAndPhotoUseOneValidatedPayloadAndOneChild() async throws {
        let seed = try await ObservationVideoDurabilityTests().seed(); defer { seed.remove() }
        let video = try await seed.cohort.compositionPayload()
        let photo = try ObservationReanalysisProducerTests().image(), photoID = UUID()
        let manifest = try #require(JSONSerialization.jsonObject(with: video.request.manifest.originalBytes) as? [String: Any])
        let graph = try #require(manifest["provenance"])
        let nodes: [[String: Any]] = [
            ["kind": "description", "text": "Before the clip"], ["kind": "video", "provenance": graph],
            ["kind": "image", "artifact": ["media_id": photoID.uuidString.lowercased(), "content_type": "image/png",
                "byte_count": photo.count, "sha256": SHA256.hash(data: photo).map { String(format: "%02x", $0) }.joined()]]
        ]
        let bytes = try JSONSerialization.data(withJSONObject: ["schema_version": 5, "items": nodes])
        let request = try ObservationCompositionReanalysisRequest(observationID: seed.source.observationID,
            analysisID: video.request.analysisID, sourceAnalysisID: seed.source.analysisID, manifestBytes: bytes)
        #expect(throws: (any Error).self) { try ObservationCompositionPayload.prepare(request: request, standalone: [photoID: photo]) }
        let differentChild = try ObservationCompositionReanalysisRequest(observationID: seed.source.observationID,
            analysisID: UUID(), sourceAnalysisID: seed.source.analysisID, manifestBytes: bytes)
        #expect(throws: (any Error).self) {
            try ObservationCompositionPayload.prepare(request: differentChild, standalone: [photoID: photo], video: video)
        }
        let payload = try ObservationCompositionPayload.prepare(request: request, standalone: [photoID: photo], video: video)
        let preparation = try ObservationCompositionPreparation(request: request, source: seed.source)
        let producer = ObservationCompositionProducer(files: .init(documents: seed.root), ownership: .init(),
            account: ObservationReanalysisProducerTests().account())
        #expect(try await producer.prepare(preparation, source: seed.source, payload: payload, container: seed.container, isCurrent: { true }) == .ready)
        #expect(try await producer.prepare(preparation, source: seed.source, payload: nil, container: seed.container, isCurrent: { true }) == .ready)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(preparation.files.count == 8 && payload.bytes.count == 8)
        for (file, data) in zip(preparation.files, payload.bytes) {
            #expect(try Data(contentsOf: seed.root.appendingPathComponent(file.path)) == data)
        }
    }

    @Test func matchingHashCannotCertifyMalformedImageAtPreparationOrRecovery() async throws {
        let seed = try seed(); defer { seed.removeFiles() }
        var manifest = try #require(JSONSerialization.jsonObject(with: seed.preparation.request.manifest.originalBytes) as? [String: Any])
        var items = try #require(manifest["items"] as? [[String: Any]])
        var artifact = try #require(items[0]["artifact"] as? [String: Any])
        let invalid = Data([1, 2, 3])
        artifact["byte_count"] = invalid.count
        artifact["sha256"] = SHA256.hash(data: invalid).map { String(format: "%02x", $0) }.joined()
        items[0]["artifact"] = artifact; manifest["items"] = items
        let request = try ObservationCompositionReanalysisRequest(observationID: seed.source.observationID,
            analysisID: seed.preparation.identity.analysisID, sourceAnalysisID: seed.source.analysisID,
            manifestBytes: JSONSerialization.data(withJSONObject: manifest))
        let preparation = try ObservationCompositionPreparation(request: request, source: seed.source), proof = try preparation.verified(source: seed.source)
        let standalone = [preparation.files[0].artifact.mediaID: invalid, preparation.files[1].artifact.mediaID: seed.payloads[1]]
        #expect(throws: (any Error).self) { try ObservationCompositionPayload.prepare(request: request, standalone: standalone) }
        _ = try ObservationCompositionPreparationStore.begin(proof, container: seed.container, isCurrent: { true })
        // Reproduce a pre-fix ready envelope with a matching hash but invalid PNG.
        for file in preparation.files {
            let path = seed.root.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try #require(standalone[file.artifact.mediaID]).write(to: path)
        }
        try ObservationCompositionPreparationStore.validate(proof, container: seed.container, isCurrent: { true }, makeReady: true)
        await #expect(throws: (any Error).self) {
            try await producer(seed).prepare(preparation, source: seed.source, payload: nil, container: seed.container, isCurrent: { true })
        }
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
    }

    @Test func explicitHeldDiscardCreatesOneCleanupReceiptAndPreservesSource() async throws {
        let seed = try seed(); defer { seed.removeFiles() }
        let producer = producer(seed)
        _ = try await producer.prepare(seed.preparation, source: seed.source, payload: seed.payload, container: seed.container, isCurrent: { true })
        let cleanup = ObservationReanalysisErasureOwner(files: .init(documents: seed.root))
        let receipt = try await producer.discard(seed.preparation, source: seed.source, container: seed.container, cleanup: cleanup, isCurrent: { true })
        #expect(try await producer.discard(seed.preparation, source: seed.source, container: seed.container, cleanup: cleanup, isCurrent: { true }) == receipt)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: seed.root.appendingPathComponent("ReanalysisQueue/" + seed.preparation.identity.analysisID.uuidString.lowercased()).path).isEmpty)
        try seed.source.validate(container: seed.container)
    }
}
