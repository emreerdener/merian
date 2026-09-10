import CoreGraphics
import Foundation
import Observation

// MARK: - Core Sensory Feedback Facade

@MainActor
@Observable
final class HapticManager {
    struct Dependencies {
        let controller: HapticFeedbackController
        let now: @MainActor () -> Date

        @MainActor static var live: Self {
            Self(
                controller: HapticFeedbackController(),
                now: Date.init
            )
        }
    }

    static let shared = HapticManager()

    @ObservationIgnored private let appSettings: AppSettings
    @ObservationIgnored private let hardwareOrchestrator: HardwareOrchestrator
    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var lastSuppressionLogKey: String?
    private(set) var lastAttempt: HapticAttemptRecord?

    convenience init(
        appSettings: AppSettings? = nil,
        hardwareOrchestrator: HardwareOrchestrator? = nil
    ) {
        self.init(
            appSettings: appSettings,
            hardwareOrchestrator: hardwareOrchestrator,
            dependencies: .live
        )
    }

    init(
        appSettings: AppSettings? = nil,
        hardwareOrchestrator: HardwareOrchestrator? = nil,
        dependencies: Dependencies
    ) {
        self.appSettings = appSettings ?? AppSettings.shared
        self.hardwareOrchestrator =
            hardwareOrchestrator ?? HardwareOrchestrator.shared
        self.dependencies = dependencies

        Task { @MainActor [weak self] in
            // Avoid boot stutters while keeping generators warm for first use.
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.dependencies.controller.prepareAll()
        }
    }

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
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.triggerNotification(
                .error,
                event: .errorNotification,
                source: source
            )
        }
    }

    func triggerSelectionPulse(source: String? = nil) {
        guard shouldFire(.selectionPulse, source: source) else { return }
        let outcome = dependencies.controller.triggerSelection(
            event: .selectionPulse,
            source: source
        )
        recordAttempt(.selectionPulse, source: source, outcome: outcome)
    }

    func triggerSuccessPulse(source: String? = nil) {
        triggerNotification(
            .success,
            event: .successNotification,
            source: source
        )
    }

    func triggerLightImpact(
        intensity: CGFloat? = nil,
        source: String? = nil
    ) {
        triggerImpact(
            .light,
            intensity: intensity,
            event: .lightImpact,
            source: source
        )
    }

    func triggerHeavyImpact(
        intensity: CGFloat? = nil,
        source: String? = nil
    ) {
        triggerImpact(
            .heavy,
            intensity: intensity,
            event: .heavyImpact,
            source: source
        )
    }

    func prepareHeavyImpact() {
        guard shouldFire(.prepareHeavyImpact) else { return }
        dependencies.controller.prepareImpact(
            .heavy,
            event: .prepareHeavyImpact
        )
    }

    func triggerDiagnosticPattern(source: String) -> HapticDiagnosticSnapshot {
        let snapshot = diagnosticSnapshot(source: source)
        logDiagnosticState(snapshot)
        Task { @MainActor [weak self] in
            self?.triggerSelectionPulse(source: source)
            try? await Task.sleep(nanoseconds: 180_000_000)
            self?.triggerMediumPulse(source: source)
            try? await Task.sleep(nanoseconds: 220_000_000)
            self?.triggerHeavyImpact(intensity: 1.0, source: source)
        }
        return snapshot
    }

    var isFeedbackEnabled: Bool {
        HapticFeedbackPolicy.isFeedbackEnabled(
            isPreferenceEnabled: appSettings.isHapticsEnabled,
            isExpeditionModeActive:
                hardwareOrchestrator.isExpeditionModeActive
        )
    }

    private func shouldFire(
        _ event: HapticEvent,
        source: String? = nil
    ) -> Bool {
        guard isFeedbackEnabled else {
            logSuppressed(event, source: source)
            recordAttempt(event, source: source, outcome: .suppressed)
            return false
        }
        lastSuppressionLogKey = nil
        dependencies.controller.prepareAudioSession(for: event)
        MerianLog.hardware.debug(
            "Haptic fired: \(event.rawValue, privacy: .public), source=\(source ?? "unspecified", privacy: .public)"
        )
        return true
    }

    private func triggerImpact(
        _ style: HapticImpactStyle,
        intensity: CGFloat? = nil,
        event: HapticEvent,
        source: String? = nil
    ) {
        guard shouldFire(event, source: source) else { return }
        let outcome = dependencies.controller.triggerImpact(
            style,
            intensity: intensity.map(Double.init),
            event: event,
            source: source
        )
        recordAttempt(event, source: source, outcome: outcome)
    }

    private func triggerNotification(
        _ kind: HapticNotificationKind,
        event: HapticEvent,
        source: String? = nil
    ) {
        guard shouldFire(event, source: source) else { return }
        let outcome = dependencies.controller.triggerNotification(kind)
        recordAttempt(event, source: source, outcome: outcome)
    }

    private func logSuppressed(
        _ event: HapticEvent,
        source: String? = nil
    ) {
        let key = HapticFeedbackPolicy.suppressionLogKey(
            event: event,
            source: source,
            isPreferenceEnabled: appSettings.isHapticsEnabled,
            isExpeditionModeActive:
                hardwareOrchestrator.isExpeditionModeActive
        )
        guard key != lastSuppressionLogKey else { return }
        lastSuppressionLogKey = key
        MerianLog.hardware.warning(
            """
            Haptic suppressed: \(event.rawValue, privacy: .public), \
            source=\(source ?? "unspecified", privacy: .public), \
            hapticsEnabled=\(self.appSettings.isHapticsEnabled, privacy: .public), \
            expeditionMode=\(self.hardwareOrchestrator.isExpeditionModeActive, privacy: .public)
            """
        )
    }

    private func diagnosticSnapshot(source: String) -> HapticDiagnosticSnapshot {
        let audioSession = dependencies.controller.audioSessionSnapshot()
        return HapticDiagnosticSnapshot(
            source: source,
            isHapticsEnabled: appSettings.isHapticsEnabled,
            isExpeditionModeActive:
                hardwareOrchestrator.isExpeditionModeActive,
            supportsCoreHaptics:
                dependencies.controller.supportsCoreHaptics,
            audioCategory: audioSession.category,
            audioMode: audioSession.mode
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
            timestamp: dependencies.now()
        )
    }
}
