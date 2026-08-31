import CoreGraphics

struct IdentificationReviewFeedbackDependencies {
    let selection: @MainActor () -> Void
    let lightImpact: @MainActor () -> Void
    let mediumPulse: @MainActor () -> Void
    let successPulse: @MainActor () -> Void
    let heavyImpact: @MainActor (_ intensity: CGFloat) -> Void

    init(
        selection: @escaping @MainActor () -> Void = {},
        lightImpact: @escaping @MainActor () -> Void = {},
        mediumPulse: @escaping @MainActor () -> Void = {},
        successPulse: @escaping @MainActor () -> Void = {},
        heavyImpact: @escaping @MainActor (_ intensity: CGFloat) -> Void = { _ in }
    ) {
        self.selection = selection
        self.lightImpact = lightImpact
        self.mediumPulse = mediumPulse
        self.successPulse = successPulse
        self.heavyImpact = heavyImpact
    }

    static let live = Self(
        selection: {
            AppDIContainer.shared.hapticManager.triggerSelectionPulse()
        },
        lightImpact: {
            AppDIContainer.shared.hapticManager.triggerLightImpact()
        },
        mediumPulse: {
            AppDIContainer.shared.hapticManager.triggerMediumPulse()
        },
        successPulse: {
            AppDIContainer.shared.hapticManager.triggerSuccessPulse()
        },
        heavyImpact: { intensity in
            AppDIContainer.shared.hapticManager.triggerHeavyImpact(
                intensity: intensity
            )
        }
    )
}
