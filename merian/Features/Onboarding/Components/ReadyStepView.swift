import SwiftUI

struct ReadyStepView: View {
    let onFinish: () -> Void
    var body: some View {
        BaseOnboardingStepView(
            iconColor: Color.yellow.opacity(0.1),
            iconText: "Success Rive Animation",
            iconCornerRadius: 32,
            title: "You're ready",
            subtitle: "Let's step outside and discover something wild.",
            primaryButtonTitle: "Start scanning",
            primaryButtonTextColor: .black,
            primaryButtonColor: .white,
            primaryAction: onFinish
        )
    }
}
