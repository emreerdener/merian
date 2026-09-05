import SwiftUI
import UIKit

struct ExplorePostMediaCarouselPageID: Hashable {
    let namespace: String
    let kind: ExploreMediaKind
    let url: String
    let occurrence: Int
}

enum ExplorePostMediaCarouselPolicy {
    struct Page: Identifiable, Equatable {
        let id: ExplorePostMediaCarouselPageID
        let index: Int
        let mediaItem: ExploreMediaItem
    }

    private struct MediaIdentity: Hashable {
        let kind: ExploreMediaKind
        let url: String
    }

    static func orderedItems(
        _ mediaItems: [ExploreMediaItem]?,
        fallbackImageUrl: String
    ) -> [ExploreMediaItem] {
        let resolvedItems: [ExploreMediaItem]
        if let mediaItems, !mediaItems.isEmpty {
            resolvedItems = mediaItems
        } else {
            resolvedItems = [.legacyImage(url: fallbackImageUrl)]
        }

        return resolvedItems
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.orderIndex == rhs.element.orderIndex {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.orderIndex < rhs.element.orderIndex
            }
            .map(\.element)
    }

    static func pages(
        for mediaItems: [ExploreMediaItem],
        namespace: String
    ) -> [Page] {
        var occurrenceCounts: [MediaIdentity: Int] = [:]

        return mediaItems.enumerated().map { index, mediaItem in
            let mediaIdentity = MediaIdentity(
                kind: mediaItem.kind,
                url: mediaItem.url
            )
            let occurrence = occurrenceCounts[mediaIdentity, default: 0]
            occurrenceCounts[mediaIdentity] = occurrence + 1

            return Page(
                id: ExplorePostMediaCarouselPageID(
                    namespace: namespace,
                    kind: mediaItem.kind,
                    url: mediaItem.url,
                    occurrence: occurrence
                ),
                index: index,
                mediaItem: mediaItem
            )
        }
    }

    static func reconciledSelectedPageID(
        currentID: ExplorePostMediaCarouselPageID?,
        previousPages: [Page],
        updatedPages: [Page]
    ) -> ExplorePostMediaCarouselPageID? {
        guard let firstUpdatedPage = updatedPages.first else { return nil }
        guard previousPages.first?.id.namespace == firstUpdatedPage.id.namespace else {
            return firstUpdatedPage.id
        }
        guard let currentID else { return firstUpdatedPage.id }
        if updatedPages.contains(where: { $0.id == currentID }) {
            return currentID
        }

        return firstUpdatedPage.id
    }

    static func detailAudioSeekingMode(mediaItemCount: Int) -> AudioSpectrogramSeekingMode {
        mediaItemCount > 1 ? .playmarkerOnly : .fullSpectrogram
    }

    static func allowsAudioBoost(mediaItem: ExploreMediaItem, index: Int) -> Bool {
        index == 0 && mediaItem.kind == .audio
    }

    static func hasPrimaryStandaloneAudio(
        _ mediaItems: [ExploreMediaItem]?,
        fallbackImageUrl: String
    ) -> Bool {
        orderedItems(
            mediaItems,
            fallbackImageUrl: fallbackImageUrl
        ).first?.kind == .audio
    }
}

struct ExploreSquareMediaView<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }
}

private struct ExplorePostMediaCarousel<Content: View>: View {
    let mediaItems: [ExploreMediaItem]
    let namespace: String
    let accessibilityIdentifier: String
    let content: (ExploreMediaItem, Int, Bool) -> Content
    @State private var selectedPageID: ExplorePostMediaCarouselPageID?

    init(
        mediaItems: [ExploreMediaItem],
        namespace: String,
        accessibilityIdentifier: String,
        @ViewBuilder content: @escaping (
            ExploreMediaItem,
            Int,
            Bool
        ) -> Content
    ) {
        self.mediaItems = mediaItems
        self.namespace = namespace
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content
    }

    private var pages: [ExplorePostMediaCarouselPolicy.Page] {
        ExplorePostMediaCarouselPolicy.pages(
            for: mediaItems,
            namespace: namespace
        )
    }

    private var resolvedSelectedPageID: ExplorePostMediaCarouselPageID? {
        guard let selectedPageID,
              pages.contains(where: { $0.id == selectedPageID }) else {
            return pages.first?.id
        }
        return selectedPageID
    }

