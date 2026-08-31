import CoreGraphics
import Foundation
import Testing

@testable import Merian

@Suite("Insight media focus presentation")
struct InsightMediaFocusPresentationTests {
    private struct ResizeSample {
        let corner: ImageFocusOverlayCorner
        let translation: CGSize
        let expectedRect: CGRect
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
        let samples = [
            ResizeSample(
                corner: .topLeading,
                translation: CGSize(width: -20, height: -10),
                expectedRect: CGRect(x: 60, y: 110, width: 120, height: 150)
            ),
            ResizeSample(
                corner: .topTrailing,
                translation: CGSize(width: 30, height: -10),
                expectedRect: CGRect(x: 80, y: 110, width: 130, height: 150)
            ),
            ResizeSample(
                corner: .bottomTrailing,
                translation: CGSize(width: 30, height: 40),
                expectedRect: CGRect(x: 80, y: 120, width: 130, height: 180)
            ),
            ResizeSample(
                corner: .bottomLeading,
                translation: CGSize(width: -20, height: 40),
                expectedRect: CGRect(x: 60, y: 120, width: 120, height: 180)
            )
        ]

        for sample in samples {
            let resizedRect = ImageFocusOverlayLayout.resizedRect(
                from: baseRect,
                corner: sample.corner,
                translation: sample.translation,
                minimumDimension: ImageFocusOverlayLayout.minimumInteractiveDimension,
                in: containerSize
            )
            #expect(resizedRect == sample.expectedRect)
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
        #expect(pages[1].stillImageSourceIndex == 0)
        #expect(pages[2].focusRegion == nil)
        #expect(pages[3].focusRegion == secondRegion)
        #expect(pages[3].stillImageSourceIndex == 1)
    }

    @Test @MainActor func keepsFocusInteractionIdentityAcrossImagePersistence() throws {
        let region = NormalizedImageFocusRegion(
            x: 0.2,
            y: 0.25,
            width: 0.4,
            height: 0.5
        )
        let livePage = try #require(CarouselPageBuilder.buildPages(
            for: ActiveScanMedia(
                items: [.liveImage(Data([0x01]))],
                focusRegionsBySourceIndex: [0: region]
            ),
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        ).first)
        let persistedPage = try #require(CarouselPageBuilder.buildPages(
            for: ActiveScanMedia(
                items: [.image("persisted.webp")],
                focusRegionsBySourceIndex: [0: region]
            ),
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        ).first)

        let liveIdentity = FocusInteractionIdentity(
            scanID: "scan-1",
            stillImageSourceIndex: livePage.stillImageSourceIndex
        )
        let persistedIdentity = FocusInteractionIdentity(
            scanID: " SCAN-1 ",
            stillImageSourceIndex: persistedPage.stillImageSourceIndex
        )

        #expect(livePage.id != persistedPage.id)
        #expect(liveIdentity == persistedIdentity)
        #expect(liveIdentity != FocusInteractionIdentity(
            scanID: "scan-1",
            stillImageSourceIndex: 1
        ))
    }

    @Test func preservesCustomizedFocusGeometryAcrossOverlayRemountSizes() throws {
        let initialSize = CGSize(width: 390, height: 440)
        let customizedRect = CGRect(x: 212, y: 74, width: 104, height: 286)
        let normalizedRect = try #require(NormalizedFocusOverlayRect(
            rect: customizedRect,
            in: initialSize
        ))

        let restoredRect = normalizedRect.rect(in: initialSize)
        #expect(abs(restoredRect.minX - customizedRect.minX) < 0.0001)
        #expect(abs(restoredRect.minY - customizedRect.minY) < 0.0001)
        #expect(abs(restoredRect.width - customizedRect.width) < 0.0001)
        #expect(abs(restoredRect.height - customizedRect.height) < 0.0001)

        let remountedSize = CGSize(width: 780, height: 880)
        let remountedRect = normalizedRect.rect(in: remountedSize)
        #expect(abs(remountedRect.minX - 424) < 0.0001)
        #expect(abs(remountedRect.minY - 148) < 0.0001)
        #expect(abs(remountedRect.width - 208) < 0.0001)
        #expect(abs(remountedRect.height - 572) < 0.0001)
    }

    @Test func isolatesCustomizedFocusGeometryByCanonicalScanIdentity() throws {
        let rect = try #require(NormalizedFocusOverlayRect(
            rect: CGRect(x: 40, y: 60, width: 120, height: 180),
            in: CGSize(width: 390, height: 440)
        ))
        let firstIdentity = FocusInteractionIdentity(
            scanID: "scan-1",
            stillImageSourceIndex: 0
        )
        var state = FocusOverlayInteractionState()
        state[firstIdentity] = rect

        #expect(state.activeScanID == "scan-1")
        #expect(state.resolvedScanID(for: nil) == "scan-1")
        state.retainValues(forScanID: " SCAN-1 ")
        #expect(state[FocusInteractionIdentity(
            scanID: "SCAN-1",
            stillImageSourceIndex: 0
        )] == rect)

        state.retainValues(forScanID: "scan-2")
        #expect(state.activeScanID == "scan-2")
        #expect(state[firstIdentity] == nil)
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

    @Test func analyzingAnimationSessionSurvivesSameScanOwnerChanges() throws {
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let token = try #require(UUID(
            uuidString: "00000000-0000-0000-0000-000000000001"
        ))
        var session = AnalyzingMediaAnimationSession(
            scanID: "scan-1",
            startedAt: startedAt,
            continuityToken: token,
            isProcessing: true
        )

        session.update(
            scanID: " SCAN-1 ",
            isProcessing: true,
            at: startedAt.addingTimeInterval(5)
        )

        #expect(session.startedAt == startedAt)
        #expect(session.continuityToken == token)
    }

    @Test func analyzingAnimationSessionResetsForNewScanOrAnalysis() throws {
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let token = try #require(UUID(
            uuidString: "00000000-0000-0000-0000-000000000001"
        ))
        var session = AnalyzingMediaAnimationSession(
            scanID: "scan-1",
            startedAt: startedAt,
            continuityToken: token,
            isProcessing: true
        )
        let newScanStart = startedAt.addingTimeInterval(5)

        session.update(
            scanID: "scan-2",
            isProcessing: true,
            at: newScanStart
        )

        #expect(session.scanID == "scan-2")
        #expect(session.startedAt == newScanStart)
        #expect(session.continuityToken != token)

        session.update(
            scanID: "scan-2",
            isProcessing: false,
            at: newScanStart.addingTimeInterval(1)
        )
        let tokenBeforeReanalysis = session.continuityToken
        let reanalysisStart = newScanStart.addingTimeInterval(2)
        session.update(
            scanID: "scan-2",
            isProcessing: true,
            at: reanalysisStart
        )

        #expect(session.startedAt == reanalysisStart)
        #expect(session.continuityToken != tokenBeforeReanalysis)
    }
}
