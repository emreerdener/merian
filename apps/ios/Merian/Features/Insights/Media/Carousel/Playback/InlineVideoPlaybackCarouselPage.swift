import AVFoundation
import Combine
import SwiftUI

struct InlineVideoPlaybackCarouselPage: View {
    @MainActor
    private static let inactivePausePublisher = Empty<Void, Never>(
        completeImmediately: false
    ).eraseToAnyPublisher()

    let path: String
    let pageIndex: Int
    @Binding var selectedIndex: Int
    @Binding var isMuted: Bool
    let playbackCoordinator: InsightCarouselVideoPlaybackCoordinator?
    let dependencies: MediaPlaybackDependencies
    let onAvailabilityChange: (Bool) -> Void

    @State private var player: AVPlayer?
    @State private var hasAutoplayed = false
    @State private var isPlaying = false
    @State private var availability = VideoPlaybackAvailability.loading
    @State private var playbackObservation = MediaPlaybackObservation()

    private var isSelected: Bool {
        selectedIndex == pageIndex
    }

    var body: some View {
        ZStack {
            Color.black

            if let player, availability != .unavailable {
                MediaCoverVideoPlayer(player: player)
                    .ignoresSafeArea()
            }

            switch availability {
            case .loading:
                ProgressView()
                    .tint(.white)
            case .ready:
                CenterVideoPlaybackControl(
                    isPlaying: isPlaying,
                    action: togglePlayback
                )
            case .unavailable:
                UnavailableVideoView()
            }
        }
        .task(id: path) {
            configurePlayer()
        }
        .onChange(of: playbackObservation.timeControlStatus) { _, status in
            handlePlaybackStatusChange(status)
        }
        .onChange(of: playbackObservation.itemStatus) { _, status in
            guard let player else { return }
            updateAvailability(for: status, observedPlayer: player)
        }
        .onChange(of: playbackObservation.eventSequence) { _, _ in
            handlePlaybackLifecycleEvent()
        }
        .onChange(of: selectedIndex) { _, _ in
            updatePlaybackForSelection()
        }
        .onChange(of: isMuted) { _, newValue in
            guard !newValue else {
                player?.isMuted = true
                return
            }
            Task { @MainActor in
                let activated = await dependencies.activatePlaybackAudio(
                    "media.insight.carousel.unmute"
                )
                guard activated, !isMuted else { return }
                player?.isMuted = false
            }
        }
        .onReceive(fullscreenPresentationPausePublisher) {
            player?.pause()
            isPlaying = false
        }
        .onDisappear {
            player?.pause()
            isPlaying = false
            playbackObservation.detach()
        }
    }

    @MainActor
    private var fullscreenPresentationPausePublisher: AnyPublisher<Void, Never> {
        playbackCoordinator?.pauseForFullscreenPresentationPublisher
            ?? Self.inactivePausePublisher
    }

    private func configurePlayer() {
        player?.pause()
        playbackObservation.detach()
        hasAutoplayed = false
        isPlaying = false
        availability = .loading
        onAvailabilityChange(false)

        guard let url = SecureTransportPolicy.localFileOrHTTPSURL(
            from: path
        ) else {
            player = nil
            markUnavailable()
            return
        }

        let configuredPlayer = AVPlayer(url: url)
        configuredPlayer.isMuted = isMuted
        configuredPlayer.actionAtItemEnd = .pause
        player = configuredPlayer
        playbackObservation.observe(configuredPlayer)
        handlePlaybackStatusChange(playbackObservation.timeControlStatus)
        updateAvailability(
            for: playbackObservation.itemStatus,
            observedPlayer: configuredPlayer
        )
        updatePlaybackForSelection()
    }

    private func updatePlaybackForSelection() {
        guard availability == .ready, let player else { return }

        if isSelected {
            if !hasAutoplayed {
                startPlayback(fromBeginning: true)
            }
        } else if isPlaying {
            player.pause()
            isPlaying = false
        }
    }

    private func startPlayback(fromBeginning: Bool) {
        guard let player else { return }
        if fromBeginning {
            player.seek(to: .zero)
        }
        player.isMuted = isMuted
        hasAutoplayed = true
        play(player, source: "media.insight.carousel.autoplay")
    }

    private func togglePlayback() {
        guard availability == .ready, let player else { return }

        if isPlaying {
            dependencies.lightImpactFeedback(
                0.55,
                "media.insight.carousel.pause"
            )
            player.pause()
            isPlaying = false
        } else {
            dependencies.mediumPulseFeedback(
                "media.insight.carousel.play"
            )
            hasAutoplayed = true
            play(player, source: "media.insight.carousel.play")
        }
    }

    private func handlePlaybackLifecycleEvent() {
        guard let player, playbackObservation.isObserving(player) else { return }

        switch playbackObservation.lastEvent {
        case .didReachEnd:
            player.seek(to: .zero)
            guard isSelected else {
                isPlaying = false
                return
            }
            play(player, source: "media.insight.carousel.loop")
        case .failedToPlayToEnd:
            markUnavailable()
        case .playbackStalled:
            player.pause()
            isPlaying = false
        case nil:
            break
        }
    }

    private func handlePlaybackStatusChange(
        _ status: AVPlayer.TimeControlStatus
    ) {
        switch status {
        case .playing:
            isPlaying = true
        case .paused:
            isPlaying = false
        case .waitingToPlayAtSpecifiedRate:
            break
        @unknown default:
            isPlaying = false
        }
    }

    private func play(_ player: AVPlayer, source: String) {
        guard availability == .ready, isSelected else { return }
        guard !isMuted else {
            player.play()
            isPlaying = true
            return
        }

        Task { @MainActor in
            let activated = await dependencies.activatePlaybackAudio(source)
            guard activated,
                  self.player === player,
                  isSelected,
                  !isMuted else { return }
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
        let nextAvailability = VideoPlaybackAvailability(
            itemStatus: status
        )
        availability = nextAvailability
        onAvailabilityChange(nextAvailability == .unavailable)

        switch nextAvailability {
        case .loading:
            break
        case .ready:
            updatePlaybackForSelection()
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
}
