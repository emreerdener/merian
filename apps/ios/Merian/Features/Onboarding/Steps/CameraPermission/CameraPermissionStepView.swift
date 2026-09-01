import SwiftUI

struct CameraPermissionStepView: View {
    // MARK: - Permission Boundary
    private let requestCameraAccess: @MainActor (
        _ completion: @escaping OnboardingPermissionCompletion
    ) -> Void

    // MARK: - Callbacks
    let onNext: () -> Void

    @MainActor
    init(onNext: @escaping () -> Void) {
        self.init(
            requestCameraAccess:
                OnboardingPermissionDependencies.live.requestCameraAccess,
            onNext: onNext
        )
    }

    @MainActor
    init(
        requestCameraAccess: @escaping @MainActor (
            _ completion: @escaping OnboardingPermissionCompletion
        ) -> Void,
        onNext: @escaping () -> Void
    ) {
        self.requestCameraAccess = requestCameraAccess
        self.onNext = onNext
    }

    // MARK: - Visual Layout
    var body: some View {
        OnboardingStepWrapper(
            imageName: "camera",
            title: "Lens for\ndiscovery",
            subtitle: "Enable camera access so Naturebook can identify the natural world right in front of you. We never record without your permission.",
            primaryButtonTitle: "Enable camera",
            primaryButtonTextColor: Color.white,
            primaryButtonColor: Color.blue,
            primaryAction: {
                requestCameraAccess {
                    onNext()
                }
            }
        )
    }
}
