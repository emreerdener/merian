import Foundation

// Using MerianError from Core/Utilities.

// MARK: - Edge Function Response DTOs

/// Outer wrapper matching the Supabase Edge Function envelope.
struct EdgeResponseWrapper: Codable {
    let success: Bool?
    let data: EdgeResponse
}

/// Exact JSON schema returned by the identify Edge Function.
struct EdgeResponse: Codable {
    let scan_id: String?
    let is_biological_subject: Bool?
    let is_live_capture: Bool?
    let ecology_type: String?
    let is_invasive: Bool?
    let scientific_name: String?
    let common_name: String?
    let confidence_score: Double?
    let blur_score: Double?
    let colors: [String]?
    let group_tags: [String]?
    
    // Extended Ecological Telemetry
    let estimated_size_cm: Double?
    let life_stage: String?
    let reproductive_condition: String?
    let sex: String?
    let sex_confidence: Double?
    let sex_evidence: String?
    let individual_count: Int?
    let ecological_interactions: [String]?

    // Present on Cache Hit — sourced from species_dictionary.
    struct Taxonomy: Codable {
        let kingdom: String?
        let phylum: String?
        let `class`: String?
        let order: String?
        let family: String?
        let genus: String?
    }
    let taxonomy: Taxonomy?

    struct Insight: Codable {
        /// Per-scan vision model reasoning — unique to the specific photo submitted.
        let ai_reasoning: String?
        /// Hazard classification: "none" | "poisonous" | "venomous" | "allergenic" | "irritant"
        let hazard_type: String?
    }
    let insight_data: Insight?

    // Present on Cache Hit for all users when already stored — sourced from species_dictionary.
    struct SpeciesInsights: Codable {
        let habitat_description: String?
    }
    let species_insights: SpeciesInsights?

    /// GBIF species usage key for occurrence density heatmap tiles. Present on Cache Hit
    /// for all tiers — sourced from species_dictionary, not AI-generated.
    let gbif_taxon_key: Int?
    let wikipedia_url: String?
    let wikipedia_overview: String?
    let reference_image_url: String?
    let iucn_red_list_status: String?
    let inference_tier: String?
    /// All known English vernacular synonyms beyond the primary canonical common name.
    /// Sourced from GBIF vernacular names endpoint during background enrichment.
    /// Present on cache hit only; nil on first-ever scan of a new species.
    /// The primary common_name value is always excluded from this array.
    let alternative_common_names: [String]?

    let pet_identification: PetIdentification?

    /// Per-scan alternative candidates output by the model when it was genuinely uncertain.
    /// Only present when `confidence_score` is below the tier's `diagnosticTrigger` threshold.
    struct IdentificationCandidate: Codable {
        let scientific_name: String
        let common_name: String?
        let confidence_score: Double
        /// The single most important observable trait separating this candidate from the primary ID.
        let distinguishing_feature: String?
    }
    let candidates: [IdentificationCandidate]?

    /// Photographic quality scores emitted by Gemini for every scan.
    /// Used for future community reference-photo curation; `overall_score` (0–100) is
    /// persisted to `LocalScanRecord.imageQualityScore` and `public.scans.image_quality_score`.
    struct ImageQuality: Codable {
        let sharpness: Int?
        let framing: Int?
        let diagnostic_utility: Int?
        let overall_score: Int?
    }
    let image_quality: ImageQuality?
}

// MARK: - Enrich-Scan Response

/// Returned by the enrich-scan Edge Function for async enrichment + similar species loading.
/// The endpoint accepts a `scope` parameter ("enrichment" | "lookalikes") and returns only
/// the fields for that scope, allowing the iOS client to fire both scopes concurrently and
/// apply each to the UI as soon as it resolves rather than waiting for a single combined response.
struct EnrichScanResponse: Codable {
    let success: Bool?
    let data: EnrichData?

    struct EnrichData: Codable {
        /// Present in "enrichment" scope responses only.
        let habitat_description: String?
        /// Present in "enrichment" scope responses only.
        let gbif_taxon_key: Int?
        /// Present in "enrichment" scope responses only.
        let taxonomy: EdgeResponse.Taxonomy?
        /// Present in "enrichment" scope responses only.
        /// GBIF vernacular name synonyms beyond the primary canonical name.
        /// Nil when GBIF hasn't enriched this species yet.
        let alternative_common_names: [String]?
        /// Present in "lookalikes" scope responses only.
        /// Rich lookalike entries sourced from the species_lookalikes join table.
        /// Nil when no lookalike data is available for this species.
        let similar_species: [SimilarSpeciesEntry]?
    }

    /// A single lookalike species record resolved from the species_lookalikes join table.
    struct SimilarSpeciesEntry: Codable {
        let species_id: String?
        let scientific_name: String
        let common_name: String?
        let reference_image_url: String?
        let iucn_red_list_status: String?
        let reason: String?
        let visual_traits: [String]?
        let confidence: Double?
        let source: String?
        let review_status: String?
        let is_bidirectional: Bool?
        let sort_order: Int?
    }
}
