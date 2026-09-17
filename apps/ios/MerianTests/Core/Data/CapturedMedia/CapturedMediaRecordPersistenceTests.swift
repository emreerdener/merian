import Foundation
@testable import Merian
import Testing

@MainActor
struct CapturedMediaRecordPersistenceTests {
    private func encodedJSON(for items: [SerializedMediaItem]) throws -> String {
        let data = try JSONEncoder().encode(items)
        return try #require(String(data: data, encoding: .utf8))
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

    @Test func videoMediaRoundTripsThroughJSONRelationshipsAndActiveMedia() throws {
        let videoFileName = "clip-\(UUID().uuidString.lowercased()).mp4"
        let videoURL = URL.documentsDirectory.appendingPathComponent(videoFileName)
        try FileManager.default.createDirectory(
            at: videoURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x42, count: 64).write(to: videoURL)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let items: [SerializedMediaItem] = [
            .image(.documents("video-cover.webp")),
            .video(StoredVideoMediaReference(.documents(videoFileName))),
            .audio(.documents("sound.wav")),
            .description(ObservationContext(freeText: "Brief movement visible"))
        ]

        let json = try encodedJSON(for: items)
        let decoded = try JSONDecoder().decode([SerializedMediaItem].self, from: Data(json.utf8))
        let entries = CapturedMediaEntry.makeEntries(from: decoded)
        let relationshipDecoded = CapturedMediaEntry.serializedItems(from: entries)
        let snapshot = CapturedMediaSnapshot(items: relationshipDecoded)

        #expect(decoded == items)
        #expect(relationshipDecoded == items)
        #expect(snapshot.videoPaths == [videoFileName])
        #expect(snapshot.summary.hasVideo)
        #expect(snapshot.summary.preferredThumbnailKind == .video)

        let activeMedia = snapshot.activeScanMedia
        #expect(activeMedia.videoPaths == [videoURL.path])
    }
}
