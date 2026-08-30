import Foundation

extension AudioRecordingPresentation {
    @MainActor
    static func live(
        audioCaptureManager: AudioCaptureManager,
        audioHintsEnabled: Bool
    ) -> Self {
        Self(
            isRecording: audioCaptureManager.isRecording,
            isReviewing: audioCaptureManager.pendingPlaybackPath != nil,
            isPlaying: audioCaptureManager.isPlaying,
            recordingProgress: audioCaptureManager.recordingProgress,
            playbackProgress: audioCaptureManager.playbackProgress,
            spectrogramColumns: audioCaptureManager.spectrogramColumns,
            snrLevel: audioCaptureManager.snrLevel,
            audioHintsEnabled: audioHintsEnabled,
            maximumDuration: AudioCaptureManager.maxDuration,
            liveColumnCapacity: AudioCaptureManager.columnCap
        )
    }
}

extension AudioRecordingViewModel.Dependencies {
    @MainActor
    static func live(audioCaptureManager: AudioCaptureManager) -> Self {
        Self(
            seekPlayback: { progress in
                audioCaptureManager.seekPlayback(to: progress)
            },
            idleArtworkSelectionFeedback: {
                HapticManager.shared.triggerSelectionPulse()
            },
            scrubBeginFeedback: {
                HapticManager.shared.triggerLightImpact(
                    intensity: 0.35,
                    source: "media.capture.audio.seek.begin"
                )
            },
            scrubCommitFeedback: {
                HapticManager.shared.triggerSelectionPulse(
                    source: "media.capture.audio.seek.commit"
                )
            }
        )
    }
}
