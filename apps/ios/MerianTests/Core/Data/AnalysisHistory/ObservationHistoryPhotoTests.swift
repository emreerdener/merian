import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct ObservationHistoryPhotoTests {
    let support = ObservationHistorySyncTests()
    let analysis = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
    let media = UUID(uuidString: "00000000-0000-4000-8000-000000000005")!

    func fixture() throws -> [String: Any] {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/page-v2.json")
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
    func seed() async throws -> ModelContainer {
        let container = try support.container(), data = try support.bytes(fixture())
        let service = ObservationHistorySyncService(cloud: support.client(fetch: { _ in data }))
        #expect(try await service.syncPage(observationID: support.observation, container: container).insertedCount == 2)
        #expect(try await service.syncPage(observationID: support.observation, container: container).insertedCount == 0)
        return container
    }
    func ticket(owner: String? = nil, url: String = "https://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.r2.cloudflarestorage.com/private/photo?synthetic=1", expiry: Date = Date().addingTimeInterval(30)) throws -> ObservationHistoryPhotoTicket {
        try JSONDecoder().decode(ObservationHistoryPhotoTicket.self, from: support.bytes([
            "schema_version": 1, "owner_id": owner ?? support.owner.uuidString.lowercased(),
            "observation_id": support.observation, "analysis_id": analysis.uuidString.lowercased(), "media_id": media.uuidString.lowercased(),
            "content_type": "image/jpeg", "byte_count": 3, "sha256": "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81",
            "url": url, "expires_at_ms": Int64(expiry.timeIntervalSince1970 * 1000)
        ]))
    }
    @Test func mixedV2PagePreservesExactBytesAndExistingSelection() async throws {
        let container = try await seed(), page = try fixture(), context = ModelContext(container)
        let records = try context.fetch(FetchDescriptor<LocalAnalysisRecord>())
        #expect(Set(records.map(\.snapshotVersion)) == [1, 2])
        for item in try #require(page["items"] as? [[String: Any]]) {
            let text = try #require(item["snapshot"] as? String)
            #expect(records.contains { $0.resultSnapshotData == Data(text.utf8) })
        }
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(scan.selectedAnalysisID == "00000000-0000-4000-8000-000000000009")
        #expect(scan.userConfirmedIdentification)
    }
    @Test func protectedManifestRejectsLeaksDuplicatesAndUnknownVersions() throws {
        let base = try fixture(), original = try #require((base["items"] as? [[String: Any]])?.first)
        let snapshot = try #require(JSONSerialization.jsonObject(with: Data((original["snapshot"] as! String).utf8)) as? [String: Any])
        let manifest = try #require(snapshot["evidence_manifest"] as? [String: Any])
        let items = try #require(manifest["items"] as? [[String: Any]])
        for invalid: [String: Any] in [
            ["schema_version": 2, "items": [items[0], items[0]]],
            ["schema_version": 2, "items": [items[0].merging(["object_id": media.uuidString]) { _, new in new }]],
            ["schema_version": 2, "items": [items[0].merging(["byte_count": true]) { _, new in new }]],
            ["schema_version": 2, "items": [items[0].merging(["content_type": "video/mp4"]) { _, new in new }]],
            ["schema_version": 2, "items": [items[1]]],
            ["schema_version": 3, "items": items]
        ] {
            var changed = snapshot; changed["evidence_manifest"] = invalid
            var page = base; page["items"] = [["ordinal": 2, "snapshot": String(decoding: try support.bytes(changed), as: UTF8.self)]]
            #expect(throws: (any Error).self) {
                try ObservationHistoryPage.decode(support.bytes(page), request: .init(observation_id: support.observation, before_ordinal: nil, limit: 20), ownerID: support.owner)
            }
        }
    }
    @Test func privatePhotoValidatesDigestWithoutChangingStorage() async throws {
        let container = try await seed(), expected = try ticket()
        let loader = ObservationHistoryPhotoLoader(account: support.client(fetch: { _ in Data() }), resolve: { _ in expected }, download: { _ in Data([1, 2, 3]) })
        #expect(try await loader.load(observationID: support.observation, analysisID: analysis, mediaID: media, container: container) == Data([1, 2, 3]))
        #expect(try support.count(container) == 2)
        var corrupt = loader; corrupt.download = { _ in Data([3, 2, 1]) }
        await #expect(throws: ObservationHistoryError.invalidSnapshot) {
            try await corrupt.load(observationID: support.observation, analysisID: analysis, mediaID: media, container: container)
        }
    }
    @Test func forgedExpiredOrRedirectableTicketNeverDownloads() async throws {
        let container = try await seed()
        for invalid in [try ticket(owner: support.observation), try ticket(url: "http://example.invalid/photo"),
                        try ticket(url: "https://example.invalid/photo"), try ticket(expiry: Date().addingTimeInterval(-1))] {
            let loader = ObservationHistoryPhotoLoader(account: support.client(fetch: { _ in Data() }), resolve: { _ in invalid }, download: { _ in Issue.record("Invalid ticket reached downloader"); return Data() })
            await #expect(throws: ObservationHistoryError.invalidSnapshot) {
                try await loader.load(observationID: support.observation, analysisID: analysis, mediaID: media, container: container)
            }
        }
    }
    @Test func accountSwitchDuringResolutionDiscardsTicket() async throws {
        let container = try await seed(), expected = try ticket()
        var current = true, finished = false
        let loader = ObservationHistoryPhotoLoader(account: support.client(fetch: { _ in Data() }, current: { current }, finish: { finished = true }),
            resolve: { _ in current = false; return expected }, download: { _ in Issue.record("Stale account downloaded"); return Data() })
        await #expect(throws: ObservationHistoryError.accountChanged) {
            try await loader.load(observationID: support.observation, analysisID: analysis, mediaID: media, container: container)
        }
        #expect(finished)
    }
    @Test func deletionDuringResolutionBlocksDownload() async throws {
        let container = try await seed(), expected = try ticket()
        let loader = ObservationHistoryPhotoLoader(account: support.client(fetch: { _ in Data() }), resolve: { _ in
            let context = ModelContext(container)
            try context.ensurePendingCloudDeletionTask(scanId: support.observation, requestingAccountID: support.owner, origin: .explicitUserDeletion)
            try context.save(); return expected
        }, download: { _ in Issue.record("Deleted observation downloaded"); return Data() })
        await #expect(throws: ObservationHistoryError.deleted) {
            try await loader.load(observationID: support.observation, analysisID: analysis, mediaID: media, container: container)
        }
    }
}
