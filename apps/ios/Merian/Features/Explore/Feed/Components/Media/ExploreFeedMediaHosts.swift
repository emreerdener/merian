import SwiftUI
import UIKit

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

struct ExploreFeedMediaView: View {
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
        self.imageUrl = imageUrl
        self.mediaItems = mediaItems?.isEmpty == false ? mediaItems! : [.legacyImage(url: imageUrl)]
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
            ExplorePublicMediaView(
                mediaItem: mediaItems.first ?? .legacyImage(url: imageUrl),
                fallbackImageUrl: imageUrl,
                reloadGeneration: reloadGeneration,
                preloadedImage: preloadedImage,
                surface: .feed,
                autoplay: true,
                showsVideoControls: true,
                audioBoostEnabled: audioBoostEnabled,
                audioBoostActionToken: audioBoostActionToken,
                onAudioBoostActionFinished: onAudioBoostActionFinished,
                onAudioBoostToggleRequested: onAudioBoostToggleRequested,
                onSingleTap: onSingleTap,
                onDoubleTap: onDoubleTap
            )
        }
    }
}

struct ExploreDetailMediaView: View {
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
        self.imageUrl = imageUrl
        self.mediaItems = mediaItems?.isEmpty == false ? mediaItems! : [.legacyImage(url: imageUrl)]
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
            if allowsZoom && primaryMediaItem.kind == .image {
                ExploreDetailZoomView {
                    heroImage
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                heroImage
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    private var primaryMediaItem: ExploreMediaItem {
        mediaItems.first ?? .legacyImage(url: imageUrl)
    }

    private var heroImage: some View {
        ExplorePublicMediaView(
            mediaItem: primaryMediaItem,
            fallbackImageUrl: imageUrl,
            reloadGeneration: reloadGeneration,
            preloadedImage: preloadedImage,
            surface: .detail,
            autoplay: true,
            showsVideoControls: true,
            allowsAutoplayInLowPowerMode: true,
            audioBoostEnabled: audioBoostEnabled,
            audioBoostActionToken: audioBoostActionToken,
            onAudioBoostActionFinished: onAudioBoostActionFinished,
            onAudioBoostToggleRequested: onAudioBoostToggleRequested
        )
    }
}
