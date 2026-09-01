import Combine
import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Merian

@MainActor
struct InsightMediaGalleryTests {
    @Test func testReferenceDeduplicationIgnoresNaturebookURLDecorationsButKeepsStrictExternalIdentity() {
        let references = [
            "https://media.merian.app/public_uploads/pro/user/photo.webp?width=900",
            "https://example.com/species.jpg?size=small#first"
        ]

        let filtered = ReferenceImageDeduplicationPolicy.filteredReferenceURLs(
            references,
            excluding: [
                "HTTPS://MEDIA.MERIAN.APP/public_uploads/pro/user/photo.webp?width=1800#capture",
                "https://example.com/species.jpg?size=small#second"
            ]
        )

        #expect(filtered == ["https://example.com/species.jpg?size=small#first"])
    }

    @Test func testInsightMediaRemovesCurrentScanReferencesFromInlineAndFullscreenCarousels() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        let captureURL = "https://media.merian.app/public_uploads/pro/user/capture.webp"
        let communityURL = "https://media.merian.app/public_uploads/pro/other/reference.webp"
        let wikipediaURL = "https://upload.wikimedia.org/species.jpg"

        viewModel.inferenceEngine = engine
        engine.activeMedia = ActiveScanMedia(
            items: [.image("\(captureURL)?download=1")],
            referenceState: .loaded([
                "\(captureURL)?width=1200",
                communityURL,
                wikipediaURL
            ])
        )
        engine.speciesData = SpeciesData(
            scanId: "reference_deduplication",
            commonName: "Test species",
            scientificName: "Testus species",
            insightData: InsightData(aiReasoning: "", hazardType: "none"),
            confidenceScore: 0.96,
            referenceImageUrl: [captureURL, communityURL, wikipediaURL].joined(separator: ","),
            isBiological: true,
            isLiveCapture: false,
            isInvasive: false,
            ecologyType: "wild"
        )

        let visibleMedia = viewModel.activeMedia
        #expect(visibleMedia.referenceState == .loaded([communityURL, wikipediaURL]))
        #expect(viewModel.refUrls == [communityURL, wikipediaURL])
        #expect(viewModel.totalImages == 3)

