import Foundation
import Testing

@testable import Merian

@MainActor
private final class HapticHardwareProbe {
    enum ProbeError: Error {
        case failedCorePlayback
    }

    var madeImpactStyles: [HapticImpactStyle] = []
    var madeNotificationKinds: [HapticNotificationKind] = []
    var preparedImpactStyles: [HapticImpactStyle] = []
    var triggeredImpacts: [(HapticImpactStyle, Double?)] = []
    var selectionPreparationCount = 0
    var selectionTriggerCount = 0
    var notificationPreparations: [HapticNotificationKind] = []
    var triggeredNotificationGenerators: [HapticNotificationKind] = []
    var requestedNotifications: [HapticNotificationKind] = []
    var audioPreparationEvents: [HapticEvent] = []
    var coreEngineCreationCount = 0
    var coreEngineStartCount = 0
    var coreTransientValues: [(Float, Float)] = []
    var shouldFailCorePlayback = false
    var stoppedHandlers:
        [@MainActor @Sendable (String) -> Void] = []
    var resetHandlers:
        [@MainActor @Sendable () -> Void] = []

    func dependencies(
        supportsCoreHaptics: Bool
    ) -> HapticFeedbackController.Dependencies {
        HapticFeedbackController.Dependencies(
            makeImpactGenerator: { [weak self] style in
                self?.madeImpactStyles.append(style)
                return HapticFeedbackController.ImpactGenerator(
                    prepare: { [weak self] in
                        self?.preparedImpactStyles.append(style)
                    },
                    trigger: { [weak self] intensity in
                        self?.triggeredImpacts.append((style, intensity))
                    }
                )
            },
            makeSelectionGenerator: { [weak self] in
                HapticFeedbackController.SelectionGenerator(
                    prepare: { [weak self] in
                        self?.selectionPreparationCount += 1
                    },
                    trigger: { [weak self] in
                        self?.selectionTriggerCount += 1
                    }
                )
            },
            makeNotificationGenerator: { [weak self] kind in
                self?.madeNotificationKinds.append(kind)
                return HapticFeedbackController.NotificationGenerator(
                    prepare: { [weak self] in
                        self?.notificationPreparations.append(kind)
                    },
                    trigger: { [weak self] requestedKind in
                        self?.triggeredNotificationGenerators.append(kind)
                        self?.requestedNotifications.append(requestedKind)
                    }
                )
            },
            supportsCoreHaptics: supportsCoreHaptics,
            makeCoreEngine: { [weak self] in
                guard let self else { throw CancellationError() }
                coreEngineCreationCount += 1
                let engineID = UUID()
                return HapticFeedbackController.CoreEngine(
                    id: engineID,
                    installStoppedHandler: { [weak self] handler in
                        self?.stoppedHandlers.append(handler)
                    },
                    installResetHandler: { [weak self] handler in
                        self?.resetHandlers.append(handler)
                    },
                    start: { [weak self] in
                        self?.coreEngineStartCount += 1
                    },
                    playTransient: { [weak self] intensity, sharpness in
                        guard let self else { throw CancellationError() }
                        if shouldFailCorePlayback {
                            throw ProbeError.failedCorePlayback
                        }
                        coreTransientValues.append((intensity, sharpness))
                    }
                )
            },
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
    }
}

@Suite("Haptic feedback controller", .serialized)
@MainActor
struct HapticFeedbackControllerTests {
    @Test("UIKit generators are constructed once and retain established routing")
    func uiKitGeneratorRouting() {
        let probe = HapticHardwareProbe()
        let controller = HapticFeedbackController(
            dependencies: probe.dependencies(supportsCoreHaptics: false)
        )

        #expect(probe.madeImpactStyles == [.heavy, .light, .rigid, .medium])
        #expect(probe.madeNotificationKinds == [.error, .success])

        controller.prepareAll()
        #expect(
            probe.preparedImpactStyles == [.heavy, .light, .rigid, .medium]
        )
        #expect(probe.selectionPreparationCount == 1)
        #expect(probe.notificationPreparations == [.error, .success])

        let lightOutcome = controller.triggerImpact(
            .light,
            intensity: 0.4,
            event: .lightImpact,
            source: "test.light"
        )
        let errorOutcome = controller.triggerNotification(.error)
        let successOutcome = controller.triggerNotification(.success)

