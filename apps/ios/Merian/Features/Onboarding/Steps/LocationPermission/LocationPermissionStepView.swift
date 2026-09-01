import SwiftUI

struct LocationPermissionStepView: View {
    // MARK: - Permission Boundary
    private let requestLocationAccess: @MainActor (
        _ completion: @escaping OnboardingPermissionCompletion
    ) -> Void

    // MARK: - Callbacks
    let onNext: () -> Void

    @MainActor
    init(onNext: @escaping () -> Void) {
        self.init(
            requestLocationAccess:
                OnboardingPermissionDependencies.live.requestLocationAccess,
            onNext: onNext
        )
    }

    @MainActor
    init(
        requestLocationAccess: @escaping @MainActor (
            _ completion: @escaping OnboardingPermissionCompletion
        ) -> Void,
        onNext: @escaping () -> Void
    ) {
        self.requestLocationAccess = requestLocationAccess
        self.onNext = onNext
    }

    @MainActor
    init(
        locationManagerDelegate: LocationPermissionDelegate,
        onNext: @escaping () -> Void
    ) {
        self.init(
            requestLocationAccess: { completion in
                locationManagerDelegate.requestWhenInUse(
                    onAuthorizationDetermined: completion
                )
            },
            onNext: onNext
        )
    }

    // MARK: - Visual Layout
    var body: some View {
        OnboardingStepWrapper(
            imageName: "location",
            title: "Context is\neverything",
            subtitle: "Location improves identification and becomes part of each submitted scientific observation. Geoprivacy controls public display; exact coordinates remain in Naturebook's scientific backend record.",
            primaryButtonTitle: "Enable location",
            primaryButtonTextColor: Color.black,
            primaryButtonColor: Color.green.opacity(0.8),
            primaryAction: {
                requestLocationAccess {
                    onNext()
                }
            },
            secondaryButtonTitle: "Skip for now",
            secondaryAction: onNext
        )
    }
}