    private var selectedIndex: Int {
        guard let resolvedSelectedPageID else { return 0 }
        return pages.firstIndex { $0.id == resolvedSelectedPageID } ?? 0
    }

    @ViewBuilder
    var body: some View {
        Group {
            if pages.count == 1, let page = pages.first {
                content(page.mediaItem, page.index, true)
            } else {
                GeometryReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(pages) { page in
                                content(
                                    page.mediaItem,
                                    page.index,
                                    page.id == resolvedSelectedPageID
                                )
                                .frame(
                                    width: proxy.size.width,
                                    height: proxy.size.height
                                )
                                .accessibilityHidden(
                                    page.id != resolvedSelectedPageID
                                )
                                .id(page.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $selectedPageID)
                }
            }
        }
        .overlay(alignment: .bottom) {
            MediaCarouselPaginationDots(
                pageCount: pages.count,
                selectedIndex: selectedIndex,
                bottomPadding: 14,
                accessibilityNoun: "Media"
            )
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .onAppear {
            selectedPageID = resolvedSelectedPageID
        }
        .onChange(of: pages) { previousPages, updatedPages in
            selectedPageID = ExplorePostMediaCarouselPolicy
                .reconciledSelectedPageID(
                    currentID: selectedPageID,
                    previousPages: previousPages,
                    updatedPages: updatedPages
                )
        }
    }
}

struct ExploreFeedMediaView: View {
    let postId: String
    let imageUrl: String
    let mediaItems: [ExploreMediaItem]
    let reloadGeneration: UInt64
    let preloadedImage: UIImage?
    @Binding var audioBoostEnabled: Bool
    let audioBoostActionToken: UUID?
    let onAudioBoostActionFinished: ((UUID) -> Void)?
    let onAudioBoostToggleRequested: (() -> Void)?
    let onSingleTap: (() -> Void)?
    let onDoubleTap: (() -> Void)?

    init(
        postId: String,
        imageUrl: String,
        mediaItems: [ExploreMediaItem]? = nil,
        reloadGeneration: UInt64,
        preloadedImage: UIImage? = nil,
        audioBoostEnabled: Binding<Bool> = .constant(false),
        audioBoostActionToken: UUID? = nil,
        onAudioBoostActionFinished: ((UUID) -> Void)? = nil,
        onAudioBoostToggleRequested: (() -> Void)? = nil,
        onSingleTap: (() -> Void)? = nil,
        onDoubleTap: (() -> Void)? = nil
    ) {
        self.postId = postId
        self.imageUrl = imageUrl
        self.mediaItems = ExplorePostMediaCarouselPolicy.orderedItems(
            mediaItems,
            fallbackImageUrl: imageUrl
        )
        self.reloadGeneration = reloadGeneration
        self.preloadedImage = preloadedImage
        self._audioBoostEnabled = audioBoostEnabled
        self.audioBoostActionToken = audioBoostActionToken
        self.onAudioBoostActionFinished = onAudioBoostActionFinished
        self.onAudioBoostToggleRequested = onAudioBoostToggleRequested
        self.onSingleTap = onSingleTap
        self.onDoubleTap = onDoubleTap
    }

    var body: some View {
        // The scrolling feed intentionally uses a plain image host instead of the zoom wrapper.
        // That keeps every card on a stable square layout proposal regardless of source aspect ratio.
        ExploreSquareMediaView {
            ExplorePostMediaCarousel(
                mediaItems: mediaItems,
                namespace: postId,
                accessibilityIdentifier: "ExploreFeedMediaCarousel"
            ) { mediaItem, index, isSelected in
                let allowsAudioBoost = ExplorePostMediaCarouselPolicy
                    .allowsAudioBoost(mediaItem: mediaItem, index: index)
                ExplorePublicMediaView(
                    mediaItem: mediaItem,
                    fallbackImageUrl: imageUrl,
                    reloadGeneration: reloadGeneration,
                    preloadedImage: index == 0 ? preloadedImage : nil,
                    surface: .feed,
                    isPlaybackActive: isSelected,
                    autoplay: true,
                    showsVideoControls: true,
                    audioBoostEnabled: allowsAudioBoost && audioBoostEnabled,
                    audioBoostActionToken: allowsAudioBoost ? audioBoostActionToken : nil,
                    onAudioBoostActionFinished: allowsAudioBoost ? onAudioBoostActionFinished : nil,
                    onAudioBoostToggleRequested: allowsAudioBoost ? onAudioBoostToggleRequested : nil,
                    onSingleTap: onSingleTap,
                    onDoubleTap: onDoubleTap
                )
                .accessibilityIdentifier("ExploreFeedMediaPage_\(index)")
            }
        }
    }
}

struct ExploreDetailMediaView: View {
    let postId: String
    let imageUrl: String
    let mediaItems: [ExploreMediaItem]
    let reloadGeneration: UInt64
    let preloadedImage: UIImage?
    let allowsZoom: Bool
    @Binding var audioBoostEnabled: Bool
    let audioBoostActionToken: UUID?
    let onAudioBoostActionFinished: ((UUID) -> Void)?
    let onAudioBoostToggleRequested: (() -> Void)?

