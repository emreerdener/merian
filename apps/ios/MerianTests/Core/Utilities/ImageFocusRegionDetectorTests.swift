import CoreGraphics
import Foundation
import Testing

@testable import Merian

@Suite("Image focus region resolver")
struct ImageFocusRegionDetectorTests {
    @Test func convertsVisionCoordinatesAndPadsAcceptedSubject() throws {
        let resolution = ImageFocusRegionResolver.resolve(candidates: [
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0.2, y: 0.1, width: 0.4, height: 0.3),
                confidence: 0.9
            )
        ])
        let region = try #require(resolution.region)

        #expect(abs(region.x - 0.152) < 0.0001)
        #expect(abs(region.y - 0.564) < 0.0001)
        #expect(abs(region.width - 0.496) < 0.0001)
        #expect(abs(region.height - 0.372) < 0.0001)
        #expect(region.source == .visionObjectness)
    }

    @Test func clampsPaddingAtImageBounds() throws {
        let resolution = ImageFocusRegionResolver.resolve(candidates: [
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0, y: 0.45, width: 0.35, height: 0.35),
                confidence: 0.9
            )
        ])
        let region = try #require(resolution.region)

        #expect(region.x == 0)
        #expect(region.y >= 0)
        #expect(region.x + region.width <= 1)
        #expect(region.y + region.height <= 1)
    }

    @Test func rejectsLowConfidenceTinyAndNearFullImageCandidates() {
        #expect(ImageFocusRegionResolver.resolve(candidates: [
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4),
                confidence: 0.49
            )
        ]) == .lowConfidence)

        #expect(ImageFocusRegionResolver.resolve(candidates: [
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.05, height: 0.05),
                confidence: 0.9
            )
        ]) == .areaRejected)

        #expect(ImageFocusRegionResolver.resolve(candidates: [
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
                confidence: 0.9
            )
        ]) == .areaRejected)
    }

    @Test func rejectsAmbiguousSeparatedSubjects() {
        let resolution = ImageFocusRegionResolver.resolve(candidates: [
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0.08, y: 0.35, width: 0.3, height: 0.3),
                confidence: 0.91
            ),
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0.62, y: 0.35, width: 0.3, height: 0.3),
                confidence: 0.86
            )
        ])

        #expect(resolution == .ambiguous)
    }

    @Test func centralCandidateWinsCloseOverlappingTie() throws {
        let resolution = ImageFocusRegionResolver.resolve(candidates: [
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0.24, y: 0.28, width: 0.4, height: 0.4),
                confidence: 0.92
            ),
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
                confidence: 0.89
            )
        ])
        let region = try #require(resolution.region)

        #expect(abs(region.x - 0.252) < 0.0001)
    }

    @Test func rejectsInvalidGeometry() {
        let resolution = ImageFocusRegionResolver.resolve(candidates: [
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: -0.1, y: 0.2, width: 0.4, height: 0.4),
                confidence: 0.9
            )
        ])

        #expect(resolution == .invalidGeometry)
    }

    @Test func mapsSquareInferenceCoordinatesIntoAspectFillCarousel() {
        let region = NormalizedImageFocusRegion(
            x: 0.2,
            y: 0.25,
            width: 0.4,
            height: 0.5
        )
        let rect = ImageFocusOverlayLayout.rect(
            for: region,
            in: CGSize(width: 400, height: 450)
        )

        #expect(abs(rect.minX - 65) < 0.0001)
        #expect(abs(rect.minY - 112.5) < 0.0001)
        #expect(abs(rect.width - 180) < 0.0001)
        #expect(abs(rect.height - 225) < 0.0001)
    }

    @Test func movesFocusOverlayFreelyWithinVisibleBounds() {
        let baseRect = CGRect(x: 80, y: 120, width: 100, height: 140)
        let draggedRect = ImageFocusOverlayLayout.draggedRect(
            from: baseRect,
            committedOffset: CGSize(width: 15, height: -20),
            activeTranslation: CGSize(width: 25, height: 10),
            in: CGSize(width: 390, height: 450)
        )

        #expect(draggedRect == CGRect(x: 120, y: 110, width: 100, height: 140))
    }

    @Test func preparesAVisibleMinimumSizedInteractiveFocusRect() {
        let minimumDimension = ImageFocusOverlayLayout.minimumInteractiveDimension
        let smallRect = ImageFocusOverlayLayout.interactiveRect(
            from: CGRect(x: 100, y: 120, width: 40, height: 50),
            in: CGSize(width: 390, height: 450),
            minimumDimension: minimumDimension
        )
        let oversizedRect = ImageFocusOverlayLayout.interactiveRect(
            from: CGRect(x: 20, y: 40, width: 500, height: 600),
            in: CGSize(width: 390, height: 450),
            minimumDimension: minimumDimension
        )

        #expect(smallRect == CGRect(x: 88, y: 113, width: 64, height: 64))
        #expect(oversizedRect == CGRect(x: 0, y: 0, width: 390, height: 450))
        #expect(ImageFocusOverlayLayout.interactiveRect(
            from: smallRect,
            in: .zero,
            minimumDimension: minimumDimension
        ) == .zero)
    }

    @Test func resizesEveryFocusOverlayCornerWithoutLockingAspectRatio() {
        let baseRect = CGRect(x: 80, y: 120, width: 100, height: 140)
        let containerSize = CGSize(width: 390, height: 450)
        let samples: [(ImageFocusOverlayCorner, CGSize, CGRect)] = [
            (
                .topLeading,
                CGSize(width: -20, height: -10),
                CGRect(x: 60, y: 110, width: 120, height: 150)
            ),
            (
                .topTrailing,
                CGSize(width: 30, height: -10),
                CGRect(x: 80, y: 110, width: 130, height: 150)
            ),
            (
                .bottomTrailing,
                CGSize(width: 30, height: 40),
                CGRect(x: 80, y: 120, width: 130, height: 180)
            ),
            (
                .bottomLeading,
                CGSize(width: -20, height: 40),
                CGRect(x: 60, y: 120, width: 120, height: 180)
            )
        ]

        for (corner, translation, expectedRect) in samples {
            let resizedRect = ImageFocusOverlayLayout.resizedRect(
                from: baseRect,
                corner: corner,
                translation: translation,
                minimumDimension: ImageFocusOverlayLayout.minimumInteractiveDimension,
                in: containerSize
            )
            #expect(resizedRect == expectedRect)
            #expect(resizedRect.width / resizedRect.height != baseRect.width / baseRect.height)
        }
    }

    @Test func clampsFocusOverlayResizeToMinimumAndVisibleEdges() {
        let baseRect = CGRect(x: 80, y: 120, width: 100, height: 140)
        let containerSize = CGSize(width: 390, height: 450)
        let minimumDimension = ImageFocusOverlayLayout.minimumInteractiveDimension
        let minimumResult = ImageFocusOverlayLayout.resizeResult(
            from: baseRect,
            corner: .topLeading,
            translation: CGSize(width: 1_000, height: 1_000),
            minimumDimension: minimumDimension,
            in: containerSize
        )
        let topLeadingResult = ImageFocusOverlayLayout.resizeResult(
            from: baseRect,
            corner: .topLeading,
            translation: CGSize(width: -1_000, height: -1_000),
            minimumDimension: minimumDimension,
            in: containerSize
        )
        let bottomTrailingResult = ImageFocusOverlayLayout.resizeResult(
            from: baseRect,
            corner: .bottomTrailing,
            translation: CGSize(width: 1_000, height: 1_000),
            minimumDimension: minimumDimension,
            in: containerSize
        )

        #expect(minimumResult.rect == CGRect(x: 116, y: 196, width: 64, height: 64))
        #expect(minimumResult.constraints == Set([.minimumWidth, .minimumHeight]))
        #expect(topLeadingResult.rect.minX == 0)
        #expect(topLeadingResult.rect.minY == 0)
        #expect(topLeadingResult.constraints == Set([.leadingEdge, .topEdge]))
        #expect(bottomTrailingResult.rect.maxX == containerSize.width)
        #expect(bottomTrailingResult.rect.maxY == containerSize.height)
        #expect(bottomTrailingResult.constraints == Set([.trailingEdge, .bottomEdge]))
        #expect(ImageFocusOverlayLayout.resizedRect(
            from: baseRect,
            corner: .bottomTrailing,
            translation: .zero,
            minimumDimension: minimumDimension,
            in: .zero
        ) == .zero)
    }

    @Test func clampsFocusOverlayDragToEveryVisibleEdge() {
        let baseRect = CGRect(x: 80, y: 120, width: 100, height: 140)
        let containerSize = CGSize(width: 390, height: 450)

        let topLeading = ImageFocusOverlayLayout.draggedRect(
            from: baseRect,
            committedOffset: .zero,
            activeTranslation: CGSize(width: -1_000, height: -1_000),
            in: containerSize
        )
        let bottomTrailing = ImageFocusOverlayLayout.draggedRect(
            from: baseRect,
            committedOffset: .zero,
            activeTranslation: CGSize(width: 1_000, height: 1_000),
            in: containerSize
        )

        #expect(topLeading.minX == 0)
        #expect(topLeading.minY == 0)
        #expect(bottomTrailing.maxX == containerSize.width)
        #expect(bottomTrailing.maxY == containerSize.height)
    }

    @Test func centersOversizedFocusOverlayAndRejectsInvalidContainer() {
        let oversizedRect = CGRect(x: 20, y: 40, width: 500, height: 600)
        let containerSize = CGSize(width: 390, height: 450)
        let centeredRect = ImageFocusOverlayLayout.draggedRect(
            from: oversizedRect,
            committedOffset: .zero,
            activeTranslation: CGSize(width: 250, height: -250),
            in: containerSize
        )

        #expect(centeredRect.midX == containerSize.width / 2)
        #expect(centeredRect.midY == containerSize.height / 2)
        #expect(ImageFocusOverlayLayout.draggedRect(
            from: oversizedRect,
            committedOffset: .zero,
            activeTranslation: .zero,
            in: .zero
        ) == .zero)
    }

    @Test func editingFocusOverlayDoesNotMutateSubmittedRegion() {
        let region = NormalizedImageFocusRegion(
            x: 0.15,
            y: 0.2,
            width: 0.3,
            height: 0.45
        )
        let originalRegion = region
        let baseRect = ImageFocusOverlayLayout.rect(
            for: region,
            in: CGSize(width: 390, height: 450)
        )

        _ = ImageFocusOverlayLayout.draggedRect(
            from: baseRect,
            committedOffset: .zero,
            activeTranslation: CGSize(width: 80, height: 45),
            in: CGSize(width: 390, height: 450)
        )
        _ = ImageFocusOverlayLayout.resizedRect(
            from: baseRect,
            corner: .bottomTrailing,
            translation: CGSize(width: 70, height: -30),
            minimumDimension: ImageFocusOverlayLayout.minimumInteractiveDimension,
            in: CGSize(width: 390, height: 450)
        )

        #expect(region == originalRegion)
        #expect(region.source == .visionObjectness)
    }

    @Test @MainActor func keepsFocusRegionsAlignedToStillImageSourceIndexes() throws {
        let firstRegion = NormalizedImageFocusRegion(
            x: 0.1,
            y: 0.2,
            width: 0.3,
            height: 0.4
        )
        let secondRegion = NormalizedImageFocusRegion(
            x: 0.45,
            y: 0.25,
            width: 0.35,
            height: 0.3
        )
        let pages = CarouselPageBuilder.buildPages(
            for: ActiveScanMedia(
                items: [
                    .audio("audio.m4a"),
                    .liveImage(Data([0x01])),
                    .video("video.mov"),
                    .liveImage(Data([0x02]))
                ],
                focusRegionsBySourceIndex: [
                    0: firstRegion,
                    1: secondRegion
                ]
            ),
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        #expect(pages.count == 4)
        #expect(pages[0].focusRegion == nil)
        #expect(pages[1].focusRegion == firstRegion)
        #expect(pages[2].focusRegion == nil)
        #expect(pages[3].focusRegion == secondRegion)
    }

    @Test func stillImageAnalyzingModesAreMutuallyExclusive() {
        let region = NormalizedImageFocusRegion(
            x: 0.2,
            y: 0.25,
            width: 0.4,
            height: 0.5
        )

        #expect(StillImageAnalyzingMode(focusRegion: nil) == .fullImageScan)
        #expect(StillImageAnalyzingMode(focusRegion: region) == .isolatedFocus(region))
    }

    @Test func analyzingSweepUsesARepeatingClockDerivedPhase() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let duration: TimeInterval = 2
        let samples: [(offset: TimeInterval, expected: CGFloat)] = [
            (0, 0),
            (duration, 1),
            (duration * 1.5, 0.5),
            (duration * 2, 0)
        ]

        for sample in samples {
            let progress = AnalyzingMediaAnimationClock.sweepProgress(
                at: startedAt.addingTimeInterval(sample.offset),
                startedAt: startedAt,
                legDuration: duration,
                reduceMotion: false
            )
            #expect(abs(progress - sample.expected) < 0.0001)
        }
    }

    @Test func analyzingSweepCentersWhenMotionIsReduced() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_000)

        #expect(AnalyzingMediaAnimationClock.sweepProgress(
            at: startedAt.addingTimeInterval(30),
            startedAt: startedAt,
            legDuration: 2.15,
            reduceMotion: true
        ) == 0.5)
    }
}
