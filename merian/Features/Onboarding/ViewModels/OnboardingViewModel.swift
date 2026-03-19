import SwiftUI

@MainActor
class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
    
    // Isolated for strict unit testing without requiring SwiftUI view hosts
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    
    func advanceStep() {
        if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        }
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}
