import Combine
import CoreGraphics

struct ExploreShellDependencies {
    let appEvents: AnyPublisher<AppEvent, Never>
    let requestScansLibrary: @MainActor () -> Void
    let triggerSelectionFeedback: @MainActor () -> Void
    let triggerLightImpact: @MainActor (_ intensity: CGFloat) -> Void
    let triggerErrorFeedback: @MainActor () -> Void
}

extension ExploreShellDependencies {
    @MainActor
    static var live: Self {
        let container = AppDIContainer.shared
        let hapticManager = container.hapticManager
        return Self(
            appEvents: container.appEventPublisher.publisher,
            requestScansLibrary: {
                container.appRouteCoordinator.request(
                    .scansLibrary,
                    source: .internalUserAction
                )
            },
            triggerSelectionFeedback: {
                hapticManager.triggerSelectionPulse()
            },
            triggerLightImpact: { intensity in
                hapticManager.triggerLightImpact(intensity: intensity)
            },
            triggerErrorFeedback: {
                hapticManager.triggerErrorThump()
            }
        )
    }
}
