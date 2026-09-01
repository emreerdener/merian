import Foundation
import Testing

@testable import Merian

@Suite("Audio playback presentation")
struct AudioPlaybackPresentationTests {
    @Test func presentationNormalizesPlaybackAndAccessibilityState() {
        let presentation = AudioPlaybackPresentation(
            filePath: "/tmp/wood-thrush.wav",
            storedProgress: 0.25,
            currentTime: 3,
            duration: 6,
            hasPlayer: true,
            isPlaying: true,
            playerIsPlaying: true,
            playerGeneration: 7,
            isSeeking: false,
            isControlVisible: true,
            isHardwareDisabled: false,
            isPreparingBoost: false,
            isRevertingBoost: false,
            isBoostEnabled: true,
            isBoostedAudioReady: true,
            boostPreparationFailed: false,
            hasBoostToggleAction: true
        )

        #expect(presentation.displayedProgress == 0.5)
        #expect(presentation.isControlPresented)
        #expect(!presentation.isControlDisabled)
        #expect(presentation.monitorID == 7)
        #expect(
            presentation.pageAccessibilityIdentifier
                == "AudioPlaybackCarouselPage_wood-thrush.wav"
        )
        #expect(
            presentation.controlAccessibilityIdentifier
                == "AudioPlaybackControl_wood-thrush.wav"
        )
        #expect(presentation.accessibilityValue == "0:03 of 0:06")
        #expect(presentation.elapsedText == "0:03")
        #expect(presentation.durationText == "0:06")
        #expect(presentation.boostPillState == .boosted)
    }

    @Test func presentationHidesTimeBadgeForZeroDurationPlayer() {
        let presentation = AudioPlaybackPresentation(
            filePath: "/tmp/empty.wav",
            storedProgress: 0,
            currentTime: 0,
            duration: 0,
            hasPlayer: true,
            isPlaying: false,
            playerIsPlaying: false,
            playerGeneration: 1,
            isSeeking: false,
            isControlVisible: true,
            isHardwareDisabled: false,
            isPreparingBoost: false,
            isRevertingBoost: false,
            isBoostEnabled: false,
            isBoostedAudioReady: false,
            boostPreparationFailed: false,
            hasBoostToggleAction: false
        )

        #expect(presentation.elapsedText == nil)
        #expect(presentation.durationText == nil)
        #expect(presentation.accessibilityValue == "Unavailable")
    }

    @Test @MainActor func dependencySeamRoutesMediaSideEffects() async throws {
        var events: [String] = []
        let dependencies = MediaPlaybackDependencies(
            activatePlaybackAudio: { source in
                events.append("activate:\(source)")
                return false
            },
            activateAudioPlayerSession: {
                events.append("activate-player")
            },
            trackAudioBoost: { event, gainBand in
                events.append("track:\(event):\(gainBand ?? "none")")
            },
            selectionFeedback: { source in
                events.append("selection:\(source ?? "none")")
            }
        )

        #expect(await dependencies.activatePlaybackAudio("inline-video") == false)
        try dependencies.activateAudioPlayerSession()
        dependencies.trackAudioBoost("enabled", "mid")
        dependencies.selectionFeedback("focus.resize")

        let featureDependencies = dependencies.configuredForFeature(
            feedbackNamespace: "media.insight"
        ) { event, gainBand in
            events.append("feature-track:\(event):\(gainBand ?? "none")")
        }
        featureDependencies.trackAudioBoost("disabled", nil)

        #expect(events == [
            "activate:inline-video",
            "activate-player",
            "track:enabled:mid",
            "selection:focus.resize",
            "feature-track:disabled:none"
        ])
        #expect(
            featureDependencies.feedbackIdentifier(.audioPause)
                == "media.insight.audio.pause"
        )
        #expect(
            dependencies.feedbackIdentifier(.fullscreenAutoplay)
                == "media.fullscreen.autoplay"
        )
    }

    @Test func boostPillTransitionsOnlyAfterBoostedAudioIsReady() {
        let unboosted = AudioBoostPillState.resolve(
            isBoostEnabled: false,
            isBoostedAudioReady: false,
            hasToggleAction: true
        )
        let preparing = AudioBoostPillState.resolve(
            isBoostEnabled: true,
            isBoostedAudioReady: false,
            hasToggleAction: true
        )
        let boosted = AudioBoostPillState.resolve(
            isBoostEnabled: true,
            isBoostedAudioReady: true,
            hasToggleAction: true
        )
        let boosting = AudioBoostPillState.resolve(
            isBoostEnabled: true,
            isPreparingBoost: true,
            isBoostedAudioReady: false,
            hasToggleAction: true
        )
        let reverting = AudioBoostPillState.resolve(
            isBoostEnabled: false,
            isRevertingBoost: true,
            isBoostedAudioReady: true,
            hasToggleAction: true
        )

        #expect(unboosted == .boost)
        #expect(preparing == .boost)
        #expect(boosted == .boosted)
        #expect(boosting == .boosting)
        #expect(boosting?.title == "Boosting…")
        #expect(reverting == .reverting)
        #expect(reverting?.title == "Reverting…")
        #expect(unboosted?.systemImage == "chevron.right")
        #expect(boosted?.systemImage == nil)
        #expect(AudioBoostPillState.resolve(
            isBoostEnabled: false,
            isBoostedAudioReady: false,
            hasToggleAction: false
        ) == nil)
    }

    @Test func timestampUsesElapsedAndDurationClockFormat() {
        #expect(AudioPlaybackTimeFormatter.string(from: 2.9) == "0:02")
        #expect(AudioPlaybackTimeFormatter.string(from: 75) == "1:15")
        #expect(AudioPlaybackTimeFormatter.string(from: .nan) == "0:00")
    }
    @Test func playbackControlAutoHidesOnlyDuringPlayback() {
        #expect(AudioPlaybackControlPolicy.autoHideDelayNanoseconds == 1_000_000_000)
        #expect(AudioPlaybackControlPolicy.shouldAutoHide(isPlaying: true, isSeeking: false))
        #expect(!AudioPlaybackControlPolicy.shouldAutoHide(isPlaying: false, isSeeking: false))
        #expect(!AudioPlaybackControlPolicy.shouldAutoHide(isPlaying: true, isSeeking: true))
        #expect(AudioPlaybackControlPolicy.shouldPresent(isVisible: true, isSeeking: false))
        #expect(!AudioPlaybackControlPolicy.shouldPresent(isVisible: true, isSeeking: true))
    }

    @Test func playbackWaitsForIdleSourceSwitchButStillAllowsPause() {
        #expect(AudioPlaybackControlPolicy.unexpectedStopGraceNanoseconds == 150_000_000)
        #expect(AudioPlaybackControlPolicy.shouldDisable(
            isHardwareDisabled: false,
            isPreparingSource: true,
            isPlaying: false
        ))
        #expect(!AudioPlaybackControlPolicy.shouldDisable(
            isHardwareDisabled: false,
            isPreparingSource: true,
            isPlaying: true
        ))
        #expect(AudioPlaybackControlPolicy.shouldDisable(
            isHardwareDisabled: true,
            isPreparingSource: false,
            isPlaying: true
        ))
    }

    @Test func playheadUsesLivePlayerTimeOnlyDuringPlayback() {
        #expect(AudioSpectrogramSeekingPolicy.displayedProgress(
            storedProgress: 0.2,
            currentTime: 3,
            duration: 6,
            isPlaying: true,
            playerIsPlaying: true,
            isSeeking: false
        ) == 0.5)
        #expect(AudioSpectrogramSeekingPolicy.displayedProgress(
            storedProgress: 0.2,
            currentTime: 3,
            duration: 6,
            isPlaying: false,
            playerIsPlaying: false,
            isSeeking: false
        ) == 0.2)
        #expect(AudioSpectrogramSeekingPolicy.displayedProgress(
            storedProgress: 0.2,
            currentTime: 3,
            duration: 6,
            isPlaying: true,
            playerIsPlaying: true,
            isSeeking: true
        ) == 0.2)
        #expect(AudioSpectrogramSeekingPolicy.displayedProgress(
            storedProgress: 0.6,
            currentTime: 6,
            duration: 6,
            isPlaying: true,
            playerIsPlaying: false,
            isSeeking: false
        ) == 0.6)
        #expect(AudioSpectrogramSeekingPolicy.normalizedProgress(
            currentTime: .nan,
            duration: 6,
            fallback: 1.4
        ) == 1)
        #expect(AudioSpectrogramSeekingPolicy.normalizedProgress(
            currentTime: .nan,
            duration: 6,
            fallback: .nan
        ) == 0)
        #expect(AudioSpectrogramSeekingPolicy.displayedProgress(
            storedProgress: .nan,
            currentTime: .nan,
            duration: 6,
            isPlaying: false,
            playerIsPlaying: false,
            isSeeking: false
        ) == 0)
        #expect(AudioSpectrogramSeekingPolicy.playmarkerLeadingX(
            progress: .nan,
            width: 300
        ) == 0)
        #expect(AudioSpectrogramSeekingPolicy.playmarkerLeadingX(
            progress: 1,
            width: 300
        ) == 298)
    }

    @Test func sourceReplacementWaitsForPlaybackToStop() {
        #expect(AudioSourceHandoffPolicy.shouldStageReplacement(
            isPlaybackActive: true,
            playerIsPlaying: false
        ))
        #expect(AudioSourceHandoffPolicy.shouldStageReplacement(
            isPlaybackActive: false,
            playerIsPlaying: true
        ))
        #expect(!AudioSourceHandoffPolicy.shouldStageReplacement(
            isPlaybackActive: false,
            playerIsPlaying: false
        ))
    }

    @Test func failureRecoveryUsesLastConfirmedPlayheadPosition() {
        #expect(AudioPlaybackFailurePolicy.recoveryTime(
            currentTime: 6,
            duration: 6,
            storedProgress: 0.5
        ) == 3)
        #expect(AudioPlaybackFailurePolicy.recoveryTime(
            currentTime: 2,
            duration: 6,
            storedProgress: 0
        ) == 2)
    }

    @Test func audioSeekingNormalizesAndClampsSpectrogramPositions() {
        #expect(AudioSpectrogramSeekingPolicy.normalizedProgress(locationX: -20, width: 200) == 0)
        #expect(AudioSpectrogramSeekingPolicy.normalizedProgress(locationX: 50, width: 200) == 0.25)
        #expect(AudioSpectrogramSeekingPolicy.normalizedProgress(locationX: 240, width: 200) == 1)
        #expect(AudioSpectrogramSeekingPolicy.normalizedProgress(locationX: 20, width: 0) == 0)
        #expect(AudioSpectrogramSeekingPolicy.seconds(progress: 0.5, duration: 15) == 7.5)
        #expect(AudioSpectrogramSeekingPolicy.seconds(progress: 2, duration: 15) == 15)
    }

    @Test func audioSeekingAccessibilityMovesInFiveSecondSteps() {
        #expect(AudioSpectrogramSeekingPolicy.progress(
            after: .forward,
            currentProgress: 0.25,
            duration: 20
        ) == 0.5)
        #expect(AudioSpectrogramSeekingPolicy.progress(
            after: .backward,
            currentProgress: 0.1,
            duration: 20
        ) == 0)
        #expect(AudioSpectrogramSeekingPolicy.progress(
            after: .forward,
            currentProgress: 0.9,
            duration: 20
        ) == 1)
    }

    @Test func playmarkerUsesMinimumFortyFourPointTarget() {
        #expect(AudioSpectrogramSeekingPolicy.playmarkerHitWidth == 44)
        #expect(AudioSpectrogramSeekingPolicy.playmarkerCenterX(progress: 0.5, width: 300) == 150)
    }

}
