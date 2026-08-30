import Foundation
import Testing
import UIKit

@testable import Merian

@Suite("Capture submission media timeline")
struct CaptureSubmissionMediaTimelineTests {
    @Test func stagedCaptureMapsChronologicalNodesIntoSubmissionItems() {
        var capture = StagedCapture()
        let image = StagedImage(
            compressedData: Data([0x00]),
            displayData: Data([0x00]),
            uiImage: UIImage(),
            original: IdentifiableImage(image: UIImage()),
            addedAt: Date(timeIntervalSince1970: 20)
        )
        capture.images.append(image)
        capture.audios.append(StagedAudio(
            filePath: "call.wav",
            addedAt: Date(timeIntervalSince1970: 10)
        ))
        capture.observationContexts.append(StagedObservationContext(
            context: ObservationContext(freeText: "Bright yellow body"),
            addedAt: Date(timeIntervalSince1970: 30)
        ))

        #expect(capture.submissionMediaTimeline == [
            .audio("call.wav"),
            .image(index: 0),
            .description(ObservationContext(freeText: "Bright yellow body"))
        ])
    }

    @Test func legacyDefaultTimelineRetainsGroupedFallbackOrder() {
        let firstDescription = ObservationContext(freeText: "first")
        let secondDescription = ObservationContext(freeText: "second")

        let timeline = CaptureSubmissionMediaItem.defaultTimeline(
            imageCount: 2,
            observationContexts: [firstDescription, secondDescription],
            audioFilePaths: ["audio-a.wav", "audio-b.wav"],
            videoFilePaths: ["video.mp4"]
        )

        #expect(timeline == [
            .image(index: 0),
            .image(index: 1),
            .description(firstDescription),
            .description(secondDescription),
            .audio("audio-a.wav"),
            .audio("audio-b.wav"),
            .video("video.mp4")
        ])
    }

    @Test func snapshotCleanupIncludesStandaloneAndVideoMediaFiles() {
        let timeline: [CaptureSubmissionMediaItem] = [
            .image(index: 0),
            .audio("standalone.wav"),
            .video(
                "/tmp/video-playback.mp4",
                posterImageIndex: 1,
                audioFilePath: "video-audio.wav"
            ),
            .description(ObservationContext(freeText: "Field note"))
        ]

        #expect(Set(timeline.discardableLocalMediaFilePaths) == [
            "standalone.wav",
            "/tmp/video-playback.mp4",
            "video-audio.wav"
        ])
    }
}
