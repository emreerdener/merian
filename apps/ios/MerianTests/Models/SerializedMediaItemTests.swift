import Foundation
import Testing
@testable import Merian

@MainActor
struct SerializedMediaItemTests {
    private func encodedJSON(for items: [SerializedMediaItem]) throws -> String {
        let data = try JSONEncoder().encode(items)
        return String(decoding: data, as: UTF8.self)
    }

    @Test func localScanRecordPrefersCapturedMediaJSONOverRelationshipMirror() throws {
        let jsonItems: [SerializedMediaItem] = [.image(.documents("json-primary.webp"))]
        let relationshipItems: [SerializedMediaItem] = [.image(.documents("relationship-stale.webp"))]

        let record = LocalScanRecord(
            speciesId: "media_precedence",
            scientificName: "Precedentia media",
            commonName: "Media Precedence",
            capturedMediaJSON: try encodedJSON(for: jsonItems)
        )
        record.capturedMediaEntries = CapturedMediaEntry.makeEntries(from: relationshipItems)

        #expect(record.serializedCapturedMediaItems == jsonItems)
        #expect(record.capturedMediaSnapshot.items == jsonItems)
    }

    @Test func offlineQueuedScanPrefersCapturedMediaJSONOverRelationshipMirror() throws {
        let jsonItems: [SerializedMediaItem] = [.audio(.documents("json-primary.wav"))]
        let relationshipItems: [SerializedMediaItem] = [.audio(.documents("relationship-stale.wav"))]

        let scan = OfflineQueuedScan(
            capturedMediaJSON: try encodedJSON(for: jsonItems)
        )
        scan.capturedMediaEntries = CapturedMediaEntry.makeEntries(from: relationshipItems)

        #expect(scan.serializedCapturedMediaItems == jsonItems)
        #expect(scan.capturedMediaSnapshot.items == jsonItems)
    }
}
