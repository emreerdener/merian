import Foundation
@testable import Merian
import Testing

@Suite("Captured Media Persistence Service")
struct CapturedMediaPersistenceServiceTests {
    @Test func finalizationValueGraphIsStaticallySendable() {
        assertSendable(SpeciesData.self)
        assertSendable(InferenceResponsePreparationService.PreparedResponse.self)
        assertSendable(InferenceProcessingActor.ParseAndSaveResult.self)
        assertSendable(OfflineScanProcessingResult.self)
    }

    @Test func explicitTimelinePreservesOrderAndMediaIdentity() async throws {
        let service = CapturedMediaPersistenceService(dependencies: .init(
            persistAudioFile: { "persisted-\($0)" },
            persistVideoFile: { "persisted-\($0)" }
        ))
        let context = ObservationContext(freeText: "Orange wings")

        let json = await service.makeCapturedMediaJSON(for: .init(
            localImagePaths: ["capture.webp"],
            audioFilePaths: ["audio.wav"],
            videoFilePaths: ["video.mov"],
            mediaTimeline: [
                .audio("audio.wav"),
                .image(index: 0),
                .description(context),
                .video(
                    "video.mov",
                    posterImageIndex: 0,
                    audioFilePath: "video-audio.wav"
                )
            ]
        ))

        let items = try decode(json)
        #expect(items == [
            .audio(.documents("persisted-audio.wav", sourceIndex: 0)),
            .image(.documents("capture.webp")),
            .description(context),
            .video(StoredVideoMediaReference(
                video: .documents("persisted-video.mov"),
                thumbnail: .documents("capture.webp"),
                audio: .documents("persisted-video-audio.wav")
            ))
        ])
    }

    @Test func failedAndInvalidItemsAreDroppedWithoutRenumberingAudio() async throws {
        let service = CapturedMediaPersistenceService(dependencies: .init(
            persistAudioFile: { path in
                path == "drop.wav" ? nil : "persisted-\(path)"
            },
            persistVideoFile: { _ in nil }
        ))

        let json = await service.makeCapturedMediaJSON(for: .init(
            localImagePaths: ["capture.webp"],
            mediaTimeline: [
                .audio("drop.wav"),
                .image(index: 4),
                .description(ObservationContext()),
                .video("drop.mov"),
                .audio("keep.wav")
            ]
        ))

        #expect(try decode(json) == [
            .audio(.documents("persisted-keep.wav", sourceIndex: 1))
        ])
    }

    @Test func defaultTimelineDecodesDescriptionsBeforeAudioAndVideo() async throws {
        let service = CapturedMediaPersistenceService(dependencies: .init(
            persistAudioFile: { "persisted-\($0)" },
            persistVideoFile: { "persisted-\($0)" }
        ))
        let context = ObservationContext(freeText: "No photo available")
        let contextData = try JSONEncoder().encode(context)
        let contextJSON = try #require(String(
            data: contextData,
            encoding: .utf8
        ))

        let json = await service.makeCapturedMediaJSON(for: .init(
            localImagePaths: ["capture.webp"],
            observationContextsJSON: [contextJSON, "not-json"],
            audioFilePaths: ["audio.wav"],
            videoFilePaths: ["video.mov"]
        ))

        #expect(try decode(json) == [
            .image(.documents("capture.webp")),
            .description(context),
            .audio(.documents("persisted-audio.wav", sourceIndex: 0)),
            .video(StoredVideoMediaReference(
                video: .documents("persisted-video.mov")
            ))
        ])
    }

    private func decode(_ json: String?) throws -> [SerializedMediaItem] {
        let json = try #require(json)
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode([SerializedMediaItem].self, from: data)
    }

    private func assertSendable<T: Sendable>(_: T.Type) {}
}
