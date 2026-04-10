import SwiftUI

struct ReadyStepView: View {
    // MARK: - Callbacks
    let onFinish: () -> Void
    
    // MARK: - Visual Layout
    var body: some View {
        OnboardingStepWrapper(
            imageName: "bird",
            title: "Citizen science",
            subtitle: "Every capture contributes to a global database tracking wildlife and biodiversity. Step outside and start scanning the natural world.",
            primaryButtonTitle: "Start scanning",
            primaryButtonTextColor: Color.black,
            primaryButtonColor: Color.white,
            primaryAction: onFinish
        )
    }
}
