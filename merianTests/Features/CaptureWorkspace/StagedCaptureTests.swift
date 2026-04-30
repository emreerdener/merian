import Testing
import UIKit
@testable import Merian

@Suite("StagedCapture", .serialized)
struct StagedCaptureTests {

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
        capture.observationContexts.append(
            StagedObservationContext(context: ObservationContext(freeText: "Green body"))
        )
        #expect(!capture.isEmpty)

        capture.clearAll()
        #expect(capture.isEmpty)
        #expect(capture.images.isEmpty)
        #expect(capture.audios.isEmpty)
        #expect(capture.observationContexts.isEmpty)
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
