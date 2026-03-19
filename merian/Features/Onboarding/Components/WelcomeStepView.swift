import SwiftUI

struct WelcomeStepView: View {
    let onNext: () -> Void
    var body: some View {
        BaseOnboardingStepView(
            iconColor: Color.white.opacity(0.1),
            iconText: "Welcome Rive Animation",
            iconCornerRadius: 32,
            title: "Your Magical\nMagnifying Glass",
            subtitle: "Merian identifies the living world around you with scientific accuracy. Point at any plant or animal to begin.",
            primaryButtonTitle: "Get started",
            primaryButtonTextColor: Color.black,
            primaryButtonColor: Color.white,
            primaryAction: onNext
        )
    }
}
