import SwiftUI

@MainActor
@Observable final class OnboardingViewModel {
    // MARK: - Published State
    var currentStep: OnboardingStep = .welcome

    // MARK: - Dependencies
    @ObservationIgnored private let appSettings: AppSettings
    @ObservationIgnored private let consentManager: ConsentManager
    @ObservationIgnored private let consentBlockedScanResumer: ((UUID) -> String?)?

    init(
        appSettings: AppSettings? = nil,
        consentManager: ConsentManager? = nil,
        resumeConsentBlockedScan: ((UUID) -> String?)? = nil
    ) {
        let resolvedSettings = appSettings ?? AppSettings.shared
        let resolvedConsentManager = consentManager ?? ConsentManager.shared
        self.appSettings = resolvedSettings
        self.consentManager = resolvedConsentManager
        self.consentBlockedScanResumer = resumeConsentBlockedScan
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
    
    func completeOnboarding(analyticsEnabled: Bool) throws {
        // Persist the legal action before opening the lifecycle/network gate.
        try consentManager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: analyticsEnabled
        )
        AppTelemetry.trackOnboardingCompleted()
        hasCompletedOnboarding = true
        guard let accountId = consentManager.currentSessionUserId else {
            return
        }
        if let consentBlockedScanResumer {
            _ = consentBlockedScanResumer(accountId)
        } else {
            _ = OfflineQueueManager.shared.resumeMostRecentConsentBlockedScan(
                accountId: accountId
            )
        }
    }
}
