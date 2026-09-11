import Foundation
import Testing
import UIKit

@testable import Merian

@MainActor
@Suite("Capture staging toolbar presentation")
struct CaptureStagingToolbarPresentationTests {
    @Test("Visible media retains canonical staging order")
    func visibleMediaRetainsCanonicalOrder() {
        var capture = StagedCapture()
        capture.images = [
            stagedImage(addedAt: Date(timeIntervalSince1970: 20))
        ]
        capture.audios = [
            StagedAudio(
                filePath: "bird.wav",
                addedAt: Date(timeIntervalSince1970: 10)
            )
        ]
        capture.observationContexts = [
            StagedObservationContext(
                context: ObservationContext(freeText: "In reeds"),
                addedAt: Date(timeIntervalSince1970: 30)
            )
        ]

        let presentation = CaptureStagingToolbarPresentation(
            stagedCapture: capture,
            isRefining: false,
            stagedCaptureLimit: 4
        )

        #expect(
            presentation.visibleNodes.map(\.id) == [
                "audio_0",
                "img_0",
                "desc_0"
            ]
        )
    }

    @Test("A video remains hidden until its sampled cover exists")
    func coverlessVideoIsHidden() {
        var capture = StagedCapture()
        capture.videos = [
            StagedVideo(
                filePath: "pending.mp4",
                sampledImages: [],
                addedAt: Date(timeIntervalSince1970: 10)
            ),
            StagedVideo(
                filePath: "ready.mp4",
                sampledImages: [
                    stagedImage(addedAt: Date(timeIntervalSince1970: 20))
                ],
                addedAt: Date(timeIntervalSince1970: 20)
            )
        ]

        let presentation = CaptureStagingToolbarPresentation(
            stagedCapture: capture,
            isRefining: false,
            stagedCaptureLimit: 3
        )

        #expect(presentation.visibleNodes.map(\.id) == ["video_1"])
    }

    @Test("Photo capacity preserves the established filtered tray behavior")
    func photoCapacityUsesVisibleTrayCount() {
        var capture = StagedCapture()
        capture.videos = [
            StagedVideo(filePath: "pending.mp4", sampledImages: [])
        ]

        let presentation = CaptureStagingToolbarPresentation(
            stagedCapture: capture,
            isRefining: false,
            stagedCaptureLimit: 1
        )

        #expect(presentation.visibleNodes.isEmpty)
        #expect(presentation.photoSelectionCount == 1)
    }

    @Test("A full visible tray omits the add-photo action")
    func fullVisibleTrayOmitsPhotoAction() {
        var capture = StagedCapture()
        capture.images = [stagedImage()]

        let presentation = CaptureStagingToolbarPresentation(
            stagedCapture: capture,
            isRefining: false,
            stagedCaptureLimit: 1
        )

        #expect(presentation.photoSelectionCount == nil)
    }

    @Test("Submission copy and enabled state follow staging context")
    func submissionStateFollowsContext() {
        let empty = CaptureStagingToolbarPresentation(
            stagedCapture: StagedCapture(),
            isRefining: false,
            stagedCaptureLimit: 1
        )
        var populatedCapture = StagedCapture()
        populatedCapture.audios = [StagedAudio(filePath: "bird.wav")]
        let refining = CaptureStagingToolbarPresentation(
            stagedCapture: populatedCapture,
            isRefining: true,
            stagedCaptureLimit: 2
        )

        #expect(empty.submitTitle == "Identify")
        #expect(empty.isSubmitDisabled)
        #expect(refining.submitTitle == "Analyze")
        #expect(!refining.isSubmitDisabled)
    }

    private func stagedImage(addedAt: Date = Date()) -> StagedImage {
        let image = UIImage()
        return StagedImage(
            compressedData: Data(),
            displayData: Data(),
            uiImage: image,
            original: IdentifiableImage(image: image),
            addedAt: addedAt
        )
    }
}
