import SwiftUI

@MainActor
@Observable final class OnboardingViewModel {
    // MARK: - Published State
    var currentStep: OnboardingStep = .welcome

    // MARK: - Dependencies
    @ObservationIgnored private let appSettings: AppSettings

    init(appSettings: AppSettings? = nil) {
        self.appSettings = appSettings ?? AppSettings.shared
    }
    
    // MARK: - App Storage
    // Isolated for strict unit testing without requiring SwiftUI view hosts
    var hasCompletedOnboarding: Bool {
        get { appSettings.hasCompletedOnboarding }
        set { appSettings.hasCompletedOnboarding = newValue }
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
