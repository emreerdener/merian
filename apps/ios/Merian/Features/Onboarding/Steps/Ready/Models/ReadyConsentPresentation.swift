import Foundation

struct ReadyConsentSnapshot: Equatable {
    let hasConfirmedAdultEligibility: Bool
    let hasAcceptedTerms: Bool
    let hasGrantedGeminiProcessing: Bool
    let hasGrantedAnalytics: Bool
}

enum ReadyConsentPresentation {
    static let title = "One last step"
    static let disclosure = ConsentPolicy.geminiDisclosureText
    static let adultStatement = ConsentPolicy.adultConfirmationText
    static let consentStatement = ConsentPolicy.combinedAcceptanceText
    static let analyticsStatement = ConsentPolicy.analyticsDisclosureText
    static let termsURL = PublicBrand.websiteURL(path: "terms")
    static let requiredIndicator = " *"

    static func canStartScanning(
        adultConfirmed: Bool,
        geminiAllowed: Bool,
        analyticsAllowed _: Bool
    ) -> Bool {
        adultConfirmed && geminiAllowed
    }
}
