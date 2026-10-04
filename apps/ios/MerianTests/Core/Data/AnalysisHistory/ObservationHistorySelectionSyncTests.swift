import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct ObservationHistorySelectionSyncTests {
    let support = ObservationHistoryStateSyncTests()
    let otherID = "00000000-0000-4000-8000-000000000004"
    typealias Failure = ObservationHistoryStateSyncService.AdmissionError

    func savedResponse(revision: Int = 10) throws -> Data {
        try replacingReview(support.fixture(revision: revision, rejected: true), outer: 3, ai: 5)
    }

    func replacingReview(_ data: Data, outer: Int, ai: Int?) throws -> Data {
        var value = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var item = value["analysis"] as! [String: Any]
        var review = item["review_snapshot"] as! [String: Any]
        if let ai {
            let rejected = try JSONSerialization.jsonObject(with: support.fixture(rejected: true)) as! [String: Any]
            var authority = ((rejected["analysis"] as! [String: Any])["review_snapshot"] as! [String: Any])["ai_identification_review"] as! [String: Any]
            authority["revision"] = ai
            review["ai_identification_review"] = authority
        } else { review["ai_identification_review"] = NSNull() }
        item["review_revision"] = outer
        item["review_snapshot"] = review
        value["analysis"] = item
        return try support.support.bytes(value)
    }

    func nativeResponse(revision: Int = 11, protected: Bool = false) throws -> Data {
        var value = try JSONSerialization.jsonObject(with: support.fixture(revision: revision)) as! [String: Any]
        var item = value["analysis"] as! [String: Any]
        let page = protected ? try ObservationHistoryPhotoTests().fixture() : try support.support.fixture()
        let text = (page["items"] as! [[String: Any]])[0]["snapshot"] as! String
        var result = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        result["analysis_id"] = otherID
        result["ordinal"] = 2
        result["source_analysis_id"] = support.analysisID
        item["snapshot"] = String(decoding: try support.support.bytes(result), as: UTF8.self)
        value["analysis"] = item
        value["selected_analysis_id"] = otherID
        return try support.support.bytes(value)
    }

    func confirmedResponse(revision: Int = 10) throws -> Data {
        var value = try JSONSerialization.jsonObject(with: support.fixture(revision: revision)) as! [String: Any]
        var item = value["analysis"] as! [String: Any], review = item["review_snapshot"] as! [String: Any]
        let species = "00000000-0000-4000-8000-000000000099"
        review["confirmed_species_identity"] = ["version": 1, "species_id": species,
            "scientific_name": "Danaus plexippus", "common_name": NSNull(), "gbif_taxon_key": 123] as [String: Any]
        review["confirmed_species_identity_revision"] = 7
        review["confirmed_species_id"] = species
        review["user_confirmed_identification"] = true
        review["user_review_state"] = "ai_confirmed"
        item["review_snapshot"] = review; item["review_revision"] = 2; value["analysis"] = item
        return try support.support.bytes(value)
    }

    func seeded(confirmed: Bool = false) async throws -> ModelContainer {
        let container = try SavedIdentificationDisplayBaselineTests().container()
        let response = confirmed ? try confirmedResponse() : try savedResponse()
        let state = try ObservationHistoryState.decode(response,
            request: .init(observation_id: support.support.observation, analysis_id: nil), ownerID: support.support.owner)
        try support.update(container) { scan, _ in
            scan.aiIdentificationReviewData = try LocalAIIdentificationReview(authority: state.review.aiReview).storedData()
            if let verified = state.review.speciesReview {
                scan.confirmedSpeciesIdentityData = try verified.storedData()
                scan.confirmedSpeciesId = verified.confirmedSpeciesID
                scan.userConfirmedIdentification = verified.userConfirmedIdentification
                scan.userReviewState = verified.userReviewState
            }
            scan.capturedMediaJSON = "[]"
            scan.coverImagePath = "synthetic-local-photo.jpg"
        }
        _ = try await support.service(data: response).syncSelected(observationID: support.support.observation, container: container)
        return container
    }

    func parent(_ container: ModelContainer) throws -> LocalScanRecord {
        try #require(ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first)
    }

    func caches(_ container: ModelContainer) throws -> [String: Data] {
        Dictionary(uniqueKeysWithValues: try ModelContext(container).fetch(FetchDescriptor<LocalAnalysisStateRecord>()).compactMap {
            guard let data = $0.displaySnapshotData else { return nil }; return ($0.id, data)
        })
    }

    @Test func acknowledgedAtoBtoAPreservesEachAuthorityDisplayAndPrivateDetails() async throws {
        for protected in [false, true] {
            let container = try await seeded(), before = try caches(container), date = try parent(container).timestamp
            try support.update(container) { scan, _ in
                scan.wikipediaOverview = "Later mutable enrichment"
                scan.lookalikesData = Data("{}".utf8)
            }
            #expect(try await support.service(data: nativeResponse(protected: protected)).syncSelected(observationID: support.support.observation, container: container) == 11)
            let selected = try parent(container)
            #expect(selected.selectedAnalysisID == otherID && selected.scientificName == "Danaus plexippus")
            #expect(selected.localAIIdentificationReview.authority == nil && !selected.userConfirmedIdentification)
            #expect(selected.wikipediaOverview == nil && selected.lookalikesData == nil && selected.speciesId.isEmpty)
            #expect(selected.fieldNotes == "Preserved private note" && selected.customTags == ["Preserved tag"])
            #expect(selected.capturedMediaJSON == "[]" && selected.coverImagePath == "synthetic-local-photo.jpg" && selected.timestamp == date)
            #expect(try caches(container)[support.analysisID] == before[support.analysisID])
            _ = try await support.service(data: savedResponse(revision: 12)).syncSelected(observationID: support.support.observation, container: container)
            _ = try await support.service(data: savedResponse(revision: 12)).syncSelected(observationID: support.support.observation, container: container)
            let restored = try parent(container)
            #expect(restored.selectedAnalysisID == support.analysisID && restored.observationStateRevision == 12)
            #expect(restored.scientificName == "Preserved correction" && restored.wikipediaOverview == "Locally saved overview")
            #expect(restored.localAIIdentificationReview.authority?.revision == 5 && restored.localAIIdentificationReview.authority?.state == .aiRejected)
            #expect(try caches(container)[support.analysisID] == before[support.analysisID])
            #expect(try support.support.count(container) == 2)
            // A delayed B response cannot reapply revision 11 after returning to A.
            await #expect(throws: Failure.staleRevision) {
                try await support.service(data: nativeResponse(protected: protected)).syncSelected(observationID: support.support.observation, container: container)
            }
            #expect(try parent(container).selectedAnalysisID == support.analysisID)
        }
    }

    @Test func confirmationBelongsToAAndCannotAuthorizeB() async throws {
        let container = try await seeded(confirmed: true)
        _ = try await support.service(data: nativeResponse()).syncSelected(observationID: support.support.observation, container: container)
        let selected = try parent(container)
        #expect(!selected.userConfirmedIdentification && selected.confirmedSpeciesId == nil && selected.userReviewState == .unreviewed)
        #expect(try ConfirmedSpeciesReview.restoring(selected.confirmedSpeciesIdentityData)?.revision == 0)
        _ = try await support.service(data: confirmedResponse(revision: 12)).syncSelected(observationID: support.support.observation, container: container)
        let restored = try parent(container)
        #expect(restored.userConfirmedIdentification && restored.confirmedSpeciesId == "00000000-0000-4000-8000-000000000099")
        #expect(try ConfirmedSpeciesReview.restoring(restored.confirmedSpeciesIdentityData)?.revision == 7)
    }

    @Test func corruptedRetainedDisplayCannotAuthorizeASelectionChange() async throws {
        for imported in [false, true] {
            let container = try SavedIdentificationDisplayBaselineTests().container(), context = ModelContext(container)
            let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
            var value = try JSONSerialization.jsonObject(with: support.fixture(revision: 10)) as! [String: Any]
            if !imported {
                var item = value["analysis"] as! [String: Any]
                item["snapshot"] = (try support.support.fixture()["items"] as! [[String: Any]])[0]["snapshot"]
                value["analysis"] = item
            }
            let state = try ObservationHistoryState.decode(support.support.bytes(value),
                request: .init(observation_id: support.support.observation, analysis_id: nil), ownerID: support.support.owner)
            _ = try ObservationHistorySyncService.insert([state.result], into: scan, ownerID: support.support.owner, context: context)
            let display = imported ? try SavedIdentificationDisplayBaseline.capture(
                AnalysisDisplaySnapshot(analysisID: state.result.analysisID, record: scan), matching: state.result) :
                try ObservationHistoryDisplayProjection.snapshot(state.result)
            var object = try JSONSerialization.jsonObject(with: #require(display)) as! [String: Any]
            if imported {
                var inner = object["display"] as! [String: Any]
                inner["confidenceScore"] = 0.23; object["display"] = inner
            } else { object["scientificName"] = "Corrupted cached identification" }
            let result = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
            let cache = try LocalAnalysisStateRecord(analysisID: state.result.analysisID, observationID: scan.id,
                ownerAccountID: support.support.owner, observationStateRevision: 10, reviewRevision: 0,
                reviewSnapshotData: state.review.data, displaySnapshotData: support.support.bytes(object))
            context.insert(cache); result.state = cache; try context.save()
            await #expect(throws: ObservationHistoryError.resultConflict) {
                try await support.service(data: nativeResponse()).syncSelected(observationID: support.support.observation, container: container)
            }
            #expect(try parent(container).selectedAnalysisID == support.analysisID && support.support.count(container) == 1)
        }
    }

    @Test func changedSelectionRequiresNewerGlobalRevision() async throws {
        for revision in [9, 10] {
            let container = try await seeded()
            await #expect(throws: revision == 9 ? Failure.staleRevision : Failure.conflictingRevision) {
                try await support.service(data: nativeResponse(revision: revision)).syncSelected(observationID: support.support.observation, container: container)
            }
            #expect(try support.support.count(container) == 1)
            #expect(try parent(container).selectedAnalysisID == support.analysisID)
        }
    }

    @Test func targetReviewRegressionAndEquivocationRollBackAgainstItsOwnCache() async throws {
        for nestedRegression in [false, true] {
            let container = try await seeded()
            var preview = try JSONSerialization.jsonObject(with: replacingReview(nativeResponse(revision: 10), outer: 1, ai: 3)) as! [String: Any]
            preview["selected_analysis_id"] = support.analysisID
            var cloud = support.support.client(fetch: { _ in Data() })
            cloud.fetchState = { _ in try support.support.bytes(preview) }
            _ = try await ObservationHistoryPreviewService(cloud: cloud).preview(observationID: support.support.observation,
                analysisID: UUID(uuidString: otherID)!, container: container)
            let response = try replacingReview(nativeResponse(), outer: nestedRegression ? 2 : 1, ai: nestedRegression ? 2 : 4)
            await #expect(throws: nestedRegression ? LocalAnalysisStateRecord.StorageError.staleRevision : .conflictingRevision) {
                try await support.service(data: response).syncSelected(observationID: support.support.observation, container: container)
            }
            #expect(try parent(container).selectedAnalysisID == support.analysisID && parent(container).observationStateRevision == 10)
            let records = try ModelContext(container).fetch(FetchDescriptor<LocalAnalysisStateRecord>())
            #expect(records.first { $0.id == otherID }?.reviewRevision == 1)
        }
    }

    @Test func missingImportedDisplayDoesNotBorrowTheCurrentDisplay() async throws {
        // Simulate this device receiving B first, without A's saved local display.
        let container = try support.container()
        try support.update(container) { scan, _ in scan.selectedAnalysisID = otherID }
        _ = try await support.service(data: nativeResponse(revision: 10)).syncSelected(observationID: support.support.observation, container: container)
        let before = try parent(container).scientificName
        await #expect(throws: Failure.selectionProjectionRequired) {
            try await support.service(data: savedResponse(revision: 11)).syncSelected(observationID: support.support.observation, container: container)
        }
        #expect(try parent(container).selectedAnalysisID == otherID && parent(container).scientificName == before)
        #expect(try support.support.count(container) == 1)
        #expect(try caches(container)[support.analysisID] == nil)
    }

    @Test func unrepresentableTargetAuthorityLeavesSelectionAndHistoryUnchanged() async throws {
        let container = try await seeded()
        var value = try JSONSerialization.jsonObject(with: nativeResponse()) as! [String: Any]
        var item = value["analysis"] as! [String: Any], review = item["review_snapshot"] as! [String: Any]
        review["confirmed_species_identity_revision"] = 2
        review["user_confirmed_identification"] = NSNull()
        review["user_review_state"] = NSNull()
        item["review_snapshot"] = review; value["analysis"] = item
        await #expect(throws: Failure.authorityStorageRequired) {
            try await support.service(data: support.support.bytes(value)).syncSelected(observationID: support.support.observation, container: container)
        }
        #expect(try parent(container).selectedAnalysisID == support.analysisID && support.support.count(container) == 1)
    }

    @Test func pendingAndUnacknowledgedPreviousIntentCannotBeAbandoned() async throws {
        for unacknowledged in [false, true] {
            let container = try await seeded()
            try support.update(container) { scan, context in
                if unacknowledged {
                    scan.aiIdentificationReviewData = nil
                    scan.confirmedSpeciesIdentityData = nil
                } else {
                    context.insert(OfflineJobRecord(id: "synthetic-selection-review", kind: .identificationReviewSync, subjectId: support.support.observation))
                }
            }
            await #expect(throws: Failure.pendingReview) {
                try await support.service(data: nativeResponse()).syncSelected(observationID: support.support.observation, container: container)
            }
            #expect(try parent(container).selectedAnalysisID == support.analysisID && support.support.count(container) == 1)
        }
    }

    @Test func finalLeaseFailureRollsBackAppliedDisplaySelectionAuthorityAndTargetCache() async throws {
        let container = try await seeded()
        var checks = 0
        let service = support.service(data: try nativeResponse(), current: { checks += 1; return checks < 4 })
        await #expect(throws: ObservationHistoryError.accountChanged) {
            try await service.syncSelected(observationID: support.support.observation, container: container)
        }
        let selected = try parent(container)
        #expect(selected.selectedAnalysisID == support.analysisID && selected.observationStateRevision == 10)
        #expect(selected.localAIIdentificationReview.authority?.revision == 5 && selected.scientificName == "Preserved correction")
        #expect(try support.support.count(container) == 1 && caches(container).count == 1)
    }

    @Test func deletionOrLocalEditWhileFetchingWinsOverNewSelection() async throws {
        for deletion in [false, true] {
            let container = try await seeded()
            let service = support.service(data: try nativeResponse(), duringFetch: {
                try support.update(container) { scan, context in
                    if deletion {
                        try context.ensurePendingCloudDeletionTask(scanId: support.support.observation,
                            requestingAccountID: support.support.owner, origin: .explicitUserDeletion)
                    } else { scan.commonName = "Newer local display" }
                }
            })
            await #expect(throws: (any Error).self) { try await service.syncSelected(observationID: support.support.observation, container: container) }
            #expect(try parent(container).selectedAnalysisID == support.analysisID && support.support.count(container) == 1)
        }
    }
}
