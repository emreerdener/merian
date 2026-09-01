@testable import Merian
import Testing

@Suite("Ready step view model")
@MainActor
struct ReadyStepViewModelTests {
    @Test func initialLoadProjectsCurrentConsentOnce() {
        let viewModel = ReadyStepViewModel()
        let initial = ReadyConsentSnapshot(
            hasConfirmedAdultEligibility: true,
            hasAcceptedTerms: true,
            hasGrantedGeminiProcessing: true,
            hasGrantedAnalytics: false
        )

        viewModel.loadCurrentConsentIfNeeded(initial)
        viewModel.loadCurrentConsentIfNeeded(
            ReadyConsentSnapshot(
                hasConfirmedAdultEligibility: false,
                hasAcceptedTerms: false,
                hasGrantedGeminiProcessing: false,
                hasGrantedAnalytics: true
            )
        )

        #expect(viewModel.hasLoadedCurrentConsent)
        #expect(viewModel.hasConfirmedAdultEligibility)
        #expect(viewModel.hasAllowedGeminiProcessing)
        #expect(!viewModel.hasAllowedAnalytics)
        #expect(viewModel.canStartScanning)
    }

    @Test func geminiProjectionRequiresTermsAndProviderGrant() {
        let viewModel = ReadyStepViewModel()
        viewModel.loadCurrentConsentIfNeeded(.empty)

        for hasAcceptedTerms in [false, true] {
            for hasGrantedGeminiProcessing in [false, true] {
                viewModel.updateGeminiConsent(
                    ReadyConsentSnapshot(
                        hasConfirmedAdultEligibility: false,
                        hasAcceptedTerms: hasAcceptedTerms,
                        hasGrantedGeminiProcessing:
                            hasGrantedGeminiProcessing,
                        hasGrantedAnalytics: false
                    )
                )

                #expect(
                    viewModel.hasAllowedGeminiProcessing ==
                        (hasAcceptedTerms && hasGrantedGeminiProcessing)
                )
            }
        }
    }

    @Test func unrelatedManagerChangesPreserveUncommittedChoices() {
        let viewModel = ReadyStepViewModel()
        viewModel.loadCurrentConsentIfNeeded(.empty)
        viewModel.hasConfirmedAdultEligibility = true
        viewModel.hasAllowedAnalytics = true

        viewModel.updateGeminiConsent(
            ReadyConsentSnapshot(
                hasConfirmedAdultEligibility: false,
                hasAcceptedTerms: true,
                hasGrantedGeminiProcessing: true,
                hasGrantedAnalytics: false
            )
        )

        #expect(viewModel.hasConfirmedAdultEligibility)
        #expect(viewModel.hasAllowedAnalytics)
        #expect(viewModel.hasAllowedGeminiProcessing)
    }

    @Test func updatesAreIgnoredBeforeInitialProjection() {
        let viewModel = ReadyStepViewModel()

        viewModel.updateAdultEligibility(true)
        viewModel.updateGeminiConsent(
            ReadyConsentSnapshot(
                hasConfirmedAdultEligibility: true,
                hasAcceptedTerms: true,
                hasGrantedGeminiProcessing: true,
                hasGrantedAnalytics: true
            )
        )
        viewModel.updateAnalyticsConsent(true)

        #expect(!viewModel.hasConfirmedAdultEligibility)
        #expect(!viewModel.hasAllowedGeminiProcessing)
        #expect(!viewModel.hasAllowedAnalytics)
        #expect(!viewModel.hasLoadedCurrentConsent)
    }
}

private extension ReadyConsentSnapshot {
    static let empty = ReadyConsentSnapshot(
        hasConfirmedAdultEligibility: false,
        hasAcceptedTerms: false,
        hasGrantedGeminiProcessing: false,
        hasGrantedAnalytics: false
    )
}
