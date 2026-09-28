enum ConsentPolicy {
    static let termsVersion = "2026-08-03"
    static let adultEligibilityVersion = "2026-08-03"
    static let geminiDisclosureVersion = "2026-08-04.1"
    static let analyticsDisclosureVersion = "2026-08-04"
    static let geminiProvider = "google_gemini"
    static let analyticsProvider = "posthog"
    static let openAIProvider = "openai"
    static let openAIDisclosureVersion = "2026-09-26"
    // The beta permits app-assigned photos without a new opt-in; explicit withdrawals still deny.
    static let openAIBetaOptInDeferred = true
    static let openAIConsentCollectionEnabled = true
    static let openAIBetaProcessingText = """
    During the beta, Naturebook may use OpenAI for eligible photo identification. Photos and related observation context are sent to OpenAI under its API data policies. You can turn off future OpenAI processing here. Naturebook chooses the AI service; this setting does not select a provider.
    """

    static let openAIDisclosureText = """
    With your permission, Naturebook can send photos, written descriptions, and related observation context to OpenAI for AI-powered identification. OpenAI processes this data under its API data policies. You can withdraw permission for future OpenAI processing in Settings.
    """
    static let openAIGrantText = "I allow OpenAI to process these observations."
    static let openAIWithdrawalText = "Turn off future OpenAI processing."

    static let adultConfirmationText = """
    I confirm I am 18 or older
    """

    static let geminiDisclosureText = """
    Naturebook sends observation data to Google Gemini for AI-powered identification.
    """

    static let combinedAcceptanceText = """
    I accept the terms and allow this data sharing
    """

    static let geminiWithdrawalText = """
    I withdraw permission for Google Gemini to process future observations.
    """

    static let analyticsDisclosureText = """
    Share usage and diagnostics to help improve Naturebook
    """

    static let analyticsWithdrawalText = """
    I withdraw permission to process future usage and diagnostics.
    """
}

/// Only reviewed recipients can construct or upload AI consent evidence.
enum AIConsentProcessor: String {
    case gemini = "google_gemini"
    case openAI = "openai"

    var disclosureVersion: String {
        switch self {
        case .gemini: ConsentPolicy.geminiDisclosureVersion
        case .openAI: ConsentPolicy.openAIDisclosureVersion
        }
    }

    var disclosureText: String {
        switch self {
        case .gemini: ConsentPolicy.geminiDisclosureText
        case .openAI: ConsentPolicy.openAIDisclosureText
        }
    }

    var grantText: String {
        switch self {
        case .gemini: ConsentPolicy.combinedAcceptanceText
        case .openAI: ConsentPolicy.openAIGrantText
        }
    }

    var withdrawalText: String {
        switch self {
        case .gemini: ConsentPolicy.geminiWithdrawalText
        case .openAI: ConsentPolicy.openAIWithdrawalText
        }
    }
}
