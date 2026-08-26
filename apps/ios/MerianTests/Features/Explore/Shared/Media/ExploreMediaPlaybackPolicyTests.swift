import AVFoundation
import XCTest

@testable import Merian

final class ExploreVideoPlaybackOverlayStateTests: XCTestCase {
    func testPlaybackUnavailableRestoresVisiblePlayControlAfterFadedAutoplay() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)

        state.reduce(.playbackUnavailable)

        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
    }

    func testCoordinatorPauseRestoresVisiblePlayControl() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)

        state.reduce(.playbackPaused)

        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
    }

    func testInterruptionAfterControlFadeRestoresVisiblePlayControl() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: true)
        state.reduce(.controlFadeCompleted)

        XCTAssertTrue(state.isPlaying)
        XCTAssertFalse(state.showsPlaybackControl)

        state.reduce(.playbackPaused)

        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
    }

    func testHiddenVideoTapRevealsControlsWhilePlaybackIsStillMarkedPlaying() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)

        state.reduce(.revealControls)

        XCTAssertTrue(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
    }

    func testAutoplayStartsWithoutShowingPlaybackControl() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: false, showsPlaybackControl: true)

        state.reduce(.autoplayStarted)

        XCTAssertTrue(state.isPlaying)
        XCTAssertFalse(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
        XCTAssertTrue(state.isAutoplayControlSuppressed)
    }

    func testPlayerBecamePlayingPreservesHiddenControlsForLoopingPlayback() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)

        state.reduce(.playerBecamePlaying)

        XCTAssertTrue(state.isPlaying)
        XCTAssertFalse(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
    }

    func testPlayerBecamePlayingHidesStaleVisibleControlDuringHiddenAutoplay() {
        var state = ExploreVideoPlaybackOverlayState(
            isPlaying: true,
            showsPlaybackControl: true,
            isAutoplayControlSuppressed: true
        )

        state.reduce(.playerBecamePlaying)

        XCTAssertTrue(state.isPlaying)
        XCTAssertFalse(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
        XCTAssertTrue(state.isAutoplayControlSuppressed)
    }

    func testRevealControlsClearsHiddenAutoplaySuppression() {
        var state = ExploreVideoPlaybackOverlayState(
            isPlaying: true,
            showsPlaybackControl: false,
            isAutoplayControlSuppressed: true
        )

        state.reduce(.revealControls)
        state.reduce(.playerBecamePlaying)

        XCTAssertTrue(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertFalse(state.isAutoplayControlSuppressed)
    }

    func testPlaybackWaitingDuringVisiblePlaybackStillAllowsFade() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: true)

        state.reduce(.playbackWaiting)
        state.reduce(.controlFadeCompleted)

        XCTAssertTrue(state.isPlaying)
        XCTAssertFalse(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
    }

    func testPlaybackWaitingBeforePlaybackKeepsPlayControlVisible() {
        var state = ExploreVideoPlaybackOverlayState(
            isPlaying: false,
            showsPlaybackControl: false,
            isAutoplayControlSuppressed: true
        )

        state.reduce(.playbackWaiting)

        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertFalse(state.isAutoplayControlSuppressed)
    }

    func testTemporaryPlayerPauseDuringHiddenAutoplayDoesNotRevealControl() {
        var state = ExploreVideoPlaybackOverlayState(
            isPlaying: true,
            showsPlaybackControl: false,
            isAutoplayControlSuppressed: true
        )

        state.reduce(.playbackTemporarilyPaused)

        XCTAssertTrue(state.isPlaying)
        XCTAssertFalse(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
        XCTAssertTrue(state.isAutoplayControlSuppressed)
    }

    func testRecoveryRebuildCanResumeAutoplayWithoutVisibleControl() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)
        state.reduce(.playbackInterrupted)
        state.reduce(.recoveryRebuildCompleted)

        state.reduce(.autoplayStarted)

        XCTAssertTrue(state.isPlaying)
        XCTAssertFalse(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
        XCTAssertTrue(state.isAutoplayControlSuppressed)
    }

    func testInterruptionMarksPlaybackRecoverableWithVisiblePlayControl() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)

        state.reduce(.playbackInterrupted)

        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertTrue(state.needsPlayerRebuildForRecovery)
    }

    func testPauseAfterInterruptionKeepsRecoveryRebuildRequired() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)
        state.reduce(.playbackInterrupted)

        state.reduce(.playbackPaused)

        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertTrue(state.needsPlayerRebuildForRecovery)
    }

    func testAutoplayFailureAfterRecoveryLeavesVisiblePlayControl() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)
        state.reduce(.playbackInterrupted)
        state.reduce(.recoveryRebuildCompleted)

        state.reduce(.playbackPaused)

        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
        XCTAssertFalse(state.isAutoplayControlSuppressed)
    }

    func testSuccessfulRecoveryRebuildAndResumeClearsRecoveryState() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)
        state.reduce(.playbackInterrupted)

        state.reduce(.recoveryRebuildCompleted)
        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)

        state.reduce(.playbackStarted)
        XCTAssertTrue(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
    }

    func testHiddenUnhealthyTapRepairCanStartWithVisibleControl() {
        var state = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: false)
        state.reduce(.playbackInterrupted)
        state.reduce(.recoveryRebuildCompleted)

        state.reduce(.playbackStarted)

        XCTAssertTrue(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
        XCTAssertFalse(state.isAutoplayControlSuppressed)
    }

    func testPausedRecoveryRebuildLeavesPlayControlVisible() {
        var state = ExploreVideoPlaybackOverlayState(
            isPlaying: false,
            showsPlaybackControl: false,
            needsPlayerRebuildForRecovery: true
        )

        state.reduce(.recoveryRebuildCompleted)
        state.reduce(.playbackPaused)

        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertFalse(state.needsPlayerRebuildForRecovery)
        XCTAssertFalse(state.isAutoplayControlSuppressed)
    }

    func testControlFadeOnlyHidesWhilePlaybackIsStillMarkedPlaying() {
        var pausedState = ExploreVideoPlaybackOverlayState(isPlaying: false, showsPlaybackControl: true)
        pausedState.reduce(.controlFadeCompleted)

        XCTAssertFalse(pausedState.isPlaying)
        XCTAssertTrue(pausedState.showsPlaybackControl)

        var playingState = ExploreVideoPlaybackOverlayState(isPlaying: true, showsPlaybackControl: true)
        playingState.reduce(.controlFadeCompleted)

        XCTAssertTrue(playingState.isPlaying)
        XCTAssertFalse(playingState.showsPlaybackControl)
    }

    func testControlFadeDoesNotHideControlsWhileRecoveryIsPending() {
        var state = ExploreVideoPlaybackOverlayState(
            isPlaying: true,
            showsPlaybackControl: true,
            needsPlayerRebuildForRecovery: true
        )

        state.reduce(.controlFadeCompleted)

        XCTAssertTrue(state.isPlaying)
        XCTAssertTrue(state.showsPlaybackControl)
        XCTAssertTrue(state.needsPlayerRebuildForRecovery)
    }

    func testFeedAudioAndVideoUseDedicatedCenterPlaybackZone() {
        XCTAssertTrue(
            ExploreMediaInteractionPolicy.usesCenterPlaybackZone(
                surface: .feed,
                mediaKind: .video,
                hasNavigationAction: true
            )
        )
        XCTAssertTrue(
            ExploreMediaInteractionPolicy.usesCenterPlaybackZone(
                surface: .feed,
                mediaKind: .audio,
                hasNavigationAction: true
            )
        )
        XCTAssertEqual(ExploreMediaInteractionPolicy.centerPlaybackHitSize, 96)
    }

    func testCenterPlaybackZoneDoesNotReplaceImageOrDetailInteractions() {
        XCTAssertFalse(
            ExploreMediaInteractionPolicy.usesCenterPlaybackZone(
                surface: .feed,
                mediaKind: .image,
                hasNavigationAction: true
            )
        )
        XCTAssertFalse(
            ExploreMediaInteractionPolicy.usesCenterPlaybackZone(
                surface: .detail,
                mediaKind: .video,
                hasNavigationAction: true
            )
        )
        XCTAssertFalse(
            ExploreMediaInteractionPolicy.usesCenterPlaybackZone(
                surface: .feed,
                mediaKind: .video,
                hasNavigationAction: false
            )
        )
    }
}

