@testable import Merian
import XCTest

final class CaptureControlBarPresentationTests: XCTestCase {
    func testRefinementDescriptionPlusRemainsAvailableAtPhysicalMediaCapacity() {
        let description = makePresentation(
            captureMode: .describe,
            totalStagedItems: 3,
            availableStagedSlots: 0,
            capacityLimit: 2,
            isRefining: true,
            isDescriptionEmpty: false
        )
        let photo = makePresentation(
            captureMode: .visual,
            totalStagedItems: 3,
            availableStagedSlots: 0,
            capacityLimit: 2,
            isRefining: true
        )
        XCTAssertFalse(description.isAtCapacity)
        XCTAssertFalse(description.isPrimaryActionDisabled)
        XCTAssertTrue(description.willStageOnly)
        XCTAssertTrue(description.showsDictation)
        XCTAssertTrue(photo.isAtCapacity)
        XCTAssertFalse(photo.isPhotoLibraryAvailable)
    }

    func testVisualCapacityPreservesDisabledVisibleControls() {
        let presentation = makePresentation(
            captureMode: .visual,
            totalStagedItems: 2,
            availableStagedSlots: 0,
            capacityLimit: 2
        )

        XCTAssertTrue(presentation.isAtCapacity)
        XCTAssertEqual(presentation.photoSelectionCount, 1)
        XCTAssertTrue(presentation.showsPhotoLibrary)
        XCTAssertFalse(presentation.isPhotoLibraryAvailable)
        XCTAssertTrue(presentation.showsFlash)
        XCTAssertFalse(presentation.isFlashAvailable)
        XCTAssertTrue(presentation.isPrimaryActionDisabled)
    }

    func testVisualRecordingSwapsPhotoLibraryForCancel() {
        let presentation = makePresentation(
            captureMode: .visual,
            isVideoRecording: true
        )

        XCTAssertFalse(presentation.showsPhotoLibrary)
        XCTAssertFalse(presentation.isPhotoLibraryAvailable)
        XCTAssertTrue(presentation.showsVideoCancel)
        XCTAssertTrue(presentation.showsFlash)
        XCTAssertTrue(presentation.isFlashAvailable)
    }

    func testAudioControlsTrackRecordingAndReviewIndependently() {
        let recording = makePresentation(
            captureMode: .audio,
            isAudioRecording: true
        )
        let review = makePresentation(
            captureMode: .audio,
            hasPendingAudio: true
        )

        XCTAssertTrue(recording.showsAudioDelete)
        XCTAssertTrue(recording.showsAudioDone)
        XCTAssertFalse(recording.showsAudioReview)
        XCTAssertTrue(review.showsAudioDelete)
        XCTAssertFalse(review.showsAudioDone)
        XCTAssertTrue(review.showsAudioReview)
    }

    func testDescribeStatePreservesPromptInputAndRefinementRules() {
        let empty = makePresentation(
            captureMode: .describe,
            isDescriptionEmpty: true
        )
        let refinement = makePresentation(
            captureMode: .describe,
            isRefining: true,
            isStagingRefinement: true,
            isDescriptionEmpty: false
        )

        XCTAssertTrue(empty.showsPromptList)
        XCTAssertTrue(empty.showsDictation)
        XCTAssertFalse(empty.isInputActive)
        XCTAssertFalse(empty.willStageOnly)
        XCTAssertFalse(refinement.showsPromptList)
        XCTAssertTrue(refinement.isInputActive)
        XCTAssertTrue(refinement.willStageOnly)
        XCTAssertTrue(refinement.isPrimaryActionDisabled)
    }

    func testEveryStagingReasonSelectsAddPresentation() {
        let stagedVisual = makePresentation(
            captureMode: .describe,
            hasStagedVisualMedia: true
        )
        let stagedAudio = makePresentation(
            captureMode: .describe,
            hasStagedAudio: true
        )
        let stagedDescription = makePresentation(
            captureMode: .describe,
            hasStagedDescription: true
        )
        let multiCapture = makePresentation(
            captureMode: .describe,
            isMultiCaptureEnabled: true
        )
        let confirmation = makePresentation(
            captureMode: .describe,
            requiresScanConfirmation: true
        )

        XCTAssertTrue(stagedVisual.willStageOnly)
        XCTAssertTrue(stagedAudio.willStageOnly)
        XCTAssertTrue(stagedDescription.willStageOnly)
        XCTAssertTrue(multiCapture.willStageOnly)
        XCTAssertTrue(confirmation.willStageOnly)
    }

