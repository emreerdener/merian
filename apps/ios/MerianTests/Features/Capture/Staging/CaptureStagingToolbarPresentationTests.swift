import Foundation
import Testing
import UIKit

@testable import Merian

@MainActor
@Suite("Capture staging toolbar presentation")
struct CaptureStagingToolbarPresentationTests {
    @Test("Describe-first and media-first drafts show every unused physical slot")
    func allPhysicalSlotsRemainVisibleWithSharedText() {
        for limit in [1, 2] {
            for hasNote in [false, true] {
                for mediaCount in 0...limit {
                    var capture = StagedCapture()
                    capture.images = (0..<mediaCount).map { _ in stagedImage() }
                    if hasNote {
                        capture.observationContexts = [StagedObservationContext(
                            context: ObservationContext(freeText: "A bird")
                        )]
                    }
                    let presentation = CaptureStagingToolbarPresentation(
                        stagedCapture: capture, isRefining: false, stagedCaptureLimit: limit
                    )
                    #expect(presentation.emptyMediaSlotCount == limit - mediaCount)
                    #expect(presentation.visibleNodes.count + presentation.emptyMediaSlotCount == limit)
                    #expect(presentation.showsProMediaPlaceholder == (limit == 1))
                }
            }
        }
    }

    @Test("Upgrade placeholder does not admit media and disappears when access changes")
    func upgradePlaceholderPreservesCapacity() {
        var capture = StagedCapture()
        capture.audios = [StagedAudio(filePath: "bird.wav")]
        capture.observationContexts = [StagedObservationContext(
            context: ObservationContext(freeText: "Beside a pond")
        )]
        let free = CaptureStagingToolbarPresentation(
            stagedCapture: capture, isRefining: false, stagedCaptureLimit: 1
        )
        #expect(free.showsProMediaPlaceholder)
        #expect(free.photoSelectionCount == nil)
        #expect(capture.availableSlots(limit: 1) == 0)

        let unlocked = CaptureStagingToolbarPresentation(
            stagedCapture: capture, isRefining: false, stagedCaptureLimit: 2
        )
        #expect(!unlocked.showsProMediaPlaceholder)
        #expect(unlocked.photoSelectionCount == 1)
        #expect(unlocked.visibleNodes.map(\.id) == free.visibleNodes.map(\.id))

        capture.images = [stagedImage()]
        for limit in [1, 2] {
            let full = CaptureStagingToolbarPresentation(
                stagedCapture: capture, isRefining: false, stagedCaptureLimit: limit
            )
            #expect(!full.showsProMediaPlaceholder)
            #expect(full.emptyMediaSlotCount == 0)
        }
        let refining = CaptureStagingToolbarPresentation(
            stagedCapture: StagedCapture(), isRefining: true, stagedCaptureLimit: 1
        )
        #expect(!refining.showsProMediaPlaceholder)
    }

    @Test("Media wraps at complete-node boundaries and retains chronological positions")
    func mediaWrapsWithoutClipping() {
        let sizes = Array(repeating: CGSize(width: 48, height: 48), count: 7)
        let frames = CaptureStagingMediaFlowLayout.frames(sizes: sizes, width: 160)
        #expect(frames.map(\.minX) == [0, 56, 112, 0, 56, 112, 0])
        #expect(frames.map(\.minY) == [0, 0, 0, 56, 56, 56, 112])
        #expect(frames.allSatisfy { $0.width == 48 && $0.height == 48 && $0.maxX <= 160 })
        let narrow = CaptureStagingMediaFlowLayout.frames(sizes: sizes, width: 159)
        #expect(narrow[2].minY == 56)
        #expect(narrow[6].minY == 168)
        #expect(CaptureStagingMediaFlowLayout.frames(sizes: [], width: 160).isEmpty)
    }

    @Test("Expanded tray clearance moves all content together and restores the baseline")
    func toolbarClearanceTracksMeasuredHeight() {
        for height: CGFloat in [0, 88, 108] {
            let layout = CaptureChromeLayout(toolbarHeight: height)
            #expect(layout.bottomInset == 124)
            #expect(layout.reservedHeight == 204)
            #expect(layout.fullScreenOverlayClearance == 250)
        }
        for height: CGFloat in [144, 200, 264] {
            let layout = CaptureChromeLayout(toolbarHeight: height)
            #expect(layout.bottomInset - height == 16)
            #expect(layout.reservedHeight - layout.bottomInset == 80)
            #expect(layout.fullScreenOverlayClearance - layout.reservedHeight == 46)
        }
    }

    @Test("Both note states resolve to drawable system symbols")
    func noteSymbolsAreAvailable() {
        for name in [CaptureStagingNoteIcon.emptySymbol, CaptureStagingNoteIcon.populatedSymbol] {
            #expect(UIImage(systemName: name) != nil)
        }
    }

    @Test("Refinement description reserves capacity without admitting a third physical item")
    func refinementSupplementCapacityAndThreeItemTray() {
        var capture = StagedCapture()
        capture.images = [stagedImage(addedAt: Date(timeIntervalSince1970: 10))]
        capture.observationContexts = [StagedObservationContext(
            context: ObservationContext(freeText: "Compare the leaves"),
            addedAt: Date(timeIntervalSince1970: 20),
            isRefinementSupplement: true
        )]
        let withDescription = CaptureStagingToolbarPresentation(
            stagedCapture: capture, isRefining: true, stagedCaptureLimit: 2
        )
        #expect(withDescription.photoSelectionCount == 1)
        capture.audios = [StagedAudio(filePath: "call.wav", addedAt: Date(timeIntervalSince1970: 30))]
        let full = CaptureStagingToolbarPresentation(
            stagedCapture: capture, isRefining: true, stagedCaptureLimit: 2
        )
        #expect(full.visibleNodes.map(\.id) == ["img_0", "audio_0"])
        #expect(full.photoSelectionCount == nil)
        #expect(full.submitTitle == "Analyze")
        #expect(!full.isSubmitDisabled)
        #expect(capture.availableEvidenceSlots(limit: 2, isRefining: true) == 0)
        #expect(capture.canStageRefinementDescription)
        capture.audios.removeAll()
        #expect(capture.availableEvidenceSlots(limit: 2, isRefining: false) == 1)
        #expect(capture.availableEvidenceSlots(limit: 1, isRefining: false) == 0)
    }

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
                "img_0"
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
        #expect(presentation.photoSelectionCount == nil)
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
