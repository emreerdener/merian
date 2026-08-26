import AVFoundation
import Combine
import SwiftUI
import UIKit

struct ExplorePublicMediaView: View {
    let mediaItem: ExploreMediaItem
    let fallbackImageUrl: String
    let reloadGeneration: UInt64
    let preloadedImage: UIImage?
    let surface: ExploreVideoPlaybackSurface
    let autoplay: Bool
    let showsVideoControls: Bool
    let allowsAutoplayInLowPowerMode: Bool
    let onSingleTap: (() -> Void)?
    let onDoubleTap: (() -> Void)?
    let audioBoostEnabled: Bool
    let audioBoostActionToken: UUID?
    let onAudioBoostActionFinished: ((UUID) -> Void)?
    let onAudioBoostToggleRequested: (() -> Void)?

    @Environment(ExploreVideoPlaybackCoordinator.self) var playbackCoordinator: ExploreVideoPlaybackCoordinator?
    @Environment(\.scenePhase) private var scenePhase
    @State private var storedPlaybackState = ExplorePublicMediaPlaybackState()
    @AppStorage(ExploreVideoMutePreference.key) private var storedIsMuted = true

    var playbackState: ExplorePublicMediaPlaybackState {
        storedPlaybackState
    }

    var player: AVPlayer? {
        playbackState.player
    }

    var playerId: String {
        playbackState.playerID
    }

    var configuredVideoURL: String? {
        playbackState.configuredMediaURL
    }

    var videoSurfaceGeneration: Int {
        playbackState.videoSurfaceGeneration
    }

    var pendingRecoverySeekTime: CMTime? {
        playbackState.pendingRecoverySeekTime
    }

    var audioPlaybackProgress: Double {
        playbackState.audioPlaybackProgress
    }

    var audioElapsedSeconds: Double {
        playbackState.audioElapsedSeconds
    }

    var audioDurationSeconds: Double {
        playbackState.audioDurationSeconds
    }

    var isPlayerItemReady: Bool {
        playbackState.isPlayerItemReady
    }

    var playbackOverlayState: ExploreVideoPlaybackOverlayState {
        playbackState.overlayState
    }

    var boostedAudioURL: URL? {
        playbackState.boostedAudioURL
    }

    var isPreparingAudioBoost: Bool {
        playbackState.isPreparingAudioBoost
    }

    var isRevertingAudioBoost: Bool {
        playbackState.isRevertingAudioBoost
    }

    var audioBoostPreparationFailed: Bool {
        playbackState.audioBoostPreparationFailed
    }

    var showsAudioBoostPreparationStatus: Bool {
        playbackState.showsAudioBoostPreparationStatus
    }

    var isAudioSeeking: Bool {
        playbackState.isAudioSeeking
    }

    var isMuted: Bool {
        storedIsMuted
    }

    init(
        mediaItem: ExploreMediaItem,
        fallbackImageUrl: String,
        reloadGeneration: UInt64,
        preloadedImage: UIImage?,
        surface: ExploreVideoPlaybackSurface,
        autoplay: Bool,
        showsVideoControls: Bool,
        allowsAutoplayInLowPowerMode: Bool = false,
        audioBoostEnabled: Bool = false,
        audioBoostActionToken: UUID? = nil,
        onAudioBoostActionFinished: ((UUID) -> Void)? = nil,
        onAudioBoostToggleRequested: (() -> Void)? = nil,
        onSingleTap: (() -> Void)? = nil,
        onDoubleTap: (() -> Void)? = nil
    ) {
        self.mediaItem = mediaItem
        self.fallbackImageUrl = fallbackImageUrl
        self.reloadGeneration = reloadGeneration
        self.preloadedImage = preloadedImage
        self.surface = surface
        self.autoplay = autoplay
        self.showsVideoControls = showsVideoControls
        self.allowsAutoplayInLowPowerMode = allowsAutoplayInLowPowerMode
        self.audioBoostEnabled = audioBoostEnabled
        self.audioBoostActionToken = audioBoostActionToken
        self.onAudioBoostActionFinished = onAudioBoostActionFinished
        self.onAudioBoostToggleRequested = onAudioBoostToggleRequested
        self.onSingleTap = onSingleTap
        self.onDoubleTap = onDoubleTap
    }

    func toggleMutedFromControls() {
        storedIsMuted.toggle()
        HapticManager.shared.triggerSelectionPulse(
            source: "media.explore.\(surface.rawValue).mute.\(storedIsMuted ? "on" : "off")"
        )
        player?.isMuted = storedIsMuted
        if playbackOverlayState.needsPlayerRebuildForRecovery ||
            player?.timeControlStatus != .playing {
            resumeAutoplayIfEligible(force: true, revealsPlaybackControl: true)
        }
    }