final class ExploreVideoPlaybackResumeIntentStateTests: XCTestCase {
    func testSystemResumeIntentSurvivesRepeatedInterruptionWhileAlreadyPaused() {
        var state = ExploreVideoPlaybackResumeIntentState()

        state.markSystemInterruption(shouldResume: true)
        state.markSystemInterruption(shouldResume: false)

        XCTAssertTrue(state.consumeSystemResumeIntent())
        XCTAssertFalse(state.consumeSystemResumeIntent())
    }

    func testClearingResumeIntentsCancelsSystemResume() {
        var state = ExploreVideoPlaybackResumeIntentState()
        state.markSystemInterruption(shouldResume: true)

        state.clear()

        XCTAssertFalse(state.consumeSystemResumeIntent())
    }
}

@MainActor
final class ExplorePublicMediaPlaybackStateTests: XCTestCase {
    func testPlayerInstallationAndResetKeepMutableLifecycleStateContained() {
        let state = ExplorePublicMediaPlaybackState()
        let player = AVPlayer()

        state.installPlayer(player, configuredMediaURL: "https://example.com/media.mp4")
        state.incrementVideoSurfaceGeneration()
        state.setPendingRecoverySeekTime(CMTime(seconds: 8, preferredTimescale: 600))
        state.setPlayerItemReady(true)
        state.updateAudioPosition(elapsedSeconds: 4, durationSeconds: 10)

        XCTAssertTrue(state.player === player)
        XCTAssertEqual(state.configuredMediaURL, "https://example.com/media.mp4")
        XCTAssertEqual(state.videoSurfaceGeneration, 1)
        XCTAssertEqual(state.pendingRecoverySeekTime?.seconds, 8)
        XCTAssertTrue(state.isPlayerItemReady)
        XCTAssertEqual(state.audioPlaybackProgress, 0.4, accuracy: 0.001)

        state.resetPlayerState()

        XCTAssertNil(state.player)
        XCTAssertNil(state.configuredMediaURL)
        XCTAssertFalse(state.isPlayerItemReady)
        XCTAssertEqual(state.audioPlaybackProgress, 0)
        XCTAssertEqual(state.audioElapsedSeconds, 0)
        XCTAssertEqual(state.audioDurationSeconds, 0)
        XCTAssertEqual(state.observedTimeControlStatus, .paused)
    }

