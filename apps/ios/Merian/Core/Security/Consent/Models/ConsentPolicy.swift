enum ConsentPolicy {
    static let termsVersion = "2026-08-03"
    static let adultEligibilityVersion = "2026-08-03"
    static let geminiDisclosureVersion = "2026-08-04.1"
    static let analyticsDisclosureVersion = "2026-08-04"
    static let geminiProvider = "google_gemini"
    static let analyticsProvider = "posthog"

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
