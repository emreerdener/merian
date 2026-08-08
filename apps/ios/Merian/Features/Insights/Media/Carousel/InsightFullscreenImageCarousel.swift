import AVFoundation
import Combine
import SwiftUI

struct InsightFullscreenImageCarousel: View {
    let presentation: InsightImageGalleryPresentation

    @Environment(\.dismiss) private var dismiss
    @State private var selectedItemID: String?
    @State private var isVideoMuted: Bool
    @State private var unavailableVideoItemIDs: Set<String> = []

    init(presentation: InsightImageGalleryPresentation) {
        self.presentation = presentation
        _isVideoMuted = State(initialValue: presentation.initialVideoMuted)
    }

    private var selectedItem: InsightImageGalleryItem? {
        let fallbackID = presentation.items[safe: presentation.initialSelectedIndex]?.id
        let activeID = selectedItemID ?? fallbackID
        return presentation.items.first { $0.id == activeID } ?? presentation.items.first
    }

    private var isSelectedVideoUnavailable: Bool {
        guard let selectedItem, selectedItem.source.isVideo else { return false }
        return unavailableVideoItemIDs.contains(selectedItem.id)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(presentation.items) { item in
                        Group {
                            if item.source.isVideo {
                                galleryContent(for: item)
                            } else {
                                ZoomableScrollView {
                                    galleryContent(for: item)
                                }
                            }
                        }
                        .containerRelativeFrame(.horizontal)
                        .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedItemID)
            .ignoresSafeArea()

            topControls
            bottomControls
        }
        .simultaneousGesture(swipeDownToDismissGesture)
        .onAppear {
            selectedItemID = presentation.items[safe: presentation.initialSelectedIndex]?.id
        }
    }

    private var swipeDownToDismissGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let verticalDistance = value.translation.height
                let horizontalDistance = abs(value.translation.width)
                let predictedVerticalDistance = value.predictedEndTranslation.height
                let effectiveVerticalDistance = max(verticalDistance, predictedVerticalDistance * 0.55)

                guard effectiveVerticalDistance > 70 else { return }
                guard effectiveVerticalDistance > horizontalDistance * 1.2 else { return }

                dismiss()
            }
    }

    private var topControls: some View {
        VStack {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(Circle().fill(.white.opacity(0.14)))
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close image viewer")

                Spacer()

                if selectedItem?.source.isVideo == true, !isSelectedVideoUnavailable {
                    Button {
                        isVideoMuted.toggle()
                        HapticManager.shared.triggerSelectionPulse(
                            source: "media.insight.fullscreen.mute.\(isVideoMuted ? "on" : "off")"
                        )
                    } label: {
                        Image(systemName: isVideoMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(Circle().fill(.white.opacity(0.14)))
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isVideoMuted ? "Unmute video" : "Mute video")
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 16)

            Spacer()
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func galleryContent(for item: InsightImageGalleryItem) -> some View {
        if let accessibilityLabel = item.accessibilityLabel {
            galleryMedia(for: item)
                .accessibilityLabel(accessibilityLabel)
        } else {
            galleryMedia(for: item)
        }
    }

    @ViewBuilder
    private func galleryMedia(for item: InsightImageGalleryItem) -> some View {
        switch item.source {
        case .liveImage(let data):
            FullscreenLiveImageView(data: data)
        case .imagePath(let path):
            AsyncLocalImageView(
                path: path,
                fallbackImageUrl: nil,
                contentMode: .fit,
                unavailableContext: .originalPhoto,
                onImageLoadFailed: nil
            )
        case .videoPath(let path):
            FullscreenVideoView(
                path: path,
                isSelected: item.id == selectedItem?.id,
                isMuted: $isVideoMuted,
                onAvailabilityChange: {
                    updateVideoAvailability(itemID: item.id, isUnavailable: $0)
                }
            )
        case .referenceURL(let urlString):
            AsyncLocalImageView(
                path: nil,
                fallbackImageUrl: urlString,
                contentMode: .fit,
                onImageLoadFailed: nil
            )
        }
    }

    private func updateVideoAvailability(itemID: String, isUnavailable: Bool) {
        if isUnavailable {
            unavailableVideoItemIDs.insert(itemID)
        } else {
            unavailableVideoItemIDs.remove(itemID)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                if let label = selectedItem?.referenceAttributionLabel {
                    Text(label)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule(style: .continuous)
                                .fill(.white.opacity(0.14))
                        }
                        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if presentation.items.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(presentation.items) { item in
                            Circle()
                                .fill(item.id == selectedItem?.id ? Color.white : Color.white.opacity(0.35))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedItem?.id)
            .padding(.bottom, 24)
        }
    }
}

private extension InsightImageGalleryItem.Source {
    var isVideo: Bool {
        if case .videoPath = self { return true }
        return false
    }
}

private struct FullscreenVideoView: View {
    let path: String
    let isSelected: Bool
    @Binding var isMuted: Bool
    let onAvailabilityChange: (Bool) -> Void

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var availability = InsightVideoPlaybackAvailability.loading
    @State private var playbackEndObserver: NSObjectProtocol?
    @State private var playbackFailureObserver: NSObjectProtocol?

    var body: some View {
        ZStack {
            Color.black

            if let player,
               let playerItem = player.currentItem,
               availability != .unavailable {
                InsightCoverVideoPlayer(player: player, videoGravity: .resizeAspect)
                    .ignoresSafeArea()
                    .onReceive(playerItem.publisher(for: \.status).removeDuplicates()) { status in
                        updateAvailability(for: status, observedPlayer: player)
                    }
            }

            switch availability {
            case .loading:
                ProgressView()
                    .tint(.white)
            case .ready:
                InsightCenterVideoPlaybackControl(
                    isPlaying: isPlaying,
                    action: togglePlayback
                )
            case .unavailable:
                InsightUnavailableVideoView()
            }
        }
        .task(id: path) {
            configurePlayer()
        }
        .onChange(of: isMuted) { _, newValue in
            guard !newValue else {
                player?.isMuted = true
                return
            }
            Task { @MainActor in
                let activated = await MediaPlaybackAudioSession.activate(
                    source: "media.insight.fullscreen.unmute"
                )
                guard activated, !isMuted else { return }
                player?.isMuted = false
            }
        }
        .onChange(of: isSelected) { _, newValue in
            if !newValue {
                player?.pause()
                isPlaying = false
            } else if availability == .ready {
                startPlayback(source: "media.insight.fullscreen.selection")
            }
        }
        .onDisappear {
            player?.pause()
            isPlaying = false
            removePlaybackObservers()
        }
    }

    private func configurePlayer() {
        player?.pause()
        removePlaybackObservers()
        isPlaying = false
        availability = .loading
        onAvailabilityChange(false)

        guard let url = resolvedURL(path) else {
            player = nil
            markUnavailable()
            return
        }

        let configuredPlayer = AVPlayer(url: url)
        configuredPlayer.isMuted = isMuted
        configuredPlayer.actionAtItemEnd = .pause
        player = configuredPlayer
        updateAvailability(
            for: configuredPlayer.currentItem?.status ?? .unknown,
            observedPlayer: configuredPlayer
        )
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: configuredPlayer.currentItem,
            queue: .main
        ) { _ in
            configuredPlayer.seek(to: .zero)
            guard isSelected else {
                isPlaying = false
                return
            }
            startPlayback(source: "media.insight.fullscreen.loop")
        }
        playbackFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: configuredPlayer.currentItem,
            queue: .main
        ) { _ in
            guard self.player === configuredPlayer else { return }
            markUnavailable()
        }
    }

    private func togglePlayback() {
        guard availability == .ready, let player else { return }

        if isPlaying {
            HapticManager.shared.triggerLightImpact(
                intensity: 0.55,
                source: "media.insight.fullscreen.pause"
            )
            player.pause()
            isPlaying = false
        } else {
            HapticManager.shared.triggerMediumPulse(source: "media.insight.fullscreen.play")
            startPlayback(source: "media.insight.fullscreen.play")
        }
    }

    private func startPlayback(source: String) {
        guard availability == .ready, isSelected, let player else { return }
        guard !isMuted else {
            player.play()
            isPlaying = true
            return
        }

        Task { @MainActor in
            let activated = await MediaPlaybackAudioSession.activate(source: source)
            guard activated, self.player === player, isSelected, !isMuted else { return }
            player.isMuted = false
            player.play()
            isPlaying = true
        }
    }

    private func updateAvailability(
        for status: AVPlayerItem.Status,
        observedPlayer: AVPlayer
    ) {
        guard player === observedPlayer else { return }
        let nextAvailability = InsightVideoPlaybackAvailability(itemStatus: status)
        availability = nextAvailability
        onAvailabilityChange(nextAvailability == .unavailable)

        switch nextAvailability {
        case .loading:
            break
        case .ready:
            startPlayback(source: "media.insight.fullscreen.autoplay")
        case .unavailable:
            observedPlayer.pause()
            isPlaying = false
        }
    }

    private func markUnavailable() {
        availability = .unavailable
        player?.pause()
        isPlaying = false
        onAvailabilityChange(true)
    }

    private func removePlaybackObservers() {
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
        if let playbackFailureObserver {
            NotificationCenter.default.removeObserver(playbackFailureObserver)
            self.playbackFailureObserver = nil
        }
    }

    private func resolvedURL(_ rawPath: String) -> URL? {
        SecureTransportPolicy.localFileOrHTTPSURL(from: rawPath)
    }
}

private struct FullscreenLiveImageView: View {
    let data: Data

    @State private var decodedImage: UIImage?
    @State private var decodedImageKey: Int?

    var body: some View {
        Group {
            if let decodedImage {
                Image(uiImage: decodedImage)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: data.hashValue) {
            await loadImageIfNeeded()
        }
    }

    @MainActor
    private func loadImageIfNeeded() async {
        let key = data.hashValue
        if decodedImageKey == key, decodedImage != nil { return }

        let cacheKey = NSNumber(value: key)
        if let cached = liveCaptureCache.object(forKey: cacheKey) {
            decodedImage = cached
            decodedImageKey = key
            return
        }

        let imageData = data
        let preparedImage = try? await DetachedWork.value(
            priority: .utility,
            category: .imagePreparation
        ) {
            autoreleasepool {
                ImageDownsampler.downsample(data: imageData, maxSize: 2048)
                    .map { SendableCGImage(image: $0) }
            }
        }

        guard let preparedImage, !Task.isCancelled else { return }
        let image = UIImage(cgImage: preparedImage.image)
        let cost = Int(image.size.width * image.size.height * 4)
        liveCaptureCache.setObject(image, forKey: cacheKey, cost: cost)
        decodedImage = image
        decodedImageKey = key
    }
}
