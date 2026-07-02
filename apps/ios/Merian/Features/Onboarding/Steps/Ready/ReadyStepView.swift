import SwiftUI

struct ReadyStepView: View {
    // MARK: - Callbacks
    let onFinish: () -> Void
    
    // MARK: - Visual Layout
    var body: some View {
        OnboardingStepWrapper(
            imageName: "bird-magnifier",
            title: "Explore. Identify. Contribute.",
            subtitle: "Every capture contributes to a global database tracking wildlife and biodiversity.",
            primaryButtonTitle: "Start scanning",
            primaryButtonTextColor: Color(uiColor: .systemBackground),
            primaryButtonColor: Color.primary,
            primaryAction: onFinish
        )
    }
}
