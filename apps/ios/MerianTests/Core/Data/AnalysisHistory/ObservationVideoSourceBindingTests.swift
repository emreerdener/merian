import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoSourceBindingTests {
    let fixture = ObservationReanalysisSourceTests()

    private func request(_ source: ObservationReanalysisSource, collision: UUID? = nil, artifactIndex: Int = 0,
                         observationID: UUID? = nil, sourceID: UUID? = nil) throws -> ObservationVideoReanalysisRequest {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at: "services/supabase/functions/_shared/analysisHistory/fixtures/video-request-v4.json")
        let vectors = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        let input = try #require(vectors.first?["input"] as? [String: Any])
        let manifest = try #require(input["evidence_manifest"])
        var bytes = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        let child = UUID()
        let parsed = try ObservationVideoManifest(data: bytes, observationID: UUID(), analysisID: child)
        let graph = parsed.provenance
        let originalIDs = [graph.source.mediaID] + graph.frames.map(\.artifact.mediaID) + (graph.audio.map { [$0.artifact.mediaID] } ?? [])
        // Golden fixtures deliberately share small UUIDs with historical fixtures.
        // Fresh evidence must start disjoint; inject only the collision under test.
        let freshIDs = originalIDs.map { _ in UUID() }
        for (original, replacement) in zip(originalIDs, freshIDs) {
            bytes = Data(try #require(String(data: bytes, encoding: .utf8))
                .replacingOccurrences(of: original.uuidString.lowercased(), with: replacement.uuidString.lowercased()).utf8)
        }
        if let collision, artifactIndex >= 0 {
            bytes = Data(try #require(String(data: bytes, encoding: .utf8))
                .replacingOccurrences(of: freshIDs[artifactIndex].uuidString.lowercased(), with: collision.uuidString.lowercased()).utf8)
        }
        return try .init(observationID: observationID ?? source.observationID, analysisID: artifactIndex == -1 ? #require(collision) : child,
                         sourceAnalysisID: sourceID ?? source.analysisID, manifestBytes: bytes)
    }

    @Test(arguments: [1, 2, 3, 4])
    func exactProofSurvivesSelectionAndReviewChanges(version: Int) throws {
        let seed = try fixture.seed(version: version)
        let source = try ObservationReanalysisSource.captureForVideo(observationID: seed.observationID,
            ownerID: fixture.fixture.owner, container: seed.container)
        let preparation = try ObservationVideoPreparation(request: request(source), source: source)
        let restored = try ObservationVideoPreparation.decode(preparation.storedData(phase: .pending)).preparation
        let proof = try restored.verified(source: source)
        let context = ModelContext(seed.container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        parent.selectedAnalysisID = UUID().uuidString.lowercased(); parent.observationStateRevision = 11
        try context.save()
        try proof.validate(container: seed.container)
        try ConfirmedSpeciesReviewPersistence.transaction { try proof.validate(context: ModelContext(seed.container)) }
        #expect(proof.preparation.request.body == preparation.request.body)
        #expect(try ObservationReanalysisSource.captureForVideo(observationID: seed.observationID, analysisID: source.analysisID,
            ownerID: source.ownerID, container: seed.container) == source)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }

    @Test(arguments: ["owner", "parent", "source", "pending-delete", "enrollment", "snapshot"], [2, 4])
    func proofRevalidatesFreshPersistence(reason: String, version: Int) throws {
        let seed = try fixture.seed(version: version)
        let source = try ObservationReanalysisSource.captureForVideo(observationID: seed.observationID,
            ownerID: fixture.fixture.owner, container: seed.container)
        let proof = try ObservationVideoPreparation(request: request(source), source: source).verified(source: source)
        let context = ModelContext(seed.container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let record = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        switch reason {
        case "owner": parent.analysisOwnerAccountID = UUID().uuidString.lowercased()
        case "parent": context.delete(parent)
        case "source": context.delete(record)
        case "pending-delete": context.insert(PendingCloudDeletionTask(scanId: parent.id))
        case "enrollment": _ = try ObservationHistoryEnrollmentIntent.stage(observationID: seed.observationID, ownerID: source.ownerID, context: context)
        default:
            let object = try JSONSerialization.jsonObject(with: source.snapshot)
            let replacement = try LocalAnalysisRecord(analysisID: source.analysisID, observationID: parent.id, ownerAccountID: source.ownerID,
                completedAt: record.completedAt, snapshotVersion: record.snapshotVersion,
                resultSnapshotData: JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]))
            context.delete(record); try context.save()
            context.insert(replacement); parent.analysisRecords = [replacement]
        }
        try context.save()
        #expect(throws: (any Error).self) { try proof.validate(container: seed.container) }
    }

    @Test(arguments: [2, 4])
    func everyNewMediaAndChildIdentityRejectsHistoricalMediaReuse(version: Int) throws {
        let seed = try fixture.seed(version: version)
        let source = try ObservationReanalysisSource.captureForVideo(observationID: seed.observationID,
            ownerID: fixture.fixture.owner, container: seed.container)
        let media = try #require(source.photos.first?.mediaID ?? source.audio?.mediaID)
        for index in -1..<7 {
            let candidate = try request(source, collision: media, artifactIndex: index)
            #expect(throws: (any Error).self) { try ObservationVideoPreparation(request: candidate, source: source) }
        }
    }

    @Test func storedHashOwnerAndRequestScopeCannotFabricateProof() throws {
        let seed = try fixture.seed(version: 2)
        let source = try ObservationReanalysisSource.captureForVideo(observationID: seed.observationID,
            ownerID: fixture.fixture.owner, container: seed.container)
        let preparation = try ObservationVideoPreparation(request: request(source), source: source)
        let variants = [
            try ObservationVideoPreparation(ownerID: UUID(), request: preparation.request, sourceSnapshotSHA256: preparation.sourceSnapshotSHA256),
            try ObservationVideoPreparation(ownerID: source.ownerID, request: preparation.request, sourceSnapshotSHA256: String(repeating: "0", count: 64)),
            try ObservationVideoPreparation(ownerID: source.ownerID, request: request(source, observationID: UUID()), sourceSnapshotSHA256: preparation.sourceSnapshotSHA256),
            try ObservationVideoPreparation(ownerID: source.ownerID, request: request(source, sourceID: UUID()), sourceSnapshotSHA256: preparation.sourceSnapshotSHA256)
        ]
        for variant in variants {
            let restored = try ObservationVideoPreparation.decode(variant.storedData(phase: .ready)).preparation
            #expect(throws: (any Error).self) { try restored.verified(source: source) }
        }
    }
}
