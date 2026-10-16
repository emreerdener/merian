import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct ObservationHistoryStateCacheTests {
    let support = ObservationHistoryStateSyncTests()

    @Test func equivalentNestedCandidateEncodingRetainsBoundDisplay() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let fixture = try PublicationConsentUIFixture(container: context.container, namedReview: false,
            confirmationUndo: false, candidateConfirmation: true)
        let bytes = try #require(fixture.snapshots[PublicationConsentUIFixture.selected])
        let result = try ObservationHistoryPage.snapshot(bytes, observationID: PublicationConsentUIFixture.observation, ordinal: 2)
        let display = try #require(try ObservationHistoryDisplayProjection.snapshot(result))
        var object = try #require(JSONSerialization.jsonObject(with: display) as? [String: Any])
        let encoded = try #require(object["candidatesData"] as? String)
        let nested = try JSONSerialization.jsonObject(with: #require(Data(base64Encoded: encoded)))
        object["candidatesData"] = try JSONSerialization.data(withJSONObject: nested, options: [.sortedKeys, .prettyPrinted]).base64EncodedString()
        let equivalent = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(equivalent != display)
        let restored = try ObservationHistoryDisplayProjection.restore(equivalent, matching: result)
        #expect(restored.analysisID == result.analysisID)
        #expect(try restored.storedData() == display)
        try fixture.seed(context: context); try context.save()
        let record = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first { $0.id == PublicationConsentUIFixture.selected })
        let prior = try #require(record.state)
        let replacement = try LocalAnalysisStateRecord(analysisID: result.analysisID,
            observationID: prior.observationID, ownerAccountID: PublicationConsentUIFixture.owner,
            observationStateRevision: prior.observationStateRevision, reviewRevision: prior.reviewRevision,
            reviewSnapshotData: prior.reviewSnapshotData, displaySnapshotData: equivalent)
        record.state = nil; context.delete(prior); try context.save()
        context.insert(replacement); record.state = replacement; try context.save()
        let request = ObservationHistoryStateRequest(observation_id: PublicationConsentUIFixture.observation, analysis_id: nil)
        let state = try ObservationHistoryState.decode(await fixture.cloud.fetchState(request), request: request, ownerID: PublicationConsentUIFixture.owner)
        let parent = try ObservationHistorySyncService.enrolledScan(PublicationConsentUIFixture.observation, context: context)
        let refreshed = try ConfirmedSpeciesReviewPersistence.transaction {
            let refreshed = try ObservationHistoryStateCache.admit(state, scan: parent, context: context)
            try context.save()
            return refreshed
        }
        #expect(replacement.displaySnapshotData == equivalent)
        #expect(try refreshed?.storedData() == display)
        let candidates = try #require(nested as? [[String: Any]])
        for change in ["score", "order", "extra", "outer"] {
            var altered = object, changed = candidates
            switch change {
            case "score": changed[0]["confidenceScore"] = 0.99
            case "order": changed.reverse()
            case "extra": changed[0]["untrusted"] = "extra"
            default: altered["commonName"] = "Another identification"
            }
            altered["candidatesData"] = try JSONSerialization.data(withJSONObject: changed).base64EncodedString()
            let tampered = try JSONSerialization.data(withJSONObject: altered, options: [.sortedKeys])
            #expect(throws: ObservationHistoryError.resultConflict) {
                try ObservationHistoryDisplayProjection.restore(tampered, matching: result)
            }
        }
    }

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
            result["candidates"] = [["scientific_name": "Synthetic alternative", "confidence_score": 0.3]]
            result["pet_identification"] = ["species_group": "dog", "label": "Synthetic breed", "label_type": "breed",
                "confidence_score": 0.5, "evidence": ["Synthetic trait"]]
            envelope["result"] = result
            items[index]["snapshot"] = try #require(String(bytes: photos.support.bytes(envelope), encoding: .utf8))
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
            for _ in 0..<5 {
                #expect(try ObservationHistoryDisplayProjection.snapshot(result) == data)
                #expect(try ObservationHistoryDisplayProjection.restore(data, matching: result).storedData() == data)
            }
        }
    }
}
