import Foundation

// MARK: - API Errors

enum APIError: Error {
    case proRequiredForOfflineTracking
    case decodingFailed
}

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
        let global_distribution_regions: [String]?
    }
    let species_insights: SpeciesInsights?

    /// GBIF species usage key for occurrence density heatmap tiles. Present on Cache Hit
    /// for all tiers — sourced from species_dictionary, not AI-generated.
    let gbif_taxon_key: Int?
    let wikipedia_url: String?
    let wikipedia_overview: String?
    let reference_image_url: String?
    let iucn_red_list_status: String?
}

// MARK: - Enrich-Scan Response

/// Returned by the enrich-scan Edge Function for async enrichment + diagnostic loading.
struct EnrichScanResponse: Codable {
    let success: Bool?
    let data: EnrichData?

    struct EnrichData: Codable {
        let habitat_description: String?
        let global_distribution_regions: [String]?
        let gbif_taxon_key: Int?
        let diagnostic_comparison: DiagnosticData?

        struct DiagnosticData: Codable {
            let primary_match_rationale: String?
            let confusing_lookalike_name: String?
            let key_differentiators: [String]?
        }
    }
}
