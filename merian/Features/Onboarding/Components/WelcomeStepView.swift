import SwiftUI

struct WelcomeStepView: View {
    // MARK: - Callbacks
    let onNext: () -> Void
    
    // MARK: - Visual Layout
    var body: some View {
        OnboardingStepWrapper(
            imageName: "journal",
            title: "Your pocket\nnaturalist",
            subtitle: "Merian identifies the living world around you with scientific accuracy. Scan any plant, animal, or fungi to begin.",
            primaryButtonTitle: "Get started",
            primaryButtonTextColor: Color.black,
            primaryButtonColor: Color.white,
            primaryAction: onNext
        )
    }
}
