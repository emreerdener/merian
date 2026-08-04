import SwiftUI

@MainActor
@Observable final class OnboardingViewModel {
    // MARK: - Published State
    var currentStep: OnboardingStep = .welcome

    // MARK: - Dependencies
    @ObservationIgnored private let appSettings: AppSettings
    @ObservationIgnored private let consentManager: ConsentManager

    init(
        appSettings: AppSettings? = nil,
        consentManager: ConsentManager? = nil
    ) {
        let resolvedSettings = appSettings ?? AppSettings.shared
        let resolvedConsentManager = consentManager ?? ConsentManager.shared
        self.appSettings = resolvedSettings
        self.consentManager = resolvedConsentManager
        if resolvedSettings.hasCompletedOnboarding,
           !resolvedConsentManager.hasCurrentRequiredConsent {
            currentStep = .ready
        }
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
    
    func completeOnboarding(analyticsEnabled: Bool) {
        // Persist the legal action before opening the lifecycle/network gate.
        consentManager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: analyticsEnabled
        )
        AppTelemetry.trackOnboardingCompleted()
        hasCompletedOnboarding = true
    }
}
