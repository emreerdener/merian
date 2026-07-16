import SwiftUI

struct WelcomeStepView: View {
    // MARK: - Callbacks
    let onNext: () -> Void
    
    // MARK: - Visual Layout
    var body: some View {
        OnboardingStepWrapper(
            imageName: "journal",
            title: "Your pocket\nnaturalist",
            subtitle: "Naturebook identifies the living world around you with scientific accuracy. Scan any plant, animal, or fungi to begin.",
            primaryButtonTitle: "Get started",
            primaryButtonTextColor: Color(uiColor: .systemBackground),
            primaryButtonColor: Color.primary,
            primaryAction: onNext
        )
    }
}
