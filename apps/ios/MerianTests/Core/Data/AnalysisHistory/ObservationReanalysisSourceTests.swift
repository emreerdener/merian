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

    func seed(version: Int = 2) throws -> Seed {
        let file = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/page-v\(version).json")
        let page = try #require(JSONSerialization.jsonObject(with: Data(file.utf8)) as? [String: Any])
        let item = try #require((page["items"] as? [[String: Any]])?.first)
        let bytes = Data(try #require(item["snapshot"] as? String).utf8)
        let snapshot = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let observation = try #require(snapshot["observation_id"] as? String)
        let result = try ObservationHistoryPage.snapshot(bytes, observationID: observation,
            ordinal: ObservationHistoryPage.integer(snapshot["ordinal"]))
        let container = try fixture.container(seed: false), context = ModelContext(container)
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
        if version != 2 { #expect(source.photos.isEmpty) }
        #expect(throws: (any Error).self) {
            try ObservationReanalysisSource.capture(observationID: seed.observationID, ownerID: fixture.owner, container: seed.container)
        }
    }

    @Test(arguments: ["owner", "deleted-parent", "deleted-source", "pending-delete", "enrollment", "changed-bytes"])
    func frozenSourceFailsClosedAfterInvalidation(reason: String) throws {
        let seed = try seed()
        let source = try ObservationReanalysisSource.capture(observationID: seed.observationID, ownerID: fixture.owner, container: seed.container)
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
}
