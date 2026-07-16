import CoreLocation
import Testing
import UIKit

@testable import Merian

@Suite("StagedCapture", .serialized)
struct StagedCaptureTests {

    @Test func liveImageLatencyOptimizationExcludesGalleryAudioAndVideo() {
        #expect(CaptureWorkspaceViewModel.shouldOptimizeLiveImageAnalysis(
            hasStillImage: true,
            hasAudio: false,
            hasVideo: false,
            isGalleryPhoto: false
        ))
        #expect(!CaptureWorkspaceViewModel.shouldOptimizeLiveImageAnalysis(
            hasStillImage: true,
            hasAudio: false,
            hasVideo: false,
            isGalleryPhoto: true
        ))
        #expect(!CaptureWorkspaceViewModel.shouldOptimizeLiveImageAnalysis(
            hasStillImage: true,
            hasAudio: true,
            hasVideo: false,
            isGalleryPhoto: false
        ))
        #expect(!CaptureWorkspaceViewModel.shouldOptimizeLiveImageAnalysis(
            hasStillImage: false,
            hasAudio: false,
            hasVideo: true,
            isGalleryPhoto: false
        ))
    }

    // MARK: - isEmpty

    @Test func isEmptyWhenAllModalitiesAreEmpty() {
        let capture = StagedCapture()
        #expect(capture.isEmpty)
    }

    @Test func isEmptyFalseWhenImagesPresent() {
        var capture = StagedCapture()
        let image = StagedImage(
            compressedData: Data([0x00]),
            displayData: Data([0x00]),
            uiImage: UIImage(),
            original: IdentifiableImage(image: UIImage())
        )
        capture.images.append(image)
        #expect(!capture.isEmpty)
    }

    @Test func isEmptyFalseWhenAudiosPresent() {
        var capture = StagedCapture()
        capture.audios.append(StagedAudio(filePath: "recording.wav"))
        #expect(!capture.isEmpty)
    }

    @Test func isEmptyFalseWhenObservationContextsPresent() {
        var capture = StagedCapture()
        capture.observationContexts.append(
            StagedObservationContext(context: ObservationContext(freeText: "Yellow wings"))
        )
        #expect(!capture.isEmpty)
    }

    // MARK: - isMultiModal

    @Test func isMultiModalFalseForImagesOnly() {
        var capture = StagedCapture()
        let image = StagedImage(
            compressedData: Data([0x00]),
            displayData: Data([0x00]),
            uiImage: UIImage(),
            original: IdentifiableImage(image: UIImage())
        )
        capture.images.append(image)
        #expect(!capture.isMultiModal)
    }

    @Test func isMultiModalFalseForAudiosOnly() {
        var capture = StagedCapture()
        capture.audios.append(StagedAudio(filePath: "bird.wav"))
        #expect(!capture.isMultiModal)
    }

    @Test func isMultiModalFalseForContextsOnly() {
        var capture = StagedCapture()
        capture.observationContexts.append(
            StagedObservationContext(context: ObservationContext(freeText: "Small brown beetle"))
        )
        #expect(!capture.isMultiModal)
    }

    @Test func isMultiModalTrueForImagesAndAudios() {
        var capture = StagedCapture()
        let image = StagedImage(
            compressedData: Data([0x00]),
            displayData: Data([0x00]),
            uiImage: UIImage(),
            original: IdentifiableImage(image: UIImage())
        )
        capture.images.append(image)
        capture.audios.append(StagedAudio(filePath: "sound.wav"))
        #expect(capture.isMultiModal)
    }

    @Test func isMultiModalTrueForImagesAndContexts() {
        var capture = StagedCapture()
        let image = StagedImage(
            compressedData: Data([0x00]),
            displayData: Data([0x00]),
            uiImage: UIImage(),
            original: IdentifiableImage(image: UIImage())
        )
        capture.images.append(image)
        capture.observationContexts.append(
            StagedObservationContext(context: ObservationContext(freeText: "Large wings"))
        )
        #expect(capture.isMultiModal)
    }

    @Test func isMultiModalTrueForAudiosAndContexts() {
        var capture = StagedCapture()
        capture.audios.append(StagedAudio(filePath: "frog.wav"))
        capture.observationContexts.append(
            StagedObservationContext(context: ObservationContext(freeText: "Nocturnal call"))
        )
        #expect(capture.isMultiModal)
    }

    @Test func isMultiModalTrueForAllThreeModalities() {
        var capture = StagedCapture()
        let image = StagedImage(
            compressedData: Data([0x00]),
            displayData: Data([0x00]),
            uiImage: UIImage(),
            original: IdentifiableImage(image: UIImage())
        )
        capture.images.append(image)
        capture.audios.append(StagedAudio(filePath: "call.wav"))
        capture.observationContexts.append(
            StagedObservationContext(context: ObservationContext(freeText: "Spotted on a leaf"))
        )
        #expect(capture.isMultiModal)
    }

    // MARK: - clearAll

    @Test func clearAllResetsAllModalities() {
        var capture = StagedCapture()
        let image = StagedImage(
            compressedData: Data([0x00]),
            displayData: Data([0x00]),
            uiImage: UIImage(),
            original: IdentifiableImage(image: UIImage())
        )
        capture.images.append(image)
        capture.audios.append(StagedAudio(filePath: "call.wav"))
        capture.videos.append(StagedVideo(filePath: "clip.mp4", sampledImages: [image], audioFilePath: "clip-audio.wav"))
        capture.observationContexts.append(
            StagedObservationContext(context: ObservationContext(freeText: "Green body"))
        )
        #expect(!capture.isEmpty)

        capture.clearAll()
        #expect(capture.isEmpty)
        #expect(capture.images.isEmpty)
        #expect(capture.audios.isEmpty)
        #expect(capture.videos.isEmpty)
        #expect(capture.observationContexts.isEmpty)
    }

    @Test func discardableLocalMediaFilePathsIncludesAudioVideoAndVideoAudio() {
        var capture = StagedCapture()
        let image = StagedImage(
            compressedData: Data([0x00]),
            displayData: Data([0x00]),
            uiImage: UIImage(),
            original: IdentifiableImage(image: UIImage())
        )

        capture.audios.append(StagedAudio(filePath: "standalone.wav"))
        capture.videos.append(
            StagedVideo(
                filePath: "/tmp/video-playback.mp4",
                sampledImages: [image],
                audioFilePath: "video-audio.wav"
            )
        )

        #expect(
            Set(capture.discardableLocalMediaFilePaths) == [
                "standalone.wav",
                "/tmp/video-playback.mp4",
                "video-audio.wav"
            ],
            "Cancel cleanup must include standalone audio, playback video, and extracted video audio"
        )
        #expect(
            Set(capture.submissionMediaTimeline.discardableLocalMediaFilePaths) == [
                "standalone.wav",
                "/tmp/video-playback.mp4",
                "video-audio.wav"
            ],
            "Submission snapshots need the same cleanup list when queue ownership fails"
        )
    }

    @Test func availableSlotsUsesTotalMixedItemCount() {
        var capture = StagedCapture()
        capture.audios.append(StagedAudio(filePath: "bird.wav"))
        capture.observationContexts.append(
            StagedObservationContext(context: ObservationContext(freeText: "Perched in reeds"))
        )

        #expect(capture.totalItemCount == 2)
        #expect(capture.availableSlots(limit: stagedCaptureCapacity) == 0)
        #expect(capture.isAtCapacity(limit: stagedCaptureCapacity))
    }

    @Test func submissionMediaTimelinePreservesChronologicalMixedOrder() {
        var capture = StagedCapture()

        let image = StagedImage(
            compressedData: Data([0x00]),
            displayData: Data([0x00]),
            uiImage: UIImage(),
            original: IdentifiableImage(image: UIImage()),
            addedAt: Date(timeIntervalSince1970: 20)
        )
        capture.images.append(image)
        capture.audios.append(
            StagedAudio(filePath: "call.wav", addedAt: Date(timeIntervalSince1970: 10))
        )
        capture.observationContexts.append(
            StagedObservationContext(
                context: ObservationContext(freeText: "Bright yellow body"),
                addedAt: Date(timeIntervalSince1970: 30)
            )
        )

        let timeline = capture.submissionMediaTimeline
        #expect(timeline.count == 3)

        if case .audio(let audioPath) = timeline[0] {
            #expect(audioPath == "call.wav")
        } else {
            Issue.record("First timeline item must preserve the staged audio clip")
        }

        if case .image(let index) = timeline[1] {
            #expect(index == 0)
        } else {
            Issue.record("Second timeline item must preserve the staged image")
        }

        if case .description(let context) = timeline[2] {
            #expect(context.freeText == "Bright yellow body")
        } else {
            Issue.record("Third timeline item must preserve the staged description")
        }
    }

    @Test func stagedImageReplacingPreservesChronologicalInsertionTime() {
        let originalAddedAt = Date(timeIntervalSince1970: 20)
        let historicalCaptureDate = Date(timeIntervalSince1970: 10)
        var originalImage = IdentifiableImage(
            image: UIImage(),
            environmentContext: EnvironmentContext(
                location: CLLocation(latitude: 41.8781, longitude: -87.6298),
                locationName: nil,
                weatherCondition: nil,
                weatherTemperature: nil,
                captureDate: historicalCaptureDate
            ),
            isFromGallery: true
        )
        originalImage.lastCropScale = 1.2
        let stagedImage = StagedImage(
            compressedData: Data([0x01]),
            displayData: Data([0x02]),
            uiImage: UIImage(),
            original: originalImage,
            addedAt: originalAddedAt
        )

        var croppedOriginal = originalImage
        croppedOriginal.lastCropScale = 2.0
        let replacement = stagedImage.replacing(
            compressedData: Data([0x03]),
            displayData: Data([0x04]),
            uiImage: UIImage(),
            original: croppedOriginal
        )

        #expect(replacement.addedAt == originalAddedAt)
        #expect(replacement.compressedData == Data([0x03]))
        #expect(replacement.displayData == Data([0x04]))
        #expect(replacement.original.lastCropScale == 2.0)
        #expect(replacement.original.isFromGallery)
        #expect(replacement.original.environmentContext?.captureDate == historicalCaptureDate)
        #expect(replacement.original.environmentContext?.location?.coordinate.latitude == 41.8781)
        #expect(replacement.original.environmentContext?.location?.coordinate.longitude == -87.6298)
    }

    @Test func submissionMediaTimelineSupportsAllowedCombinationMatrix() {
        func makeImage(addedAt: TimeInterval) -> StagedImage {
            StagedImage(
                compressedData: Data([0x00]),
                displayData: Data([0x00]),
                uiImage: UIImage(),
                original: IdentifiableImage(image: UIImage()),
                addedAt: Date(timeIntervalSince1970: addedAt)
            )
        }

        let descriptionA = ObservationContext(freeText: "description A")
        let descriptionB = ObservationContext(freeText: "description B")

        let scenarios: [(name: String, capture: StagedCapture, expectedCount: Int)] = [
            (
                "audio only",
                StagedCapture(
                    images: [],
                    audios: [StagedAudio(filePath: "audio_only.wav", addedAt: Date(timeIntervalSince1970: 10))],
                    observationContexts: [],
                    lastSubmitTime: nil
                ),
                1
            ),
            (
                "audio and audio",
                StagedCapture(
                    images: [],
                    audios: [
                        StagedAudio(filePath: "audio_a.wav", addedAt: Date(timeIntervalSince1970: 10)),
                        StagedAudio(filePath: "audio_b.wav", addedAt: Date(timeIntervalSince1970: 20))
                    ],
                    observationContexts: [],
                    lastSubmitTime: nil
                ),
                2
            ),
            (
                "audio and description",
                StagedCapture(
                    images: [],
                    audios: [StagedAudio(filePath: "audio_description.wav", addedAt: Date(timeIntervalSince1970: 10))],
                    observationContexts: [StagedObservationContext(context: descriptionA, addedAt: Date(timeIntervalSince1970: 20))],
                    lastSubmitTime: nil
                ),
                2
            ),
            (
                "audio and image",
                StagedCapture(
                    images: [makeImage(addedAt: 20)],
                    audios: [StagedAudio(filePath: "audio_image.wav", addedAt: Date(timeIntervalSince1970: 10))],
                    observationContexts: [],
                    lastSubmitTime: nil
                ),
                2
            ),
            (
                "description only",
                StagedCapture(
                    images: [],
                    audios: [],
                    observationContexts: [StagedObservationContext(context: descriptionA, addedAt: Date(timeIntervalSince1970: 10))],
                    lastSubmitTime: nil
                ),
                1
            ),
            (
                "description and description",
                StagedCapture(
                    images: [],
                    audios: [],
                    observationContexts: [
                        StagedObservationContext(context: descriptionA, addedAt: Date(timeIntervalSince1970: 10)),
                        StagedObservationContext(context: descriptionB, addedAt: Date(timeIntervalSince1970: 20))
                    ],
                    lastSubmitTime: nil
                ),
                2
            ),
            (
                "description and image",
                StagedCapture(
                    images: [makeImage(addedAt: 20)],
                    audios: [],
                    observationContexts: [StagedObservationContext(context: descriptionA, addedAt: Date(timeIntervalSince1970: 10))],
                    lastSubmitTime: nil
                ),
                2
            ),
            (
                "image only",
                StagedCapture(
                    images: [makeImage(addedAt: 10)],
                    audios: [],
                    observationContexts: [],
                    lastSubmitTime: nil
                ),
                1
            ),
            (
                "image and image",
                StagedCapture(
                    images: [makeImage(addedAt: 10), makeImage(addedAt: 20)],
                    audios: [],
                    observationContexts: [],
                    lastSubmitTime: nil
                ),
                2
            )
        ]

        for scenario in scenarios {
            #expect(
                scenario.capture.totalItemCount == scenario.expectedCount,
                "\(scenario.name) must count every staged item"
            )
            #expect(
                scenario.capture.submissionMediaTimeline.count == scenario.expectedCount,
                "\(scenario.name) must produce the expected submission timeline size"
            )
            #expect(
                scenario.capture.availableSlots(limit: stagedCaptureCapacity) == stagedCaptureCapacity - scenario.expectedCount,
                "\(scenario.name) must respect the shared two-item capacity"
            )
        }
    }
}