        let pageIDs = CarouselPageBuilder.buildPages(
            for: visibleMedia,
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        ).map(\.id)
        #expect(pageIDs == [
            "image-\(captureURL)?download=1",
            "reference-\(communityURL)",
            "reference-\(wikipediaURL)"
        ])

        let fullscreenIDs = InsightImageGalleryBuilder.buildItems(
            for: visibleMedia,
            referenceWikipediaUrl: nil
        ).map(\.id)
        #expect(fullscreenIDs == pageIDs)
    }

    @Test func testInsightMediaConvertsAnAllDuplicateReferenceSetToEmpty() {
        let captureURL = "https://media.merian.app/public_uploads/free/user/capture.webp"
        let media = ActiveScanMedia(
            items: [.image(captureURL)],
            referenceState: .loaded(["\(captureURL)?width=640"])
        ).removingDuplicateReferenceImages()

        #expect(media.referenceState == .empty)
        #expect(media.totalItems == 1)
    }

    @Test func testNativeCarouselResetsDataSourceWhenReferencesAppendAfterAudioPage() {
        let audioPath = "documents/audio_only.wav"
        let audioOnlyPages = CarouselPageBuilder.buildPages(
            for: ActiveScanMedia(items: [.audio(audioPath)]),
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        let withReferencePages = CarouselPageBuilder.buildPages(
            for: ActiveScanMedia(
                items: [.audio(audioPath)],
                referenceState: .loaded(["https://example.com/field-sparrow.jpg"])
            ),
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        #expect(audioOnlyPages.map(\.id) == ["audio-\(audioPath)"])
        #expect(withReferencePages.map(\.id) == ["audio-\(audioPath)", "reference-https://example.com/field-sparrow.jpg"])
        #expect(NativePageCarousel.Coordinator.requiresDataSourceReset(
            previousPages: audioOnlyPages.map(\.nativePage),
            nextPages: withReferencePages.map(\.nativePage)
        ))
    }

    @Test func testInsightNativePageProjectionPreservesExistingReuseIdentity() {
        let focusRegion = NormalizedImageFocusRegion(
            x: 0.1,
            y: 0.2,
            width: 0.3,
            height: 0.4
        )
        let baseline = carouselPage(
            mediaKind: .visual,
            imageOrigin: .user,
            stillImageSourceIndex: 2,
            focusRegion: focusRegion
        )
        let presentationOnlyChange = carouselPage(
            mediaKind: .description,
            imageOrigin: .user,
            stillImageSourceIndex: 2,
            focusRegion: focusRegion
        )

        #expect(baseline == presentationOnlyChange)
        #expect(baseline.nativePage == presentationOnlyChange.nativePage)
        #expect(baseline.nativePage != carouselPage(
            imageOrigin: .reference,
            stillImageSourceIndex: 2,
            focusRegion: focusRegion
        ).nativePage)
        #expect(baseline.nativePage != carouselPage(
            imageOrigin: .user,
            stillImageSourceIndex: 3,
            focusRegion: focusRegion
        ).nativePage)
        #expect(baseline.nativePage != carouselPage(
            imageOrigin: .user,
            stillImageSourceIndex: 2,
            focusRegion: nil
        ).nativePage)
    }

    @Test func testCoreNativePageDefaultsToIDOnlyReuseIdentity() {
        let first = NativePageCarouselPage(
            id: "field-trip-goal",
            view: AnyView(Color.red)
        )
        let updated = NativePageCarouselPage(
            id: "field-trip-goal",
            view: AnyView(Color.blue)
        )

        #expect(first == updated)
        #expect(!NativePageCarousel.Coordinator.requiresDataSourceReset(
            previousPages: [first],
            nextPages: [updated]
        ))
    }

    @Test func testNativeCarouselResetsDataSourceWhenReuseIdentityChanges() {
        let first = NativePageCarouselPage(
            id: "field-trip-goal",
            reuseKey: AnyHashable("reference"),
            view: AnyView(Color.red)
        )
        let updated = NativePageCarouselPage(
            id: "field-trip-goal",
            reuseKey: AnyHashable("user"),
            view: AnyView(Color.blue)
        )

        #expect(NativePageCarousel.Coordinator.requiresDataSourceReset(
            previousPages: [first],
            nextPages: [updated]
        ))
    }

    @Test func testInsightImageGalleryIncludesOnlyVisualLoadedPages() {
        let liveImageData = Data([1, 2, 3])
        let imagePath = "documents/original.webp"
        let media = ActiveScanMedia(
            items: [
                .audio("documents/audio.wav"),
                .liveImage(liveImageData),
                .description(ObservationContext(freeText: "A perched bird")),
                .image(imagePath)
            ],
            referenceState: .loaded([
                "https://media.merian.app/reference.webp",
                "https://upload.wikimedia.org/species.jpg",
                "https://static.inaturalist.org/photos/1/original.jpg"
            ])
        )

        let items = InsightImageGalleryBuilder.buildItems(
            for: media,
            referenceWikipediaUrl: "https://en.wikipedia.org/wiki/Test_species"
        )

        #expect(items.map(\.id) == [
            "liveImage-\(liveImageData.hashValue)",
            "image-\(imagePath)",
            "reference-https://media.merian.app/reference.webp",
            "reference-https://upload.wikimedia.org/species.jpg",
            "reference-https://static.inaturalist.org/photos/1/original.jpg"
        ])
        #expect(items.map(\.referenceAttributionLabel) == [nil, nil, "Naturebook", "Wikipedia", "GBIF"])
    }

    private func carouselPage(
        mediaKind: CarouselMediaKind = .visual,
        imageOrigin: CarouselImageOrigin,
        stillImageSourceIndex: Int?,
        focusRegion: NormalizedImageFocusRegion?
    ) -> CarouselPageItem {
        CarouselPageItem(
            id: "stable-page",
            mediaKind: mediaKind,
            view: AnyView(EmptyView()),
            imageOrigin: imageOrigin,
            stillImageSourceIndex: stillImageSourceIndex,
            focusRegion: focusRegion
        )
    }

    @Test func testInsightImageGalleryExcludesReferenceLoadingPlaceholder() {
        let media = ActiveScanMedia(
            items: [.audio("documents/audio.wav")],
            referenceState: .loading
        )

        let items = InsightImageGalleryBuilder.buildItems(
            for: media,
            referenceWikipediaUrl: nil
        )

        #expect(items.isEmpty)
    }

    @Test func testInsightImageGalleryPresentationMapsSelectedVisualPage() {
        let media = ActiveScanMedia(
            items: [
                .audio("documents/audio.wav"),
                .image("documents/first.webp"),
                .description(ObservationContext(freeText: "Wing bars")),
                .image("documents/second.webp")
            ],
            referenceState: .loaded(["https://example.com/reference.jpg"])
        )

        let presentation = InsightImageGalleryBuilder.presentation(
            for: media,
            referenceWikipediaUrl: nil,
            selectedCarouselPageID: "image-documents/second.webp"
        )

        #expect(presentation?.items.map(\.id) == [
            "image-documents/first.webp",
            "image-documents/second.webp",
            "reference-https://example.com/reference.jpg"
        ])
        #expect(presentation?.initialSelectedIndex == 1)
    }

    @Test func testInsightImageGalleryMatchesVisibleCarouselOrder() {
        let unavailablePath = "documents/unavailable.webp"
        let availablePath = "documents/available.webp"
        let videoPath = "documents/observation.mp4"
        let referenceURL = "https://example.com/reference.webp"
        let media = ActiveScanMedia(
            items: [
                .image(unavailablePath),
                .video(videoPath),
                .image(availablePath)
            ],
            referenceState: .loaded([referenceURL])
        )
        let sourcePages = CarouselPageBuilder.buildPages(
            for: media,
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )
        let visiblePages = CarouselImageAvailabilityPolicy.visiblePages(
            sourcePages,
            unavailableIdentifiers: [unavailablePath],
            loadedReferenceIdentifiers: [referenceURL]
        )

        let presentation = InsightImageGalleryBuilder.presentation(
            for: media,
            referenceWikipediaUrl: nil,
            selectedCarouselPageID: "reference-\(referenceURL)",
            orderedCarouselPageIDs: visiblePages.map(\.id)
        )
        let hiddenPresentation = InsightImageGalleryBuilder.presentation(
            for: media,
            referenceWikipediaUrl: nil,
            selectedCarouselPageID: "image-\(unavailablePath)",
            orderedCarouselPageIDs: visiblePages.map(\.id)
        )

        #expect(presentation?.items.map(\.id) == [
            "image-\(availablePath)",
            "video-\(videoPath)",
            "reference-\(referenceURL)"
        ])
        #expect(presentation?.initialSelectedIndex == 2)
        #expect(hiddenPresentation == nil)
    }

    @Test func testInsightImageGalleryPresentationIncludesSelectedVideoPage() {
        let videoPath = "documents/observation.mp4"
        let media = ActiveScanMedia(
            items: [
                .image("documents/poster.webp"),
                .video(videoPath)
            ],
            referenceState: .loaded(["https://example.com/reference.jpg"])
        )

        let presentation = InsightImageGalleryBuilder.presentation(
            for: media,
            referenceWikipediaUrl: nil,
            selectedCarouselPageID: "video-\(videoPath)",
            isVideoMuted: false
        )

        #expect(presentation?.items.map(\.id) == [
            "image-documents/poster.webp",
            "video-\(videoPath)",
            "reference-https://example.com/reference.jpg"
        ])
        #expect(presentation?.initialSelectedIndex == 1)
        #expect(presentation?.initialVideoMuted == false)
    }

    @Test func testInsightVideoCenterPlaybackZoneProtectsNavigationTap() {
        let containerSize = CGSize(width: 390, height: 440)
        let center = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)

        #expect(MediaCarouselInteractionPolicy.centerPlaybackHitSize == 96)
        #expect(MediaCarouselInteractionPolicy.isCenterPlaybackTap(
            location: center,
            containerSize: containerSize,
            mediaKind: .video
        ))
        #expect(!MediaCarouselInteractionPolicy.isCenterPlaybackTap(
            location: CGPoint(x: 24, y: 24),
            containerSize: containerSize,
            mediaKind: .video
        ))
        #expect(!MediaCarouselInteractionPolicy.isCenterPlaybackTap(
            location: center,
            containerSize: containerSize,
            mediaKind: .visual
        ))
    }

    @Test func testInsightVideoPlaybackAvailabilityMapsPlayerItemStatus() {
        #expect(VideoPlaybackAvailability(itemStatus: .unknown) == .loading)
        #expect(VideoPlaybackAvailability(itemStatus: .readyToPlay) == .ready)
        #expect(VideoPlaybackAvailability(itemStatus: .failed) == .unavailable)
    }

    @Test func testInsightVideoPlaybackCoordinatorPausesBeforeFullscreenPresentation() {
        let coordinator = InsightCarouselVideoPlaybackCoordinator()
        var pauseCommandCount = 0
        let cancellable = coordinator.pauseForFullscreenPresentationPublisher.sink {
            pauseCommandCount += 1
        }

        coordinator.pauseForFullscreenPresentation()

        #expect(pauseCommandCount == 1)
        withExtendedLifetime(cancellable) {}
    }

    @Test func testInsightImageGalleryPresentationIgnoresNonVisualPages() {
        let media = ActiveScanMedia(
            items: [
                .audio("documents/audio.wav"),
                .description(ObservationContext(freeText: "Heard nearby"))
            ],
            referenceState: .loaded(["https://example.com/reference.jpg"])
        )

        let audioPresentation = InsightImageGalleryBuilder.presentation(
            for: media,
            referenceWikipediaUrl: nil,
            selectedCarouselPageID: "audio-documents/audio.wav"
        )
        let descriptionPresentation = InsightImageGalleryBuilder.presentation(
            for: media,
            referenceWikipediaUrl: nil,
            selectedCarouselPageID: "description-\(ObservationContext(freeText: "Heard nearby").serialized())"
        )
        let referencePresentation = InsightImageGalleryBuilder.presentation(
            for: media,
            referenceWikipediaUrl: nil,
            selectedCarouselPageID: "reference-https://example.com/reference.jpg"
        )

        #expect(audioPresentation == nil)
        #expect(descriptionPresentation == nil)
        #expect(referencePresentation?.initialSelectedIndex == 0)
    }
}
