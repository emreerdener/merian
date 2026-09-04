import Foundation

/// Bounded, non-media state used by owner-scoped scan recovery.
///
/// The server derives and verifies ownership from the authenticated request;
/// `userId` binds the encoded snapshot to that same account at transport time.
struct OwnedScanRecoveryPayload: Encodable, Sendable {
    let id: String
    let userId: String
    let speciesId: String?
    let confirmedSpeciesId: String?
    let imageStorageUrls: [String]
    let timestamp: String
    let gpsLatExact: Double?
    let gpsLongExact: Double?
    let gpsLatPublic: Double?
    let gpsLongPublic: Double?
    let gpsElevation: Double?
    let geoprivacy: String
    let weatherCondition: String?
    let weatherTemperatureF: Double?
    let aiConfidenceScore: Double
    let ecologyType: String
    let isInvasive: Bool
    let invasiveStatusRegion: String?
    let invasiveRationale: String?
    let invasiveConfidence: Double?
    let isLiveCapture: Bool
    let isBiologicalSubject: Bool
    let aiReasoning: String?
    let semanticLocation: String?
    let publicLocationLabel: String?
    let inferenceTier: String
    let imageQualityScore: Int?
    let userIdentificationOverride: String?
    let userConfirmedIdentification: Bool
    let userReviewState: String

    private enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case speciesId = "species_id"
        case confirmedSpeciesId = "confirmed_species_id"
        case imageStorageUrls = "image_storage_urls"
        case timestamp
        case gpsLatExact = "gps_lat_exact"
        case gpsLongExact = "gps_long_exact"
        case gpsLatPublic = "gps_lat_public"
        case gpsLongPublic = "gps_long_public"
        case gpsElevation = "gps_elevation"
        case geoprivacy
        case weatherCondition = "weather_condition"
        case weatherTemperatureF = "weather_temperature_f"
        case aiConfidenceScore = "ai_confidence_score"
        case ecologyType = "ecology_type"
        case isInvasive = "is_invasive"
        case invasiveStatusRegion = "invasive_status_region"
        case invasiveRationale = "invasive_rationale"
        case invasiveConfidence = "invasive_confidence"
        case isLiveCapture = "is_live_capture"
        case isBiologicalSubject = "is_biological_subject"
        case aiReasoning = "ai_reasoning"
        case semanticLocation = "semantic_location"
        case publicLocationLabel = "public_location_label"
        case inferenceTier = "inference_tier"
        case imageQualityScore = "image_quality_score"
        case userIdentificationOverride = "user_identification_override"
        case userConfirmedIdentification = "user_confirmed_identification"
        case userReviewState = "user_review_state"
    }
}