        #expect(lightOutcome == .uiKitFallback)
        #expect(probe.triggeredImpacts.count == 1)
        #expect(probe.triggeredImpacts[0].0 == .light)
        #expect(probe.triggeredImpacts[0].1 == 0.4)
        #expect(errorOutcome == .uiKitNotification)
        #expect(successOutcome == .uiKitNotification)
        #expect(probe.triggeredNotificationGenerators == [.error, .success])
        #expect(probe.requestedNotifications == [.error, .success])
    }

    @Test("Core engine reset is identity-fenced against its replacement")
    func staleCoreEngineResetCannotClearReplacement() throws {
        let probe = HapticHardwareProbe()
        let controller = HapticFeedbackController(
            dependencies: probe.dependencies(supportsCoreHaptics: true)
        )

        #expect(
            controller.triggerSelection(
                event: .selectionPulse,
                source: "first"
            ) == .coreHapticsAndUIKit
        )
        let staleReset = try #require(probe.resetHandlers.first)
        staleReset()

        #expect(
            controller.triggerSelection(
                event: .selectionPulse,
                source: "replacement"
            ) == .coreHapticsAndUIKit
        )
        staleReset()
        #expect(
            controller.triggerSelection(
                event: .selectionPulse,
                source: "reuse"
            ) == .coreHapticsAndUIKit
        )

        #expect(probe.coreEngineCreationCount == 2)
        #expect(probe.coreEngineStartCount == 2)
        #expect(probe.coreTransientValues.count == 3)
        #expect(probe.selectionTriggerCount == 3)
    }

    @Test("Core engine stop is identity-fenced against its replacement")
    func staleCoreEngineStopCannotClearReplacement() throws {
        let probe = HapticHardwareProbe()
        let controller = HapticFeedbackController(
            dependencies: probe.dependencies(supportsCoreHaptics: true)
        )

        #expect(
            controller.triggerSelection(
                event: .selectionPulse,
                source: "first"
            ) == .coreHapticsAndUIKit
        )
        let staleStop = try #require(probe.stoppedHandlers.first)
        staleStop("test stop")

        #expect(
            controller.triggerSelection(
                event: .selectionPulse,
                source: "replacement"
            ) == .coreHapticsAndUIKit
        )
        staleStop("stale stop")
        #expect(
            controller.triggerSelection(
                event: .selectionPulse,
                source: "reuse"
            ) == .coreHapticsAndUIKit
        )

        #expect(probe.coreEngineCreationCount == 2)
        #expect(probe.coreEngineStartCount == 2)
        #expect(probe.coreTransientValues.count == 3)
        #expect(probe.selectionTriggerCount == 3)
    }

    @Test("Core playback failure falls back and rebuilds on the next request")
    func corePlaybackFailureFallsBackAndClearsEngine() {
        let probe = HapticHardwareProbe()
        probe.shouldFailCorePlayback = true
        let controller = HapticFeedbackController(
            dependencies: probe.dependencies(supportsCoreHaptics: true)
        )

        let firstOutcome = controller.triggerImpact(
            .heavy,
            intensity: 2,
            event: .heavyImpact,
            source: "first"
        )
        let secondOutcome = controller.triggerImpact(
            .heavy,
            intensity: -1,
            event: .heavyImpact,
            source: "second"
        )

        #expect(firstOutcome == .uiKitFallback)
        #expect(secondOutcome == .uiKitFallback)
        #expect(probe.coreEngineCreationCount == 2)
        #expect(probe.triggeredImpacts.count == 2)
    }

    @Test("Audio-session effects and diagnostics use the injected adapter")
    func audioSessionAdapterBoundary() {
        let probe = HapticHardwareProbe()
        let controller = HapticFeedbackController(
            dependencies: probe.dependencies(supportsCoreHaptics: false)
        )

        controller.prepareAudioSession(for: .focusSnap)

        #expect(probe.audioPreparationEvents == [.focusSnap])
        #expect(
            controller.audioSessionSnapshot() == HapticAudioSessionSnapshot(
                category: "test.category",
                mode: "test.mode"
            )
        )
    }
}
