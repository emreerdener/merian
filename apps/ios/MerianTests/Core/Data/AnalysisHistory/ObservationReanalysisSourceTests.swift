import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisSourceTests {
    let fixture = ObservationPublicationPersistenceTests()

    struct Seed {
        let container: ModelContainer
        let result: ObservationHistoryPage.Result
        let observationID: UUID
    }

    func seed(version: Int = 2, url: URL? = nil) throws -> Seed {
        let file = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/page-v\(version == 4 ? 2 : version).json")
        let page = try #require(JSONSerialization.jsonObject(with: Data(file.utf8)) as? [String: Any])
        let item = try #require((page["items"] as? [[String: Any]])?.first)
        let bytes = try version == 4 ? JSONSerialization.data(withJSONObject: ObservationHistorySyncTests().audioSnapshot()) : Data(#require(item["snapshot"] as? String).utf8)
        let snapshot = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let observation = try #require(snapshot["observation_id"] as? String)
        let result = try ObservationHistoryPage.snapshot(bytes, observationID: observation,
            ordinal: ObservationHistoryPage.integer(snapshot["ordinal"]))
        let container = try fixture.container(url: url, seed: false), context = ModelContext(container)
        let parent = LocalScanRecord(id: observation, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        parent.analysisOwnerAccountID = fixture.owner.uuidString.lowercased()
        parent.selectedAnalysisID = result.analysisID.uuidString.lowercased()
        parent.analysisSelectionInitialized = true; parent.observationStateRevision = 10
        context.insert(parent)
        let record = try LocalAnalysisRecord(analysisID: result.analysisID, observationID: observation, ownerAccountID: fixture.owner,
            completedAt: result.completedAt, snapshotVersion: result.version, resultSnapshotData: bytes)
        context.insert(record); parent.analysisRecords = [record]; try context.save()
        return Seed(container: container, result: result, observationID: try #require(UUID(uuidString: observation)))
    }

    @Test(arguments: [1, 2, 3])
    func frozenSourceSurvivesSelectionAndReviewRevisionChanges(version: Int) throws {
        let seed = try seed(version: version)
        let source = try ObservationReanalysisSource.capture(observationID: seed.observationID, ownerID: fixture.owner, container: seed.container)
        let context = ModelContext(seed.container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        parent.selectedAnalysisID = UUID().uuidString.lowercased(); parent.observationStateRevision = 11
        try context.save()
        try source.validate(container: seed.container)
        #expect(source.analysisID == seed.result.analysisID && source.snapshot == seed.result.bytes)
        #expect(source.photos == seed.result.photos)
        if version != 2 { #expect(source.photos.isEmpty && source.evidence.isEmpty) }
        #expect(throws: (any Error).self) {
            try ObservationReanalysisSource.capture(observationID: seed.observationID, ownerID: fixture.owner, container: seed.container)
        }
    }

    @Test func immutableEvidenceKeepsDescriptionsAndPhotoOrder() throws {
        let observationID = UUID(), analysisID = UUID(), first = UUID(), second = UUID()
        func photo(_ id: UUID) -> [String: Any] {
            ["kind": "image", "media_id": id.uuidString.lowercased(), "content_type": "image/png",
             "byte_count": 12, "sha256": String(repeating: "a", count: 64)]
        }
        let manifest: [String: Any] = ["schema_version": 2, "items": [
            ["kind": "description", "text": "  First retained note  "], photo(second),
            ["kind": "description", "text": "Between photos"], photo(first),
            ["kind": "description", "text": "Last note"]
        ]]
        let evidence = try ObservationHistoryPhotoReference.decodeEvidence(manifest, observationID: observationID, analysisID: analysisID)
        let photos = try ObservationHistoryPhotoReference.decodeManifest(manifest, observationID: observationID, analysisID: analysisID)
        #expect(evidence == [.description("  First retained note  "), .photo(photos[0]),
                             .description("Between photos"), .photo(photos[1]), .description("Last note")])
        #expect(photos.map(\.mediaID) == [second, first])
        var invalid = manifest
        invalid["items"] = [["kind": "description", "text": " "], photo(first)]
        #expect(throws: (any Error).self) {
            try ObservationHistoryPhotoReference.decodeEvidence(invalid, observationID: observationID, analysisID: analysisID)
        }
        invalid["items"] = [["kind": "description", "text": "Note", "url": "unexpected"], photo(first)]
        #expect(throws: (any Error).self) {
            try ObservationHistoryPhotoReference.decodeEvidence(invalid, observationID: observationID, analysisID: analysisID)
        }
    }

    @Test(arguments: ["owner", "deleted-parent", "deleted-source", "pending-delete", "enrollment", "changed-bytes"], [2, 4])
    func frozenSourceFailsClosedAfterInvalidation(reason: String, version: Int) throws {
        let seed = try seed(version: version)
        let source = try ObservationReanalysisSource.captureForAudio(observationID: seed.observationID, ownerID: fixture.owner, container: seed.container)
        let context = ModelContext(seed.container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let record = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        switch reason {
        case "owner": parent.analysisOwnerAccountID = UUID().uuidString.lowercased()
        case "deleted-parent": context.delete(parent)
        case "deleted-source": context.delete(record)
        case "pending-delete": context.insert(PendingCloudDeletionTask(scanId: parent.id))
        case "enrollment":
            _ = try ObservationHistoryEnrollmentIntent.stage(observationID: seed.observationID, ownerID: fixture.owner, context: context)
        default:
            // Even semantically equivalent replacement bytes must not replace the frozen snapshot.
            let object = try JSONSerialization.jsonObject(with: seed.result.bytes)
            let replacement = try LocalAnalysisRecord(analysisID: seed.result.analysisID, observationID: parent.id, ownerAccountID: fixture.owner,
                completedAt: record.completedAt, snapshotVersion: record.snapshotVersion,
                resultSnapshotData: JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]))
            context.delete(record); try context.save()
            context.insert(replacement); parent.analysisRecords = [replacement]
        }
        try context.save()
        #expect(throws: (any Error).self) { try source.validate(container: seed.container) }
    }
    @Test func audioSourceRetainsAuthorityWithoutBecomingAnEmptyPhotoSource() throws {
        let seed = try seed(version: 4)
        #expect(throws: (any Error).self) {
            try ObservationReanalysisSource.capture(observationID: seed.observationID, ownerID: fixture.owner, container: seed.container)
        }
        let source = try ObservationReanalysisSource.captureForAudio(observationID: seed.observationID,
            ownerID: fixture.owner, container: seed.container)
        #expect(source.audio == seed.result.audio && source.audio != nil)
        #expect(source.snapshot == seed.result.bytes && source.photos.isEmpty && source.evidence.isEmpty)
        #expect(throws: (any Error).self) { try CaptureReanalysisEvidenceSelection(source: source, selectedPhotoIDs: []) }
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPreparationPlan(source: source, choices: [.photo(.added(Data([1])))])
        }
        let context = ModelContext(seed.container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        parent.selectedAnalysisID = UUID().uuidString.lowercased(); parent.observationStateRevision = 11
        try context.save()
        try source.validate(container: seed.container)
        #expect(try ObservationReanalysisSource.captureForAudio(observationID: seed.observationID,
            analysisID: source.analysisID, ownerID: fixture.owner, container: seed.container) == source)
        let bytes = makeInferenceTestPCM16WAVData(sampleRate: 44_100, frameCount: 16, sampleAt: { Int16($0) })
        let plan = try CaptureAudioReanalysisPlan(source: source, choices: [.description("Explicit new note"), .audio(bytes)])
        let verified = try plan.verify()
        #expect(verified.bytes == bytes && verified.proof.preparation.identity.sourceAnalysisID == source.analysisID)
        #expect(verified.proof.preparation.audio.mediaID != source.audio?.mediaID)
        #expect(throws: (any Error).self) {
            try ObservationAudioPreparation(identity: verified.proof.preparation.identity,
                evidence: [.audio(#require(source.audio))], source: source, action: .submit)
        }
    }

    @Test func audioSourceAndPendingProofRecoverAfterDiskReopen() async throws {
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("source.store")
        let seed = try seed(version: 4, url: url)
        let source = try ObservationReanalysisSource.captureForAudio(observationID: seed.observationID,
            ownerID: fixture.owner, container: seed.container)
        let bytes = makeInferenceTestPCM16WAVData(sampleRate: 44_100, frameCount: 16, sampleAt: { Int16($0) })
        let plan = try CaptureAudioReanalysisPlan(source: source, choices: [.audio(bytes)])
        let proof = try plan.verify().proof
        _ = try ObservationAudioPreparationStore.begin(proof, container: seed.container, isCurrent: { true })
        let reopened = try fixture.container(url: url, seed: false)
        let saved = try await ObservationAudioResumeStore.read(proof.preparation.identity, container: reopened, isCurrent: { true })
        #expect(saved.source == source && saved.proof.preparation == proof.preparation)
        guard case .preparation(.pending) = saved.state else { Issue.record("Pending proof changed on reopening"); return }
    }

}
