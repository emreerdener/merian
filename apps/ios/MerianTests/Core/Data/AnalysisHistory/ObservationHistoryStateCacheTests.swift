import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct ObservationHistoryStateCacheTests {
    let support = ObservationHistoryStateSyncTests()

    @Test func changedAuthorityWithSameReviewRevisionRollsBackEntireAdmission() async throws {
        let container = try support.container()
        _ = try await support.service(data: support.fixture()).syncSelected(observationID: support.support.observation, container: container)
        var value = try JSONSerialization.jsonObject(with: support.fixture(revision: 12, rejected: true)) as! [String: Any]
        var item = value["analysis"] as! [String: Any]
        item["review_revision"] = 0
        value["analysis"] = item
        let service = support.service(data: try JSONSerialization.data(withJSONObject: value))
        await #expect(throws: LocalAnalysisStateRecord.StorageError.conflictingRevision) {
            try await service.syncSelected(observationID: support.support.observation, container: container)
        }
        let context = ModelContext(container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.observationStateRevision == 11)
        #expect(parent.localAIIdentificationReview.authority == nil)
        let cache = try #require(context.fetch(FetchDescriptor<LocalAnalysisStateRecord>()).first)
        #expect(cache.observationStateRevision == 11 && cache.reviewRevision == 0)
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 1)
    }

    @Test func foreignCacheIdentityRollsBackNewResultInsertion() async throws {
        let container = try support.container(), context = ModelContext(container)
        let otherOwner = UUID(uuidString: "00000000-0000-4000-8000-000000000099")!
        context.insert(try LocalAnalysisStateRecord(analysisID: UUID(uuidString: support.analysisID)!,
            observationID: support.support.observation, ownerAccountID: otherOwner,
            observationStateRevision: 1, reviewRevision: 0, reviewSnapshotData: Data("{}".utf8)))
        try context.save()
        await #expect(throws: ObservationHistoryError.resultConflict) {
            try await support.service(data: support.fixture()).syncSelected(observationID: support.support.observation, container: container)
        }
        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<LocalAnalysisStateRecord>()) == 1)
        #expect(try fresh.fetch(FetchDescriptor<LocalScanRecord>()).first?.observationStateRevision == 10)
    }

    @Test func completeV1AndV2ResultsHaveBoundDisplayWithoutBorrowedPrivateFields() throws {
        let photos = ObservationHistoryPhotoTests()
        var fixture = try photos.fixture()
        var items = fixture["items"] as! [[String: Any]]
        for index in items.indices {
            var envelope = try JSONSerialization.jsonObject(with: Data((items[index]["snapshot"] as! String).utf8)) as! [String: Any]
            var result = envelope["result"] as! [String: Any]
            // The canonical native contract nests reasoning under insight_data.
            // Unknown top-level fixture keys must never become display authority.
            result["insight_data"] = ["ai_reasoning": "Synthetic nested reasoning", "hazard_type": "none"]
            result["wikipedia_overview"] = "Synthetic overview"
            envelope["result"] = result
            items[index]["snapshot"] = String(decoding: try photos.support.bytes(envelope), as: UTF8.self)
        }
        fixture["items"] = items
        let page = try ObservationHistoryPage.decode(photos.support.bytes(fixture),
            request: .init(observation_id: photos.support.observation, before_ordinal: nil, limit: 20), ownerID: photos.support.owner)
        #expect(Set(page.results.map(\.version)) == [1, 2])
        for result in page.results {
            let data = try #require(try ObservationHistoryDisplayProjection.snapshot(result))
            let display = try AnalysisDisplaySnapshot.restore(data, analysisID: result.analysisID)
            #expect(display.scientificName == "Danaus plexippus")
            #expect(display.commonName == "Monarch Butterfly" && display.speciesId.isEmpty)
            #expect(display.estimatedSizeCm == 8.5 && display.imageQualityScore == 82)
            #expect(display.aiReasoning == "Synthetic nested reasoning")
            #expect(display.wikipediaOverview == "Synthetic overview")
            let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            for key in ["gpsLatitude", "gpsLongitude", "locationName", "fieldNotes", "customTags", "capturedMediaJSON", "aiIdentificationReviewData"] {
                #expect(object[key] == nil)
            }
            #expect(try ObservationHistoryDisplayProjection.snapshot(result) == data)
        }
    }
}
