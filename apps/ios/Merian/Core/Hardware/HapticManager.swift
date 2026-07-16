import AVFoundation
import CoreHaptics
import Foundation
import SwiftUI
import UIKit

// MARK: - Core Sensory Feedback Engine
@MainActor
@Observable
final class HapticManager {
    // MARK: - Singleton Architecture
    static let shared = HapticManager()

    // MARK: - Prepared Hardware
    @ObservationIgnored private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    @ObservationIgnored private let light = UIImpactFeedbackGenerator(style: .light)
    @ObservationIgnored private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    @ObservationIgnored private let medium = UIImpactFeedbackGenerator(style: .medium)
    @ObservationIgnored private let selection = UISelectionFeedbackGenerator()
    @ObservationIgnored private let error = UINotificationFeedbackGenerator()
    @ObservationIgnored private let success = UINotificationFeedbackGenerator()
    @ObservationIgnored private var coreHapticsEngine: CHHapticEngine?
    @ObservationIgnored private let appSettings: AppSettings
    @ObservationIgnored private let supportsCoreHaptics: Bool
    @ObservationIgnored private var lastSuppressionLogKey: String?
    private(set) var lastAttempt: HapticAttemptRecord?

    // MARK: - Lifecycle
    init(appSettings: AppSettings? = nil, hardwareOrchestrator _: HardwareOrchestrator? = nil) {
        self.appSettings = appSettings ?? AppSettings.shared
        self.supportsCoreHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

        Task { @MainActor in
            // Delay preparation to avoid boot stutters while keeping the Taptic Engine warm for the first interaction.
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.prepareUIKitGenerators()
        }
    }

    // MARK: - Public Triggers

    func triggerFocusSnap(source: String? = nil) {
        triggerImpact(.heavy, event: .focusSnap, source: source)
    }

    func triggerSheetSpring(source: String? = nil) {
        triggerImpact(.light, event: .sheetSpring, source: source)
    }

    func triggerMediumPulse(source: String? = nil) {
        triggerImpact(.medium, event: .mediumPulse, source: source)
    }

