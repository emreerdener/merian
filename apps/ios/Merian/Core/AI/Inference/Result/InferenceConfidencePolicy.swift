enum InferenceConfidencePolicy {
    struct Bands: Sendable, Equatable {
        /// Minimum score for the green "Strong match" UI.
        let strong: Double
        /// Minimum score for the orange "Possible match" UI.
        let possible: Double
        /// Score below which diagnostic comparison UI remains available.
        let diagnosticTrigger: Double
    }

    /// Gemini 2.5 Flash is fast but can be overconfident on edge cases.
    ///
    /// Server source: `services/supabase/functions/_shared/identify/thresholds.ts`.
    static let flash = Bands(
        strong: 0.95,
        possible: 0.75,
        diagnosticTrigger: 0.99
    )

    /// Gemini 2.5 Pro is more cautious and better calibrated.
    ///
    /// Server source: `services/supabase/functions/_shared/identify/thresholds.ts`.
    static let pro = Bands(
        strong: 0.85,
        possible: 0.65,
        diagnosticTrigger: 0.99
    )

    /// Unknown and legacy tiers retain the existing safe Flash fallback.
    static func bands(forInferenceTier tier: String?) -> Bands {
        tier == "pro" ? pro : flash
    }
}
