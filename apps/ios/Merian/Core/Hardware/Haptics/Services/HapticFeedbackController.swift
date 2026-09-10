import CoreHaptics
import Foundation
import UIKit

@MainActor
final class HapticFeedbackController {
    struct ImpactGenerator {
        let prepare: @MainActor () -> Void
        let trigger: @MainActor (_ intensity: Double?) -> Void
    }

    struct SelectionGenerator {
        let prepare: @MainActor () -> Void
        let trigger: @MainActor () -> Void
    }

    struct NotificationGenerator {
        let prepare: @MainActor () -> Void
        let trigger: @MainActor (_ kind: HapticNotificationKind) -> Void
    }

    struct CoreEngine {
        let id: UUID
        let installStoppedHandler:
            @MainActor (
                _ handler: @escaping @MainActor @Sendable (String) -> Void
            ) -> Void
        let installResetHandler:
            @MainActor (
                _ handler: @escaping @MainActor @Sendable () -> Void
            ) -> Void
        let start: @MainActor () throws -> Void
        let playTransient:
            @MainActor (
                _ intensity: Float,
                _ sharpness: Float
            ) throws -> Void
    }

    struct Dependencies {
        let makeImpactGenerator:
            @MainActor (HapticImpactStyle) -> ImpactGenerator
        let makeSelectionGenerator: @MainActor () -> SelectionGenerator
        let makeNotificationGenerator:
            @MainActor (HapticNotificationKind) -> NotificationGenerator
        let supportsCoreHaptics: Bool
        let makeCoreEngine: @MainActor () throws -> CoreEngine
        let audioSession: HapticAudioSessionAdapter

        @MainActor static var live: Self {
            Self(
                makeImpactGenerator: { style in
                    let generator = UIImpactFeedbackGenerator(
                        style: style.uiKitStyle
                    )
                    return ImpactGenerator(
                        prepare: { generator.prepare() },
                        trigger: { intensity in
                            if let intensity {
                                generator.impactOccurred(
                                    intensity: CGFloat(intensity)
                                )
                            } else {
                                generator.impactOccurred()
                            }
                        }
                    )
                },
                makeSelectionGenerator: {
                    let generator = UISelectionFeedbackGenerator()
                    return SelectionGenerator(
                        prepare: { generator.prepare() },
                        trigger: { generator.selectionChanged() }
                    )
                },
                makeNotificationGenerator: { _ in
                    let generator = UINotificationFeedbackGenerator()
                    return NotificationGenerator(
                        prepare: { generator.prepare() },
                        trigger: { kind in
                            generator.notificationOccurred(kind.uiKitType)
                        }
                    )
                },
                supportsCoreHaptics:
                    CHHapticEngine.capabilitiesForHardware().supportsHaptics,
                makeCoreEngine: {
                    let engine = try CHHapticEngine()
                    return CoreEngine(
                        id: UUID(),
                        installStoppedHandler: { handler in
                            engine.stoppedHandler = { reason in
                                Task { @MainActor in
                                    handler(String(describing: reason))
                                }
                            }
                        },
                        installResetHandler: { handler in
                            engine.resetHandler = {
                                Task { @MainActor in handler() }
                            }
                        },
                        start: { try engine.start() },
                        playTransient: { intensity, sharpness in
                            let event = CHHapticEvent(
                                eventType: .hapticTransient,
                                parameters: [
                                    CHHapticEventParameter(
                                        parameterID: .hapticIntensity,
                                        value: intensity
                                    ),
                                    CHHapticEventParameter(
                                        parameterID: .hapticSharpness,
                                        value: sharpness
                                    )
                                ],
                                relativeTime: 0
                            )
                            let pattern = try CHHapticPattern(
                                events: [event],
                                parameters: []
                            )
                            let player = try engine.makePlayer(with: pattern)
                            try player.start(atTime: CHHapticTimeImmediate)
                        }
                    )
                },
                audioSession: .live
            )
        }
    }

    private let heavy: ImpactGenerator
    private let light: ImpactGenerator
    private let rigid: ImpactGenerator
    private let medium: ImpactGenerator
    private let selection: SelectionGenerator
    private let error: NotificationGenerator
    private let success: NotificationGenerator
    private let dependencies: Dependencies
    private var coreHapticsEngine: CoreEngine?

