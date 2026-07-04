import XCTest
@testable import Merian

@MainActor
final class HapticManagerTests: XCTestCase {

    var hapticManager: HapticManager!
    var appSettings: AppSettings!
    var userDefaults: UserDefaults!
    var suiteName: String!

    override func setUp() async throws {
        suiteName = "merian.tests.haptics.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        appSettings = AppSettings(userDefaults: userDefaults, observeExternalChanges: false)
        let hardwareOrchestrator = HardwareOrchestrator(appSettings: appSettings, observeSystemChanges: false)
        hapticManager = HapticManager(appSettings: appSettings, hardwareOrchestrator: hardwareOrchestrator)
    }

    override func tearDown() async throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        hapticManager = nil
        appSettings = nil
        userDefaults = nil
        suiteName = nil
    }

    func testHapticManagerInstantiation() {
        XCTAssertNotNil(hapticManager)
        
        appSettings.isHapticsEnabled = true
        // Since haptic hardware cannot be explicitly queried for state in the Simulator,
        // we ensure the methods don't crash when executed consecutively.
        
        hapticManager.triggerFocusSnap()
        hapticManager.triggerSheetSpring()
        hapticManager.triggerMediumPulse()
        hapticManager.triggerErrorThump()
        hapticManager.triggerSelectionPulse()
        hapticManager.triggerSuccessPulse()
    }
    
    func testHapticManagerRespectsUserDefaultsToggle() {
        XCTAssertNotNil(hapticManager)
        
        appSettings.isHapticsEnabled = false
        
        // This should skip internally without crashing or side effects
        hapticManager.triggerFocusSnap()
        hapticManager.triggerSheetSpring()
        hapticManager.triggerMediumPulse()
        hapticManager.triggerErrorThump()
        hapticManager.triggerSelectionPulse()
        hapticManager.triggerSuccessPulse()
    }

    func testCaptureButtonReleaseHapticRoutesVisualPhotoToHeavyImpact() {
        let feedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .visual,
            isVideoRecording: false,
            isVisualCaptureAllowed: true,
            audioState: .idle,
            isDescribeInputActive: true
        )

        XCTAssertEqual(feedback, .heavyImpact)
    }

    func testCaptureButtonReleaseHapticLeavesVideoStartToRecordingTransition() {
        let feedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .visual,
            isVideoRecording: true,
            isVisualCaptureAllowed: true,
            audioState: .idle,
            isDescribeInputActive: true
        )

        XCTAssertEqual(feedback, .none)
    }

    func testCaptureButtonReleaseHapticSkipsRejectedVisualCapture() {
        let feedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .visual,
            isVideoRecording: false,
            isVisualCaptureAllowed: false,
            audioState: .idle,
            isDescribeInputActive: true
        )

        XCTAssertEqual(feedback, .none)
    }

    func testCaptureButtonReleaseHapticRoutesAudioStatesToMediumPulse() {
        let idleFeedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .audio,
            isVideoRecording: false,
            isVisualCaptureAllowed: false,
            audioState: .idle,
            isDescribeInputActive: true
        )
        let pauseFeedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .audio,
            isVideoRecording: false,
            isVisualCaptureAllowed: false,
            audioState: .recording,
            isDescribeInputActive: true
        )
        let resumeFeedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .audio,
            isVideoRecording: false,
            isVisualCaptureAllowed: false,
            audioState: .paused,
            isDescribeInputActive: true
        )
        let reviewFeedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .audio,
            isVideoRecording: false,
            isVisualCaptureAllowed: false,
            audioState: .review,
            isDescribeInputActive: true
        )

        XCTAssertEqual(idleFeedback, .mediumPulse)
        XCTAssertEqual(pauseFeedback, .mediumPulse)
        XCTAssertEqual(resumeFeedback, .mediumPulse)
        XCTAssertEqual(reviewFeedback, .mediumPulse)
    }

    func testCaptureButtonReleaseHapticRoutesDescribeOnlyWhenInputIsActive() {
        let activeFeedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .describe,
            isVideoRecording: false,
            isVisualCaptureAllowed: false,
            audioState: .idle,
            isDescribeInputActive: true
        )
        let emptyFeedback = CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: .describe,
            isVideoRecording: false,
            isVisualCaptureAllowed: false,
            audioState: .idle,
            isDescribeInputActive: false
        )

        XCTAssertEqual(activeFeedback, .mediumPulse)
        XCTAssertEqual(emptyFeedback, .none)
    }
}
