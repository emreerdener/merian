import AVFoundation
import SwiftUI

extension ExplorePublicMediaView {
    @discardableResult
    func configurePlayerIfNeeded(forceRebuildForRecovery: Bool = false) -> AVPlayer? {
        guard isPlaybackActive else { return nil }
        guard let videoURLString = videoURLStringForPlayerConfiguration(forceRebuildForRecovery: forceRebuildForRecovery),
              let url = SecureTransportPolicy.httpsURL(
                  from: videoURLString
              ) else {
            cleanupPlayer()
            return nil
        }
        let shouldRebuildPlayer = forceRebuildForRecovery ||
            playbackOverlayState.needsPlayerRebuildForRecovery ||
            pendingRecoverySeekTime != nil
        guard configuredVideoURL != videoURLString || player == nil || shouldRebuildPlayer else { return player }

        let recoverySeekTime = shouldRebuildPlayer ? (pendingRecoverySeekTime ?? currentRecoverySeekTime()) : nil
        resetCurrentPlayer()
        if shouldRebuildPlayer {
            playbackState.incrementVideoSurfaceGeneration()
        }
        logPlayback(
            shouldRebuildPlayer ? "configure-rebuild" : "configure",
            extra: "generation=\(videoSurfaceGeneration)"
        )
        let player = AVPlayer(url: url)
        player.isMuted = mediaItem.kind == .video ? isMuted : false
        player.actionAtItemEnd = .none
        playbackState.installPlayer(player, configuredMediaURL: videoURLString)
        handlePlaybackStatusChange(playbackState.observedTimeControlStatus)
        handlePlaybackItemStatusChange(playbackState.observedItemStatus)
        if let recoverySeekTime {
            logPlayback("seek-recovery", extra: "seconds=\(recoverySeekTime.seconds)")
            player.seek(to: recoverySeekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        playbackState.setPendingRecoverySeekTime(nil)
        if shouldRebuildPlayer {
            reducePlaybackOverlay(.recoveryRebuildCompleted, animation: .easeInOut(duration: 0.18))
        }
        reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
        return player
    }

    private func videoURLStringForPlayerConfiguration(forceRebuildForRecovery: Bool) -> String? {
        if mediaItem.kind == .video || mediaItem.kind == .audio {
            if mediaItem.kind == .audio, audioBoostEnabled, let boostedAudioURL {
                return boostedAudioURL.absoluteString
            }
            return mediaItem.url
        }

        let shouldRecoverExistingVideo = forceRebuildForRecovery ||
            playbackOverlayState.needsPlayerRebuildForRecovery ||
            player != nil

        return shouldRecoverExistingVideo ? configuredVideoURL : nil
    }

    func cleanupPlayer() {
        let cleanupState = [
            "kind=\(mediaItem.kind.rawValue)",
            "overlay=\(playbackCoordinator?.hasActiveOverlay == true)",
            "rebuild=\(playbackOverlayState.needsPlayerRebuildForRecovery)"
        ].joined(separator: " ")
        logPlayback("cleanup", extra: cleanupState)
        let hasConfiguredPlayback = player != nil || configuredVideoURL != nil
        if hasConfiguredPlayback,
           playbackCoordinator?.hasActiveOverlay == true ||
           playbackOverlayState.needsPlayerRebuildForRecovery {
            cleanupPlayerForOverlayRecovery()
            return
        }

        resetCurrentPlayer()
        playbackState.clearResumeIntent()
        playbackState.setPendingRecoverySeekTime(nil)
        reducePlaybackOverlay(.playbackUnavailable, animation: .easeInOut(duration: 0.18))
    }

    private func cleanupPlayerForOverlayRecovery() {
        playbackState.preservePendingRecoverySeekTime(currentRecoverySeekTime())

        logPlayback(
            "overlay-cleanup-preserved",
            extra: "seek=\(pendingRecoverySeekTime?.seconds ?? -1)"
        )
        player?.pause()
        playbackCoordinator?.clearActivePlayer(playerId)
        playbackState.cancelPlaybackRecoveryWatchdog()
        playbackState.cancelUnexpectedPauseRecovery()
        playbackState.cancelPlaybackControlFade()
        playbackState.incrementVideoSurfaceGeneration()
        reducePlaybackOverlay(.playbackInterrupted, animation: .easeInOut(duration: 0.18))
    }

    func resetCurrentPlayer() {
        if player != nil {
            logPlayback("reset-player")
            playbackCoordinator?.clearActivePlayer(playerId)
        }
        playbackState.resetPlayerState()
        deactivateAudioPlaybackSessionIfNeeded()
    }

    func currentRecoverySeekTime() -> CMTime? {
        guard let player else { return nil }
        let currentTime = player.currentTime()
        guard currentTime.isNumeric,
              currentTime.seconds.isFinite,
              currentTime.seconds > 0 else {
            return nil
        }

        if let duration = player.currentItem?.duration,
           duration.isNumeric,
           duration.seconds.isFinite,
           duration.seconds - currentTime.seconds <= 0.5 {
            return .zero
        }

        return currentTime
    }

    func pauseForUserInteraction() {
        logPlayback("pause-user")
        synchronizeAudioPlaybackProgress()
        player?.pause()
        playbackState.cancelPlaybackRecoveryWatchdog()
        playbackState.cancelUnexpectedPauseRecovery()
        playbackState.clearResumeIntent()
        playbackState.setPendingRecoverySeekTime(nil)
        reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
        playbackState.cancelPlaybackControlFade()
    }

    func pauseForExternalActivePlayer() {
        logPlayback("pause-external-active-player")
        synchronizeAudioPlaybackProgress()
        player?.pause()
        reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
    }

    func pauseForOverlayPresentation(shouldResume: Bool) {
        logPlayback("pause-overlay", extra: "shouldResume=\(shouldResume)")
        pauseForRecoverableInterruption()
    }

    func pauseForSystemInterruption(shouldResume: Bool) {
        logPlayback("pause-system", extra: "shouldResume=\(shouldResume)")
        playbackState.markSystemInterruption(shouldResume: shouldResume)
        pauseForRecoverableInterruption()
    }

    func pauseForRecoverableInterruption() {
        guard isVideoPlaybackHost else { return }
        if let recoverySeekTime = currentRecoverySeekTime() {
            playbackState.setPendingRecoverySeekTime(recoverySeekTime)
        }
        logPlayback(
            "pause-recoverable",
            extra: "seek=\(pendingRecoverySeekTime?.seconds ?? -1)"
        )
        synchronizeAudioPlaybackProgress()
        player?.pause()
        playbackState.cancelPlaybackRecoveryWatchdog()
        playbackState.cancelUnexpectedPauseRecovery()
        playbackState.cancelPlaybackControlFade()
        reducePlaybackOverlay(.playbackInterrupted, animation: .easeInOut(duration: 0.18))
    }

    func finishOverlayDismissalPaused() {
        logPlayback(
            "overlay-dismiss-paused",
            extra: "status=\(playbackStatusDescription(player?.timeControlStatus))"
        )
        playbackState.clearResumeIntent()
        playbackState.cancelPlaybackControlFade()
        playbackState.cancelPlaybackRecoveryWatchdog()
        playbackState.cancelUnexpectedPauseRecovery()
        player?.pause()

        if player == nil || playbackOverlayState.needsPlayerRebuildForRecovery {
            rebuildPausedPlayerForRecovery(reason: "overlay-dismiss")
        } else {
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
        }
    }

    func resumeAfterInterruptionIfNeeded() {
        guard playbackState.consumeSystemResumeIntent() else {
            reconcilePlaybackStateWithPlayer()
            return
        }

        resumeAutoplayIfEligible(ignoreLowPowerMode: allowsAutoplayInLowPowerMode)
    }

    func resumeAutoplayIfUncovered() {
        guard playbackCoordinator?.hasActiveOverlay != true else {
            logPlayback("skip-autoplay-covered")
            pauseForOverlayPresentation(shouldResume: false)
            return
        }

        resumeAutoplayIfEligible(ignoreLowPowerMode: allowsAutoplayInLowPowerMode)
    }

    func revealPlaybackControlFromTap() {
        logPlayback("tap-reveal-control")
        playbackState.cancelPlaybackControlFade()
        reducePlaybackOverlay(.revealControls, animation: .easeInOut(duration: 0.18))
    }

    func repairHiddenPlaybackControlFromTap() {
        logPlayback(
            "tap-repair-hidden-control",
            extra: "status=\(playbackStatusDescription(player?.timeControlStatus)) rebuild=\(playbackOverlayState.needsPlayerRebuildForRecovery)"
        )
        resumeAutoplayIfEligible(
            force: true,
            revealsPlaybackControl: true,
            forcePlayerRebuild: playbackOverlayState.needsPlayerRebuildForRecovery || player?.timeControlStatus != .playing,
            verifiesRecovery: true
        )
    }

    func rebuildPausedPlayerForRecovery(reason: String) {
        guard isVideoPlaybackHost else { return }

        logPlayback(
            "rebuild-paused-recovery",
            extra: "reason=\(reason) status=\(playbackStatusDescription(player?.timeControlStatus))"
        )
        playbackState.cancelPlaybackControlFade()
        playbackState.cancelPlaybackRecoveryWatchdog()
        playbackState.cancelUnexpectedPauseRecovery()

        guard configurePlayerIfNeeded(forceRebuildForRecovery: true) != nil else {
            reducePlaybackOverlay(.playbackUnavailable, animation: .easeInOut(duration: 0.18))
            return
        }

        player?.pause()
        reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
    }

    func reducePlaybackOverlay(
        _ event: ExploreVideoPlaybackOverlayState.Event,
        animation: Animation? = nil
    ) {
        if let animation {
            withAnimation(animation) {
                playbackState.reduceOverlay(event)
            }
        } else {
            playbackState.reduceOverlay(event)
        }
    }

}
