import CoreLocation
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
            subtitle: "Merian uses your environment to cross-reference local habitats, instantly boosting AI accuracy. Your exact coordinates always remain strictly private.",
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