    func testPrimaryPresentationSelectsModeSpecificProgressAndFeedback() {
        let video = CapturePrimaryActionPresentation(
            captureMode: .visual,
            willStageOnly: false,
            isInputActive: true,
            isVisualCaptureAllowed: true,
            isVideoRecording: true,
            videoRecordingProgress: 0.75,
            audioState: .idle,
            audioRecordingProgress: 0.25
        )
        let pausedAudio = CapturePrimaryActionPresentation(
            captureMode: .audio,
            willStageOnly: false,
            isInputActive: true,
            isVisualCaptureAllowed: false,
            isVideoRecording: false,
            videoRecordingProgress: 0.75,
            audioState: .paused,
            audioRecordingProgress: 0.25
        )

        XCTAssertTrue(video.shouldShowRecordingChrome)
        XCTAssertEqual(video.recordingProgress, 0.75)
        XCTAssertEqual(video.releaseHapticFeedback, .none)
        XCTAssertTrue(pausedAudio.shouldShowRecordingChrome)
        XCTAssertTrue(pausedAudio.isAudioPaused)
        XCTAssertEqual(pausedAudio.recordingProgress, 0.25)
        XCTAssertEqual(
            pausedAudio.releaseHapticFeedback,
            .mediumPulse(.audioResume)
        )
    }

    func testLatentAudioStateDoesNotChangeOtherModeChrome() {
        let visual = CapturePrimaryActionPresentation(
            captureMode: .visual,
            willStageOnly: false,
            isInputActive: true,
            isVisualCaptureAllowed: true,
            isVideoRecording: false,
            videoRecordingProgress: 0.75,
            audioState: .review,
            audioRecordingProgress: 0.25
        )
        let describe = CapturePrimaryActionPresentation(
            captureMode: .describe,
            willStageOnly: false,
            isInputActive: true,
            isVisualCaptureAllowed: false,
            isVideoRecording: false,
            videoRecordingProgress: 0.75,
            audioState: .paused,
            audioRecordingProgress: 0.25
        )

        XCTAssertFalse(visual.isAudioReview)
        XCTAssertFalse(visual.shouldShowRecordingChrome)
        XCTAssertFalse(describe.isAudioRecording)
        XCTAssertFalse(describe.shouldShowRecordingChrome)
    }

    private func makePresentation(
        captureMode: CaptureMode,
        totalStagedItems: Int = 0,
        availableStagedSlots: Int = 1,
        capacityLimit: Int = 1,
        hasStagedVisualMedia: Bool = false,
        hasStagedAudio: Bool = false,
        hasStagedDescription: Bool = false,
        isRefining: Bool = false,
        isMultiCaptureEnabled: Bool = false,
        requiresScanConfirmation: Bool = false,
        isVideoRecording: Bool = false,
        isAudioRecording: Bool = false,
        hasPendingAudio: Bool = false,
        isCheckingScanAdmission: Bool = false,
        isStagingRefinement: Bool = false,
        isDescriptionEmpty: Bool = false
    ) -> CaptureControlBarPresentation {
        CaptureControlBarPresentation(
            captureMode: captureMode,
            totalStagedItems: totalStagedItems,
            availableStagedSlots: availableStagedSlots,
            capacityLimit: capacityLimit,
            hasStagedVisualMedia: hasStagedVisualMedia,
            hasStagedAudio: hasStagedAudio,
            hasStagedDescription: hasStagedDescription,
            isRefining: isRefining,
            isMultiCaptureEnabled: isMultiCaptureEnabled,
            requiresScanConfirmation: requiresScanConfirmation,
            isVideoRecording: isVideoRecording,
            isAudioRecording: isAudioRecording,
            hasPendingAudio: hasPendingAudio,
            isCheckingScanAdmission: isCheckingScanAdmission,
            isStagingRefinement: isStagingRefinement,
            isDescriptionEmpty: isDescriptionEmpty
        )
    }
}
