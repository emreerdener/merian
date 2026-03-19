import SwiftUI
import CoreLocation

struct LocationPermissionStepView: View {
    @ObservedObject var locationManagerDelegate: LocationPermissionDelegate
    let onNext: () -> Void
    
    var body: some View {
        BaseOnboardingStepView(
            iconColor: Color.green.opacity(0.1),
            iconText: "Location Rive Animation",
            iconCornerRadius: 100,
            title: "Where you are\nmatters",
            subtitle: "Merian uses your geographic coordinate context to instantly improve AI accuracy and identify local ecology.",
            primaryButtonTitle: "Enable location",
            primaryButtonTextColor: .black,
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
