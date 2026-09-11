@testable import Merian
import XCTest

@MainActor
final class CaptureControlHapticPolicyTests: XCTestCase {
    func testVisualPhotoRoutesToHeavyImpact() {
        let feedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .visual,
            isVideoRecording: false,
            isVisualCaptureAllowed: true,
            audioState: .idle,
            isDescribeInputActive: true,
            willStageDescribeOnly: false
        )

        XCTAssertEqual(feedback, .heavyImpact(.visualPhoto))
    }

    func testVideoStartRemainsOwnedByRecordingTransition() {
        let feedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .visual,
            isVideoRecording: true,
            isVisualCaptureAllowed: true,
            audioState: .idle,
            isDescribeInputActive: true,
            willStageDescribeOnly: false
        )

        XCTAssertEqual(feedback, .none)
    }

    func testRejectedVisualCaptureDoesNotEmitFeedback() {
        let feedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .visual,
            isVideoRecording: false,
            isVisualCaptureAllowed: false,
            audioState: .idle,
            isDescribeInputActive: true,
            willStageDescribeOnly: false
        )

        XCTAssertEqual(feedback, .none)
    }

    func testAudioStatesRouteToMediumPulse() {
        let idleFeedback = audioFeedback(for: .idle)
        let pauseFeedback = audioFeedback(for: .recording)
        let resumeFeedback = audioFeedback(for: .paused)
        let reviewFeedback = audioFeedback(for: .review)

        XCTAssertEqual(idleFeedback, .mediumPulse(.audioStart))
        XCTAssertEqual(pauseFeedback, .mediumPulse(.audioPause))
        XCTAssertEqual(resumeFeedback, .mediumPulse(.audioResume))
        XCTAssertEqual(reviewFeedback, .mediumPulse(.audioConfirm))
    }

    func testDescribeRequiresActiveInput() {
        let submitFeedback = describeFeedback(
            isInputActive: true,
            willStageOnly: false
        )
        let addFeedback = describeFeedback(
            isInputActive: true,
            willStageOnly: true
        )
        let emptyFeedback = describeFeedback(
            isInputActive: false,
            willStageOnly: false
        )

        XCTAssertEqual(submitFeedback, .mediumPulse(.describeSubmit))
        XCTAssertEqual(addFeedback, .mediumPulse(.describeAdd))
        XCTAssertEqual(emptyFeedback, .none)
    }

    func testAudioStateNormalizesReviewBeforeRecordingState() {
        XCTAssertEqual(
            CaptureButtonAudioState(
                isRecording: true,
                isPaused: true,
                hasPendingRecording: true
            ),
            .review
        )
        XCTAssertEqual(
            CaptureButtonAudioState(
                isRecording: true,
                isPaused: true,
                hasPendingRecording: false
            ),
            .paused
        )
        XCTAssertEqual(
            CaptureButtonAudioState(
                isRecording: false,
                isPaused: true,
                hasPendingRecording: false
            ),
            .idle
        )
    }

    private func audioFeedback(
        for audioState: CaptureButtonAudioState
    ) -> CaptureButtonHapticFeedback {
        CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .audio,
            isVideoRecording: false,
            isVisualCaptureAllowed: false,
            audioState: audioState,
            isDescribeInputActive: true,
            willStageDescribeOnly: false
        )
    }

    private func describeFeedback(
        isInputActive: Bool,
        willStageOnly: Bool
    ) -> CaptureButtonHapticFeedback {
        CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .describe,
            isVideoRecording: false,
            isVisualCaptureAllowed: false,
            audioState: .idle,
            isDescribeInputActive: isInputActive,
            willStageDescribeOnly: willStageOnly
        )
    }
}
