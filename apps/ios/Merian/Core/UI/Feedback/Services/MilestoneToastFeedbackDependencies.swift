import CoreGraphics
import SwiftUI

struct MilestoneToastFeedbackDependencies {
    let successPulse: @MainActor () -> Void
    let lightImpact: @MainActor (
        _ intensity: CGFloat,
        _ source: String
    ) -> Void
    let selectionPulse: @MainActor (_ source: String?) -> Void

    init(
        successPulse: @escaping @MainActor () -> Void = {},
        lightImpact: @escaping @MainActor (
            _ intensity: CGFloat,
            _ source: String
        ) -> Void = { _, _ in },
        selectionPulse: @escaping @MainActor (
            _ source: String?
        ) -> Void = { _ in }
    ) {
        self.successPulse = successPulse
        self.lightImpact = lightImpact
        self.selectionPulse = selectionPulse
    }

    @MainActor
    static func live(hapticManager: HapticManager) -> Self {
        Self(
            successPulse: {
                hapticManager.triggerSuccessPulse()
            },
            lightImpact: { intensity, source in
                hapticManager.triggerLightImpact(
                    intensity: intensity,
                    source: source
                )
            },
            selectionPulse: { source in
                hapticManager.triggerSelectionPulse(source: source)
            }
        )
    }
}

private struct MilestoneToastFeedbackEnvironmentKey: EnvironmentKey {
    static let defaultValue = MilestoneToastFeedbackDependencies()
}

extension EnvironmentValues {
    var milestoneToastFeedback: MilestoneToastFeedbackDependencies {
        get { self[MilestoneToastFeedbackEnvironmentKey.self] }
        set { self[MilestoneToastFeedbackEnvironmentKey.self] = newValue }
    }
}
