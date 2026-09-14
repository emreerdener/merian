import Foundation
import Testing

@testable import Merian

@Suite("Inference Live Media Projector")
struct InferenceLiveMediaProjectorTests {
    @Test func visualDefaultTimelineUsesDisplayImagesAndFiltersContexts() {
        let compressedImage = Data([0x01])
        let firstDisplayImage = Data([0x11])
        let secondDisplayImage = Data([0x12])
        let context = ObservationContext(freeText: "Near a wetland")
        let focusRegion = NormalizedImageFocusRegion(
            x: 0.1,
            y: 0.2,
            width: 0.3,
            height: 0.4
        )
        let projector = makeProjector(existingPaths: [
            "/documents/listen.wav"
        ])

        let projection = projector.projectVisual(
            imageDatas: [compressedImage],
            displayDatas: [firstDisplayImage, secondDisplayImage],
            audioFilePaths: ["listen.wav"],
            videoFilePaths: ["clip.mp4"],
            observationContexts: [
                ObservationContext(freeText: " \n "),
                context
            ],
            mediaTimeline: nil,
            visualMediaItems: [
                .image(sourceIndex: 0, focusRegion: focusRegion)
            ]
        )

        #expect(projection.mediaTimeline == [
            .image(index: 0),
            .image(index: 1),
            .description(context),
            .audio("listen.wav"),
            .video("clip.mp4")
        ])
        #expect(projection.ownerMediaTimeline == nil)
        #expect(projection.submission.audioFilePaths == ["listen.wav"])
        #expect(projection.submission.videoFilePaths == ["clip.mp4"])
        #expect(projection.submission.observationContexts == [context])
        #expect(projection.activeMedia == ActiveScanMedia(
            items: [
                .liveImage(firstDisplayImage),
                .liveImage(secondDisplayImage),
                .description(context),
                .audio("/documents/listen.wav"),
                .video("/temporary/clip.mp4")
            ],
            focusRegionsBySourceIndex: [0: focusRegion]
        ))
    }

    @Test func explicitTimelinePreservesOwnerOrderAndVideoPosterPolicy() {
        let firstImage = Data([0x21])
        let secondImage = Data([0x22])
        let context = ObservationContext(freeText: "On bark")
        let timeline: [CaptureSubmissionMediaItem] = [
            .image(index: 0),
            .video(
                "https://media.example/accepted.mp4",
                posterImageIndex: 0
            ),
            .image(index: 1),
            .video(
                "http://media.example/rejected.mp4",
                posterImageIndex: 1
            ),
            .description(ObservationContext(freeText: " \n ")),
            .description(context),
            .audio(" /legacy/audio.wav ")
        ]
        let projector = makeProjector(existingPaths: [
            "/documents/audio.wav"
        ])

        let projection = projector.projectVisual(
            imageDatas: [firstImage, secondImage],
            displayDatas: [],
            audioFilePaths: nil,
            videoFilePaths: nil,
            observationContexts: [],
            mediaTimeline: timeline,
            visualMediaItems: nil
        )

        #expect(projection.mediaTimeline == timeline)
        #expect(projection.ownerMediaTimeline == [
            .image(sourceIndex: 0),
            .video(clipIndex: 0),
            .image(sourceIndex: 1),
            .video(clipIndex: 1),
            .description(contextIndex: 0),
            .audio(audioInputIndex: 0, sourceIndex: 0)
        ])
        #expect(projection.activeMedia.items == [
            .video(
                "https://media.example/accepted.mp4",
                fallbackImage: .liveImage(firstImage)
            ),
            .liveImage(secondImage),
            .description(context),
            .audio("/documents/audio.wav")
        ])
    }

    @Test func persistedRemappingRetainsPosterAndTimelineOrder() {
        let context = ObservationContext(freeText: "Below the canopy")
        let timeline: [CaptureSubmissionMediaItem] = [
            .image(index: 0),
            .video(
                "https://media.example/clip.mp4",
                posterImageIndex: 0
            ),
            .description(context),
            .image(index: 1)
        ]
        let projector = makeProjector()

        let items = projector.persistedMediaItems(
            from: timeline,
            imagePaths: ["poster.webp", "detail.webp"]
        )

        #expect(items == [
            .video(
                "https://media.example/clip.mp4",
                fallbackImage: .imagePath("poster.webp")
            ),
            .description(context),
            .image("detail.webp")
        ])
    }

    @Test func adjacentStillIsNotMistakenForVideoPoster() {
        // CaptureSubmissionPayload emits the still as timeline image 0 and
        // references the video's cover at display-image index 1 without
        // emitting that cover as a separate timeline image.
        let compressedStill = Data([0x30])
        let sampledVideoFrame = Data([0x31])
        let displayStill = Data([0x40])
        let videoCover = Data([0x41])
        let timeline: [CaptureSubmissionMediaItem] = [
            .image(index: 0),
            .video(
                "https://media.example/clip.mp4",
                posterImageIndex: 1
            )
        ]
        let projector = makeProjector()

        let projection = projector.projectVisual(
            imageDatas: [compressedStill, sampledVideoFrame],
            displayDatas: [displayStill, videoCover],
            audioFilePaths: nil,
            videoFilePaths: nil,
            observationContexts: [],
            mediaTimeline: timeline,
            visualMediaItems: nil
        )

        #expect(projection.activeMedia.items == [
            .liveImage(displayStill),
            .video(
                "https://media.example/clip.mp4",
                fallbackImage: .liveImage(videoCover)
            )
        ])
        #expect(projector.persistedMediaItems(
            from: timeline,
            imagePaths: ["still.webp", "cover.webp"]
        ) == [
            .image("still.webp"),
            .video(
                "https://media.example/clip.mp4",
                fallbackImage: .imagePath("cover.webp")
            )
        ])
    }

    @Test func localPathResolutionPreservesCompatibilityFallbacks() {
        let projector = makeProjector(existingPaths: [
            "/absolute/present.wav",
            "/documents/moved.wav",
            "/documents/relative.wav"
        ])
        let projection = projector.projectNonVisual(
            audioFilePaths: nil,
            videoFilePaths: nil,
            observationContexts: [],
            mediaTimeline: [
                .audio(" /absolute/present.wav "),
                .audio("/old/location/moved.wav"),
                .audio("/old/location/missing.wav"),
                .audio("relative.wav"),
                .audio("temporary.wav")
            ]
        )

        #expect(projection.media.activeMedia.items == [
            .audio("/absolute/present.wav"),
            .audio("/documents/moved.wav"),
            .audio("/old/location/missing.wav"),
            .audio("/documents/relative.wav"),
            .audio("/temporary/temporary.wav")
        ])
    }

    @Test func nonVisualDefaultProjectionFiltersEmptyLegacyInputs() {
        let context = ObservationContext(freeText: "Heard at dusk")
        let projector = makeProjector()

        let projection = projector.projectNonVisual(
            audioFilePaths: ["", "voice.wav"],
            videoFilePaths: ["", "clip.mp4"],
            observationContexts: [
                ObservationContext(freeText: " \n "),
                context
            ],
            mediaTimeline: nil
        )

        #expect(projection.hasAudioInput)
        #expect(projection.media.mediaTimeline == [
            .description(context),
            .audio("voice.wav"),
            .video("clip.mp4")
        ])
        #expect(projection.media.ownerMediaTimeline == nil)
        #expect(projection.media.submission.audioFilePaths == ["voice.wav"])
        #expect(projection.media.activeMedia.items == [
            .description(context),
            .audio("/temporary/voice.wav"),
            .video("/temporary/clip.mp4")
        ])
    }

    @Test func explicitTimelineDoesNotInventLegacyAudioModality() {
        let projector = makeProjector()

        let projection = projector.projectNonVisual(
            audioFilePaths: nil,
            videoFilePaths: nil,
            observationContexts: [],
            mediaTimeline: [.audio("timeline.wav")]
        )

        #expect(!projection.hasAudioInput)
        #expect(
            projection.media.submission.audioFilePaths == ["timeline.wav"]
        )
        #expect(projection.media.ownerMediaTimeline == [
            .audio(audioInputIndex: 0, sourceIndex: 0)
        ])
    }

    private func makeProjector(
        existingPaths: Set<String> = []
    ) -> InferenceLiveMediaProjector {
        InferenceLiveMediaProjector(dependencies: .init(
            documentsDirectory: URL(
                fileURLWithPath: "/documents",
                isDirectory: true
            ),
            temporaryDirectory: URL(
                fileURLWithPath: "/temporary",
                isDirectory: true
            ),
            fileExists: { existingPaths.contains($0) },
            secureRemoteURL: { rawValue in
                guard rawValue.hasPrefix("https://") else { return nil }
                return URL(string: rawValue)
            }
        ))
    }
}