    init(
        postId: String,
        imageUrl: String,
        mediaItems: [ExploreMediaItem]? = nil,
        reloadGeneration: UInt64,
        preloadedImage: UIImage? = nil,
        allowsZoom: Bool = true,
        audioBoostEnabled: Binding<Bool> = .constant(false),
        audioBoostActionToken: UUID? = nil,
        onAudioBoostActionFinished: ((UUID) -> Void)? = nil,
        onAudioBoostToggleRequested: (() -> Void)? = nil
    ) {
        self.postId = postId
        self.imageUrl = imageUrl
        self.mediaItems = ExplorePostMediaCarouselPolicy.orderedItems(
            mediaItems,
            fallbackImageUrl: imageUrl
        )
        self.reloadGeneration = reloadGeneration
        self.preloadedImage = preloadedImage
        self.allowsZoom = allowsZoom
        self._audioBoostEnabled = audioBoostEnabled
        self.audioBoostActionToken = audioBoostActionToken
        self.onAudioBoostActionFinished = onAudioBoostActionFinished
        self.onAudioBoostToggleRequested = onAudioBoostToggleRequested
    }

    var body: some View {
        // Detail is the only path that opts into transient zoom behavior.
        ExploreSquareMediaView {
            ExplorePostMediaCarousel(
                mediaItems: mediaItems,
                namespace: postId,
                accessibilityIdentifier: "ExploreDetailMediaCarousel"
            ) { mediaItem, index, isSelected in
                mediaPage(
                    mediaItem,
                    index: index,
                    isSelected: isSelected
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func mediaPage(
        _ mediaItem: ExploreMediaItem,
        index: Int,
        isSelected: Bool
    ) -> some View {
        if allowsZoom && mediaItem.kind == .image {
            ExploreDetailZoomView {
                publicMediaView(
                    mediaItem,
                    index: index,
                    isSelected: isSelected
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            publicMediaView(
                mediaItem,
                index: index,
                isSelected: isSelected
            )
        }
    }

    private func publicMediaView(
        _ mediaItem: ExploreMediaItem,
        index: Int,
        isSelected: Bool
    ) -> some View {
        let allowsAudioBoost = ExplorePostMediaCarouselPolicy
            .allowsAudioBoost(mediaItem: mediaItem, index: index)
        return ExplorePublicMediaView(
            mediaItem: mediaItem,
            fallbackImageUrl: imageUrl,
            reloadGeneration: reloadGeneration,
            preloadedImage: index == 0 ? preloadedImage : nil,
            surface: .detail,
            isPlaybackActive: isSelected,
            autoplay: true,
            showsVideoControls: true,
            allowsAutoplayInLowPowerMode: true,
            detailAudioSeekingMode: ExplorePostMediaCarouselPolicy
                .detailAudioSeekingMode(mediaItemCount: mediaItems.count),
            audioBoostEnabled: allowsAudioBoost && audioBoostEnabled,
            audioBoostActionToken: allowsAudioBoost ? audioBoostActionToken : nil,
            onAudioBoostActionFinished: allowsAudioBoost ? onAudioBoostActionFinished : nil,
            onAudioBoostToggleRequested: allowsAudioBoost ? onAudioBoostToggleRequested : nil
        )
        .accessibilityIdentifier("ExploreDetailMediaPage_\(index)")
    }
}
