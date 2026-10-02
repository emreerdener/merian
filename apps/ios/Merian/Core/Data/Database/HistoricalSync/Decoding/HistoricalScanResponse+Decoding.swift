import Foundation

extension HistoricalScanResponse {
    private enum CodingKeys: String, CodingKey {
        case confirmed_species_id, user_review_state
        case ai_identification_review
        case id
        case created_at
        case image_storage_urls
        case video_storage_urls
        case audio_storage_urls
        case captured_media
        case user_observation_context
        case timestamp
        case weather_condition
        case weather_temperature_f
        case ai_confidence_score
        case is_biological_subject
        case ecology_type
        case is_invasive
        case invasive_status_region
        case invasive_rationale
        case invasive_confidence
        case is_live_capture
        case colors
        case semantic_location
        case gps_lat_exact
        case gps_long_exact
        case gps_elevation
        case ai_reasoning
        case estimated_size_cm
        case life_stage
        case reproductive_condition
        case sex
        case sex_confidence
        case sex_evidence
        case individual_count
        case ecological_interactions
        case inference_tier
        case identification_provenance
        case primary_identification
        case custom_tags
        case candidates
        case pet_identification
        case user_identification_override
        case user_confirmed_identification
        case image_quality_score
        case species_dictionary
        case explore_posts
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        created_at = try values.decodeIfPresent(String.self, forKey: .created_at)
        image_storage_urls = try values.decodeIfPresent([String].self, forKey: .image_storage_urls)
        video_storage_urls = try values.decodeIfPresent([String].self, forKey: .video_storage_urls)
        audio_storage_urls = try values.decodeIfPresent([String].self, forKey: .audio_storage_urls)
        captured_media = try values.decodeIfPresent(CapturedMediaWireManifestDTO.self, forKey: .captured_media)
        user_observation_context = try values.decodeIfPresent(HistoricalObservationContext.self, forKey: .user_observation_context)
        timestamp = try values.decodeIfPresent(String.self, forKey: .timestamp)
        weather_condition = try values.decodeIfPresent(String.self, forKey: .weather_condition)
        weather_temperature_f = try values.decodeIfPresent(Double.self, forKey: .weather_temperature_f)
        ai_confidence_score = try values.decodeIfPresent(Double.self, forKey: .ai_confidence_score)
        is_biological_subject = try values.decodeIfPresent(Bool.self, forKey: .is_biological_subject)
        ecology_type = try values.decodeIfPresent(String.self, forKey: .ecology_type)
        is_invasive = try values.decodeIfPresent(Bool.self, forKey: .is_invasive)
        invasive_status_region = try values.decodeIfPresent(String.self, forKey: .invasive_status_region)
        invasive_rationale = try values.decodeIfPresent(String.self, forKey: .invasive_rationale)
        invasive_confidence = try values.decodeIfPresent(Double.self, forKey: .invasive_confidence)
        is_live_capture = try values.decodeIfPresent(Bool.self, forKey: .is_live_capture)
        colors = try values.decodeIfPresent([String].self, forKey: .colors)
        semantic_location = try values.decodeIfPresent(String.self, forKey: .semantic_location)
        gps_lat_exact = try values.decodeIfPresent(Double.self, forKey: .gps_lat_exact)
        gps_long_exact = try values.decodeIfPresent(Double.self, forKey: .gps_long_exact)
        gps_elevation = try values.decodeIfPresent(Double.self, forKey: .gps_elevation)
        ai_reasoning = try values.decodeIfPresent(String.self, forKey: .ai_reasoning)
        estimated_size_cm = try values.decodeIfPresent(Double.self, forKey: .estimated_size_cm)
        life_stage = try values.decodeIfPresent(String.self, forKey: .life_stage)
        reproductive_condition = try values.decodeIfPresent(String.self, forKey: .reproductive_condition)
        sex = try values.decodeIfPresent(String.self, forKey: .sex)
        sex_confidence = try values.decodeIfPresent(Double.self, forKey: .sex_confidence)
        sex_evidence = try values.decodeIfPresent(String.self, forKey: .sex_evidence)
        individual_count = try values.decodeIfPresent(Int.self, forKey: .individual_count)
        ecological_interactions = try values.decodeIfPresent([String].self, forKey: .ecological_interactions)
        inference_tier = try values.decodeIfPresent(String.self, forKey: .inference_tier)
        identification_provenance = try values.decodeIfPresent(IdentificationProvenanceDTO.self, forKey: .identification_provenance)
        primary_identification = try values.decodeIfPresent(PrimaryIdentificationDTO.self, forKey: .primary_identification)
        custom_tags = try values.decodeIfPresent([String].self, forKey: .custom_tags)
        candidates = try values.decodeIfPresent([CloudIdentificationCandidate].self, forKey: .candidates)
        pet_identification = try values.decodeIfPresent(PetIdentification.self, forKey: .pet_identification)
        user_identification_override = try values.decodeIfPresent(String.self, forKey: .user_identification_override)
        user_confirmed_identification = try values.decodeIfPresent(Bool.self, forKey: .user_confirmed_identification)
        image_quality_score = try values.decodeIfPresent(Int.self, forKey: .image_quality_score)
        species_dictionary = try values.decodeIfPresent(CloudSpeciesDictionary.self, forKey: .species_dictionary)
        explore_posts = try values.decodeIfPresent(HistoricalExplorePostResponse.self, forKey: .explore_posts)
        reviewConfirmedSpeciesID = try values.decodeIfPresent(String.self, forKey: .confirmed_species_id)
        reviewState = try values.decodeIfPresent(UserReviewState.self, forKey: .user_review_state)
        aiIdentificationReview = try values.decodeIfPresent(AIIdentificationReview.self, forKey: .ai_identification_review)
        confirmedSpeciesReview = try VerifiedSpeciesReviewProjection.decode(
            from: decoder, hasPrimary: primary_identification != nil)
    }
}
