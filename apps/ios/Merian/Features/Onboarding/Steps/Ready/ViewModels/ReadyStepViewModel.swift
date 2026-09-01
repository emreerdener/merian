import Foundation
import Observation

@MainActor
@Observable final class ReadyStepViewModel {
    var hasConfirmedAdultEligibility = false
    var hasAllowedGeminiProcessing = false
    var hasAllowedAnalytics = false

    private(set) var hasLoadedCurrentConsent = false

    var canStartScanning: Bool {
        ReadyConsentPresentation.canStartScanning(
            adultConfirmed: hasConfirmedAdultEligibility,
            geminiAllowed: hasAllowedGeminiProcessing,
            analyticsAllowed: hasAllowedAnalytics
        )
    }

    func loadCurrentConsentIfNeeded(_ snapshot: ReadyConsentSnapshot) {
        guard !hasLoadedCurrentConsent else { return }
        hasConfirmedAdultEligibility =
            snapshot.hasConfirmedAdultEligibility
        hasAllowedGeminiProcessing = Self.hasEffectiveGeminiConsent(
            snapshot
        )
        hasAllowedAnalytics = snapshot.hasGrantedAnalytics
        hasLoadedCurrentConsent = true
    }

    func updateAdultEligibility(_ isConfirmed: Bool) {
        guard hasLoadedCurrentConsent else { return }
        hasConfirmedAdultEligibility = isConfirmed
    }

    func updateGeminiConsent(_ snapshot: ReadyConsentSnapshot) {
        guard hasLoadedCurrentConsent else { return }
        hasAllowedGeminiProcessing = Self.hasEffectiveGeminiConsent(snapshot)
    }

    func updateAnalyticsConsent(_ isGranted: Bool) {
        guard hasLoadedCurrentConsent else { return }
        hasAllowedAnalytics = isGranted
    }

    private static func hasEffectiveGeminiConsent(
        _ snapshot: ReadyConsentSnapshot
    ) -> Bool {
        snapshot.hasAcceptedTerms && snapshot.hasGrantedGeminiProcessing
    }
}
