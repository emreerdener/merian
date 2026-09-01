import SwiftUI

struct CarouselVideoFallback: Equatable {
    let source: VideoFallbackImageSource
    let view: AnyView
    let imageIdentifier: String?

    func galleryItem(pageID: String) -> MediaGalleryItem {
        let gallerySource: MediaGalleryItem.Source
        switch source {
        case .liveImage(let data):
            gallerySource = .liveImage(data)
        case .imagePath(let path):
            gallerySource = .imagePath(path)
        }
        return MediaGalleryItem(
            id: pageID,
            source: gallerySource,
            referenceAttributionLabel: nil
        )
    }

    static func == (
        lhs: CarouselVideoFallback,
        rhs: CarouselVideoFallback
    ) -> Bool {
        lhs.source == rhs.source && lhs.imageIdentifier == rhs.imageIdentifier
    }
}

/// Provides an explicit, stable identity for each page in the carousel.
/// This prevents positional diffing bugs where removing a page from the
/// start or middle recreates stateful tail controllers such as audio playback.
struct CarouselPageItem:
    Identifiable,
    Equatable,
    CarouselSelectionCandidate {
    private struct ReuseIdentity: Hashable {
        let id: String
        let imageOrigin: CarouselImageOrigin?
        let stillImageSourceIndex: Int?
        let focusRegion: NormalizedImageFocusRegion?
    }

    let id: String
    let mediaKind: CarouselMediaKind
    let view: AnyView
    let imageIdentifier: String?
    let imageOrigin: CarouselImageOrigin?
    let referenceAttributionLabel: String?
    let galleryItem: MediaGalleryItem?
    let videoFallback: CarouselVideoFallback?
    let isUserMediaZeroState: Bool
    let stillImageSourceIndex: Int?
    let focusRegion: NormalizedImageFocusRegion?

    init(
        id: String,
        mediaKind: CarouselMediaKind,
        view: AnyView,
        imageIdentifier: String? = nil,
        imageOrigin: CarouselImageOrigin? = nil,
        referenceAttributionLabel: String? = nil,
        galleryItem: MediaGalleryItem? = nil,
        videoFallback: CarouselVideoFallback? = nil,
        isUserMediaZeroState: Bool = false,
        stillImageSourceIndex: Int? = nil,
        focusRegion: NormalizedImageFocusRegion? = nil
    ) {
        self.id = id
        self.mediaKind = mediaKind
        self.view = view
        self.imageIdentifier = imageIdentifier
        self.imageOrigin = imageOrigin
        self.referenceAttributionLabel = referenceAttributionLabel
        self.galleryItem = galleryItem
        self.videoFallback = videoFallback
        self.isUserMediaZeroState = isUserMediaZeroState
        self.stillImageSourceIndex = stillImageSourceIndex
        self.focusRegion = focusRegion
    }

    static func == (lhs: CarouselPageItem, rhs: CarouselPageItem) -> Bool {
        lhs.reuseIdentity == rhs.reuseIdentity
    }

    var nativePage: NativePageCarouselPage {
        NativePageCarouselPage(
            id: id,
            reuseKey: AnyHashable(reuseIdentity),
            view: view
        )
    }

    private var reuseIdentity: ReuseIdentity {
        ReuseIdentity(
            id: id,
            imageOrigin: imageOrigin,
            stillImageSourceIndex: stillImageSourceIndex,
            focusRegion: focusRegion
        )
    }
}
