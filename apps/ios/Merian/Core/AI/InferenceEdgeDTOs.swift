import Foundation

// Using MerianError from Core/Utilities.

// BEGIN GENERATED: Identify wire DTOs
// Generated from services/supabase/functions/_shared/identify/contract.ts.
// Do not edit this block by hand; run make generate-edge-dto-contract.

private enum TaxonomyCodingKeys: String, CodingKey {
    case kingdom
    case phylum
    case `class`
    case order
    case family
    case genus
}

private enum InsightCodingKeys: String, CodingKey {
    case ai_reasoning
    case hazard_type
}

private enum SpeciesInsightsCodingKeys: String, CodingKey {
    case habitat_description
}

private enum IdentificationCandidateCodingKeys: String, CodingKey {
    case scientific_name
    case confidence_score
    case distinguishing_feature
    case common_name
}

private enum ImageQualityCodingKeys: String, CodingKey {
    case sharpness
    case framing
    case diagnostic_utility
    case overall_score
}

struct EdgeResponseWrapper: Codable {
    let success: Bool?
    let data: EdgeResponse

    enum CodingKeys: String, CodingKey {
        case success
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        data = try container.decode(EdgeResponse.self, forKey: .data)
    }
}

struct PetIdentificationDTO: Codable {
    let speciesGroup: String
    let label: String
    let labelType: String
    let confidenceScore: Double
    let evidence: [String]

    enum CodingKeys: String, CodingKey {
        case speciesGroup = "species_group"
        case label
        case labelType = "label_type"
        case confidenceScore = "confidence_score"
        case evidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speciesGroup = try container.decode(String.self, forKey: .speciesGroup)
        label = try container.decode(String.self, forKey: .label)
        labelType = try container.decode(String.self, forKey: .labelType)
        confidenceScore = try container.decode(Double.self, forKey: .confidenceScore)
        evidence = try container.decode([String].self, forKey: .evidence)
    }
}

