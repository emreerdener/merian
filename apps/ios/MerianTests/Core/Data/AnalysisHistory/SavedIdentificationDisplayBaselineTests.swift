import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct SavedIdentificationDisplayBaselineTests {
    let support = ObservationHistoryStateSyncTests()

    func container() throws -> ModelContainer {
        let container = try support.container()
        try support.update(container) { scan, _ in
            scan.speciesId = ""
            scan.confidenceScore = 0.75
            scan.aiReasoning = "Synthetic saved identification."
            scan.inferenceTier = "flash"
            scan.candidatesData = Data("{}".utf8)
            scan.wikipediaOverview = "Locally saved overview"
        }
        return container
    }

    @Test func acknowledgedSelectedImportRetainsLocalDisplayWithExplicitProvenance() async throws {
        let container = try container()
        _ = try await support.service(data: support.fixture(revision: 10)).syncSelected(observationID: support.support.observation, container: container)
        let context = ModelContext(container)
        let cache = try #require(context.fetch(FetchDescriptor<LocalAnalysisStateRecord>()).first)
        let data = try #require(cache.displaySnapshotData)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(object["origin"] as? String == "saved_local_projection")
        #expect(object["source_result_version"] as? Int == 3)
        let target = UUID(uuidString: support.analysisID)!
        let display = try SavedIdentificationDisplayBaseline.restore(data, analysisID: target)
        #expect(display.scientificName == "Preserved correction" && display.wikipediaOverview == "Locally saved overview")
        #expect(!String(decoding: data, as: UTF8.self).contains("Preserved private note"))
        let result = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        #expect(result.completedAt == nil && result.snapshotVersion == 3)
        try support.update(container) { scan, _ in scan.wikipediaOverview = "New mutable enrichment" }
        _ = try await support.service(data: support.fixture(revision: 10)).syncSelected(observationID: support.support.observation, container: container)
        #expect(try ModelContext(container).fetch(FetchDescriptor<LocalAnalysisStateRecord>()).first?.displaySnapshotData == data)
        var cloud = support.support.client(fetch: { _ in Data() })
        cloud.fetchState = { _ in try support.fixture(revision: 10) }
        let preview = try await ObservationHistoryPreviewService(cloud: cloud).preview(observationID: support.support.observation,
            analysisID: target, container: container)
        #expect(preview.displayOrigin == .savedLocalProjection && preview.isSelected)
        #expect(preview.display?.wikipediaOverview == "Locally saved overview")
    }

    @Test func evidenceMismatchAndRemoteReviewChangeCannotCreateLocalBaseline() async throws {
        for changeReview in [false, true] {
            let container = try container()
            if !changeReview { try support.update(container) { scan, _ in scan.confidenceScore = 0.5 } }
            _ = try await support.service(data: support.fixture(rejected: changeReview)).syncSelected(observationID: support.support.observation, container: container)
            #expect(try ModelContext(container).fetch(FetchDescriptor<LocalAnalysisStateRecord>()).first?.displaySnapshotData == nil)
        }
    }

    @Test func displayChangeWhileFetchingPreventsCaptureAndEveryOtherWrite() async throws {
        let container = try container()
        let service = support.service(data: try support.fixture(), duringFetch: {
            try support.update(container) { scan, _ in scan.commonName = "A newer local display" }
        })
        await #expect(throws: ObservationHistoryStateSyncService.AdmissionError.conflictingRevision) {
            try await service.syncSelected(observationID: support.support.observation, container: container)
        }
        #expect(try support.support.count(container) == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalAnalysisStateRecord>()) == 0)
    }

    @Test func oversizedOptionalEnvelopeDoesNotBlockResultAndAuthorityAdmission() async throws {
        for extraByte in [0, 1] {
            let container = try container()
            let target = UUID(uuidString: support.analysisID)!
            try support.update(container) { scan, _ in
                scan.wikipediaOverview = ""
                let overhead = try AnalysisDisplaySnapshot(analysisID: target, record: scan).storedData().count
                scan.wikipediaOverview = String(repeating: "x", count: LocalAnalysisRecord.maximumSnapshotBytes - overhead + extraByte)
                let display = AnalysisDisplaySnapshot(analysisID: target, record: scan)
                if extraByte == 0 {
                    #expect(try display.storedData().count == LocalAnalysisRecord.maximumSnapshotBytes)
                } else {
                    #expect(throws: (any Error).self) { try display.storedData() }
                }
            }
            #expect(try await support.service(data: support.fixture()).syncSelected(observationID: support.support.observation, container: container) == 11)
            let context = ModelContext(container)
            #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 1)
            let cache = try #require(context.fetch(FetchDescriptor<LocalAnalysisStateRecord>()).first)
            #expect(cache.displaySnapshotData == nil)
            #expect(try context.fetch(FetchDescriptor<LocalScanRecord>()).first?.observationStateRevision == 11)
        }
    }

    @Test func baselineCodecRejectsUnknownOriginsWrongIdentityAndIncompleteDisplay() async throws {
        let container = try container()
        _ = try await support.service(data: support.fixture(revision: 10)).syncSelected(observationID: support.support.observation, container: container)
        let context = ModelContext(container)
        let cache = try #require(context.fetch(FetchDescriptor<LocalAnalysisStateRecord>()).first)
        let data = try #require(cache.displaySnapshotData)
        let target = UUID(uuidString: support.analysisID)!
        let original = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["origin", "source_result_version", "schema_version", "private_notes"] {
            var changed = original
            changed[key] = "invalid"
            #expect(throws: (any Error).self) {
                try SavedIdentificationDisplayBaseline.restore(JSONSerialization.data(withJSONObject: changed), analysisID: target)
            }
        }
        var changed = original, display = original["display"] as! [String: Any]
        display.removeValue(forKey: "wikipediaOverview")
        changed["display"] = display
        #expect(throws: (any Error).self) {
            try SavedIdentificationDisplayBaseline.restore(JSONSerialization.data(withJSONObject: changed), analysisID: target)
        }
        #expect(throws: (any Error).self) { try SavedIdentificationDisplayBaseline.restore(data, analysisID: support.support.owner) }
    }
}
