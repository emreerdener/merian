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

/// Exact JSON schema returned by the Gemini Edge Function.
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
        let is_poisonous: Bool?
        let regional_status_rationale: String?
    }
    let insight_data: Insight?

    struct Diagnostic: Codable {
        let primary_match_rationale: String?
        let confusing_lookalike_name: String?
        let key_differentiators: [String]?
    }
    let diagnostic_comparison: Diagnostic?

    let wikipedia_url: String?
    let wikipedia_extract: String?
    let reference_image_url: String?
    let iucn_red_list_status: String?
}
