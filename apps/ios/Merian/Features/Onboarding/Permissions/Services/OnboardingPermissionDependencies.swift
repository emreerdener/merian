import AVFoundation

typealias OnboardingPermissionCompletion = @MainActor () -> Void

@MainActor
struct OnboardingPermissionDependencies {
    let requestCameraAccess: @MainActor (
        _ completion: @escaping OnboardingPermissionCompletion
    ) -> Void
    let requestLocationAccess: @MainActor (
        _ completion: @escaping OnboardingPermissionCompletion
    ) -> Void

    init(
        requestCameraAccess: @escaping @MainActor (
            _ completion: @escaping OnboardingPermissionCompletion
        ) -> Void = { completion in completion() },
        requestLocationAccess: @escaping @MainActor (
            _ completion: @escaping OnboardingPermissionCompletion
        ) -> Void = { completion in completion() }
    ) {
        self.requestCameraAccess = requestCameraAccess
        self.requestLocationAccess = requestLocationAccess
    }

    static var live: Self {
        let locationDelegate = LocationPermissionDelegate()
        return Self(
            requestCameraAccess: { completion in
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    Task { @MainActor in
                        completion()
                    }
                }
            },
            requestLocationAccess: { completion in
                locationDelegate.requestWhenInUse(
                    onAuthorizationDetermined: completion
                )
            }
        )
    }
}