    var body: some View {
        ZStack {
            posterImage

            if mediaItem.kind == .video, let player {
                ExploreCoverVideoPlayer(player: player, playerId: playerId, surface: surface)
                    .id("\(configuredVideoURL ?? mediaItem.url)|\(videoSurfaceGeneration)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .allowsHitTesting(false)
                    .opacity(isPlayerItemReady ? 0.96 : 0)
            }

            if mediaItem.kind == .audio,
               audioPlaybackProgress > 0 || playbackOverlayState.isPlaying {
                TimelineView(.animation(paused: !playbackOverlayState.isPlaying)) { _ in
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(.white.opacity(0.92))
                            .frame(width: 2)
                            .shadow(color: .black.opacity(0.45), radius: 2)
                            .offset(
                                x: AudioSpectrogramSeekingPolicy.playmarkerLeadingX(
                                    progress: displayedAudioPlaybackProgress,
                                    width: proxy.size.width
                                )
                            )
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(1)
            }

            if mediaItem.kind == .audio, audioDurationSeconds > 0 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(formattedAudioTime(audioElapsedSeconds)) / \(formattedAudioTime(audioDurationSeconds))")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.58), in: Capsule())
                    }
                }
                .padding(12)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(3)
            }

            audioBoostOverlay

            if mediaItem.kind == .audio &&
                isPreparingAudioBoost &&
                showsAudioBoostPreparationStatus &&
                onAudioBoostToggleRequested == nil {
                Text("Boosting audio…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.62), in: Capsule())
                    .allowsHitTesting(false)
                    .zIndex(4)
            }

            if mediaItem.kind == .audio && audioBoostPreparationFailed {
                Text("Audio boost unavailable. Playing original.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.68), in: Capsule())
                    .allowsHitTesting(false)
                    .zIndex(4)
            }

            if audioSeekingMode == .fullSpectrogram {
                audioSeekLayer
                    .zIndex(2)
            } else {
                mediaTapLayer
                    .zIndex(2)
            }

            if isVideoPlaybackHost {
                videoOverlay
                    .zIndex(4)
            }
        }
        .task(id: "\(mediaItem.url)|\(reloadGeneration)") {
            configurePlayerIfNeeded()
            resumeAutoplayIfUncovered()
        }
        .task(id: audioBoostEnabled) {
            guard mediaItem.kind == .audio else { return }
            await updateAudioBoostMode()
        }
        .onAppear {
            logPlayback("appear")
            resumeAutoplayIfUncovered()
        }
        .onChange(of: shouldDisplayPlaybackControl) { _, isVisible in
            logPlayback(
                "control-visibility",
                extra: "visible=\(isVisible) playerNil=\(player == nil) rebuild=\(playbackOverlayState.needsPlayerRebuildForRecovery)"
            )
        }
        .onChange(of: playbackState.observedTimeControlStatus) { _, status in
            handlePlaybackStatusChange(status)
        }
        .onChange(of: playbackState.observedItemStatus) { _, status in
            handlePlaybackItemStatusChange(status)
        }
        .onChange(of: playbackState.observedEventSequence) { _, _ in
            handlePlaybackLifecycleEvent()
        }
        .onChange(of: playbackState.observedCurrentTimeSeconds) { _, seconds in
            updateAudioPlaybackProgress(
                elapsedSeconds: seconds,
                durationSeconds: playbackState.observedDurationSeconds
            )
        }
        .onChange(of: playbackState.observedDurationSeconds) { _, duration in
            updateAudioPlaybackProgress(
                elapsedSeconds: playbackState.observedCurrentTimeSeconds,
                durationSeconds: duration
            )
        }
        .onChange(of: storedIsMuted) { _, newValue in
            guard mediaItem.kind == .video else { return }
            guard !newValue else {
                player?.isMuted = true
                logPlayback("mute-changed", extra: "muted=true")
                return
            }
            Task { @MainActor in
                let activated = await MediaPlaybackAudioSession.activate(
                    source: "media.explore.\(surface.rawValue).unmute"
                )
                guard activated, !storedIsMuted else { return }
                player?.isMuted = false
                logPlayback("mute-changed", extra: "muted=false")
            }
        }
        .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
            guard case .exploreVideoMutePreferenceReset = event else { return }
            guard mediaItem.kind == .video else { return }
            storedIsMuted = true
            player?.isMuted = true
        }
        .onDisappear {
            logPlayback("disappear")
            cleanupPlayer()
        }
        .onChange(of: playbackCoordinator?.activePlayerID) { _, activeId in
            guard let activeId,
                  activeId != playerId,
                  player != nil else { return }
            pauseForExternalActivePlayer()
        }
        .onChange(of: playbackCoordinator?.pauseGeneration) { _, _ in
            guard playbackCoordinator?.hasActiveOverlay == true else { return }
            pauseForOverlayPresentation(shouldResume: playbackOverlayState.isPlaying || player?.timeControlStatus == .playing)
        }
        .onChange(of: playbackCoordinator?.resumeGeneration) { _, _ in
            guard playbackCoordinator?.hasActiveOverlay != true else { return }
            finishOverlayDismissalPaused()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                resumeAfterInterruptionIfNeeded()
            case .inactive, .background:
                pauseForSystemInterruption(
                    shouldResume: playbackOverlayState.isPlaying || player?.timeControlStatus == .playing
                )
            @unknown default:
                break
            }
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: AVAudioSession.interruptionNotification)
                .receive(on: DispatchQueue.main)
        ) { notification in
            handleAudioSessionInterruption(notification)
        }
    }
}
