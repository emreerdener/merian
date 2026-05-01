import SwiftUI

@MainActor
@Observable final class OnboardingViewModel {
    // MARK: - Published State
    var currentStep: OnboardingStep = .welcome
    
    // MARK: - App Storage
    // Isolated for strict unit testing without requiring SwiftUI view hosts
    var hasCompletedOnboarding: Bool {
        get { AppSettings.shared.hasCompletedOnboarding }
        set { AppSettings.shared.hasCompletedOnboarding = newValue }
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
