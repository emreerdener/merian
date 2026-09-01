import AVFoundation
import SwiftUI
import UIKit

private enum AudioPlayerSource { case original, boosted }

struct AudioPlaybackCarouselPage: View {
    let filePath: String
    @Binding var isAudioBoostEnabled: Bool
    let audioBoostActionToken: UUID?
    let onAudioBoostActionFinished: ((UUID) -> Void)?
    let onAudioBoostToggleRequested: (() -> Void)?
    let dependencies: MediaPlaybackDependencies

    @State private var player: AVAudioPlayer?
    @State private var activePlayerSource: AudioPlayerSource = .original
    @State private var pendingPlayer: AVAudioPlayer?
    @State private var pendingPlayerSource: AudioPlayerSource?
    @State private var playerDelegate = AudioPlayerDelegate()
    @State private var playerGeneration = 0
    @State private var columns: [SpectrogramColumn] = []
    @State private var playbackProgress = 0.0
    @State private var isDecoding = true
    @State private var audioBoostRequestState = AudioBoostRequestState()
    @State private var audioBoostPreparationFailed = false
    @State private var isBoostedAudioReady = false
    @State private var hasTrackedBoostedPlaybackStart = false
    @State private var originalAudioLease: AudioSourceLease?
    @State private var isAudioSeeking = false
    @State private var audioSeekWasPlaying = false
    @State private var audioSeekStartProgress = 0.0
    @State private var playbackControlVisibility =
        AudioPlaybackControlVisibility()
    @State private var sessionController =
        AudioPlaybackSessionController()
    @State private var isPlaying = false

    @Environment(SpeechManager.self) private var speechManager
    @Environment(AudioCaptureManager.self) private var audioCaptureManager
    @Environment(\.scenePhase) private var scenePhase

    init(
        filePath: String,
        isAudioBoostEnabled: Binding<Bool> = .constant(false),
        audioBoostActionToken: UUID? = nil,
        onAudioBoostActionFinished: ((UUID) -> Void)? = nil,
        onAudioBoostToggleRequested: (() -> Void)? = nil,
        dependencies: MediaPlaybackDependencies? = nil
    ) {
        self.filePath = filePath
        _isAudioBoostEnabled = isAudioBoostEnabled
        self.audioBoostActionToken = audioBoostActionToken
        self.onAudioBoostActionFinished = onAudioBoostActionFinished
        self.onAudioBoostToggleRequested = onAudioBoostToggleRequested
        self.dependencies = dependencies ?? .live
    }

    private var presentation: AudioPlaybackPresentation {
        AudioPlaybackPresentation(
            filePath: filePath,
            storedProgress: playbackProgress,
            currentTime: player?.currentTime ?? 0,
            duration: player?.duration ?? 0,
            hasPlayer: player != nil,
            isPlaying: isPlaying,
            playerIsPlaying: player?.isPlaying == true,
            playerGeneration: playerGeneration,
            isSeeking: isAudioSeeking,
            isControlVisible: playbackControlVisibility.isVisible,
            isHardwareDisabled:
                speechManager.isRecording || audioCaptureManager.isRecording,
            isPreparingBoost: audioBoostRequestState.isPreparing,
            isRevertingBoost: audioBoostRequestState.isReverting,
            isBoostEnabled: isAudioBoostEnabled,
            isBoostedAudioReady: isBoostedAudioReady,
            boostPreparationFailed: audioBoostPreparationFailed,
            hasBoostToggleAction: onAudioBoostToggleRequested != nil
        )
    }

