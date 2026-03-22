import SwiftUI

struct WelcomeStepView: View {
    // MARK: - Callbacks
    let onNext: () -> Void
    
    // MARK: - Visual Layout
    var body: some View {
        OnboardingStepWrapper(
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
