struct CaptureControlDependencies {
    let isVisualCaptureAllowed: @MainActor @Sendable () -> Bool
    let isProVideoAvailable: @MainActor @Sendable () -> Bool
    let dismissKeyboard: @MainActor @Sendable () -> Void
    let trackProVideoPaywallImpression: @MainActor @Sendable () -> Void
    let performHapticFeedback: @MainActor @Sendable (
        CaptureButtonHapticFeedback
    ) -> Void

    @MainActor
    static func live(diContainer: AppDIContainer) -> Self {
        Self(
            isVisualCaptureAllowed: {
                diContainer.usageManager.canPerformScan(
                    isProActive: diContainer.revenueCatManager.canStartProScan
                )
            },
            isProVideoAvailable: {
                diContainer.revenueCatManager.canStartProScan
            },
            dismissKeyboard: {
                CaptureWorkspaceKeyboardService.dismissKeyboard()
            },
            trackProVideoPaywallImpression: {
                AppTelemetry.trackPaywallImpression()
            },
            performHapticFeedback: { feedback in
                let hapticManager = diContainer.hapticManager
                switch feedback {
                case .none:
                    break
                case .prepareHeavyImpact:
                    hapticManager.prepareHeavyImpact()
                case .heavyImpact(let source):
                    hapticManager.triggerHeavyImpact(
                        intensity: 1.0,
                        source: source.rawValue
                    )
                case .mediumPulse(let source):
                    hapticManager.triggerMediumPulse(source: source.rawValue)
                case .lightImpact(let source, let intensity):
                    hapticManager.triggerLightImpact(
                        intensity: intensity,
                        source: source.rawValue
                    )
                case .focusSnap(let source):
                    hapticManager.triggerFocusSnap(source: source.rawValue)
                }
            }
        )
    }
}
