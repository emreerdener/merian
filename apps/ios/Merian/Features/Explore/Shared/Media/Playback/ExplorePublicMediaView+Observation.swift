import AVFoundation
import Foundation
import SwiftUI

extension ExplorePublicMediaView {
    func handlePlaybackLifecycleEvent() {
        guard let player, playbackState.isObserving(player) else { return }

        switch playbackState.lastPlaybackEvent {
        case .didReachEnd:
            logPlayback("item-ended")
            if mediaItem.kind == .audio {
                playbackState.resetAudioPosition()
                AppTelemetry.trackExploreAudioPlaybackCompleted(surface: surface.rawValue)
            }
            player.seek(to: .zero)
            if playbackOverlayState.isPlaying {
                player.play()
            } else {
                reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
            }
        case .playbackStalled:
            logPlayback("item-stalled")
            pauseForRecoverableInterruption()
        case .failedToPlayToEnd:
            logPlayback("item-failed-to-end")
            if mediaItem.kind == .audio {
                AppTelemetry.trackExploreAudioPlaybackFailed(surface: surface.rawValue)
            }
            pauseForRecoverableInterruption()
        case nil:
            break
        }
    }

    func handlePlaybackItemStatusChange(_ status: AVPlayerItem.Status) {
        guard let player, playbackState.isObserving(player) else { return }

        playbackState.setPlayerItemReady(status == .readyToPlay)
        if mediaItem.kind == .audio, status == .readyToPlay {
            updateAudioPlaybackProgress(
                elapsedSeconds: playbackState.observedCurrentTimeSeconds,
                durationSeconds: playbackState.observedDurationSeconds
            )
        }
        if status == .failed {
            reducePlaybackOverlay(.playbackUnavailable, animation: .easeInOut(duration: 0.18))
            if mediaItem.kind == .audio {
                AppTelemetry.trackExploreAudioPlaybackFailed(surface: surface.rawValue)
            }
        }
    }

    func handlePlaybackStatusChange(_ status: AVPlayer.TimeControlStatus) {
        logPlayback("status-change", extra: "status=\(playbackStatusDescription(status))")
        guard !playbackOverlayState.needsPlayerRebuildForRecovery else {
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
            return
        }

        switch status {
        case .playing:
            playbackState.cancelUnexpectedPauseRecovery()
            let shouldFadeVisibleControl = playbackOverlayState.showsPlaybackControl &&
                !playbackOverlayState.isAutoplayControlSuppressed
            reducePlaybackOverlay(.playerBecamePlaying)
            if shouldFadeVisibleControl {
                showPlaybackControlTemporarily()
            }
        case .paused:
            if isAudioSeeking {
                reducePlaybackOverlay(.playbackTemporarilyPaused)
                return
            }
            if playbackOverlayState.isPlaying {
                reducePlaybackOverlay(.playbackTemporarilyPaused)
                scheduleUnexpectedPauseRecoveryIfNeeded(for: player)
                return
            }
            playbackState.cancelPlaybackControlFade()
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
        case .waitingToPlayAtSpecifiedRate:
            if playbackOverlayState.isPlaying {
                reducePlaybackOverlay(.playbackWaiting)
                return
            }
            playbackState.cancelPlaybackControlFade()
            reducePlaybackOverlay(.playbackWaiting, animation: .easeInOut(duration: 0.18))
        @unknown default:
            playbackState.cancelPlaybackControlFade()
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
        }
    }

    func reconcilePlaybackStateWithPlayer() {
        guard let player else {
            logPlayback(
                "reconcile-player-nil",
                extra: "rebuild=\(playbackOverlayState.needsPlayerRebuildForRecovery)"
            )
            rebuildPausedPlayerForRecovery(reason: "reconcile-player-nil")
            return
        }
        logPlayback(
            "reconcile",
            extra: "status=\(playbackStatusDescription(player.timeControlStatus)) rebuild=\(playbackOverlayState.needsPlayerRebuildForRecovery)"
        )
        guard !playbackOverlayState.needsPlayerRebuildForRecovery else {
            playbackState.cancelPlaybackControlFade()
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
            return
        }

        if player.timeControlStatus == .playing {
            let shouldFadeVisibleControl = playbackOverlayState.showsPlaybackControl &&
                !playbackOverlayState.isAutoplayControlSuppressed
            reducePlaybackOverlay(.playerBecamePlaying)
            if shouldFadeVisibleControl {
                showPlaybackControlTemporarily()
            }
        } else {
            playbackState.cancelPlaybackControlFade()
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
        }
    }

    func handleAudioSessionInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        switch type {
        case .began:
            pauseForSystemInterruption(shouldResume: playbackOverlayState.isPlaying || player?.timeControlStatus == .playing)
        case .ended:
            resumeAfterInterruptionIfNeeded()
        @unknown default:
            reconcilePlaybackStateWithPlayer()
        }
    }

    func playbackStatusDescription(_ status: AVPlayer.TimeControlStatus?) -> String {
        switch status {
        case .playing:
            return "playing"
        case .paused:
            return "paused"
        case .waitingToPlayAtSpecifiedRate:
            return "waiting"
        case nil:
            return "nil"
        @unknown default:
            return "unknown"
        }
    }

    func logPlayback(_ event: String, extra: String = "") {
        MerianLog.exploreVideo.debug(
            "player=\(self.playerId, privacy: .public) surface=\(self.surface.rawValue, privacy: .public) event=\(event, privacy: .public) \(extra, privacy: .public)"
        )
    }
}
