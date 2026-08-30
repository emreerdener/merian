import Foundation
import Testing

@testable import Merian

@Suite("AudioRecordingPresentation")
struct AudioRecordingPresentationTests {
    @Test("Idle, recording, and review states retain their presentation rules")
    func statePresentationRules() {
        let idle = makePresentation(playbackProgress: 0.2)
        #expect(!idle.showsSpectrogram)
        #expect(idle.countdownProgress == 0.2)
        #expect(
            idle.countdownAccessibilityPrefix
                == "Audio playback time remaining"
        )

        let recording = makePresentation(
            isRecording: true,
            recordingProgress: 0.4
        )
        #expect(recording.showsSpectrogram)
        #expect(recording.countdownProgress == 0.4)
        #expect(
            recording.countdownAccessibilityPrefix
                == "Audio recording time remaining"
        )
        #expect(
            recording.spectrogramLayout == .liveHorizon(capacity: 360)
        )

        let review = makePresentation(
            isReviewing: true,
            playbackProgress: 0.7
        )
        #expect(review.showsSpectrogram)
        #expect(review.countdownProgress == 0.7)
        #expect(review.spectrogramLayout == .fitToData)
    }

    @Test("Playhead visibility matches review playback and scrubbing state")
    func playheadVisibility() {
        #expect(!makePresentation().showsPlayhead(isScrubbing: true))
        #expect(
            makePresentation(isReviewing: true)
                .showsPlayhead(isScrubbing: true)
        )
        #expect(
            makePresentation(isReviewing: true, isPlaying: true)
                .showsPlayhead(isScrubbing: false)
        )
        #expect(
            makePresentation(isReviewing: true, playbackProgress: 0.1)
                .showsPlayhead(isScrubbing: false)
        )
        #expect(
            !makePresentation(isReviewing: true)
                .showsPlayhead(isScrubbing: false)
        )
    }

    @Test("Spectrogram layout preserves the composing-center clearance")
    func spectrogramLayoutPreservesClearance() {
        #expect(
            AudioRecordingLayoutPolicy.spectrogramHeight(
                viewportHeight: 800,
                composingCenter: 0.45,
                bottomClearance: 120
            ) == 464
        )
        #expect(
            AudioRecordingLayoutPolicy.spectrogramHeight(
                viewportHeight: 300,
                composingCenter: 0.5,
                bottomClearance: 180
            ) == 180
        )
    }

    @Test("SNR guidance copy remains stable")
    func snrGuidanceCopy() {
        #expect(AudioSNRPresentation.label(for: .clear) == "Clear")
        #expect(AudioSNRPresentation.label(for: .caution) == "Some noise")
        #expect(AudioSNRPresentation.label(for: .warning) == "Shield mic")
        #expect(AudioSNRPresentation.label(for: .clipping) == "Move mic away")
    }

    @Test("Idle artwork wraps through the established catalog")
    func idleArtworkWraps() {
        #expect(AudioRecordingIdleArtwork.names.first == "blue-bird")
        #expect(AudioRecordingIdleArtwork.names.last == "whale")
        #expect(
            AudioRecordingIdleArtwork.nextIndex(
                after: AudioRecordingIdleArtwork.names.count - 1
            ) == 0
        )
    }

    private func makePresentation(
        isRecording: Bool = false,
        isReviewing: Bool = false,
        isPlaying: Bool = false,
        recordingProgress: Double = 0.1,
        playbackProgress: Double = 0
    ) -> AudioRecordingPresentation {
        AudioRecordingPresentation(
            isRecording: isRecording,
            isReviewing: isReviewing,
            isPlaying: isPlaying,
            recordingProgress: recordingProgress,
            playbackProgress: playbackProgress,
            spectrogramColumns: [],
            snrLevel: .clear,
            audioHintsEnabled: true,
            maximumDuration: 15,
            liveColumnCapacity: 360
        )
    }
}
