import SwiftUI

struct ReadyStepView: View {
    // MARK: - Callbacks
    let onFinish: () -> Void
    
    // MARK: - Visual Layout
    var body: some View {
        OnboardingStepWrapper(
            iconColor: Color.yellow.opacity(0.1),
            iconText: "Success Rive Animation",
            iconCornerRadius: 32,
            title: "You're ready",
            subtitle: "Let's step outside and discover something wild.",
            primaryButtonTitle: "Start scanning",
            primaryButtonTextColor: Color.black,
            primaryButtonColor: Color.white,
            primaryAction: onFinish
        )
    }
}
