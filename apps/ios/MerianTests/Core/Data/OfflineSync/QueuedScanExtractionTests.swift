import Foundation
@testable import Merian
import Testing

@Suite("Queued Scan Extraction")
@MainActor
struct QueuedScanExtractionTests {
    private struct QueueReplayScenario {
        let items: [SerializedMediaItem]
        let paths: [String]
        let descriptors: [IdentifyAudioMediaItem]
        let ownerTimeline: [IdentifyOwnerMediaTimelineItem]
    }

    private func encodedJSONString<Value: Encodable>(
        _ value: Value
    ) throws -> String {
        let data = try JSONEncoder().encode(value)
        // JSONEncoder guarantees UTF-8 output, so replacement decoding cannot
        // mask malformed external input here.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: data, as: UTF8.self)
    }

    @Test func queuedContextProjectionPreservesRouteSnapshotFields() throws {
        let timestamp = try #require(
            ISO8601DateFormatter().date(from: "2026-09-16T12:34:56Z")
        )
        let retryAt = timestamp.addingTimeInterval(90)
        let mediaItems: [SerializedMediaItem] = [
            .description(ObservationContext(freeText: "Wing bars visible"))
        ]
        let visualMediaItemsJSON = "[{\"kind\":\"image\"}]"
        let scan = OfflineQueuedScan(
            id: "queued-context-projection",
            timestamp: timestamp,
            capturedMediaJSON: try encodedJSONString(mediaItems),
            gpsLatitude: 41.8781,
            gpsLongitude: -87.6298,
            gpsElevation: 181,
            weatherCondition: "Clear",
            weatherTemperatureF: 72,
            locationName: "Chicago",
            scanState: .failed,
            visualMediaItemsJSON: visualMediaItemsJSON,
            queueAttemptCount: 3,
            queueNextRetryAt: retryAt,
            queueLastErrorCode: "temporary_failure",
            queueLastErrorMessage: "Try again",
            queueNeedsAttention: true
        )

        let snapshot = scan.queuedScanContext()