struct EdgeResponse: Codable {
    struct Taxonomy: Codable {
        let kingdom: String?
        let phylum: String?
        let `class`: String?
        let order: String?
        let family: String?
        let genus: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: TaxonomyCodingKeys.self)
            kingdom = try container.decodeIfPresent(String.self, forKey: .kingdom)
            phylum = try container.decodeIfPresent(String.self, forKey: .phylum)
            `class` = try container.decodeIfPresent(String.self, forKey: .`class`)
            order = try container.decodeIfPresent(String.self, forKey: .order)
            family = try container.decodeIfPresent(String.self, forKey: .family)
            genus = try container.decodeIfPresent(String.self, forKey: .genus)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: TaxonomyCodingKeys.self)
            try container.encodeIfPresent(kingdom, forKey: .kingdom)
            try container.encodeIfPresent(phylum, forKey: .phylum)
            try container.encodeIfPresent(`class`, forKey: .`class`)
            try container.encodeIfPresent(order, forKey: .order)
            try container.encodeIfPresent(family, forKey: .family)
            try container.encodeIfPresent(genus, forKey: .genus)
        }
    }

    struct Insight: Codable {
        let ai_reasoning: String?
        let hazard_type: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: InsightCodingKeys.self)
            ai_reasoning = try container.decodeIfPresent(String.self, forKey: .ai_reasoning)
            hazard_type = try container.decodeIfPresent(String.self, forKey: .hazard_type)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: InsightCodingKeys.self)
            try container.encodeIfPresent(ai_reasoning, forKey: .ai_reasoning)
            try container.encodeIfPresent(hazard_type, forKey: .hazard_type)
        }
    }

    struct SpeciesInsights: Codable {
        let habitat_description: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: SpeciesInsightsCodingKeys.self)
            habitat_description = try container.decodeIfPresent(String.self, forKey: .habitat_description)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: SpeciesInsightsCodingKeys.self)
            try container.encodeIfPresent(habitat_description, forKey: .habitat_description)
        }
    }

    struct IdentificationCandidate: Codable {
        let scientific_name: String
        let confidence_score: Double
        let distinguishing_feature: String?
        let common_name: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: IdentificationCandidateCodingKeys.self)
            scientific_name = try container.decode(String.self, forKey: .scientific_name)
            confidence_score = try container.decode(Double.self, forKey: .confidence_score)
            distinguishing_feature = try container.decodeIfPresent(String.self, forKey: .distinguishing_feature)
            common_name = try container.decodeIfPresent(String.self, forKey: .common_name)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: IdentificationCandidateCodingKeys.self)
            try container.encode(scientific_name, forKey: .scientific_name)
            try container.encode(confidence_score, forKey: .confidence_score)
            try container.encodeIfPresent(distinguishing_feature, forKey: .distinguishing_feature)
            try container.encodeIfPresent(common_name, forKey: .common_name)
        }
    }

    struct ImageQuality: Codable {
        let sharpness: Int?
        let framing: Int?
        let diagnostic_utility: Int?
        let overall_score: Int?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: ImageQualityCodingKeys.self)
            sharpness = try container.decodeIfPresent(Int.self, forKey: .sharpness)
            framing = try container.decodeIfPresent(Int.self, forKey: .framing)
            diagnostic_utility = try container.decodeIfPresent(Int.self, forKey: .diagnostic_utility)
            overall_score = try container.decodeIfPresent(Int.self, forKey: .overall_score)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: ImageQualityCodingKeys.self)
            try container.encodeIfPresent(sharpness, forKey: .sharpness)
            try container.encodeIfPresent(framing, forKey: .framing)
            try container.encodeIfPresent(diagnostic_utility, forKey: .diagnostic_utility)
            try container.encodeIfPresent(overall_score, forKey: .overall_score)
        }
    }

    let scan_id: String?
    let is_biological_subject: Bool?
    let is_live_capture: Bool?
    let ecology_type: String?
    let is_invasive: Bool?
    let invasive_status_region: String?
    let invasive_rationale: String?
    let invasive_confidence: Double?
    let scientific_name: String?
    let common_name: String?
    let confidence_score: Double?
    let blur_score: Double?
    let colors: [String]?
    let group_tags: [String]?
    let is_new_to_merian_dictionary: Bool?
    let estimated_size_cm: Double?
    let life_stage: String?
    let reproductive_condition: String?
    let sex: String?
    let sex_confidence: Double?
    let sex_evidence: String?
    let individual_count: Int?
    let ecological_interactions: [String]?
    let taxonomy: Taxonomy?
    let insight_data: Insight?
    let species_insights: SpeciesInsights?
    let gbif_taxon_key: Int?
    let wikipedia_url: String?
    let wikipedia_overview: String?
    let reference_image_url: String?
    let iucn_red_list_status: String?
    let inference_tier: String?
    let alternative_common_names: [String]?
    let pet_identification: PetIdentificationDTO?
    let candidates: [IdentificationCandidate]?
    let image_quality: ImageQuality?

    enum CodingKeys: String, CodingKey {
        case scan_id
        case is_biological_subject
        case is_live_capture
        case ecology_type
        case is_invasive
        case invasive_status_region
        case invasive_rationale
        case invasive_confidence
        case scientific_name
        case common_name
        case confidence_score
        case blur_score
        case colors
        case group_tags
        case is_new_to_merian_dictionary
        case estimated_size_cm
        case life_stage
        case reproductive_condition
        case sex
        case sex_confidence
        case sex_evidence
        case individual_count
        case ecological_interactions
        case taxonomy
        case insight_data
        case species_insights
        case gbif_taxon_key
        case wikipedia_url
        case wikipedia_overview
        case reference_image_url
        case iucn_red_list_status
        case inference_tier
        case alternative_common_names
        case pet_identification
        case candidates
        case image_quality
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scan_id = try container.decodeIfPresent(String.self, forKey: .scan_id)
        is_biological_subject = try container.decodeIfPresent(Bool.self, forKey: .is_biological_subject)
        is_live_capture = try container.decodeIfPresent(Bool.self, forKey: .is_live_capture)
        ecology_type = try container.decodeIfPresent(String.self, forKey: .ecology_type)
        is_invasive = try container.decodeIfPresent(Bool.self, forKey: .is_invasive)
        invasive_status_region = try container.decodeIfPresent(String.self, forKey: .invasive_status_region)
        invasive_rationale = try container.decodeIfPresent(String.self, forKey: .invasive_rationale)
        invasive_confidence = try container.decodeIfPresent(Double.self, forKey: .invasive_confidence)
        scientific_name = try container.decodeIfPresent(String.self, forKey: .scientific_name)
        common_name = try container.decodeIfPresent(String.self, forKey: .common_name)
        confidence_score = try container.decodeIfPresent(Double.self, forKey: .confidence_score)
        blur_score = try container.decodeIfPresent(Double.self, forKey: .blur_score)
        colors = try container.decodeIfPresent([String].self, forKey: .colors)
        group_tags = try container.decodeIfPresent([String].self, forKey: .group_tags)
        is_new_to_merian_dictionary = try container.decodeIfPresent(Bool.self, forKey: .is_new_to_merian_dictionary)
        estimated_size_cm = try container.decodeIfPresent(Double.self, forKey: .estimated_size_cm)
        life_stage = try container.decodeIfPresent(String.self, forKey: .life_stage)
        reproductive_condition = try container.decodeIfPresent(String.self, forKey: .reproductive_condition)
        sex = try container.decodeIfPresent(String.self, forKey: .sex)
        sex_confidence = try container.decodeIfPresent(Double.self, forKey: .sex_confidence)
        sex_evidence = try container.decodeIfPresent(String.self, forKey: .sex_evidence)
        individual_count = try container.decodeIfPresent(Int.self, forKey: .individual_count)
        ecological_interactions = try container.decodeIfPresent([String].self, forKey: .ecological_interactions)
        taxonomy = try container.decodeIfPresent(Taxonomy.self, forKey: .taxonomy)
        insight_data = try container.decodeIfPresent(Insight.self, forKey: .insight_data)
        species_insights = try container.decodeIfPresent(SpeciesInsights.self, forKey: .species_insights)
        gbif_taxon_key = try container.decodeIfPresent(Int.self, forKey: .gbif_taxon_key)
        wikipedia_url = try container.decodeIfPresent(String.self, forKey: .wikipedia_url)
        wikipedia_overview = try container.decodeIfPresent(String.self, forKey: .wikipedia_overview)
        reference_image_url = try container.decodeIfPresent(String.self, forKey: .reference_image_url)
        iucn_red_list_status = try container.decodeIfPresent(String.self, forKey: .iucn_red_list_status)
        inference_tier = try container.decodeIfPresent(String.self, forKey: .inference_tier)
        alternative_common_names = try container.decodeIfPresent([String].self, forKey: .alternative_common_names)
        pet_identification = try container.decodeIfPresent(PetIdentificationDTO.self, forKey: .pet_identification)
        candidates = try container.decodeIfPresent([IdentificationCandidate].self, forKey: .candidates)
        image_quality = try container.decodeIfPresent(ImageQuality.self, forKey: .image_quality)
    }
}
// END GENERATED: Identify wire DTOs

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
