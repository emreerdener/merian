@testable import Merian
import XCTest

@MainActor
private final class HapticManagerHardwareProbe {
    private enum TestError: Error {
        case unexpectedCoreEngine
    }

    var triggeredImpactStyles: [HapticImpactStyle] = []
    var selectionTriggerCount = 0
    var triggeredNotificationGenerators: [HapticNotificationKind] = []
    var audioPreparationEvents: [HapticEvent] = []

    func controller() -> HapticFeedbackController {
        HapticFeedbackController(
            dependencies: HapticFeedbackController.Dependencies(
                makeImpactGenerator: { [weak self] style in
                    HapticFeedbackController.ImpactGenerator(
                        prepare: {},
                        trigger: { [weak self] _ in
                            self?.triggeredImpactStyles.append(style)
                        }
                    )
                },
                makeSelectionGenerator: { [weak self] in
                    HapticFeedbackController.SelectionGenerator(
                        prepare: {},
                        trigger: { [weak self] in
                            self?.selectionTriggerCount += 1
                        }
                    )
                },
                makeNotificationGenerator: { [weak self] kind in
                    HapticFeedbackController.NotificationGenerator(
                        prepare: {},
                        trigger: { [weak self] _ in
                            self?.triggeredNotificationGenerators.append(kind)
                        }
                    )
                },
                supportsCoreHaptics: false,
                makeCoreEngine: { throw TestError.unexpectedCoreEngine },
                audioSession: HapticAudioSessionAdapter(
                    prepareForFeedback: { [weak self] event in
                        self?.audioPreparationEvents.append(event)
                    },
                    snapshot: {
                        HapticAudioSessionSnapshot(
                            category: "test.category",
                            mode: "test.mode"
                        )
                    }
                )
            )
        )
    }
}

@MainActor
final class HapticManagerTests: XCTestCase {
    var hapticManager: HapticManager!
    var appSettings: AppSettings!
    private var hardwareProbe: HapticManagerHardwareProbe!
    var userDefaults: UserDefaults!
    var suiteName: String!

    override func setUp() async throws {
        suiteName = "merian.tests.haptics.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        appSettings = AppSettings(
            userDefaults: userDefaults,
            observeExternalChanges: false
        )
        let hardwareOrchestrator = HardwareOrchestrator(
            appSettings: appSettings,
            observeSystemChanges: false,
            functionalProAccessProvider: { true }
        )
        hardwareProbe = HapticManagerHardwareProbe()
        hapticManager = makeManager(
            hardwareOrchestrator: hardwareOrchestrator
        )
    }

    override func tearDown() async throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        hapticManager = nil
        appSettings = nil
        hardwareProbe = nil
        userDefaults = nil
        suiteName = nil
    }

    func testSemanticRoutesUseInjectedHardwareController() async throws {
        appSettings.isHapticsEnabled = true

        hapticManager.triggerFocusSnap()
        hapticManager.triggerSheetSpring()
        hapticManager.triggerMediumPulse()
        hapticManager.triggerErrorThump()
        hapticManager.triggerSelectionPulse()
        hapticManager.triggerSuccessPulse()

        XCTAssertEqual(
            hardwareProbe.triggeredImpactStyles,
            [.heavy, .light, .medium, .rigid]
        )
        XCTAssertEqual(hardwareProbe.selectionTriggerCount, 1)
        XCTAssertEqual(
            hardwareProbe.triggeredNotificationGenerators,
            [.success]
        )
        XCTAssertEqual(
            hardwareProbe.audioPreparationEvents,
            [
                .focusSnap,
                .sheetSpring,
                .mediumPulse,
                .errorImpact,
                .selectionPulse,
                .successNotification
            ]
        )

        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(
            hardwareProbe.triggeredNotificationGenerators,
            [.success, .error]
        )
        XCTAssertEqual(
            hardwareProbe.audioPreparationEvents.last,
            .errorNotification
        )
        XCTAssertEqual(hapticManager.lastAttempt?.event, "errorNotification")
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

        XCTAssertTrue(hardwareProbe.triggeredImpactStyles.isEmpty)
        XCTAssertEqual(hardwareProbe.selectionTriggerCount, 0)
        XCTAssertTrue(hardwareProbe.triggeredNotificationGenerators.isEmpty)
        XCTAssertTrue(hardwareProbe.audioPreparationEvents.isEmpty)
        XCTAssertEqual(hapticManager.lastAttempt?.outcome, .suppressed)
    }

    func testCaptureModeSelectionFeedbackUsesSelectionPulseAndGlobalGates() {
        appSettings.isHapticsEnabled = true
        appSettings.isExpeditionModeActive = false

        hapticManager.triggerSelectionPulse(source: "capture.modeSelector")

        XCTAssertEqual(hapticManager.lastAttempt?.event, "selectionPulse")
        XCTAssertEqual(hapticManager.lastAttempt?.source, "capture.modeSelector")
        XCTAssertNotEqual(hapticManager.lastAttempt?.outcome, .suppressed)
        XCTAssertEqual(
            hapticManager.lastAttempt?.timestamp,
            Date(timeIntervalSince1970: 1)
        )

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
        let lockedHapticManager = makeManager(
            hardwareOrchestrator: lockedOrchestrator
        )

        appSettings.isHapticsEnabled = true
        appSettings.isExpeditionModeActive = true

        XCTAssertTrue(lockedHapticManager.isFeedbackEnabled)
    }

    private func makeManager(
        hardwareOrchestrator: HardwareOrchestrator
    ) -> HapticManager {
        HapticManager(
            appSettings: appSettings,
            hardwareOrchestrator: hardwareOrchestrator,
            dependencies: HapticManager.Dependencies(
                controller: hardwareProbe.controller(),
                now: { Date(timeIntervalSince1970: 1) }
            )
        )
    }

}
