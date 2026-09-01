import AVFoundation
import SwiftUI

struct FullscreenMediaVideoPlaybackView: View {
    let path: String
    let isSelected: Bool
    @Binding var isMuted: Bool
    let dependencies: MediaPlaybackDependencies
    let onAvailabilityChange: (Bool) -> Void

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var availability = VideoPlaybackAvailability.loading
    @State private var playbackObservation = MediaPlaybackObservation()

    var body: some View {
        ZStack {
            Color.black

            if let player, availability != .unavailable {
                MediaCoverVideoPlayer(
                    player: player,
                    videoGravity: .resizeAspect
                )
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
        .onChange(of: playbackObservation.itemStatus) { _, status in
            guard let player else { return }
            updateAvailability(for: status, observedPlayer: player)
        }
        .onChange(of: playbackObservation.eventSequence) { _, _ in
            handlePlaybackLifecycleEvent()
        }
        .onChange(of: isMuted) { _, newValue in
            guard !newValue else {
                player?.isMuted = true
                return
            }
            Task { @MainActor in
                let activated = await dependencies.activatePlaybackAudio(
                    dependencies.feedbackIdentifier(.fullscreenUnmute)
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
                startPlayback(
                    source: dependencies.feedbackIdentifier(
                        .fullscreenSelection
                    )
                )
            }
        }
        .onDisappear {
            player?.pause()
            isPlaying = false
            playbackObservation.detach()
        }
    }

    private func configurePlayer() {
        player?.pause()
        playbackObservation.detach()
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
        updateAvailability(
            for: playbackObservation.itemStatus,
            observedPlayer: configuredPlayer
        )
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
            startPlayback(
                source: dependencies.feedbackIdentifier(.fullscreenLoop)
            )
        case .failedToPlayToEnd:
            markUnavailable()
        case .playbackStalled:
            player.pause()
            isPlaying = false
        case nil:
            break
        }
    }

    private func togglePlayback() {
        guard availability == .ready, let player else { return }

        if isPlaying {
            dependencies.lightImpactFeedback(
                0.55,
                dependencies.feedbackIdentifier(.fullscreenPause)
            )
            player.pause()
            isPlaying = false
        } else {
            dependencies.mediumPulseFeedback(
                dependencies.feedbackIdentifier(.fullscreenPlay)
            )
            startPlayback(
                source: dependencies.feedbackIdentifier(.fullscreenPlay)
            )
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
            startPlayback(
                source: dependencies.feedbackIdentifier(.fullscreenAutoplay)
            )
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