        #expect(snapshot.id == scan.id)
        #expect(snapshot.capturedMediaItems == mediaItems)
        #expect(snapshot.queueState == .failed)
        #expect(snapshot.timestamp == timestamp)
        #expect(snapshot.locationName == "Chicago")
        #expect(snapshot.weatherTemperatureF == 72)
        #expect(snapshot.weatherCondition == "Clear")
        #expect(snapshot.gpsElevation == 181)
        #expect(snapshot.gpsLatitude == 41.8781)
        #expect(snapshot.gpsLongitude == -87.6298)
        #expect(snapshot.queueAttemptCount == 3)
        #expect(snapshot.queueNextRetryAt == retryAt)
        #expect(snapshot.queueLastErrorCode == "temporary_failure")
        #expect(snapshot.queueLastErrorMessage == "Try again")
        #expect(snapshot.queueNeedsAttention)
        #expect(snapshot.approximateQueuedBytes == 0)
        #expect(snapshot.visualMediaItemsJSON == visualMediaItemsJSON)
    }

    @Test func galleryQueueReplayOmitsBookkeepingTimestampWhenPhotoHasNoEmbeddedDate() throws {
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        let queueTimestamp = try #require(
            ISO8601DateFormatter().date(from: "2026-07-15T22:05:04Z")
        )
        let galleryItem = IdentifyVisualMediaItem.image(
            sourceIndex: 0,
            captureSource: .gallery,
            hasEmbeddedCaptureDate: false
        )
        let visualMediaItemsJSON = try #require(
            String(data: JSONEncoder().encode([galleryItem]), encoding: .utf8)
        )
        let scan = OfflineQueuedScan(
            timestamp: queueTimestamp,
            gpsLatitude: 33.45,
            gpsLongitude: 18.42,
            visualMediaItemsJSON: visualMediaItemsJSON
        )

        let extracted = try OfflineQueueManager.shared.buildExtractedScanData(
            from: scan,
            container: context.container
        )

        #expect(extracted.telemetry.gpsLatitude == 33.45)
        #expect(extracted.telemetry.gpsLongitude == 18.42)
        #expect(extracted.telemetry.timestamp == nil)
        #expect(galleryItem.jsonObject["captureSource"] == nil)
        #expect(galleryItem.jsonObject["hasEmbeddedCaptureDate"] == nil)
    }

    @Test func queueReplayReusesPersistedStandaloneAudioIdentity() throws {
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        let items: [SerializedMediaItem] = [
            .audio(.documents("first.wav", sourceIndex: 0))
        ]
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try encodedJSONString(items)
        )

        let extracted = try OfflineQueueManager.shared.buildExtractedScanData(
            from: scan,
            container: context.container
        )

        #expect(extracted.audioMediaItems == [.audio(sourceIndex: 0)])
        #expect(extracted.ownerMediaTimeline == [
            .audio(audioInputIndex: 0, sourceIndex: 0)
        ])
    }

    @Test func legacyQueueReplayDoesNotRenumberSparseAudioIdentity() throws {
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        let items: [SerializedMediaItem] = [
            .audio(.documents("second.wav", sourceIndex: 1))
        ]
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try encodedJSONString(items)
        )

        let extracted = try OfflineQueueManager.shared.buildExtractedScanData(
            from: scan,
            container: context.container
        )

        #expect(extracted.audioMediaItems == [.audio(sourceIndex: 1)])
        #expect(extracted.ownerMediaTimeline == nil)
    }

    @Test func legacyVisualQueueWithoutDescriptorsUsesConservativeReplay() throws {
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        let items: [SerializedMediaItem] = [
            .image(.documents("legacy-image.webp"))
        ]
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try encodedJSONString(items),
            visualMediaItemsJSON: nil
        )

        let extracted = try OfflineQueueManager.shared.buildExtractedScanData(
            from: scan,
            container: context.container
        )

        #expect(extracted.localImagePaths == ["legacy-image.webp"])
        #expect(extracted.visualMediaItems == nil)
        #expect(extracted.ownerMediaTimeline == nil)
    }

    @Test func queueReplayKeepsAudioPathsAlignedWithDescriptorsAcrossMixedTimeline() throws {
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        let standalone = SerializedMediaItem.audio(
            .documents("standalone.wav", sourceIndex: 0)
        )
        let video = SerializedMediaItem.video(StoredVideoMediaReference(
            .documents("clip.mp4"),
            audio: .documents("video-audio.wav")
        ))
        let description = SerializedMediaItem.description(
            ObservationContext(freeText: "Interleaved field note")
        )
        let visualMediaItemsJSON = try encodedJSONString([
            IdentifyVisualMediaItem.videoFrame(
                clipIndex: 0,
                frameIndex: 0
            )
        ])
        let scenarios = [
            QueueReplayScenario(
                items: [video, description, standalone],
                paths: ["video-audio.wav", "standalone.wav"],
                descriptors: [
                    .videoAudio(clipIndex: 0),
                    .audio(sourceIndex: 0)
                ],
                ownerTimeline: [
                    .video(clipIndex: 0),
                    .description(contextIndex: 0),
                    .audio(audioInputIndex: 1, sourceIndex: 0)
                ]
            ),
            QueueReplayScenario(
                items: [standalone, description, video],
                paths: ["standalone.wav", "video-audio.wav"],
                descriptors: [
                    .audio(sourceIndex: 0),
                    .videoAudio(clipIndex: 0)
                ],
                ownerTimeline: [
                    .audio(audioInputIndex: 0, sourceIndex: 0),
                    .description(contextIndex: 0),
                    .video(clipIndex: 0)
                ]
            )
        ]

        for scenario in scenarios {
            let scan = OfflineQueuedScan(
                capturedMediaJSON: try encodedJSONString(scenario.items),
                inferenceImagePaths: ["video-frame.webp"],
                visualMediaItemsJSON: visualMediaItemsJSON
            )
            let extracted = try OfflineQueueManager.shared.buildExtractedScanData(
                from: scan,
                container: context.container
            )

            #expect(extracted.audioFilePaths == scenario.paths)
            #expect(extracted.audioMediaItems == scenario.descriptors)
            #expect(extracted.ownerMediaTimeline == scenario.ownerTimeline)
            #expect(extracted.capturedMediaSnapshot.audioPaths == scenario.paths)
            let pendingPayload = PendingScanPayload(
                id: scan.id,
                localImagePaths: [],
                localAudioPaths: extracted.capturedMediaSnapshot.audioPaths,
                localVideoPaths: extracted.videoFilePaths ?? []
            )
            let uploadItems = MediaStagingContract.uploadItems(
                for: pendingPayload,
                userId: "00000000-0000-4000-8000-000000000001"
            )
            #expect(
                uploadItems
                    .filter { $0.mediaKind == .audio }
                    .map(\.localPath) == scenario.paths
            )
            let splitKeys = MediaStagingContract.splitObjectKeys(
                uploadItems.map(\.objectKey),
                scanId: scan.id,
                localImagePaths: [],
                localAudioPaths: scenario.paths,
                localVideoPaths: extracted.videoFilePaths ?? []
            )
            #expect(
                splitKeys.audioR2ObjectKeys
                    == uploadItems
                        .filter { $0.mediaKind == .audio }
                        .map(\.objectKey)
            )
            let durableStandalonePaths = zip(
                extracted.audioFilePaths ?? [],
                extracted.audioMediaItems ?? []
            ).compactMap { pair -> String? in
                let (path, descriptor) = pair
                return descriptor.kind == .audio ? path : nil
            }
            #expect(durableStandalonePaths == ["standalone.wav"])
        }
    }

    @Test func galleryQueueReplayUsesEmbeddedCaptureDateWhenPresent() throws {
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        let captureDate = try #require(
            ISO8601DateFormatter().date(from: "2026-07-15T22:05:04Z")
        )
        let galleryItem = IdentifyVisualMediaItem.image(
            sourceIndex: 0,
            captureSource: .gallery,
            hasEmbeddedCaptureDate: true
        )
        let visualMediaItemsJSON = try #require(
            String(data: JSONEncoder().encode([galleryItem]), encoding: .utf8)
        )
        let scan = OfflineQueuedScan(
            timestamp: captureDate,
            gpsLatitude: 41.8781,
            gpsLongitude: -87.6298,
            visualMediaItemsJSON: visualMediaItemsJSON
        )

        let extracted = try OfflineQueueManager.shared.buildExtractedScanData(
            from: scan,
            container: context.container
        )

        #expect(extracted.telemetry.timestamp == DateUtilities.iso8601Formatter.string(from: captureDate))
    }
}
