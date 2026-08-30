import Combine
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
struct InsightMediaAvailabilityTests {
    @Test func testFailedUserImageIsHiddenAfterReferenceLoads() {
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

        #expect(visiblePages.map(\.id) == [
            "image-\(availablePath)",
            "video-\(videoPath)",
            "reference-\(referenceURL)"
        ])
        #expect(visiblePages[1].id == sourcePages[1].id, "Non-image carousel slots must remain stable")
        #expect(!visiblePages.contains { $0.imageIdentifier == unavailablePath })
        #expect(media.items.contains(.image(unavailablePath)))
    }

    @Test func testFailedOnlyUserImageResolvesToFinalZeroState() {
        let unavailablePath = "documents/unavailable.webp"

        for referenceState in [ReferenceState.empty, .loading] {
            let sourcePages = CarouselPageBuilder.buildPages(
                for: ActiveScanMedia(
                    items: [.image(unavailablePath)],
                    referenceState: referenceState
                ),
                referenceWikipediaUrl: nil,
                onImageFailure: { _ in },
                onDescriptionTap: nil
            )
            let visiblePages = CarouselImageAvailabilityPolicy.visiblePages(
                sourcePages,
                unavailableIdentifiers: [unavailablePath],
                loadedReferenceIdentifiers: []
            )

            #expect(!visiblePages.contains { $0.imageIdentifier == unavailablePath })
            #expect(visiblePages.last?.id == "user-media-unavailable")
            #expect(visiblePages.last?.isUserMediaZeroState == true)
        }
    }

    @Test func testFailedOnlyUserImageShowsZeroStateWhileReferenceLoads() {
        let unavailablePath = "documents/unavailable.webp"
        let referenceURL = "https://example.com/reference.webp"
        let media = ActiveScanMedia(
            items: [.image(unavailablePath)],
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
            loadedReferenceIdentifiers: []
        )

        #expect(!visiblePages.contains { $0.imageIdentifier == unavailablePath })
        #expect(visiblePages.contains { $0.imageIdentifier == referenceURL })
        #expect(visiblePages.last?.id == "user-media-unavailable")
    }

    @Test func testFailedUserImageStaysRemovedWhenEveryReferenceFails() {
        let unavailablePath = "documents/unavailable.webp"
        let referenceURL = "https://example.com/reference.webp"
        let media = ActiveScanMedia(
            items: [.image(unavailablePath)],
            referenceState: .loaded([referenceURL])
        )
        let sourcePages = CarouselPageBuilder.buildPages(
            for: media,
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        let hiddenPages = CarouselImageAvailabilityPolicy.visiblePages(
            sourcePages,
            unavailableIdentifiers: [unavailablePath],
            loadedReferenceIdentifiers: [referenceURL]
        )
        let restoredPages = CarouselImageAvailabilityPolicy.visiblePages(
            sourcePages,
            unavailableIdentifiers: [unavailablePath, referenceURL],
            loadedReferenceIdentifiers: []
        )

        #expect(!hiddenPages.contains { $0.imageIdentifier == unavailablePath })
        #expect(!restoredPages.contains { $0.imageIdentifier == unavailablePath })
        #expect(restoredPages.last?.id == "user-media-unavailable")
    }

    @Test func testRemovedSelectedUserImagePrefersLoadedReference() {
        let unavailablePath = "documents/unavailable.webp"
        let availablePath = "documents/available.webp"
        let referenceURL = "https://example.com/reference.webp"
        let media = ActiveScanMedia(
            items: [.image(unavailablePath), .image(availablePath)],
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

        let selectedIndex = CarouselSelectionResolver.selectedIndex(
            preserving: "image-\(unavailablePath)",
            previousSelectedIndex: 0,
            in: visiblePages,
            loadedReferenceIdentifiers: [referenceURL]
        )

        #expect(visiblePages[selectedIndex].id == "reference-\(referenceURL)")
    }

    @Test func testAvailableLiveImageMovesAheadOfUnavailablePersistedImage() {
        let unavailablePath = "documents/unavailable.webp"
        let liveImageData = Data([0x01, 0x02, 0x03])
        let media = ActiveScanMedia(items: [
            .image(unavailablePath),
            .liveImage(liveImageData)
        ])
        let sourcePages = CarouselPageBuilder.buildPages(
            for: media,
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        let visiblePages = CarouselImageAvailabilityPolicy.visiblePages(
            sourcePages,
            unavailableIdentifiers: [unavailablePath],
            loadedReferenceIdentifiers: []
        )

        #expect(visiblePages.map(\.id) == [
            "liveImage-\(liveImageData.hashValue)",
            "image-\(unavailablePath)"
        ])
    }

    @Test func testUnavailableVideoReplacesInPlaceWithZoomableFallbackImage() {
        let videoPath = "https://cdn.example.com/missing.mp4"
        let posterPath = "https://cdn.example.com/poster.webp"
        let sourcePages = CarouselPageBuilder.buildPages(
            for: ActiveScanMedia(items: [
                .video(videoPath, fallbackImage: .imagePath(posterPath))
            ]),
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        let visiblePages = CarouselImageAvailabilityPolicy.visiblePages(
            sourcePages,
            unavailableIdentifiers: [],
            loadedReferenceIdentifiers: [],
            unavailableVideoPageIDs: ["video-\(videoPath)"]
        )
        let fallbackPage = visiblePages.first
        let presentation = InsightImageGalleryBuilder.presentation(
            items: visiblePages.compactMap(\.galleryItem),
            selectedCarouselPageID: fallbackPage?.id
        )
        let resolvedSelection = CarouselSelectionResolver.selectedIndex(
            preserving: sourcePages.first?.id,
            previousSelectedIndex: 0,
            in: visiblePages,
            loadedReferenceIdentifiers: []
        )

        #expect(fallbackPage?.id == "video-\(videoPath)")
        #expect(fallbackPage?.mediaKind == .visual)
        #expect(fallbackPage?.imageIdentifier == posterPath)
        #expect(fallbackPage?.galleryItem?.source == .imagePath(posterPath))
        #expect(presentation?.items.map(\.source) == [.imagePath(posterPath)])
        #expect(presentation?.initialSelectedIndex == 0)
        #expect(resolvedSelection == 0)
    }

    @Test func testUnavailableVideoWithoutFallbackAppendsZeroStateAfterOtherPages() {
        let videoPath = "https://cdn.example.com/missing.mp4"
        let referenceURL = "https://cdn.example.com/reference.webp"
        let context = ObservationContext(freeText: "Observed after sunset")
        let sourcePages = CarouselPageBuilder.buildPages(
            for: ActiveScanMedia(
                items: [
                    .video(videoPath),
                    .audio("documents/call.wav"),
                    .description(context)
                ],
                referenceState: .loaded([referenceURL])
            ),
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        let visiblePages = CarouselImageAvailabilityPolicy.visiblePages(
            sourcePages,
            unavailableIdentifiers: [],
            loadedReferenceIdentifiers: [referenceURL],
            unavailableVideoPageIDs: ["video-\(videoPath)"]
        )

        #expect(visiblePages.map(\.id) == [
            "audio-documents/call.wav",
            "description-\(context.serialized())",
            "reference-\(referenceURL)",
            "user-media-unavailable"
        ])
        #expect(visiblePages.last?.galleryItem == nil)
        #expect(InsightImageGalleryBuilder.presentation(
            items: visiblePages.compactMap(\.galleryItem),
            selectedCarouselPageID: visiblePages.last?.id
        ) == nil)
    }

    @Test func testAudioDescriptionAndLoadingPagesDoNotInventMissingPhotoState() {
        let context = ObservationContext(freeText: "A distant call")
        let sourcePages = CarouselPageBuilder.buildPages(
            for: ActiveScanMedia(
                items: [.audio("documents/call.wav"), .description(context)],
                referenceState: .loading
            ),
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        let visiblePages = CarouselImageAvailabilityPolicy.visiblePages(
            sourcePages,
            unavailableIdentifiers: [],
            loadedReferenceIdentifiers: []
        )

        #expect(visiblePages.map(\.id) == [
            "audio-documents/call.wav",
            "description-\(context.serialized())",
            "reference-loading"
        ])
        #expect(visiblePages.map(\.isUserMediaZeroState) == [false, false, false])
    }

    @Test func testFailedVideoFallbackAlsoResolvesToFinalZeroState() {
        let videoPath = "https://cdn.example.com/missing.mp4"
        let posterPath = "https://cdn.example.com/missing-poster.webp"
        let sourcePages = CarouselPageBuilder.buildPages(
            for: ActiveScanMedia(items: [
                .video(videoPath, fallbackImage: .imagePath(posterPath))
            ]),
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        let visiblePages = CarouselImageAvailabilityPolicy.visiblePages(
            sourcePages,
            unavailableIdentifiers: [posterPath],
            loadedReferenceIdentifiers: [],
            unavailableVideoPageIDs: ["video-\(videoPath)"]
        )

        #expect(visiblePages.map(\.id) == ["user-media-unavailable"])
        #expect(visiblePages[0].isUserMediaZeroState)
    }

}
