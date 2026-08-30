import Foundation
import Testing

@testable import Merian

@Suite("Capture submission media projection")
struct CaptureSubmissionMediaProjectionTests {
    @Test func interleavedAudioPathsDescriptorsAndTimelineStayAligned() {
        let description = ObservationContext(freeText: "Interleaved field note")
        let projection: CaptureSubmissionMediaProjection = [
            CaptureSubmissionProjectionItem.video(
                "clip-a.mp4",
                audioFilePath: "clip-a.wav"
            ),
            .description(description),
            .audio("standalone-a.wav", sourceIndex: 7),
            .image,
            .video("clip-b.mp4", audioFilePath: nil),
            .audio("standalone-b.wav", sourceIndex: nil)
        ].submissionMediaProjection

        #expect(projection.audioFilePaths == [
            "clip-a.wav",
            "standalone-a.wav",
            "standalone-b.wav"
        ])
        #expect(projection.audioMediaItems == [
            .videoAudio(clipIndex: 0),
            .audio(sourceIndex: 7),
            .audio(sourceIndex: 1)
        ])
        #expect(projection.videoFilePaths == ["clip-a.mp4", "clip-b.mp4"])
        #expect(projection.observationContexts == [description])
        #expect(projection.ownerMediaTimeline == [
            .video(clipIndex: 0),
            .description(contextIndex: 0),
            .audio(audioInputIndex: 1, sourceIndex: 7),
            .image(sourceIndex: 0),
            .video(clipIndex: 1),
            .audio(audioInputIndex: 2, sourceIndex: 1)
        ])
    }

    @Test func omittedInputsDoNotConsumeProjectionIndexes() {
        let projection: CaptureSubmissionMediaProjection = [
            CaptureSubmissionProjectionItem.audio("", sourceIndex: 4),
            .video("", audioFilePath: "orphan.wav"),
            .description(ObservationContext(freeText: " \n ")),
            .image,
            .audio("valid.wav", sourceIndex: nil),
            .video("valid.mp4", audioFilePath: "")
        ].submissionMediaProjection

        #expect(projection.audioFilePaths == ["valid.wav"])
        #expect(projection.audioMediaItems == [.audio(sourceIndex: 0)])
        #expect(projection.videoFilePaths == ["valid.mp4"])
        #expect(projection.observationContexts.isEmpty)
        #expect(projection.ownerMediaTimeline == [
            .image(sourceIndex: 0),
            .audio(audioInputIndex: 0, sourceIndex: 0),
            .video(clipIndex: 0)
        ])
    }

    @Test func visualDescriptorOmitsLocalProvenanceFromNetworkJSON() throws {
        let focusRegion = NormalizedImageFocusRegion(
            x: 0.1,
            y: 0.2,
            width: 0.5,
            height: 0.4
        )
        let item = IdentifyVisualMediaItem.image(
            sourceIndex: 3,
            focusRegion: focusRegion,
            captureSource: .gallery,
            hasEmbeddedCaptureDate: true
        )
        let object = item.jsonObject
        let encodedFocus = try #require(
            object["focusRegion"] as? [String: Any]
        )

        #expect(Set(object.keys) == ["kind", "sourceIndex", "focusRegion"])
        #expect(object["kind"] as? String == "image")
        #expect(object["sourceIndex"] as? Int == 3)
        #expect(object["captureSource"] == nil)
        #expect(object["hasEmbeddedCaptureDate"] == nil)
        #expect(encodedFocus["source"] as? String == "vision_objectness")
        #expect(encodedFocus["x"] as? Double == 0.1)
        #expect(encodedFocus["width"] as? Double == 0.5)
    }

    @Test func localVisualProvenanceStillRoundTripsThroughCodable() throws {
        let item = IdentifyVisualMediaItem.image(
            sourceIndex: 2,
            captureSource: .gallery,
            hasEmbeddedCaptureDate: true
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(
            IdentifyVisualMediaItem.self,
            from: data
        )

        #expect(decoded == item)
        #expect(decoded.captureSource == .gallery)
        #expect(decoded.hasEmbeddedCaptureDate == true)
    }

    @Test func descriptorFactoriesEmitOnlyTheirWireKeys() {
        let videoFrame = IdentifyVisualMediaItem.videoFrame(
            clipIndex: 2,
            frameIndex: 4
        ).jsonObject
        let videoAudio = IdentifyAudioMediaItem.videoAudio(
            clipIndex: 2
        ).jsonObject
        let ownerAudio = IdentifyOwnerMediaTimelineItem.audio(
            audioInputIndex: 5,
            sourceIndex: 8
        ).jsonObject

        #expect(Set(videoFrame.keys) == ["kind", "clipIndex", "frameIndex"])
        #expect(videoFrame["kind"] as? String == "video_frame")
        #expect(videoFrame["clipIndex"] as? Int == 2)
        #expect(videoFrame["frameIndex"] as? Int == 4)
        #expect(Set(videoAudio.keys) == ["kind", "clipIndex"])
        #expect(videoAudio["kind"] as? String == "video_audio")
        #expect(videoAudio["clipIndex"] as? Int == 2)
        #expect(Set(ownerAudio.keys) == [
            "kind",
            "sourceIndex",
            "audioInputIndex"
        ])
        #expect(ownerAudio["kind"] as? String == "audio")
        #expect(ownerAudio["sourceIndex"] as? Int == 8)
        #expect(ownerAudio["audioInputIndex"] as? Int == 5)
    }

    @Test func focusLookupIncludesOnlyAddressableStillImages() {
        let first = NormalizedImageFocusRegion(
            x: 0.1,
            y: 0.2,
            width: 0.3,
            height: 0.4
        )
        let second = NormalizedImageFocusRegion(
            x: 0.5,
            y: 0.6,
            width: 0.2,
            height: 0.3
        )
        let items: [IdentifyVisualMediaItem] = [
            .image(sourceIndex: 4, focusRegion: first),
            .videoFrame(clipIndex: 0, frameIndex: 0),
            .image(sourceIndex: 6),
            .image(sourceIndex: 9, focusRegion: second)
        ]

        #expect(items.focusRegionsBySourceIndex == [4: first, 9: second])
    }

}
