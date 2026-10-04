import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct ObservationHistorySavedIdentificationTests {
    let support = ObservationHistorySyncTests()
    func fixture() throws -> [String: Any] {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/page-v3.json")
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
    func decode(_ page: [String: Any]) throws -> ObservationHistoryPage {
        try ObservationHistoryPage.decode(support.bytes(page),
            request: .init(observation_id: support.observation, before_ordinal: nil, limit: 20), ownerID: support.owner)
    }
    @Test func importDateRemainsSeparateFromUnknownCompletionAndExactBytes() async throws {
        let page = try fixture(), decoded = try decode(page)
        let result = try #require(decoded.results.first)
        #expect(result.completedAt == nil)
        #expect(result.importedAt == Date(timeIntervalSince1970: 1_750_000_000))
        #expect(result.photos.isEmpty)
        let container = try support.container(), data = try support.bytes(page)
        let service = ObservationHistorySyncService(cloud: support.client(fetch: { _ in data }))
        #expect(try await service.syncPage(observationID: support.observation, container: container).insertedCount == 1)
        #expect(try await service.syncPage(observationID: support.observation, container: container).insertedCount == 0)
        let context = ModelContext(container)
        let saved = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        #expect(saved.completedAt == nil)
        #expect(saved.snapshotVersion == 3)
        #expect(saved.resultSnapshotData == result.bytes)
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(scan.userIdentificationOverride == "Existing correction")
        #expect(scan.selectedAnalysisID == "00000000-0000-4000-8000-000000000009")
        #expect(scan.observationStateRevision == 10)
    }
    @Test func importsRejectFabricatedExecutionAndMediaWithoutPartialAdmission() throws {
        let page = try fixture(), item = try #require((page["items"] as? [[String: Any]])?.first)
        let original = try #require(JSONSerialization.jsonObject(with: Data((item["snapshot"] as! String).utf8)) as? [String: Any])
        let manifest = try #require(original["evidence_manifest"] as? [String: Any])
        let result = try #require(original["result"] as? [String: Any])
        let patches: [[String: Any]] = [
            ["schema_version": 4], ["request_digest": String(repeating: "a", count: 64)],
            ["completed_at_ms": 1_750_000_000_000], ["source_analysis_id": support.observation],
            ["evidence_manifest": manifest.merging(["origin": "original"]) { _, new in new }],
            ["evidence_manifest": manifest.merging(["imported_at_ms": true]) { _, new in new }],
            ["evidence_manifest": manifest.merging(["url": "https://example.invalid"]) { _, new in new }],
            ["result": result.merging(["ai_confidence_score": true]) { _, new in new }],
            ["result": result.merging(["is_biological_subject": 1]) { _, new in new }],
            ["result": result.merging(["user_confirmed_identification": true]) { _, new in new }],
            ["result": result.merging(["primary_identification": ["version": 1, "resolution": "genus", "scientific_name": "Savedfixture", "common_name": NSNull()]]) { _, new in new }]
        ]
        for patch in patches {
            let changed = original.merging(patch) { _, new in new }
            var invalid = page
            invalid["items"] = [["ordinal": 1, "snapshot": String(decoding: try support.bytes(changed), as: UTF8.self)]]
            #expect(throws: (any Error).self) { try decode(invalid) }
        }
    }
    @Test func changedImportDateIsAConflictAndAccountSwitchCannotAdmit() async throws {
        let container = try support.container(), page = try fixture()
        let service = ObservationHistorySyncService(cloud: support.client(fetch: { _ in try support.bytes(page) }))
        _ = try await service.syncPage(observationID: support.observation, container: container)
        var item = try #require((page["items"] as? [[String: Any]])?.first)
        var snapshot = try #require(JSONSerialization.jsonObject(with: Data((item["snapshot"] as! String).utf8)) as? [String: Any])
        var manifest = try #require(snapshot["evidence_manifest"] as? [String: Any])
        manifest["imported_at_ms"] = 1_750_000_000_001
        snapshot["evidence_manifest"] = manifest
        item["snapshot"] = String(decoding: try support.bytes(snapshot), as: UTF8.self)
        var changed = page; changed["items"] = [item]
        let conflict = ObservationHistorySyncService(cloud: support.client(fetch: { _ in try support.bytes(changed) }))
        await #expect(throws: ObservationHistoryError.resultConflict) {
            try await conflict.syncPage(observationID: support.observation, container: container)
        }
        let other = try support.container()
        var current = true
        let stale = ObservationHistorySyncService(cloud: support.client(fetch: { _ in
            current = false; return try support.bytes(page)
        }, current: { current }))
        await #expect(throws: ObservationHistoryError.accountChanged) {
            try await stale.syncPage(observationID: support.observation, container: other)
        }
        #expect(try support.count(other) == 0)
    }
}