    convenience init() {
        self.init(dependencies: .live)
    }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        heavy = dependencies.makeImpactGenerator(.heavy)
        light = dependencies.makeImpactGenerator(.light)
        rigid = dependencies.makeImpactGenerator(.rigid)
        medium = dependencies.makeImpactGenerator(.medium)
        selection = dependencies.makeSelectionGenerator()
        error = dependencies.makeNotificationGenerator(.error)
        success = dependencies.makeNotificationGenerator(.success)
    }

    var supportsCoreHaptics: Bool {
        dependencies.supportsCoreHaptics
    }

    func prepareAll() {
        heavy.prepare()
        light.prepare()
        rigid.prepare()
        medium.prepare()
        selection.prepare()
        error.prepare()
        success.prepare()
    }

    func prepareAudioSession(for event: HapticEvent) {
        dependencies.audioSession.prepareForFeedback(event)
    }

    func audioSessionSnapshot() -> HapticAudioSessionSnapshot {
        dependencies.audioSession.snapshot()
    }

    func prepareImpact(
        _ style: HapticImpactStyle,
        event: HapticEvent
    ) {
        prepareCoreHapticsEngine(for: event)
        impactGenerator(for: style).prepare()
    }

    func triggerImpact(
        _ style: HapticImpactStyle,
        intensity: Double?,
        event: HapticEvent,
        source: String?
    ) -> HapticAttemptOutcome {
        let didPlayCoreHaptics = playCoreImpact(
            HapticFeedbackPolicy.coreProfile(for: style),
            intensity: intensity,
            event: event,
            source: source
        )
        let generator = impactGenerator(for: style)
        generator.trigger(intensity)
        generator.prepare()
        return didPlayCoreHaptics
            ? .coreHapticsAndUIKit
            : .uiKitFallback
    }

    func triggerSelection(
        event: HapticEvent,
        source: String?
    ) -> HapticAttemptOutcome {
        let didPlayCoreHaptics = playCoreImpact(
            HapticFeedbackPolicy.selectionProfile,
            intensity: nil,
            event: event,
            source: source
        )
        selection.trigger()
        selection.prepare()
        return didPlayCoreHaptics
            ? .coreHapticsAndUIKit
            : .uiKitFallback
    }

    func triggerNotification(
        _ kind: HapticNotificationKind
    ) -> HapticAttemptOutcome {
        let generator = notificationGenerator(for: kind)
        generator.prepare()
        generator.trigger(kind)
        generator.prepare()
        return .uiKitNotification
    }

    private func impactGenerator(
        for style: HapticImpactStyle
    ) -> ImpactGenerator {
        switch style {
        case .light:
            light
        case .medium:
            medium
        case .heavy:
            heavy
        case .rigid:
            rigid
        }
    }

    private func notificationGenerator(
        for kind: HapticNotificationKind
    ) -> NotificationGenerator {
        switch kind {
        case .error:
            error
        case .success:
            success
        }
    }

    private func playCoreImpact(
        _ profile: HapticCoreProfile,
        intensity overrideIntensity: Double?,
        event: HapticEvent,
        source: String?
    ) -> Bool {
        guard supportsCoreHaptics else { return false }

        do {
            let engine = try runningCoreHapticsEngine(for: event)
            let intensity = HapticFeedbackPolicy.resolvedIntensity(
                overrideIntensity,
                profile: profile
            )
            try engine.playTransient(intensity, profile.sharpness)
            MerianLog.hardware.debug(
                "Core haptic fired: \(event.rawValue, privacy: .public), source=\(source ?? "unspecified", privacy: .public)"
            )
            return true
        } catch {
            coreHapticsEngine = nil
            MerianLog.hardware.warning(
                """
                Core haptic failed for \
                \(event.rawValue, privacy: .public); falling back to UIKit: \
                \(error, privacy: .private)
                """
            )
            return false
        }
    }

    private func prepareCoreHapticsEngine(for event: HapticEvent) {
        guard supportsCoreHaptics else { return }

        do {
            _ = try runningCoreHapticsEngine(for: event)
        } catch {
            coreHapticsEngine = nil
            MerianLog.hardware.warning(
                "Core haptic prepare failed for \(event.rawValue, privacy: .public): \(error, privacy: .private)"
            )
        }
    }

    private func runningCoreHapticsEngine(
        for event: HapticEvent
    ) throws -> CoreEngine {
        if let coreHapticsEngine {
            return coreHapticsEngine
        }

        let engine = try dependencies.makeCoreEngine()
        let engineID = engine.id
        engine.installStoppedHandler { [weak self] reason in
            guard self?.coreHapticsEngine?.id == engineID else { return }
            self?.coreHapticsEngine = nil
            MerianLog.hardware.warning(
                """
                Core haptic engine stopped for \
                \(event.rawValue, privacy: .public): \
                \(reason, privacy: .public)
                """
            )
        }
        engine.installResetHandler { [weak self] in
            guard self?.coreHapticsEngine?.id == engineID else { return }
            self?.coreHapticsEngine = nil
            MerianLog.hardware.debug("Core haptic engine reset")
        }
        try engine.start()
        coreHapticsEngine = engine
        return engine
    }
}

private extension HapticImpactStyle {
    var uiKitStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light:
            .light
        case .medium:
            .medium
        case .heavy:
            .heavy
        case .rigid:
            .rigid
        }
    }
}

private extension HapticNotificationKind {
    var uiKitType: UINotificationFeedbackGenerator.FeedbackType {
        switch self {
        case .error:
            .error
        case .success:
            .success
        }
    }
}
