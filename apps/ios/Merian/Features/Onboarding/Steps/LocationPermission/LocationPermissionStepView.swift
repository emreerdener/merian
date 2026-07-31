import SwiftUI

struct LocationPermissionStepView: View {
    // MARK: - State Dependencies
    var locationManagerDelegate: LocationPermissionDelegate
    
    // MARK: - Callbacks
    let onNext: () -> Void
    
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
                locationManagerDelegate.onAuthorizationDetermined = {
                    onNext()
                }
                locationManagerDelegate.requestWhenInUse()
            },
            secondaryButtonTitle: "Skip for now",
            secondaryAction: onNext
        )
    }
}
