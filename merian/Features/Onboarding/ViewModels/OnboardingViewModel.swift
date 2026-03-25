import SwiftUI

@MainActor
@Observable final class OnboardingViewModel {
    // MARK: - Published State
    var currentStep: OnboardingStep = .welcome
    
    // MARK: - App Storage
    // Isolated for strict unit testing without requiring SwiftUI view hosts
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }
    
    // MARK: - State Transitions
    func advanceStep() {
        if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        }
    }
    
    func completeOnboarding() {
        AppTelemetry.trackOnboardingCompleted()
        hasCompletedOnboarding = true
    }
}
