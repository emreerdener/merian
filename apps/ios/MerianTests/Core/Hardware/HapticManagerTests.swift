@testable import Merian
import XCTest

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
        let hardwareOrchestrator = HardwareOrchestrator(
            appSettings: appSettings,
            observeSystemChanges: false,
            functionalProAccessProvider: { true }
        )
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

    func testCaptureModeSelectionFeedbackUsesSelectionPulseAndGlobalGates() {
        appSettings.isHapticsEnabled = true
        appSettings.isExpeditionModeActive = false

        hapticManager.triggerSelectionPulse(source: "capture.modeSelector")

        XCTAssertEqual(hapticManager.lastAttempt?.event, "selectionPulse")
        XCTAssertEqual(hapticManager.lastAttempt?.source, "capture.modeSelector")
        XCTAssertNotEqual(hapticManager.lastAttempt?.outcome, .suppressed)

        appSettings.isHapticsEnabled = false
        hapticManager.triggerSelectionPulse(source: "capture.modePager")

        XCTAssertEqual(hapticManager.lastAttempt?.event, "selectionPulse")
        XCTAssertEqual(hapticManager.lastAttempt?.source, "capture.modePager")
        XCTAssertEqual(hapticManager.lastAttempt?.outcome, .suppressed)

        appSettings.isHapticsEnabled = true
        appSettings.isExpeditionModeActive = true
        hapticManager.triggerSelectionPulse(source: "capture.modeSelector")

        XCTAssertEqual(hapticManager.lastAttempt?.outcome, .suppressed)
    }

    func testHapticManagerReadsExpeditionStateFromAppSettings() {
        XCTAssertNotNil(hapticManager)

        appSettings.isHapticsEnabled = true
        appSettings.isExpeditionModeActive = false
        XCTAssertTrue(hapticManager.isFeedbackEnabled)

        appSettings.isExpeditionModeActive = true
        XCTAssertFalse(hapticManager.isFeedbackEnabled)
    }

    func testUnverifiedExpeditionPreferenceDoesNotSuppressHaptics() {
        let lockedOrchestrator = HardwareOrchestrator(
            appSettings: appSettings,
            observeSystemChanges: false,
            functionalProAccessProvider: { false }
        )
        let lockedHapticManager = HapticManager(
            appSettings: appSettings,
            hardwareOrchestrator: lockedOrchestrator
        )

        appSettings.isHapticsEnabled = true
        appSettings.isExpeditionModeActive = true

        XCTAssertTrue(lockedHapticManager.isFeedbackEnabled)
    }

    func testCaptureButtonReleaseHapticRoutesVisualPhotoToHeavyImpact() {
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

    func testCaptureButtonReleaseHapticLeavesVideoStartToRecordingTransition() {
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

    func testCaptureButtonReleaseHapticSkipsRejectedVisualCapture() {
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

    func testCaptureButtonReleaseHapticRoutesAudioStatesToMediumPulse() {
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

    func testCaptureButtonReleaseHapticRoutesDescribeOnlyWhenInputIsActive() {
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
