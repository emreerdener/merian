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
        let description: String?
        /// Hazard classification: "none" | "poisonous" | "venomous" | "allergenic" | "irritant"
        let hazard_type: String?
        let regional_status_rationale: String?
    }
    let insight_data: Insight?

    // Present on Cache Hit for Pro users — sourced from species_dictionary.
    struct Premium: Codable {
        let habitat_description: String?
        let global_distribution_regions: [String]?
    }
    let premium_insights: Premium?

    let wikipedia_url: String?
    let wikipedia_extract: String?
    let reference_image_url: String?
    let iucn_red_list_status: String?
}

// MARK: - Enrich-Scan Response

/// Returned by the enrich-scan Edge Function for async premium + diagnostic loading.
struct EnrichScanResponse: Codable {
    let success: Bool?
    let data: EnrichData?

    struct EnrichData: Codable {
        let habitat_description: String?
        let global_distribution_regions: [String]?
        let diagnostic_comparison: DiagnosticData?

        struct DiagnosticData: Codable {
            let primary_match_rationale: String?
            let confusing_lookalike_name: String?
            let key_differentiators: [String]?
        }
    }
}
