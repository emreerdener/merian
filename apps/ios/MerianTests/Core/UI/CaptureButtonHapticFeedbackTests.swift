@testable import Merian
import XCTest

@MainActor
final class CaptureButtonHapticFeedbackTests: XCTestCase {
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
        let idleFeedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .audio,
            isVideoRecording: false,
            isVisualCaptureAllowed: false,
            audioState: .idle,
            isDescribeInputActive: true,
            willStageDescribeOnly: false
        )
        let pauseFeedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .audio,
            isVideoRecording: false,
            isVisualCaptureAllowed: false,
            audioState: .recording,
            isDescribeInputActive: true,
            willStageDescribeOnly: false
        )
        let resumeFeedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .audio,
            isVideoRecording: false,
            isVisualCaptureAllowed: false,
            audioState: .paused,
            isDescribeInputActive: true,
            willStageDescribeOnly: false
        )
        let reviewFeedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .audio,
            isVideoRecording: false,
            isVisualCaptureAllowed: false,
            audioState: .review,
            isDescribeInputActive: true,
            willStageDescribeOnly: false
        )

        XCTAssertEqual(idleFeedback, .mediumPulse(.audioStart))
        XCTAssertEqual(pauseFeedback, .mediumPulse(.audioPause))
        XCTAssertEqual(resumeFeedback, .mediumPulse(.audioResume))
        XCTAssertEqual(reviewFeedback, .mediumPulse(.audioConfirm))
    }

    func testDescribeRequiresActiveInput() {
        let submitFeedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .describe,
            isVideoRecording: false,
            isVisualCaptureAllowed: false,
            audioState: .idle,
            isDescribeInputActive: true,
            willStageDescribeOnly: false
        )
        let addFeedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .describe,
            isVideoRecording: false,
            isVisualCaptureAllowed: false,
            audioState: .idle,
            isDescribeInputActive: true,
            willStageDescribeOnly: true
        )
        let emptyFeedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .describe,
            isVideoRecording: false,
            isVisualCaptureAllowed: false,
            audioState: .idle,
            isDescribeInputActive: false,
            willStageDescribeOnly: false
        )

        XCTAssertEqual(submitFeedback, .mediumPulse(.describeSubmit))
        XCTAssertEqual(addFeedback, .mediumPulse(.describeAdd))
        XCTAssertEqual(emptyFeedback, .none)
    }
}
