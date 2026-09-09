import Foundation

struct HistoricalScanPageRequest: Equatable, Sendable {
    let userID: String
    let offset: Int
    let pageSize: Int
}

struct HistoricalScanRecordRequest: Equatable, Sendable {
    let userID: String
    let scanID: String
}

struct HistoricalCollectionPageRequest: Equatable, Sendable {
    let userID: String
    let offset: Int
    let pageSize: Int
}

enum HistoricalScanDownOutcome: Equatable, Sendable {
    case reconciled
    case notFound
    case transientFailure
    case contractMismatch
}

struct HistoricalScanPageDecodeResult: Sendable {
    let responses: [HistoricalScanResponse]
    let remoteRowCount: Int
    let rejectedRowCount: Int
    let firstRejectedCodingPath: String?
}

enum HistoricalScanPageContractError: Error, Equatable {
    case invalidTopLevel
}

// MARK: - Cloud Data Transfer Objects (DTOs)
struct CloudSpeciesDictionary: Decodable, Sendable {
    let scientific_name: String?
    let kingdom: String?
    let phylum: String?
    let `class`: String?
    let order: String?
    let family: String?
    let genus: String?
    let wikipedia_url: String?
    let reference_image_url: String?
    let hazard_type: String?
    let common_names: [String: String?]?
    let wikipedia_overview: String?
    let iucn_red_list_status: String?
    let habitat_description: String?
    let group_tags: [String]?
}

struct HistoricalObservationContext: Decodable, Sendable {
    let freeText: String?

    private enum CodingKeys: String, CodingKey {
        case freeText
        case free_text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        freeText = (try? container.decode(String.self, forKey: .freeText))
            ?? (try? container.decode(String.self, forKey: .free_text))
    }

    var observationContext: ObservationContext? {
        guard let normalizedText = freeText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !normalizedText.isEmpty else {
            return nil
        }
        return ObservationContext(freeText: normalizedText)
    }
}

struct HistoricalScanResponse: Decodable, Sendable {
    let id: String
    let created_at: String?
    let image_storage_urls: [String]?
    let video_storage_urls: [String]?
    let audio_storage_urls: [String]?
    let captured_media: CapturedMediaWireManifestDTO?
    let user_observation_context: HistoricalObservationContext?
    let timestamp: String?
    let weather_condition: String?
    let weather_temperature_f: Double?
    let ai_confidence_score: Double?
    let is_biological_subject: Bool?
    let ecology_type: String?
    let is_invasive: Bool?
    let invasive_status_region: String?
    let invasive_rationale: String?
    let invasive_confidence: Double?
    let is_live_capture: Bool?
    let colors: [String]?
    let semantic_location: String?
    let gps_lat_exact: Double?
    let gps_long_exact: Double?
    let gps_elevation: Double?
    let ai_reasoning: String?
    let estimated_size_cm: Double?
    let life_stage: String?
    let reproductive_condition: String?
    let sex: String?
    let sex_confidence: Double?
    let sex_evidence: String?
    let individual_count: Int?
    let ecological_interactions: [String]?
    let inference_tier: String?
    let custom_tags: [String]?
    let candidates: [CloudIdentificationCandidate]?
    let pet_identification: PetIdentification?
    let user_identification_override: String?
    let user_confirmed_identification: Bool?
    let image_quality_score: Int?
    let species_dictionary: CloudSpeciesDictionary?
    let explore_posts: HistoricalExplorePostResponse?

    var capturedMediaItems: [SerializedMediaItem]? {
        captured_media?.serializedMediaItems
    }

    var activeExplorePostId: String? {
        guard let explorePost = explore_posts,
              explorePost.unshared_at == nil else {
            return nil
        }
        return explorePost.id
    }
}

struct HistoricalExplorePostResponse: Decodable, Sendable {
    let id: String
    let unshared_at: String?
}

struct CloudIdentificationCandidate: Decodable, Sendable {
    let scientific_name: String
    let common_name: String?
    let confidence_score: Double
    let distinguishing_feature: String?
}

struct CloudCollectionResponse: Decodable, Sendable {
    let id: String
    let name: String
    let created_at: String
    let collection_scans: [CloudCollectionScan]?
}

struct CloudCollectionScan: Decodable, Sendable {
    let scan_id: String
}
