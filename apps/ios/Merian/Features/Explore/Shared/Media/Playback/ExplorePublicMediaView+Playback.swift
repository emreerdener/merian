import AVFoundation
import SwiftUI

extension ExplorePublicMediaView {
    func togglePlayback() {
        if playbackOverlayState.needsPlayerRebuildForRecovery || player == nil {
            HapticManager.shared.triggerMediumPulse(
                source: "media.explore.\(surface.rawValue).play"
            )
            resumeAutoplayIfEligible(
                force: true,
                revealsPlaybackControl: true,
                forcePlayerRebuild: playbackOverlayState.needsPlayerRebuildForRecovery || player == nil,
                verifiesRecovery: true
            )
            return
        }

        let player = configurePlayerIfNeeded()
        guard let player else {
            reducePlaybackOverlay(.playbackUnavailable, animation: .easeInOut(duration: 0.18))
            return
        }

        if player.timeControlStatus == .playing {
            HapticManager.shared.triggerLightImpact(
                intensity: 0.55,
                source: "media.explore.\(surface.rawValue).pause"
            )
            pauseForUserInteraction()
        } else {
            HapticManager.shared.triggerMediumPulse(
                source: "media.explore.\(surface.rawValue).play"
            )
            resumeAutoplayIfEligible(force: true, revealsPlaybackControl: true)
        }
    }

    func resumeAutoplayIfEligible(
        force: Bool = false,
        ignoreLowPowerMode: Bool = false,
        revealsPlaybackControl: Bool = false,
        forcePlayerRebuild: Bool = false,
        verifiesRecovery: Bool = false
    ) {
        guard isVideoPlaybackHost else { return }
        guard mediaItem.kind != .audio || force else { return }
        guard force || playbackCoordinator?.hasActiveOverlay != true else {
            logPlayback("skip-resume-covered")
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
            return
        }
        guard autoplay || force,
              force || ignoreLowPowerMode || !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            logPlayback("skip-resume-low-power")
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
            return
        }
        let isRecoveringPlayback = forcePlayerRebuild || playbackOverlayState.needsPlayerRebuildForRecovery
        let shouldRevealPlaybackControl = revealsPlaybackControl
        let shouldVerifyRecovery = verifiesRecovery || isRecoveringPlayback
        guard let player = configurePlayerIfNeeded(
            forceRebuildForRecovery: isRecoveringPlayback
        ) else {
            logPlayback("resume-unavailable")
            reducePlaybackOverlay(.playbackUnavailable, animation: .easeInOut(duration: 0.18))
            return
        }
        playbackCoordinator?.activate(playerID: playerId, surface: surface)
        logPlayback(
            "resume",
            extra: "force=\(force) rebuild=\(isRecoveringPlayback) reveal=\(shouldRevealPlaybackControl) verify=\(shouldVerifyRecovery)"
        )
        if shouldRevealPlaybackControl {
            reducePlaybackOverlay(.playbackStarted, animation: .easeInOut(duration: 0.18))
            showPlaybackControlTemporarily()
        } else {
            reducePlaybackOverlay(.autoplayStarted, animation: .easeInOut(duration: 0.18))
        }
        if mediaItem.kind == .audio {
            guard activateAudioPlaybackSession() else {
                reducePlaybackOverlay(.playbackUnavailable, animation: .easeInOut(duration: 0.18))
                AppTelemetry.trackExploreAudioPlaybackFailed(surface: surface.rawValue)
                return
            }
            player.isMuted = false
            if playbackState.markAudioPlaybackStartedIfNeeded() {
                AppTelemetry.trackExploreAudioPlaybackStarted(surface: surface.rawValue)
                if audioBoostEnabled, boostedAudioURL != nil {
                    AppTelemetry.trackExploreAudioBoost(
                        event: "boosted_playback_started",
                        surface: surface.rawValue
                    )
                }
            }
        }
        if mediaItem.kind == .video, !isMuted {
            Task { @MainActor in
                let activated = await MediaPlaybackAudioSession.activate(
                    source: "media.explore.\(surface.rawValue).video.play"
                )
                guard activated, self.player === player, !isMuted else { return }
                player.isMuted = false
                player.play()
                if shouldVerifyRecovery {
                    startPlaybackRecoveryWatchdog(for: player)
                }
                playbackState.clearResumeIntent()
            }
            return
        }
        player.play()
        if shouldVerifyRecovery {
            startPlaybackRecoveryWatchdog(for: player)
        }
        playbackState.clearResumeIntent()
    }

    private func startPlaybackRecoveryWatchdog(for watchedPlayer: AVPlayer) {
        playbackState.cancelPlaybackRecoveryWatchdog()
        logPlayback("start-recovery-watchdog")
        let task = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let player, player === watchedPlayer else { return }
                playbackState.clearPlaybackRecoveryWatchdogTask()

                guard watchedPlayer.timeControlStatus == .playing else {
                    logPlayback(
                        "recovery-watchdog-failed",
                        extra: "status=\(playbackStatusDescription(watchedPlayer.timeControlStatus))"
                    )
                    pauseForRecoverableInterruption()
                    return
                }

                logPlayback("recovery-watchdog-passed")
            }
        }
        playbackState.replacePlaybackRecoveryWatchdogTask(task)
    }

    func scheduleUnexpectedPauseRecoveryIfNeeded(for watchedPlayer: AVPlayer?) {
        guard let watchedPlayer else { return }
        playbackState.cancelUnexpectedPauseRecovery()
        let task = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let player,
                      player === watchedPlayer,
                      playbackOverlayState.isPlaying else {
                    playbackState.clearUnexpectedPauseRecoveryTask()
                    return
                }

                playbackState.clearUnexpectedPauseRecoveryTask()
                guard watchedPlayer.timeControlStatus == .playing else {
                    logPlayback(
                        "unexpected-pause-confirmed",
                        extra: "status=\(playbackStatusDescription(watchedPlayer.timeControlStatus))"
                    )
                    pauseForRecoverableInterruption()
                    return
                }
            }
        }
        playbackState.replaceUnexpectedPauseRecoveryTask(task)
    }

    func showPlaybackControlTemporarily() {
        playbackState.cancelPlaybackControlFade()
        logPlayback("show-control-temporarily")
        reducePlaybackOverlay(.revealControls, animation: .easeInOut(duration: 0.18))
        guard playbackOverlayState.isPlaying,
              !playbackOverlayState.needsPlayerRebuildForRecovery else {
            playbackState.clearPlaybackControlFadeTask()
            return
        }

        let task = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard playbackOverlayState.isPlaying,
                      !playbackOverlayState.needsPlayerRebuildForRecovery else {
                    return
                }
                logPlayback("control-fade-completed")
                reducePlaybackOverlay(.controlFadeCompleted, animation: .easeInOut(duration: 0.26))
            }
        }
        playbackState.replacePlaybackControlFadeTask(task)
    }
}
