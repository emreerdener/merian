import Foundation

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

    /// Existing Gemini 2.5 Pro presentation bands; not an empirical accuracy claim.
    ///
    /// Server source: `services/supabase/functions/_shared/identify/thresholds.ts`.
    static let pro = Bands(
        strong: 0.85,
        possible: 0.65,
        diagnosticTrigger: 0.99
    )

    /// Historical omission preserves existing behavior. Recorded configurations
    /// must match a known profile before their scores receive Gemini meanings.
    static func bands(
        forInferenceTier tier: String?,
        provenance: IdentificationResultProvenance? = nil
    ) -> Bands? {
        if let provenance, !provenance.supportsGeminiBands(forInferenceTier: tier) {
            return nil
        }
        return tier == "pro" ? pro : flash
    }
}

extension IdentificationResultProvenance {
    func supportsGeminiBands(forInferenceTier tier: String?) -> Bool {
        guard data.count <= 2_048,
              let value = try? JSONDecoder().decode(IdentificationProvenanceDTO.self, from: data),
              value.version == 1,
              value.provider == "gemini",
              value.binding == "gemini_baseline_v1",
              value.policy_version > 0,
              value.timeout_ms == 90_000,
              tier == "flash" || tier == "pro",
              value.model == (tier == "pro" ? "gemini-2.5-pro" : "gemini-2.5-flash"),
              value.generation.seed == 42 else { return false }
        let pro = tier == "pro"
        let generation = value.generation
        switch value.variant {
        case "audio_compat":
            return value.operation == "scan_audio_identification" &&
                value.prompt == "identify_audio_compat_v2" &&
                value.schema == "merian_audio_v2" &&
                value.confidence == "gemini_audio_compat_v2" &&
                value.diagnostic_trigger == nil && value.prompt_diagnostic_trigger == nil &&
                value.safety == nil && generation.temperature == 0.1 &&
                generation.top_k == nil && generation.max_output_tokens == 2_048 &&
                generation.thinking_budget == 2_048
        case "vision_compat":
            return value.operation == "scan_identification" &&
                value.prompt == "identify_vision_v1" && value.schema == "merian_identify_v1" &&
                value.confidence == "gemini_vision_compat_v1" &&
                value.diagnostic_trigger == 0.99 && value.prompt_diagnostic_trigger == 0.99 &&
                value.safety == "biological_vision_v1" && generation.temperature == 0.1 &&
                generation.top_k == 40 && generation.max_output_tokens == (pro ? 8_192 : 4_096) &&
                generation.thinking_budget == (pro ? 5_000 : 2_048)
        case "description_compat":
            return value.operation == "scan_identification" &&
                value.prompt == "identify_describe_v1" && value.schema == "merian_describe_v1" &&
                value.confidence == "gemini_describe_v1" &&
                value.diagnostic_trigger == nil && value.prompt_diagnostic_trigger == nil &&
                value.safety == nil && generation.temperature == 0.15 &&
                generation.top_k == 40 && generation.max_output_tokens == (pro ? 4_096 : 2_048) &&
                generation.thinking_budget == (pro ? 3_000 : 1_024)
        case "multimodal":
            let audio = value.prompt == "identify_audio_v2" ||
                (pro && value.prompt == "identify_audio_uncertainty_experiment_v1")
            let promptKnown = audio || ["identify_vision_v1", "identify_blended_v1", "identify_text_v1"]
                .contains(value.prompt)
            return value.operation == "scan_identification" && promptKnown &&
                value.schema == (audio ? "merian_audio_v2" : "merian_identify_v1") &&
                value.confidence == (audio ? "gemini_audio_v2" : "gemini_identify_v1") &&
                value.diagnostic_trigger == 0.99 && value.prompt_diagnostic_trigger == nil &&
                value.safety == nil && generation.temperature == 0.1 &&
                generation.top_k == nil && generation.max_output_tokens == 8_192 &&
                generation.thinking_budget == (pro ? 5_000 : nil)
        default:
            return false
        }
    }
}

extension SpeciesData {
    var identificationConfidenceBands: InferenceConfidencePolicy.Bands? {
        InferenceConfidencePolicy.bands(
            forInferenceTier: inferenceTier,
            provenance: identificationProvenance
        )
    }
}
