import SwiftUI

enum CarouselImageAvailabilityPolicy {
    static func visiblePages(
        _ pages: [CarouselPageItem],
        unavailableIdentifiers: Set<String>,
        loadedReferenceIdentifiers: Set<String>,
        unavailableVideoPageIDs: Set<String> = []
    ) -> [CarouselPageItem] {
        let hasSubmittedUserVisual = pages.contains { page in
            isUserVisual(page) && !page.isUserMediaZeroState
        }
        let resolvedVideoPages = pages.compactMap { page -> CarouselPageItem? in
            guard page.mediaKind == .video,
                  unavailableVideoPageIDs.contains(page.id) else {
                return page
            }
            guard let fallback = page.videoFallback else { return nil }
            return CarouselPageItem(
                id: page.id,
                mediaKind: .visual,
                view: fallback.view,
                imageIdentifier: fallback.imageIdentifier,
                imageOrigin: .user,
                galleryItem: fallback.galleryItem(pageID: page.id),
                focusRegion: page.focusRegion
            )
        }
        let orderedPages = movingUnavailableImagesToBack(
            resolvedVideoPages,
            unavailableIdentifiers: unavailableIdentifiers
        )
        let hasUsableUserVisual = orderedPages.contains { page in
            guard isUserVisual(page), !page.isUserMediaZeroState else {
                return false
            }
            if page.mediaKind == .video { return true }
            guard let identifier = page.imageIdentifier else { return true }
            return !unavailableIdentifiers.contains(identifier)
        }
        guard hasUsableUserVisual else {
            let pagesWithoutFailedUserVisuals = orderedPages.filter {
                guard !isUserVisual($0), !$0.isUserMediaZeroState else {
                    return false
                }
                guard $0.mediaKind == .visual,
                      let identifier = $0.imageIdentifier else {
                    return true
                }
                return !unavailableIdentifiers.contains(identifier)
            }
            guard hasSubmittedUserVisual else {
                return pagesWithoutFailedUserVisuals
            }
            return pagesWithoutFailedUserVisuals + [userMediaZeroStatePage]
        }

        let hasLoadedReference = orderedPages.contains { page in
            guard page.imageOrigin == .reference,
                  let identifier = page.imageIdentifier else {
                return false
            }
            return loadedReferenceIdentifiers.contains(identifier)
                && !unavailableIdentifiers.contains(identifier)
        }
        guard hasLoadedReference else {
            return orderedPages
        }

        return orderedPages.filter { page in
            guard page.imageOrigin == .user,
                  let identifier = page.imageIdentifier else {
                return true
            }
            return !unavailableIdentifiers.contains(identifier)
        }
    }

    private static func isUserVisual(_ page: CarouselPageItem) -> Bool {
        guard page.imageOrigin == .user else { return false }
        return page.mediaKind == .visual || page.mediaKind == .video
    }

    private static var userMediaZeroStatePage: CarouselPageItem {
        CarouselPageItem(
            id: "user-media-unavailable",
            mediaKind: .visual,
            view: AnyView(
                UnavailableVisualsView(
                    isOffline: false,
                    context: .originalPhoto
                )
                .accessibilityIdentifier("InsightUserMediaUnavailableState")
            ),
            imageOrigin: .user,
            isUserMediaZeroState: true
        )
    }

    private static func movingUnavailableImagesToBack(
        _ pages: [CarouselPageItem],
        unavailableIdentifiers: Set<String>
    ) -> [CarouselPageItem] {
        let imageIndices = pages.indices.filter { index in
            pages[index].mediaKind == .visual
                && pages[index].id != "reference-loading"
        }
        guard imageIndices.count > 1, !unavailableIdentifiers.isEmpty else {
            return pages
        }

        let imagePages = imageIndices.map { pages[$0] }
        let availablePages = imagePages.filter { page in
            guard let identifier = page.imageIdentifier else { return true }
            return !unavailableIdentifiers.contains(identifier)
        }
        let unavailablePages = imagePages.filter { page in
            guard let identifier = page.imageIdentifier else { return false }
            return unavailableIdentifiers.contains(identifier)
        }

        var reorderedPages = pages
        for (index, page) in zip(
            imageIndices,
            availablePages + unavailablePages
        ) {
            reorderedPages[index] = page
        }
        return reorderedPages
    }
}
