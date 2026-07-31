import Foundation
@testable import Merian
import Testing

@MainActor
struct SerializedMediaItemTests {
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
        let snapshot = CapturedMediaSnapshot(items: hydrated)
        #expect(snapshot.activeScanMedia.videoPaths == ["https://cdn.example.com/clip.mp4"])
        #expect(snapshot.activeScanMedia.items == [
            .video(
                "https://cdn.example.com/clip.mp4",
                fallbackImage: .imagePath("https://cdn.example.com/poster.webp")
            )
        ])
        #expect(snapshot.imagePaths.isEmpty)
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
        #expect(snapshot.thumbnailImagePaths == ["https://cdn.example.com/frame-3.webp"])
        #expect(snapshot.videoPaths == ["https://cdn.example.com/clip.mp4"])
        #expect(snapshot.activeScanMedia.items == [
            .video(
                "https://cdn.example.com/clip.mp4",
                fallbackImage: .imagePath("https://cdn.example.com/frame-3.webp")
            )
        ])
    }

    @Test func cloudHydrationRepairsImageOnlyManifestWhenVideoURLExists() throws {
        let frameURLs = (1...5).map { "https://cdn.example.com/frame-\($0).webp" }
        let staleManifestItems = frameURLs.map { SerializedMediaItem.image(.remoteURL($0)) }

        let hydrated = CapturedMediaSnapshot.cloudHydratedItems(
            capturedMediaItems: staleManifestItems,
            imageStorageURLs: frameURLs,
            videoStorageURLs: ["https://cdn.example.com/clip.mp4"]
        )
        let snapshot = CapturedMediaSnapshot(items: hydrated)

        #expect(snapshot.items.count == 1)
        #expect(snapshot.imagePaths.isEmpty)
        #expect(snapshot.thumbnailImagePaths == ["https://cdn.example.com/frame-3.webp"])
        #expect(snapshot.videoPaths == ["https://cdn.example.com/clip.mp4"])
    }

    @Test func cloudHydrationKeepsStandaloneOrderingWithoutExposingVideoFrames() {
        let standaloneURL = "https://cdn.example.com/standalone.webp"
        let frameURLs = (1...5).map { "https://cdn.example.com/frame-\($0).webp" }
        let audio = SerializedMediaItem.audio(.remoteURL("https://cdn.example.com/call.wav"))
        let manifestItems: [SerializedMediaItem] = [
            .image(.remoteURL(standaloneURL))
        ] + frameURLs.map { .image(.remoteURL($0)) } + [
            .video(StoredVideoMediaReference(.remoteURL("https://cdn.example.com/clip.mp4"))),
            audio
        ]

        let hydrated = CapturedMediaSnapshot.cloudHydratedItems(
            capturedMediaItems: manifestItems,
            imageStorageURLs: [standaloneURL] + frameURLs,
            videoStorageURLs: ["https://cdn.example.com/clip.mp4"]
        )

        #expect(hydrated == [
            .image(.remoteURL(standaloneURL)),
            .video(StoredVideoMediaReference(
                .remoteURL("https://cdn.example.com/clip.mp4"),
                thumbnail: .remoteURL(frameURLs[2])
            )),
            audio
        ])
    }

    @Test func cloudHydrationUsesLegacyManifestFramesWhenCloudArraysAreUnknown() {
        let frameReferences = (1...5).map {
            StoredMediaReference.documents("legacy-frame-\($0).webp")
        }
        let manifestItems = frameReferences.map { SerializedMediaItem.image($0) } + [
            .video(StoredVideoMediaReference(.documents("legacy-clip.mp4")))
        ]

        let hydrated = CapturedMediaSnapshot.cloudHydratedItems(
            capturedMediaItems: manifestItems,
            imageStorageURLs: nil,
            videoStorageURLs: nil
        )

        #expect(hydrated == [
            .video(StoredVideoMediaReference(
                .documents("legacy-clip.mp4"),
                thumbnail: frameReferences[2]
            ))
        ])
    }

    @Test func cloudHydrationFallsBackToMiddleFrameWhenManifestVideoIsMissing() throws {
        let frameURLs = (1...5).map { "https://cdn.example.com/frame-\($0).webp" }
        let staleManifestItems = frameURLs.map { SerializedMediaItem.image(.remoteURL($0)) }

        let hydrated = CapturedMediaSnapshot.cloudHydratedItems(
            capturedMediaItems: staleManifestItems,
            imageStorageURLs: frameURLs,
            videoStorageURLs: nil
        )
        let snapshot = CapturedMediaSnapshot(items: hydrated)

        #expect(snapshot.items.count == 1)
        #expect(snapshot.imagePaths == ["https://cdn.example.com/frame-3.webp"])
        #expect(snapshot.videoPaths.isEmpty)
    }

    @Test func cloudHydrationFallsBackToMiddleFrameWhenOnlyFrameURLsRemain() throws {
        let frameURLs = (1...5).map { "https://cdn.example.com/frame-\($0).webp" }

        let hydrated = CapturedMediaSnapshot.cloudHydratedItems(
            capturedMediaItems: nil,
            imageStorageURLs: frameURLs,
            videoStorageURLs: nil
        )
        let snapshot = CapturedMediaSnapshot(items: hydrated)

        #expect(snapshot.items.count == 1)
        #expect(snapshot.imagePaths == ["https://cdn.example.com/frame-3.webp"])
        #expect(snapshot.videoPaths.isEmpty)
    }

    @Test func cloudHydrationDemotesMissingManifestVideoToStoredPoster() {
        let poster = StoredMediaReference.remoteURL("https://cdn.example.com/poster.webp")
        let manifestItems: [SerializedMediaItem] = [
            .video(StoredVideoMediaReference(
                .remoteURL("https://cdn.example.com/missing.mp4"),
                thumbnail: poster
            ))
        ]

        let hydrated = CapturedMediaSnapshot.cloudHydratedItems(
            capturedMediaItems: manifestItems,
            imageStorageURLs: (1...5).map { "https://cdn.example.com/frame-\($0).webp" },
            videoStorageURLs: []
        )

        #expect(hydrated == [.image(poster)])
    }

    @Test func cloudHydrationDemotesMissingManifestVideoToOneMiddleSampledFrame() {
        let frameURLs = (1...5).map { "https://cdn.example.com/frame-\($0).webp" }
        let manifestItems: [SerializedMediaItem] = [
            .video(StoredVideoMediaReference(.remoteURL("https://cdn.example.com/missing.mp4")))
        ]

        let hydrated = CapturedMediaSnapshot.cloudHydratedItems(
            capturedMediaItems: manifestItems,
            imageStorageURLs: frameURLs,
            videoStorageURLs: []
        )

        #expect(hydrated == [.image(.remoteURL(frameURLs[2]))])
    }

    @Test func cloudHydrationProducesOneFallbackPerMissingVideoItem() {
        let frameURLs = (1...10).map { "https://cdn.example.com/frame-\($0).webp" }
        let firstPoster = StoredMediaReference.remoteURL("https://cdn.example.com/first-poster.webp")
        let manifestItems: [SerializedMediaItem] = [
            .video(StoredVideoMediaReference(
                .remoteURL("https://cdn.example.com/first-missing.mp4"),
                thumbnail: firstPoster
            )),
            .video(StoredVideoMediaReference(.remoteURL("https://cdn.example.com/second-missing.mp4")))
        ]

        let hydrated = CapturedMediaSnapshot.cloudHydratedItems(
            capturedMediaItems: manifestItems,
            imageStorageURLs: frameURLs,
            videoStorageURLs: []
        )

        #expect(hydrated == [
            .image(firstPoster),
            .image(.remoteURL(frameURLs[7]))
        ])
    }

    @Test func cloudHydrationRemovesMissingVideoWhenNoFallbackRemains() {
        let context = ObservationContext(freeText: "Heard calling from the canopy")
        let manifestItems: [SerializedMediaItem] = [
            .video(StoredVideoMediaReference(.remoteURL("https://cdn.example.com/missing.mp4"))),
            .audio(.remoteURL("https://cdn.example.com/call.wav")),
            .description(context)
        ]

        let hydrated = CapturedMediaSnapshot.cloudHydratedItems(
            capturedMediaItems: manifestItems,
            imageStorageURLs: [],
            videoStorageURLs: []
        )

        #expect(hydrated == [
            .audio(.remoteURL("https://cdn.example.com/call.wav")),
            .description(context)
        ])
    }

    @Test func cloudHydrationNeverExposesStaleManifestFramesWhenImagesAreExplicitlyEmpty() {
        let context = ObservationContext(freeText: "Only the field note remains")
        let manifestItems = (1...5).map {
            SerializedMediaItem.image(.remoteURL("https://cdn.example.com/stale-frame-\($0).webp"))
        } + [
            .video(StoredVideoMediaReference(.remoteURL("https://cdn.example.com/missing.mp4"))),
            .description(context)
        ]

        let hydrated = CapturedMediaSnapshot.cloudHydratedItems(
            capturedMediaItems: manifestItems,
            imageStorageURLs: [],
            videoStorageURLs: []
        )

        #expect(hydrated == [.description(context)])
    }

    @Test func cloudHydrationStripsUnavailableLegacyFramesFromPlayableVideo() {
        let manifestItems = (1...5).map {
            SerializedMediaItem.image(.remoteURL("https://cdn.example.com/stale-frame-\($0).webp"))
        } + [
            .video(StoredVideoMediaReference(.remoteURL("https://cdn.example.com/clip.mp4")))
        ]

        let hydrated = CapturedMediaSnapshot.cloudHydratedItems(
            capturedMediaItems: manifestItems,
            imageStorageURLs: [],
            videoStorageURLs: ["https://cdn.example.com/clip.mp4"]
        )

        #expect(hydrated == [
            .video(StoredVideoMediaReference(.remoteURL("https://cdn.example.com/clip.mp4")))
        ])
    }

    @Test func cloudReplacementRepairsCachedRemoteVideoDowngrade() {
        let existing = CapturedMediaSnapshot(items: [
            .video(StoredVideoMediaReference(
                .remoteURL("https://cdn.example.com/missing.mp4"),
                thumbnail: .remoteURL("https://cdn.example.com/poster.webp")
            ))
        ])
        let fallbackItems: [SerializedMediaItem] = [
            .image(.remoteURL("https://cdn.example.com/poster.webp"))
        ]

        #expect(CloudMediaReplacementPolicy.shouldReplace(
            existing: existing,
            hydratedItems: fallbackItems,
            imageStorageURLs: ["https://cdn.example.com/poster.webp"],
            videoStorageURLs: []
        ))
    }

    @Test func cloudReplacementClearsCachedRemoteVisualsButPreservesLocalMedia() {
        let remote = CapturedMediaSnapshot(items: [
            .video(StoredVideoMediaReference(.remoteURL("https://cdn.example.com/missing.mp4")))
        ])
        let local = CapturedMediaSnapshot(items: [
            .video(StoredVideoMediaReference(.documents("still-local.mp4")))
        ])

        #expect(CloudMediaReplacementPolicy.shouldReplace(
            existing: remote,
            hydratedItems: [],
            imageStorageURLs: [],
            videoStorageURLs: []
        ))
        #expect(CloudMediaReplacementPolicy.shouldReplace(
            existing: remote,
            hydratedItems: [],
            imageStorageURLs: ["https://cdn.example.com/unrelated.webp"],
            videoStorageURLs: []
        ))
        #expect(!CloudMediaReplacementPolicy.shouldReplace(
            existing: local,
            hydratedItems: [],
            imageStorageURLs: [],
            videoStorageURLs: []
        ))
    }
}
