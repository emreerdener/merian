import SwiftUI

@MainActor
class OnboardingViewModel: ObservableObject {
    // MARK: - Published State
    @Published var currentStep: OnboardingStep = .welcome
    
    // MARK: - App Storage
    // Isolated for strict unit testing without requiring SwiftUI view hosts
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    
    // MARK: - State Transitions
    func advanceStep() {
        if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        }
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}
