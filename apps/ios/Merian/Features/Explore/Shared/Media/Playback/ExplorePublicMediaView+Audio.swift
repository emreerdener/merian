import AVFoundation
import SwiftUI
import UIKit

extension ExplorePublicMediaView {
    func updateAudioSeek(progress: Double) {
        guard resolvedAudioDuration > 0, let player else { return }
        if !isAudioSeeking {
            playbackState.beginAudioSeek(
                wasPlaying: player.timeControlStatus == .playing || playbackOverlayState.isPlaying
            )
            HapticManager.shared.triggerLightImpact(
                intensity: 0.35,
                source: "media.explore.detail.seek.begin"
            )
            player.pause()
            reducePlaybackOverlay(.playbackTemporarilyPaused)
        }
        applyAudioSeek(progress: progress, player: player)
    }

    func finishAudioSeek(progress: Double) {
        guard isAudioSeeking, let player else { return }
        applyAudioSeek(progress: progress, player: player)
        let shouldResume = playbackState.finishAudioSeek()
        HapticManager.shared.triggerSelectionPulse(source: "media.explore.detail.seek.commit")
        if shouldResume {
            playbackCoordinator?.activate(playerID: playerId, surface: surface)
            player.play()
        } else {
            reducePlaybackOverlay(.playbackPaused, animation: .easeInOut(duration: 0.18))
        }
    }

    private func applyAudioSeek(progress: Double, player: AVPlayer) {
        let seconds = AudioSpectrogramSeekingPolicy.seconds(
            progress: progress,
            duration: resolvedAudioDuration
        )
        playbackState.setAudioPosition(progress: progress, elapsedSeconds: seconds)
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func seekAudioForAccessibility(_ adjustment: AudioSeekAdjustment) {
        guard resolvedAudioDuration > 0, let player else { return }
        let progress = AudioSpectrogramSeekingPolicy.progress(
            after: adjustment,
            currentProgress: audioPlaybackProgress,
            duration: resolvedAudioDuration
        )
        applyAudioSeek(progress: progress, player: player)
        HapticManager.shared.triggerSelectionPulse(source: "media.explore.detail.seek.accessibility")
        UIAccessibility.post(
            notification: .announcement,
            argument: formattedAudioTime(audioElapsedSeconds)
        )
    }

    private var resolvedAudioDuration: TimeInterval {
        if audioDurationSeconds.isFinite, audioDurationSeconds > 0 {
            return audioDurationSeconds
        }
        guard let duration = player?.currentItem?.duration,
              duration.isNumeric,
              duration.seconds.isFinite,
              duration.seconds > 0 else {
            return 0
        }
        return duration.seconds
    }

    var displayedAudioPlaybackProgress: Double {
        AudioSpectrogramSeekingPolicy.displayedProgress(
            storedProgress: audioPlaybackProgress,
            currentTime: player?.currentTime().seconds ?? 0,
            duration: resolvedAudioDuration,
            isPlaying: playbackOverlayState.isPlaying,
            playerIsPlaying: player?.timeControlStatus == .playing,
            isSeeking: isAudioSeeking
        )
    }

    func synchronizeAudioPlaybackProgress() {
        guard mediaItem.kind == .audio,
              let player,
              resolvedAudioDuration > 0 else { return }
        let currentTime = player.currentTime().seconds
        let progress = AudioSpectrogramSeekingPolicy.normalizedProgress(
            currentTime: currentTime,
            duration: resolvedAudioDuration,
            fallback: audioPlaybackProgress
        )
        let elapsedSeconds: Double
        if currentTime.isFinite {
            elapsedSeconds = min(resolvedAudioDuration, max(0, currentTime))
        } else {
            elapsedSeconds = audioElapsedSeconds
        }
        playbackState.setAudioPosition(progress: progress, elapsedSeconds: elapsedSeconds)
    }

    func seekAudioWithoutChangingPlayback(progress: Double) {
        guard resolvedAudioDuration > 0, let player else { return }
        applyAudioSeek(progress: progress, player: player)
        HapticManager.shared.triggerSelectionPulse(source: "media.explore.detail.seek.tap")
    }

    @MainActor
    func updateAudioBoostMode() async {
        let wasPlaying = player?.timeControlStatus == .playing
        let resumeTime = player?.currentTime()
        let shouldShowReverting = !audioBoostEnabled && boostedAudioURL != nil
        playbackState.setAudioBoostReverting(shouldShowReverting)
        defer {
            if shouldShowReverting { playbackState.setAudioBoostReverting(false) }
        }

        if audioBoostEnabled {
            let actionToken = audioBoostActionToken
            playbackState.beginAudioBoostPreparation(
                showsStatus: AudioBoostFeedbackPolicy.shouldPresent(
                    actionToken: actionToken
                )
            )
            defer {
                playbackState.finishAudioBoostPreparation()
                if let actionToken {
                    onAudioBoostActionFinished?(actionToken)
                }
            }
            do {
                let result = try await AudioBoostProcessor.shared.prepare(urlString: mediaItem.url)
                guard !Task.isCancelled else { return }
                playbackState.setBoostedAudioURL(result.url)
                AppTelemetry.trackExploreAudioBoost(
                    event: "enabled",
                    surface: surface.rawValue,
                    gainBand: result.gainBand
                )
            } catch {
                guard !Task.isCancelled else { return }
                playbackState.setBoostedAudioURL(nil)
                let shouldPresentFailure = AudioBoostFeedbackPolicy.shouldPresent(
                    actionToken: actionToken
                )
                playbackState.setAudioBoostPreparationFailed(shouldPresentFailure)
                if shouldPresentFailure {
                    HapticManager.shared.triggerErrorThump(
                        source: "media.explore.\(surface.rawValue).audioBoost.failed"
                    )
                }
                AppTelemetry.trackExploreAudioBoost(event: "preparation_failed", surface: surface.rawValue)
            }
        } else {
            playbackState.clearAudioBoostFeedback()
            guard boostedAudioURL != nil else { return }
            AppTelemetry.trackExploreAudioBoost(event: "disabled", surface: surface.rawValue)
        }

        resetCurrentPlayer()
        guard let rebuilt = configurePlayerIfNeeded() else { return }
        if let resumeTime, resumeTime.isNumeric {
            await rebuilt.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if wasPlaying {
            resumeAutoplayIfEligible(force: true, revealsPlaybackControl: true)
        }
    }

    func formattedAudioTime(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    func activateAudioPlaybackSession() -> Bool {
        guard mediaItem.kind == .audio else { return true }
        guard !playbackState.hasActivatedAudioPlaybackSession else { return true }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: .duckOthers)
            try session.setActive(true)
            playbackState.markAudioPlaybackSessionActive()
            return true
        } catch {
            logPlayback("audio-session-activation-failed", extra: "error=\(error.localizedDescription)")
            return false
        }
    }

    func deactivateAudioPlaybackSessionIfNeeded() {
        guard playbackState.hasActivatedAudioPlaybackSession else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        playbackState.markAudioPlaybackSessionInactive()
    }

    func updateAudioPlaybackProgress(
        elapsedSeconds: Double,
        durationSeconds: Double
    ) {
        guard mediaItem.kind == .audio, durationSeconds.isFinite, durationSeconds > 0 else {
            return
        }
        playbackState.updateAudioPosition(
            elapsedSeconds: elapsedSeconds,
            durationSeconds: durationSeconds
        )
    }

}
