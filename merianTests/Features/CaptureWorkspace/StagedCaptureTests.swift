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
}
