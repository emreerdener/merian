import SwiftUI

@MainActor
struct CarouselPageBuilder {
    static func buildPages(
        for activeMedia: ActiveScanMedia,
        referenceWikipediaUrl: String?,
        selectedIndex: Binding<Int> = .constant(0),
        isVideoMuted: Binding<Bool> = .constant(true),
        videoPlaybackCoordinator: InsightCarouselVideoPlaybackCoordinator? = nil,
        dependencies: MediaPlaybackDependencies? = nil,
        onVideoAvailabilityChange: @escaping (String, Bool) -> Void = { _, _ in },
        isAudioBoostEnabled: Binding<Bool> = .constant(false),
        audioBoostActionToken: UUID? = nil,
        onAudioBoostActionFinished: ((UUID) -> Void)? = nil,
        onAudioBoostToggleRequested: (() -> Void)? = nil,
        onImageSuccess: @escaping (String) -> Void = { _ in },
        onImageFailure: @escaping (String) -> Void,
        onDescriptionTap: (() -> Void)?
    ) -> [CarouselPageItem] {
        let dependencies = dependencies ?? .live
        var pages: [CarouselPageItem] = []
        var stillImageSourceIndex = 0

        for item in activeMedia.items {
            switch item {
            case .liveImage(let data):
                let sourceIndex = stillImageSourceIndex
                let focusRegion = activeMedia.focusRegionsBySourceIndex[sourceIndex]
                stillImageSourceIndex += 1
                let pageID = "liveImage-\(data.hashValue)"
                pages.append(CarouselPageItem(
                    id: pageID,
                    mediaKind: .visual,
                    view: AnyView(LiveCapturePageView(data: data)),
                    imageOrigin: .user,
                    galleryItem: MediaGalleryItem(
                        id: pageID,
                        source: .liveImage(data),
                        referenceAttributionLabel: nil
                    ),
                    stillImageSourceIndex: sourceIndex,
                    focusRegion: focusRegion
                ))
            case .image(let path):
                let sourceIndex = stillImageSourceIndex
                let focusRegion = activeMedia.focusRegionsBySourceIndex[sourceIndex]
                stillImageSourceIndex += 1
                let pageID = "image-\(path)"
                pages.append(CarouselPageItem(
                    id: pageID,
                    mediaKind: .visual,
                    view: AnyView(
                        AsyncLocalImageView(
                            path: path,
                            fallbackImageUrl: nil,
                            unavailableContext: .originalPhoto,
                            onImageLoaded: { onImageSuccess(path) },
                            onImageLoadFailed: { onImageFailure(path) }
                        )
                    ),
                    imageIdentifier: path,
                    imageOrigin: .user,
                    galleryItem: MediaGalleryItem(
                        id: pageID,
                        source: .imagePath(path),
                        referenceAttributionLabel: nil
                    ),
                    stillImageSourceIndex: sourceIndex,
                    focusRegion: focusRegion
                ))
            case .description(let context):
                pages.append(CarouselPageItem(
                    id: "description-\(context.serialized())",
                    mediaKind: .description,
                    view: AnyView(DescriptionTextCarouselPage(
                        text: context.serialized(),
                        onTap: onDescriptionTap
                    ))
                ))
            case .audio(let resolvedPath):
                pages.append(CarouselPageItem(
                    id: "audio-\(resolvedPath)",
                    mediaKind: .audio,
                    view: AnyView(AudioPlaybackCarouselPage(
                        filePath: resolvedPath,
                        isAudioBoostEnabled: isAudioBoostEnabled,
                        audioBoostActionToken: audioBoostActionToken,
                        onAudioBoostActionFinished: onAudioBoostActionFinished,
                        onAudioBoostToggleRequested: onAudioBoostToggleRequested,
                        dependencies: dependencies
                    ))
                ))
            case .video(let resolvedPath, let fallbackImage):
                let pageIndex = pages.count
                let pageID = "video-\(resolvedPath)"
                pages.append(CarouselPageItem(
                    id: pageID,
                    mediaKind: .video,
                    view: AnyView(InlineVideoPlaybackCarouselPage(
                        path: resolvedPath,
                        pageIndex: pageIndex,
                        selectedIndex: selectedIndex,
                        isMuted: isVideoMuted,
                        playbackCoordinator: videoPlaybackCoordinator,
                        dependencies: dependencies,
                        onAvailabilityChange: {
                            onVideoAvailabilityChange(pageID, $0)
                        }
                    )),
                    imageOrigin: .user,
                    galleryItem: MediaGalleryItem(
                        id: pageID,
                        source: .videoPath(resolvedPath),
                        referenceAttributionLabel: nil
                    ),
                    videoFallback: fallbackImage.map {
                        makeVideoFallback(
                            source: $0,
                            onImageSuccess: onImageSuccess,
                            onImageFailure: onImageFailure
                        )
                    }
                ))
            }
        }

        switch activeMedia.referenceState {
        case .empty:
            break
        case .loading:
            pages.append(CarouselPageItem(
                id: "reference-loading",
                mediaKind: .visual,
                view: AnyView(
                    ZStack {
                        Color(uiColor: .systemGray6)
                        ProgressView()
                            .controlSize(.regular)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                )
            ))
        case .loaded(let urls):
            for (index, urlString) in urls.enumerated() {
                let label = CarouselReferenceAttributionPolicy.label(
                    for: urlString,
                    wikipediaURL: referenceWikipediaUrl,
                    index: index
                )
                let pageID = "reference-\(urlString)"
                pages.append(CarouselPageItem(
                    id: pageID,
                    mediaKind: .visual,
                    view: AnyView(
                        AsyncLocalImageView(
                            path: nil,
                            fallbackImageUrl: urlString,
                            onImageLoaded: { onImageSuccess(urlString) },
                            onImageLoadFailed: { onImageFailure(urlString) }
                        )
                    ),
                    imageIdentifier: urlString,
                    imageOrigin: .reference,
                    referenceAttributionLabel: label,
                    galleryItem: MediaGalleryItem(
                        id: pageID,
                        source: .referenceURL(urlString),
                        referenceAttributionLabel: label
                    )
                ))
            }
        }

        return pages
    }

    private static func makeVideoFallback(
        source: VideoFallbackImageSource,
        onImageSuccess: @escaping (String) -> Void,
        onImageFailure: @escaping (String) -> Void
    ) -> CarouselVideoFallback {
        switch source {
        case .liveImage(let data):
            CarouselVideoFallback(
                source: source,
                view: AnyView(
                    LiveCapturePageView(data: data)
                        .accessibilityIdentifier("InsightVideoFallbackImage")
                ),
                imageIdentifier: nil
            )
        case .imagePath(let path):
            CarouselVideoFallback(
                source: source,
                view: AnyView(
                    AsyncLocalImageView(
                        path: path,
                        fallbackImageUrl: nil,
                        unavailableContext: .originalPhoto,
                        onImageLoaded: { onImageSuccess(path) },
                        onImageLoadFailed: { onImageFailure(path) }
                    )
                    .accessibilityIdentifier("InsightVideoFallbackImage")
                ),
                imageIdentifier: path
            )
        }
    }
}
