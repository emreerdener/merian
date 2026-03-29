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
            iconColor: Color.green.opacity(0.1),
            iconText: "Location Rive Animation",
            iconCornerRadius: 100,
            title: "Where you are\nmatters",
            subtitle: "Merian uses your geographic coordinate context to instantly improve AI accuracy and identify local ecology.",
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