    func triggerErrorThump(source: String? = nil) {
        triggerImpact(.rigid, event: .errorImpact, source: source)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.triggerNotification(.error, event: .errorNotification, source: source)
        }
    }

    func triggerSelectionPulse(source: String? = nil) {
        guard shouldFire(.selectionPulse, source: source) else { return }
        let didPlayCoreHaptics = playCoreImpact(.selection, event: .selectionPulse, source: source)
        selection.selectionChanged()
        selection.prepare()
        recordAttempt(.selectionPulse, source: source, outcome: didPlayCoreHaptics ? .coreHapticsAndUIKit : .uiKitFallback)
    }

    func triggerSuccessPulse(source: String? = nil) {
        triggerNotification(.success, event: .successNotification, source: source)
    }

    func triggerLightImpact(intensity: CGFloat? = nil, source: String? = nil) {
        triggerImpact(.light, intensity: intensity, event: .lightImpact, source: source)
    }

    func triggerHeavyImpact(intensity: CGFloat? = nil, source: String? = nil) {
        guard shouldFire(.heavyImpact, source: source) else { return }
        let didPlayCoreHaptics = playCoreImpact(.heavy, intensity: intensity, event: .heavyImpact, source: source)
        if let intensity {
            heavy.impactOccurred(intensity: intensity)
        } else {
            heavy.impactOccurred()
        }
        heavy.prepare()
        recordAttempt(.heavyImpact, source: source, outcome: didPlayCoreHaptics ? .coreHapticsAndUIKit : .uiKitFallback)
    }

    func prepareHeavyImpact() {
        guard shouldFire(.prepareHeavyImpact) else { return }
        prepareCoreHapticsEngine(for: .prepareHeavyImpact)
        heavy.prepare()
    }

    func triggerDiagnosticPattern(source: String) -> HapticDiagnosticSnapshot {
        let snapshot = diagnosticSnapshot(source: source)
        logDiagnosticState(snapshot)
        Task { @MainActor in
            self.triggerSelectionPulse(source: source)
            try? await Task.sleep(nanoseconds: 180_000_000)
            self.triggerMediumPulse(source: source)
            try? await Task.sleep(nanoseconds: 220_000_000)
            self.triggerHeavyImpact(intensity: 1.0, source: source)
        }
        return snapshot
    }

    // MARK: - Private

    var isFeedbackEnabled: Bool {
        appSettings.isHapticsEnabled &&
        !appSettings.isExpeditionModeActive
    }

    /// Haptics are suppressed when the user has disabled them or when expedition mode is
    /// active — expedition mode prioritises battery over feedback without permanently
    /// modifying the user's haptics preference.
    private func shouldFire(_ event: HapticEvent, source: String? = nil) -> Bool {
        guard isFeedbackEnabled else {
            logSuppressed(event, source: source)
            recordAttempt(event, source: source, outcome: .suppressed)
            return false
        }
        lastSuppressionLogKey = nil
        allowHapticsDuringRecordingIfNeeded(event)
        MerianLog.hardware.debug(
            "Haptic fired: \(event.rawValue, privacy: .public), source=\(source ?? "unspecified", privacy: .public)"
        )
        return true
    }

    private func allowHapticsDuringRecordingIfNeeded(_ event: HapticEvent) {
        let session = AVAudioSession.sharedInstance()
        guard session.category == .record ||
              session.category == .playAndRecord ||
              session.category == .multiRoute else {
            return
        }

        do {
            try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        } catch {
            MerianLog.hardware.warning(
                """
                Unable to allow haptics during recording for \
                \(event.rawValue, privacy: .public): \(error, privacy: .private)
                """
            )
        }
    }

    private func triggerImpact(
        _ style: UIImpactFeedbackGenerator.FeedbackStyle,
        intensity: CGFloat? = nil,
        event: HapticEvent,
        source: String? = nil
    ) {
        guard shouldFire(event, source: source) else { return }
        let didPlayCoreHaptics = playCoreImpact(
            CoreHapticProfile(style: style),
            intensity: intensity,
            event: event,
            source: source
        )
        let generator = impactGenerator(for: style)
        if let intensity {
            generator.impactOccurred(intensity: intensity)
        } else {
            generator.impactOccurred()
        }
        generator.prepare()
        recordAttempt(event, source: source, outcome: didPlayCoreHaptics ? .coreHapticsAndUIKit : .uiKitFallback)
    }

    private func triggerNotification(
        _ type: UINotificationFeedbackGenerator.FeedbackType,
        event: HapticEvent,
        source: String? = nil
    ) {
        guard shouldFire(event, source: source) else { return }
        let generator = notificationGenerator(for: type)
        generator.prepare()
        generator.notificationOccurred(type)
        generator.prepare()
        recordAttempt(event, source: source, outcome: .uiKitNotification)
    }

    private func prepareUIKitGenerators() {
        heavy.prepare()
        light.prepare()
        rigid.prepare()
        medium.prepare()
        selection.prepare()
        error.prepare()
        success.prepare()
    }

    private func impactGenerator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch style {
        case .light:
            light
        case .medium:
            medium
        case .heavy:
            heavy
        case .rigid:
            rigid
        case .soft:
            light
        @unknown default:
            medium
        }
    }

    private func notificationGenerator(
        for type: UINotificationFeedbackGenerator.FeedbackType
    ) -> UINotificationFeedbackGenerator {
        switch type {
        case .error:
            error
        case .success:
            success
        case .warning:
            error
        @unknown default:
            success
        }
    }

    @discardableResult
    private func playCoreImpact(
        _ profile: CoreHapticProfile,
        intensity overrideIntensity: CGFloat? = nil,
        event: HapticEvent,
        source: String? = nil
    ) -> Bool {
        guard supportsCoreHaptics else { return false }

        do {
            let engine = try runningCoreHapticsEngine(for: event)
            let resolvedIntensity: Float
            if let overrideIntensity {
                resolvedIntensity = Float(min(max(overrideIntensity, 0), 1))
            } else {
                resolvedIntensity = profile.intensity
            }
            let hapticEvent = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: resolvedIntensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: profile.sharpness)
                ],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [hapticEvent], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            MerianLog.hardware.debug(
                "Core haptic fired: \(event.rawValue, privacy: .public), source=\(source ?? "unspecified", privacy: .public)"
            )
            recordAttempt(event, source: source, outcome: .coreHaptics)
            return true
        } catch {
            coreHapticsEngine = nil
            MerianLog.hardware.warning(
                """
                Core haptic failed for \(event.rawValue, privacy: .public); \
                falling back to UIKit: \(error, privacy: .private)
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

    private func runningCoreHapticsEngine(for event: HapticEvent) throws -> CHHapticEngine {
        if let coreHapticsEngine {
            return coreHapticsEngine
        }

        let engine = try CHHapticEngine()
        engine.stoppedHandler = { reason in
            Task { @MainActor in
                self.coreHapticsEngine = nil
                MerianLog.hardware.warning(
                    """
                    Core haptic engine stopped for \(event.rawValue, privacy: .public): \
                    \(String(describing: reason), privacy: .public)
                    """
                )
            }
        }
        engine.resetHandler = {
            Task { @MainActor in
                self.coreHapticsEngine = nil
                MerianLog.hardware.debug("Core haptic engine reset")
            }
        }
        try engine.start()
        coreHapticsEngine = engine
        return engine
    }

    private func logSuppressed(_ event: HapticEvent, source: String? = nil) {
        let key = [
            event.rawValue,
            source ?? "unspecified",
            appSettings.isHapticsEnabled.description,
            appSettings.isExpeditionModeActive.description
        ].joined(separator: "|")
        guard key != lastSuppressionLogKey else { return }
        lastSuppressionLogKey = key
        MerianLog.hardware.warning(
            """
            Haptic suppressed: \(event.rawValue, privacy: .public), \
            source=\(source ?? "unspecified", privacy: .public), \
            hapticsEnabled=\(self.appSettings.isHapticsEnabled, privacy: .public), \
            expeditionMode=\(self.appSettings.isExpeditionModeActive, privacy: .public)
            """
        )
    }

    private func diagnosticSnapshot(source: String) -> HapticDiagnosticSnapshot {
        let session = AVAudioSession.sharedInstance()
        return HapticDiagnosticSnapshot(
            source: source,
            isHapticsEnabled: appSettings.isHapticsEnabled,
            isExpeditionModeActive: appSettings.isExpeditionModeActive,
            supportsCoreHaptics: supportsCoreHaptics,
            audioCategory: session.category.rawValue,
            audioMode: session.mode.rawValue
        )
    }

    private func logDiagnosticState(_ snapshot: HapticDiagnosticSnapshot) {
        MerianLog.hardware.warning(
            """
            Haptic diagnostic: source=\(snapshot.source, privacy: .public), \
            enabled=\(snapshot.isHapticsEnabled, privacy: .public), \
            expeditionMode=\(snapshot.isExpeditionModeActive, privacy: .public), \
            coreHaptics=\(snapshot.supportsCoreHaptics, privacy: .public), \
            audioCategory=\(snapshot.audioCategory, privacy: .public), \
            audioMode=\(snapshot.audioMode, privacy: .public)
            """
        )
    }

    private func recordAttempt(
        _ event: HapticEvent,
        source: String?,
        outcome: HapticAttemptOutcome
    ) {
        lastAttempt = HapticAttemptRecord(
            event: event.rawValue,
            source: source ?? "unspecified",
            outcome: outcome,
            timestamp: Date()
        )
    }
}

struct HapticAttemptRecord: Equatable {
    let event: String
    let source: String
    let outcome: HapticAttemptOutcome
    let timestamp: Date

    var displaySummary: String {
        "Last attempt: \(outcome.displayName) (\(event), \(source))"
    }
}

enum HapticAttemptOutcome: String, Equatable {
    case suppressed
    case coreHaptics
    case coreHapticsAndUIKit
    case uiKitFallback
    case uiKitNotification

    var displayName: String {
        switch self {
        case .suppressed:
            "suppressed"
        case .coreHaptics:
            "Core Haptics"
        case .coreHapticsAndUIKit:
            "Core Haptics + UIKit"
        case .uiKitFallback:
            "UIKit fallback"
        case .uiKitNotification:
            "UIKit notification"
        }
    }
}

struct HapticDiagnosticSnapshot: Equatable {
    let source: String
    let isHapticsEnabled: Bool
    let isExpeditionModeActive: Bool
    let supportsCoreHaptics: Bool
    let audioCategory: String
    let audioMode: String

    var displaySummary: String {
        [
            isHapticsEnabled ? "Naturebook haptics: on" : "Naturebook haptics: off",
            isExpeditionModeActive ? "Expedition mode: on" : "Expedition mode: off",
            supportsCoreHaptics ? "Core Haptics: supported" : "Core Haptics: unavailable",
            "Audio: \(audioCategory) / \(audioMode)"
        ].joined(separator: "\n")
    }
}

private enum HapticEvent: String {
    case focusSnap
    case sheetSpring
    case mediumPulse
    case errorImpact
    case errorNotification
    case selectionPulse
    case successNotification
    case lightImpact
    case heavyImpact
    case prepareHeavyImpact
}

private struct CoreHapticProfile {
    let intensity: Float
    let sharpness: Float

    static let selection = CoreHapticProfile(intensity: 0.35, sharpness: 0.55)
    static let heavy = CoreHapticProfile(intensity: 1.0, sharpness: 0.75)

    init(intensity: Float, sharpness: Float) {
        self.intensity = intensity
        self.sharpness = sharpness
    }

    init(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        switch style {
        case .light:
            self.init(intensity: 0.35, sharpness: 0.45)
        case .medium:
            self.init(intensity: 0.68, sharpness: 0.58)
        case .heavy:
            self.init(intensity: 1.0, sharpness: 0.75)
        case .soft:
            self.init(intensity: 0.45, sharpness: 0.25)
        case .rigid:
            self.init(intensity: 0.88, sharpness: 1.0)
        @unknown default:
            self.init(intensity: 0.65, sharpness: 0.55)
        }
    }
}
