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

    @Test func videoMediaRoundTripsThroughJSONRelationshipsAndActiveMedia() throws {
        let items: [SerializedMediaItem] = [
            .image(.documents("video-cover.webp")),
            .video(StoredVideoMediaReference(.documents("clip.mp4"))),
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
        #expect(snapshot.videoPaths == ["clip.mp4"])
        #expect(snapshot.summary.hasVideo)
        #expect(snapshot.summary.preferredThumbnailKind == .video)

        let activeMedia = snapshot.activeScanMedia
        #expect(activeMedia.videoPaths == [URL.documentsDirectory.appendingPathComponent("clip.mp4").path])
    }

    @Test func cloudHydrationPrefersCapturedMediaManifestForVideoScans() throws {
        let manifestItems: [SerializedMediaItem] = [
            .video(StoredVideoMediaReference(
                .remoteURL("https://cdn.example.com/clip.mp4"),
                thumbnail: .remoteURL("https://cdn.example.com/poster.webp")
            ))
        ]

        let hydrated = CapturedMediaSnapshot.cloudHydratedItems(
            capturedMediaItems: manifestItems,
            imageStorageURLs: [
                "https://cdn.example.com/frame-1.webp",
                "https://cdn.example.com/frame-2.webp"
            ],
            videoStorageURLs: ["https://cdn.example.com/clip.mp4"]
        )

        #expect(hydrated == manifestItems)
        #expect(CapturedMediaSnapshot(items: hydrated).activeScanMedia.videoPaths == ["https://cdn.example.com/clip.mp4"])
        #expect(CapturedMediaSnapshot(items: hydrated).imagePaths.isEmpty)
    }

    @Test func cloudHydrationCollapsesLegacyVideoFramesIntoPlayableVideo() throws {
        let frameURLs = (1...5).map { "https://cdn.example.com/frame-\($0).webp" }

        let hydrated = CapturedMediaSnapshot.cloudHydratedItems(
            capturedMediaItems: nil,
            imageStorageURLs: frameURLs,
            videoStorageURLs: ["https://cdn.example.com/clip.mp4"]
        )
        let snapshot = CapturedMediaSnapshot(items: hydrated)

        #expect(snapshot.items.count == 1)
        #expect(snapshot.imagePaths.isEmpty)
        #expect(snapshot.thumbnailImagePaths == ["https://cdn.example.com/frame-1.webp"])
        #expect(snapshot.videoPaths == ["https://cdn.example.com/clip.mp4"])
    }
}