    var body: some View {
        AudioPlaybackCarouselContent(
            columns: columns,
            isDecoding: isDecoding,
            displayedProgress: { presentation.displayedProgress },
            storedProgress: playbackProgress,
            isPlaying: isPlaying,
            isSeeking: isAudioSeeking,
            isPlaybackControlDisabled: presentation.isControlDisabled,
            isPlaybackControlPresented: presentation.isControlPresented,
            playbackControlAccessibilityIdentifier:
                presentation.controlAccessibilityIdentifier,
            pageAccessibilityIdentifier:
                presentation.pageAccessibilityIdentifier,
            accessibilityPlaybackValue: presentation.accessibilityValue,
            audioBoostPillState: presentation.boostPillState,
            elapsedText: presentation.elapsedText,
            durationText: presentation.durationText,
            isBoostedAudioReady: isBoostedAudioReady,
            showsBoostPreparationStatus:
                audioBoostRequestState.isPreparing
                    && audioBoostRequestState.showsPreparationStatus
                    && onAudioBoostToggleRequested == nil,
            showsBoostFailure: audioBoostPreparationFailed,
            onSurfaceTap: handleAudioSurfaceTap,
            onSeekChanged: updateAudioSeek,
            onSeekEnded: finishAudioSeek,
            onAccessibilityAdjust: seekAudioForAccessibility,
            onTogglePlayback: togglePlayback,
            onToggleBoost: { onAudioBoostToggleRequested?() }
        )
        .onAppear {
            sessionController.captureAndSwitchSession()
        }
        .onDisappear {
            audioBoostRequestState.invalidate()
            playbackControlVisibility.cancelPendingFade()
            player?.stop()
            clearPendingPlayer()
            isPlaying = false
            originalAudioLease?.release()
            originalAudioLease = nil
            sessionController.restoreSession()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                showPlaybackControlPersistently()
                player?.stop()
                isPlaying = false
                if !commitPendingPlayer(resumeTime: 0) {
                    player?.currentTime = 0
                }
                playbackProgress = 0
                sessionController.restoreSession()
            }
        }
        .task {
            await decodeAudio()
        }
        .task(id: isAudioBoostEnabled) {
            guard !isDecoding else { return }
            await updateAudioBoostMode()
        }
        .task(id: presentation.monitorID) {
            guard isPlaying, let monitoredPlayer = player else { return }
            await AudioPlaybackMonitor.observe(
                monitoredPlayer,
                isCurrent: { monitoredPlayer === player },
                isPlaybackActive: { isPlaying },
                onProgress: { playbackProgress = $0 },
                onFailure: {
                    handlePlaybackFailure(monitoredPlayer, errorDescription: nil)
                }
            )
        }
    }

    private func togglePlayback() {
        guard !presentation.isControlDisabled, let player else { return }

        if player.isPlaying {
            player.pause()
            let pausedTime = player.currentTime
            playbackProgress = AudioSpectrogramSeekingPolicy.normalizedProgress(
                currentTime: pausedTime,
                duration: player.duration,
                fallback: playbackProgress
            )
            isPlaying = false
            commitPendingPlayer(resumeTime: pausedTime)
            showPlaybackControlPersistently()
            dependencies.lightImpactFeedback(0.55, feedback(.audioPause))
        } else {
            do {
                try dependencies.activateAudioPlayerSession()
                guard player.play() else {
                    dependencies.errorFeedback(feedback(.audioPlayFailed))
                    MerianLog.general.debug(
                        "AudioPlaybackCarouselPage: player failed to start"
                    )
                    return
                }
                isPlaying = true
                showPlaybackControlTemporarily()
                trackBoostedPlaybackStartedIfNeeded()
                dependencies.mediumPulseFeedback(feedback(.audioPlay))
            } catch {
                dependencies.errorFeedback(feedback(.audioPlayFailed))
                MerianLog.general.debug(
                    "AudioPlaybackCarouselPage: session activation failed: \(error, privacy: .private)"
                )
            }
        }
    }

    private func seekAudio(to progress: Double) {
        guard let player, player.duration > 0 else { return }
        let clampedProgress = min(1, max(0, progress))
        player.currentTime = AudioSpectrogramSeekingPolicy.seconds(
            progress: clampedProgress,
            duration: player.duration
        )
        playbackProgress = clampedProgress
    }

    private func handleAudioSurfaceTap(to progress: Double) {
        guard player?.duration ?? 0 > 0 else { return }
        if playbackControlVisibility.isVisible {
            showPlaybackControlTemporarily()
            seekAudio(to: progress)
            dependencies.selectionFeedback(
                dependencies.feedbackIdentifier(.audioSeekTap)
            )
        } else {
            showPlaybackControlTemporarily()
        }
    }

    private func updateAudioSeek(translationX: CGFloat, width: CGFloat) {
        guard let player, player.duration > 0, width > 0 else { return }
        if !isAudioSeeking {
            let currentProgress = AudioSpectrogramSeekingPolicy
                .normalizedProgress(
                    currentTime: player.currentTime,
                    duration: player.duration,
                    fallback: playbackProgress
                )
            isAudioSeeking = true
            audioSeekWasPlaying = player.isPlaying
            audioSeekStartProgress = currentProgress
            playbackProgress = currentProgress
            showPlaybackControlPersistently()
            dependencies.lightImpactFeedback(
                0.35,
                dependencies.feedbackIdentifier(.audioSeekBegin)
            )
            player.pause()
            isPlaying = false
            commitPendingPlayer(resumeTime: player.currentTime)
        }
        seekAudio(to: audioSeekStartProgress + Double(translationX / width))
    }

    private func finishAudioSeek(translationX: CGFloat, width: CGFloat) {
        guard isAudioSeeking, let player else { return }
        seekAudio(to: audioSeekStartProgress + Double(translationX / width))
        let shouldResume = audioSeekWasPlaying
        isAudioSeeking = false
        audioSeekWasPlaying = false
        dependencies.selectionFeedback(
            dependencies.feedbackIdentifier(.audioSeekCommit)
        )
        if shouldResume {
            if player.play() {
                isPlaying = true
                showPlaybackControlTemporarily()
                trackBoostedPlaybackStartedIfNeeded()
            } else {
                isPlaying = false
                showPlaybackControlPersistently()
            }
        }
    }

    private func seekAudioForAccessibility(_ adjustment: AudioSeekAdjustment) {
        guard let player, player.duration > 0 else { return }
        let progress = AudioSpectrogramSeekingPolicy.progress(
            after: adjustment,
            currentProgress: presentation.displayedProgress,
            duration: player.duration
        )
        seekAudio(to: progress)
        dependencies.selectionFeedback(
            dependencies.feedbackIdentifier(.audioSeekAccessibility)
        )
        UIAccessibility.post(
            notification: .announcement,
            argument: AudioPlaybackTimeFormatter.string(
                from: player.currentTime
            )
        )
    }

    private func showPlaybackControlTemporarily() {
        playbackControlVisibility.showTemporarily {
            AudioPlaybackControlPolicy.shouldAutoHide(
                isPlaying: isPlaying,
                isSeeking: isAudioSeeking
            )
        }
    }

    private func showPlaybackControlPersistently() {
        playbackControlVisibility.showPersistently()
    }

    private func feedback(_ event: MediaPlaybackFeedbackEvent) -> String {
        dependencies.feedbackIdentifier(event)
    }
    @MainActor
    private func decodeAudio() async {
        do {
            let lease = try await dependencies.acquireAudioSource(filePath)
            guard !Task.isCancelled else {
                lease.release()
                return
            }
            originalAudioLease = lease
            guard let originalPlayer = makePlayer(
                url: lease.url,
                resumeTime: 0
            ) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            installPlayer(
                originalPlayer,
                source: .original,
                shouldPlay: false
            )
            columns = await AudioSpectrogramDecoder.decodeColumns(
                fromFilePath: lease.url.path
            )
        } catch {
            player?.stop()
            player = nil
            clearPendingPlayer()
            playerGeneration &+= 1
            isPlaying = false
            playbackProgress = 0
            columns = []
        }
        if isAudioBoostEnabled {
            await updateAudioBoostMode()
        }
        isDecoding = false
    }

    @MainActor
    private func updateAudioBoostMode() async {
        let shouldShowReverting =
            !isAudioBoostEnabled && isBoostedAudioReady
        let actionToken = audioBoostActionToken
        let requestID = audioBoostRequestState.begin(
            isBoostEnabled: isAudioBoostEnabled,
            shouldShowReverting: shouldShowReverting,
            showsPreparationStatus: AudioBoostFeedbackPolicy.shouldPresent(
                actionToken: actionToken
            )
        )
        defer {
            if audioBoostRequestState.finish(requestID),
               isAudioBoostEnabled,
               let actionToken {
                onAudioBoostActionFinished?(actionToken)
            }
        }

        if isAudioBoostEnabled {
            if activePlayerSource == .boosted {
                clearPendingPlayer()
                isBoostedAudioReady = true
                audioBoostPreparationFailed = false
                return
            }

            audioBoostPreparationFailed = false
            do {
                let result = try await dependencies.prepareAudioBoost(filePath)
                guard !Task.isCancelled,
                      audioBoostRequestState.owns(requestID),
                      isAudioBoostEnabled else { return }
                guard let boostedPlayer = makePlayer(
                    url: result.url,
                    resumeTime: 0
                ) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                stageOrInstallPlayer(boostedPlayer, source: .boosted)
                isBoostedAudioReady = true
                dependencies.trackAudioBoost("enabled", result.gainBand)
            } catch {
                guard !Task.isCancelled,
                      audioBoostRequestState.owns(requestID) else { return }
                isBoostedAudioReady = false
                let shouldPresentFailure =
                    AudioBoostFeedbackPolicy.shouldPresent(
                        actionToken: actionToken
                    )
                audioBoostPreparationFailed = shouldPresentFailure
                if shouldPresentFailure {
                    dependencies.errorFeedback(
                        dependencies.feedbackIdentifier(.audioBoostFailed)
                    )
                }
                dependencies.trackAudioBoost("preparation_failed", nil)
            }
        } else {
            audioBoostPreparationFailed = false
            guard isBoostedAudioReady
                || activePlayerSource == .boosted else { return }

            if activePlayerSource == .original {
                clearPendingPlayer()
                isBoostedAudioReady = false
                hasTrackedBoostedPlaybackStart = false
                dependencies.trackAudioBoost("disabled", nil)
                return
            }

            guard let originalURL = originalAudioLease?.url else { return }
            guard let originalPlayer = makePlayer(
                url: originalURL,
                resumeTime: 0
            ) else { return }
            stageOrInstallPlayer(originalPlayer, source: .original)
            isBoostedAudioReady = false
            hasTrackedBoostedPlaybackStart = false
            dependencies.trackAudioBoost("disabled", nil)
        }
    }

    @MainActor
    private func makePlayer(
        url: URL,
        resumeTime: TimeInterval
    ) -> AVAudioPlayer? {
        guard let preparedPlayer = try? AVAudioPlayer(
            contentsOf: url
        ) else { return nil }
        playerDelegate.onFinish = { finishedPlayerID, successfully in
            guard let player,
                  ObjectIdentifier(player) == finishedPlayerID else { return }
            guard successfully else {
                handlePlaybackFailure(player, errorDescription: nil)
                return
            }
            isPlaying = false
            if !commitPendingPlayer(resumeTime: 0) {
                player.currentTime = 0
                playbackProgress = 0
            }
            showPlaybackControlPersistently()
        }
        playerDelegate.onDecodeError = { failedPlayerID, errorDescription in
            guard let player,
                  ObjectIdentifier(player) == failedPlayerID else { return }
            handlePlaybackFailure(
                player,
                errorDescription: errorDescription
            )
        }
        preparedPlayer.delegate = playerDelegate
        preparedPlayer.prepareToPlay()
        preparedPlayer.currentTime = min(
            max(0, resumeTime),
            preparedPlayer.duration
        )
        return preparedPlayer
    }

    @MainActor
    private func handlePlaybackFailure(
        _ failedPlayer: AVAudioPlayer,
        errorDescription: String?
    ) {
        guard failedPlayer === player else { return }
        let shouldResume = isPlaying
        let resumeTime = AudioPlaybackFailurePolicy.recoveryTime(
            currentTime: failedPlayer.currentTime,
            duration: failedPlayer.duration,
            storedProgress: playbackProgress
        )
        MerianLog.general.debug(
            "AudioPlaybackCarouselPage: playback stopped unexpectedly source=\(String(describing: activePlayerSource), privacy: .public) error=\(String(describing: errorDescription), privacy: .private)"
        )

        failedPlayer.stop()
        isPlaying = false
        clearPendingPlayer()

        guard activePlayerSource == .boosted,
              let originalURL = originalAudioLease?.url,
              let originalPlayer = makePlayer(
                  url: originalURL,
                  resumeTime: resumeTime
              ) else {
            failedPlayer.currentTime = min(
                max(0, resumeTime),
                failedPlayer.duration
            )
            playbackProgress = AudioSpectrogramSeekingPolicy
                .normalizedProgress(
                    currentTime: failedPlayer.currentTime,
                    duration: failedPlayer.duration,
                    fallback: playbackProgress
                )
            showPlaybackControlPersistently()
            return
        }

        isBoostedAudioReady = false
        hasTrackedBoostedPlaybackStart = false
        isAudioBoostEnabled = false
        installPlayer(
            originalPlayer,
            source: .original,
            shouldPlay: shouldResume
        )
        if isPlaying {
            showPlaybackControlTemporarily()
        } else {
            showPlaybackControlPersistently()
        }
        dependencies.trackAudioBoost("playback_failed", nil)
        Task {
            await dependencies.invalidateAudioBoost(filePath)
        }
    }

    @MainActor
    private func stageOrInstallPlayer(
        _ preparedPlayer: AVAudioPlayer,
        source: AudioPlayerSource
    ) {
        let resumeTime = player?.currentTime ?? 0
        if AudioSourceHandoffPolicy.shouldStageReplacement(
            isPlaybackActive: isPlaying,
            playerIsPlaying: player?.isPlaying == true
        ) {
            clearPendingPlayer()
            pendingPlayer = preparedPlayer
            pendingPlayerSource = source
            return
        }

        clearPendingPlayer()
        preparedPlayer.currentTime = min(
            max(0, resumeTime),
            preparedPlayer.duration
        )
        installPlayer(
            preparedPlayer,
            source: source,
            shouldPlay: false
        )
    }

    @MainActor
    @discardableResult
    private func commitPendingPlayer(resumeTime: TimeInterval) -> Bool {
        guard let pendingPlayer, let pendingPlayerSource else { return false }
        self.pendingPlayer = nil
        self.pendingPlayerSource = nil
        pendingPlayer.currentTime = min(
            max(0, resumeTime),
            pendingPlayer.duration
        )
        installPlayer(
            pendingPlayer,
            source: pendingPlayerSource,
            shouldPlay: false
        )
        return true
    }

    @MainActor
    private func clearPendingPlayer() {
        pendingPlayer?.stop()
        pendingPlayer = nil
        pendingPlayerSource = nil
    }

    @MainActor
    private func installPlayer(
        _ preparedPlayer: AVAudioPlayer,
        source: AudioPlayerSource,
        shouldPlay: Bool
    ) {
        player?.stop()
        player = preparedPlayer
        activePlayerSource = source
        playerGeneration &+= 1
        isPlaying = shouldPlay && preparedPlayer.play()
        playbackProgress = preparedPlayer.duration > 0
            ? preparedPlayer.currentTime / preparedPlayer.duration
            : 0
        if shouldPlay, !isPlaying {
            showPlaybackControlPersistently()
        }
    }

    private func trackBoostedPlaybackStartedIfNeeded() {
        guard isAudioBoostEnabled,
              activePlayerSource == .boosted,
              !hasTrackedBoostedPlaybackStart else { return }
        hasTrackedBoostedPlaybackStart = true
        dependencies.trackAudioBoost("boosted_playback_started", nil)
    }
}