    func testAudioSeekIntentIsConsumedExactlyOnce() {
        let state = ExplorePublicMediaPlaybackState()

        state.beginAudioSeek(wasPlaying: true)

        XCTAssertTrue(state.isAudioSeeking)
        XCTAssertTrue(state.finishAudioSeek())
        XCTAssertFalse(state.isAudioSeeking)
        XCTAssertFalse(state.finishAudioSeek())
    }

    func testAudioBoostPresentationStateHasSemanticTransitions() {
        let state = ExplorePublicMediaPlaybackState()
        let boostedURL = URL(fileURLWithPath: "/tmp/boosted.wav")

        state.beginAudioBoostPreparation(showsStatus: true)
        state.setBoostedAudioURL(boostedURL)
        state.setAudioBoostPreparationFailed(true)

        XCTAssertTrue(state.isPreparingAudioBoost)
        XCTAssertTrue(state.showsAudioBoostPreparationStatus)
        XCTAssertEqual(state.boostedAudioURL, boostedURL)
        XCTAssertTrue(state.audioBoostPreparationFailed)

        state.finishAudioBoostPreparation()
        state.clearAudioBoostFeedback()

        XCTAssertFalse(state.isPreparingAudioBoost)
        XCTAssertFalse(state.showsAudioBoostPreparationStatus)
        XCTAssertFalse(state.audioBoostPreparationFailed)
    }
}

@MainActor
final class ExploreVideoPlaybackCoordinatorTests: XCTestCase {
    func testSingleOverlayPausesAndResumesWhenDismissed() {
        let coordinator = ExploreVideoPlaybackCoordinator()

        let token = coordinator.beginOverlay(reason: "comments")

        XCTAssertEqual(coordinator.overlayDepth, 1)
        XCTAssertEqual(coordinator.pauseGeneration, 1)
        XCTAssertEqual(coordinator.resumeGeneration, 0)
        XCTAssertTrue(coordinator.hasActiveOverlay)

        coordinator.endOverlay(token)

        XCTAssertEqual(coordinator.overlayDepth, 0)
        XCTAssertEqual(coordinator.pauseGeneration, 1)
        XCTAssertEqual(coordinator.resumeGeneration, 1)
        XCTAssertFalse(coordinator.hasActiveOverlay)
    }

    func testNestedOverlaysResumeOnlyAfterFinalDismissal() {
        let coordinator = ExploreVideoPlaybackCoordinator()

        let commentsToken = coordinator.beginOverlay(reason: "comments")
        let profileToken = coordinator.beginOverlay(reason: "profile")

        XCTAssertEqual(coordinator.overlayDepth, 2)
        XCTAssertEqual(coordinator.pauseGeneration, 2)
        XCTAssertEqual(coordinator.resumeGeneration, 0)

        coordinator.endOverlay(profileToken)

        XCTAssertEqual(coordinator.overlayDepth, 1)
        XCTAssertEqual(coordinator.resumeGeneration, 0)
        XCTAssertTrue(coordinator.hasActiveOverlay)

        coordinator.endOverlay(commentsToken)

        XCTAssertEqual(coordinator.overlayDepth, 0)
        XCTAssertEqual(coordinator.resumeGeneration, 1)
        XCTAssertFalse(coordinator.hasActiveOverlay)
    }

    func testDuplicateOverlayDismissIsIgnored() {
        let coordinator = ExploreVideoPlaybackCoordinator()
        let token = coordinator.beginOverlay(reason: "share")

        coordinator.endOverlay(token)
        coordinator.endOverlay(token)

        XCTAssertEqual(coordinator.overlayDepth, 0)
        XCTAssertEqual(coordinator.pauseGeneration, 1)
        XCTAssertEqual(coordinator.resumeGeneration, 1)
    }

    func testActivePlayerCanBeActivatedAndCleared() {
        let coordinator = ExploreVideoPlaybackCoordinator()

        coordinator.activate(playerID: "player-a", surface: .feed)
        XCTAssertEqual(coordinator.activePlayerID, "player-a")

        coordinator.clearActivePlayer("player-b")
        XCTAssertEqual(coordinator.activePlayerID, "player-a")

        coordinator.clearActivePlayer("player-a")
        XCTAssertNil(coordinator.activePlayerID)
    }
}
