import Foundation
import Observation

@MainActor
@Observable final class OnboardingViewModel {
    // MARK: - Published State
    var currentStep: OnboardingStep = .welcome

    // MARK: - Dependencies
    @ObservationIgnored private let dependencies: OnboardingDependencies

    init(dependencies: OnboardingDependencies) {
        self.dependencies = dependencies
        if dependencies.hasCompletedOnboarding(),
           !dependencies.hasCurrentRequiredConsent() {
            currentStep = .ready
        }
    }

    convenience init(
        appSettings: AppSettings? = nil,
        consentManager: ConsentManager? = nil,
        resumeConsentBlockedScan: ((UUID) -> String?)? = nil
    ) {
        self.init(dependencies: .live(
            appSettings: appSettings,
            consentManager: consentManager,
            resumeConsentBlockedScan: resumeConsentBlockedScan
        ))
    }

    // MARK: - App Storage
    // Isolated for strict unit testing without requiring SwiftUI view hosts
    var hasCompletedOnboarding: Bool {
        get { dependencies.hasCompletedOnboarding() }
        set { dependencies.setHasCompletedOnboarding(newValue) }
    }

    // MARK: - State Transitions
    func advanceStep() {
        if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        }
    }

    func advanceStep(from expectedStep: OnboardingStep) {
        guard currentStep == expectedStep else { return }
        advanceStep()
    }

    func completeOnboarding(analyticsEnabled: Bool) throws {
        // Persist the legal action before opening the lifecycle/network gate.
        try dependencies.recordCurrentConsent(analyticsEnabled)
        dependencies.trackCompletion()
        hasCompletedOnboarding = true
        guard let accountID = dependencies.currentSessionUserID() else {
            return
        }
        dependencies.resumeConsentBlockedScan(accountID)
    }
}
