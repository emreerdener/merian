import Foundation

// Uses the shared MerianError taxonomy from Core/Errors.

// BEGIN GENERATED: Identify wire DTOs
// Generated from services/supabase/functions/_shared/identify/contract.ts.
// Do not edit this block by hand; run make generate-edge-dto-contract.

private struct IdentifyWireCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

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
    case taxon_rank
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

private enum GenerationCodingKeys: String, CodingKey {
    case temperature
    case seed
    case top_k
    case max_output_tokens
    case thinking_budget
}

private enum OpenAIGenerationCodingKeys: String, CodingKey {
    case max_output_tokens
    case reasoning_effort
    case image_detail
}

struct EdgeResponseWrapper: Codable {
    let success: Bool?
    let data: EdgeResponse
    let entitlement: ScanEntitlementMetadataDTO?

    enum CodingKeys: String, CodingKey {
        case success
        case data
        case entitlement
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        data = try container.decode(EdgeResponse.self, forKey: .data)
        entitlement = try container.decodeIfPresent(ScanEntitlementMetadataDTO.self, forKey: .entitlement)
    }
}

struct ScanEntitlementMetadataDTO: Codable {
    let userID: String
    let planUsed: String
    let creditConsumed: Bool
    let entitlementAfter: EntitlementSnapshotDTO

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case planUsed = "plan_used"
        case creditConsumed = "credit_consumed"
        case entitlementAfter = "entitlement_after"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(String.self, forKey: .userID)
        planUsed = try container.decode(String.self, forKey: .planUsed)
        creditConsumed = try container.decode(Bool.self, forKey: .creditConsumed)
        entitlementAfter = try container.decode(EntitlementSnapshotDTO.self, forKey: .entitlementAfter)
    }
}

struct EntitlementSnapshotDTO: Codable {
    let currentPlan: String
    let currentTier: String
    let isPaid: Bool
    let scansRemaining: Int
    let scansAvailableToStart: Int
    let inFlightCount: Int
    let entitlementVersion: Int

    enum CodingKeys: String, CodingKey {
        case currentPlan = "current_plan"
        case currentTier = "current_tier"
        case isPaid = "is_paid"
        case scansRemaining = "scans_remaining"
        case scansAvailableToStart = "scans_available_to_start"
        case inFlightCount = "in_flight_count"
        case entitlementVersion = "entitlement_version"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentPlan = try container.decode(String.self, forKey: .currentPlan)
        currentTier = try container.decode(String.self, forKey: .currentTier)
        isPaid = try container.decode(Bool.self, forKey: .isPaid)
        scansRemaining = try container.decode(Int.self, forKey: .scansRemaining)
        scansAvailableToStart = try container.decode(Int.self, forKey: .scansAvailableToStart)
        inFlightCount = try container.decode(Int.self, forKey: .inFlightCount)
        entitlementVersion = try container.decode(Int.self, forKey: .entitlementVersion)
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
        let taxon_rank: String?
        let scientific_name: String
        let confidence_score: Double
        let distinguishing_feature: String?
        let common_name: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: IdentificationCandidateCodingKeys.self)
            taxon_rank = container.contains(.taxon_rank)
                ? try container.decode(String.self, forKey: .taxon_rank) : nil
            scientific_name = try container.decode(String.self, forKey: .scientific_name)
            confidence_score = try container.decode(Double.self, forKey: .confidence_score)
            distinguishing_feature = try container.decodeIfPresent(String.self, forKey: .distinguishing_feature)
            common_name = try container.decodeIfPresent(String.self, forKey: .common_name)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: IdentificationCandidateCodingKeys.self)
            try container.encodeIfPresent(taxon_rank, forKey: .taxon_rank)
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
    let identification_provenance: IdentificationProvenanceDTO?
    let primary_identification: PrimaryIdentificationDTO?
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
        case identification_provenance
        case primary_identification
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
        identification_provenance = container.contains(.identification_provenance)
            ? try container.decode(IdentificationProvenanceDTO.self, forKey: .identification_provenance) : nil
        primary_identification = container.contains(.primary_identification)
            ? try container.decode(PrimaryIdentificationDTO.self, forKey: .primary_identification) : nil
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

struct IdentificationProvenanceV1DTO: Codable {
    struct Generation: Codable {
        let temperature: Double
        let seed: Int?
        let top_k: Int?
        let max_output_tokens: Int
        let thinking_budget: Int?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: GenerationCodingKeys.self)
            let rawContainer = try decoder.container(keyedBy: IdentifyWireCodingKey.self)
            let allowedKeys: Set<String> = ["temperature", "seed", "top_k", "max_output_tokens", "thinking_budget"]
            guard rawContainer.allKeys.allSatisfy({ allowedKeys.contains($0.stringValue) }) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected field in strict identification metadata."))
            }
            temperature = try container.decode(Double.self, forKey: .temperature)
            seed = try container.decode(Int?.self, forKey: .seed)
            top_k = try container.decode(Int?.self, forKey: .top_k)
            max_output_tokens = try container.decode(Int.self, forKey: .max_output_tokens)
            thinking_budget = try container.decode(Int?.self, forKey: .thinking_budget)
            guard temperature >= 0 && temperature <= 2 else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
            }
            if let seed {
                guard seed >= 0 && seed <= 999999999 else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
                }
            }
            if let top_k {
                guard top_k >= 1 && top_k <= 999999999 else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
                }
            }
            guard max_output_tokens >= 1 && max_output_tokens <= 999999999 else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
            }
            if let thinking_budget {
                guard thinking_budget >= 0 && thinking_budget <= 999999999 else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
                }
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: GenerationCodingKeys.self)
            try container.encode(temperature, forKey: .temperature)
            try container.encode(seed, forKey: .seed)
            try container.encode(top_k, forKey: .top_k)
            try container.encode(max_output_tokens, forKey: .max_output_tokens)
            try container.encode(thinking_budget, forKey: .thinking_budget)
        }
    }

    let version: Int
    let provider: String
    let binding: String
    let model: String
    let variant: String
    let operation: String
    let policy_version: Int
    let prompt: String
    let schema: String
    let confidence: String
    let diagnostic_trigger: Double?
    let prompt_diagnostic_trigger: Double?
    let safety: String?
    let timeout_ms: Int
    let generation: Generation

    enum CodingKeys: String, CodingKey {
        case version
        case provider
        case binding
        case model
        case variant
        case operation
        case policy_version
        case prompt
        case schema
        case confidence
        case diagnostic_trigger
        case prompt_diagnostic_trigger
        case safety
        case timeout_ms
        case generation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawContainer = try decoder.container(keyedBy: IdentifyWireCodingKey.self)
        let allowedKeys: Set<String> = ["version", "provider", "binding", "model", "variant", "operation", "policy_version", "prompt", "schema", "confidence", "diagnostic_trigger", "prompt_diagnostic_trigger", "safety", "timeout_ms", "generation"]
        guard rawContainer.allKeys.allSatisfy({ allowedKeys.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected field in strict identification metadata."))
        }
        version = try container.decode(Int.self, forKey: .version)
        provider = try container.decode(String.self, forKey: .provider)
        binding = try container.decode(String.self, forKey: .binding)
        model = try container.decode(String.self, forKey: .model)
        variant = try container.decode(String.self, forKey: .variant)
        operation = try container.decode(String.self, forKey: .operation)
        policy_version = try container.decode(Int.self, forKey: .policy_version)
        prompt = try container.decode(String.self, forKey: .prompt)
        schema = try container.decode(String.self, forKey: .schema)
        confidence = try container.decode(String.self, forKey: .confidence)
        diagnostic_trigger = try container.decode(Double?.self, forKey: .diagnostic_trigger)
        prompt_diagnostic_trigger = try container.decode(Double?.self, forKey: .prompt_diagnostic_trigger)
        safety = try container.decode(String?.self, forKey: .safety)
        timeout_ms = try container.decode(Int.self, forKey: .timeout_ms)
        generation = try container.decode(Generation.self, forKey: .generation)
        guard version >= 1 && version <= 1 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard provider.utf16.count >= 1 && provider.utf16.count <= 80 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard binding.utf16.count >= 1 && binding.utf16.count <= 80 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard model.utf16.count >= 1 && model.utf16.count <= 80 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard variant.utf16.count >= 1 && variant.utf16.count <= 80 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard operation.utf16.count >= 1 && operation.utf16.count <= 80 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard policy_version >= 1 && policy_version <= 999999999 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard prompt.utf16.count >= 1 && prompt.utf16.count <= 80 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard schema.utf16.count >= 1 && schema.utf16.count <= 80 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard confidence.utf16.count >= 1 && confidence.utf16.count <= 80 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        if let diagnostic_trigger {
            guard diagnostic_trigger >= 0 && diagnostic_trigger <= 1 else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
            }
        }
        if let prompt_diagnostic_trigger {
            guard prompt_diagnostic_trigger >= 0 && prompt_diagnostic_trigger <= 1 else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
            }
        }
        if let safety {
            guard safety.utf16.count >= 1 && safety.utf16.count <= 80 else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
            }
        }
        guard timeout_ms >= 1 && timeout_ms <= 999999 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(provider, forKey: .provider)
        try container.encode(binding, forKey: .binding)
        try container.encode(model, forKey: .model)
        try container.encode(variant, forKey: .variant)
        try container.encode(operation, forKey: .operation)
        try container.encode(policy_version, forKey: .policy_version)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(schema, forKey: .schema)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(diagnostic_trigger, forKey: .diagnostic_trigger)
        try container.encode(prompt_diagnostic_trigger, forKey: .prompt_diagnostic_trigger)
        try container.encode(safety, forKey: .safety)
        try container.encode(timeout_ms, forKey: .timeout_ms)
        try container.encode(generation, forKey: .generation)
    }
}

struct IdentificationProvenanceV2DTO: Codable {
    struct OpenAIGeneration: Codable {
        let max_output_tokens: Int
        let reasoning_effort: String
        let image_detail: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: OpenAIGenerationCodingKeys.self)
            let rawContainer = try decoder.container(keyedBy: IdentifyWireCodingKey.self)
            let allowedKeys: Set<String> = ["max_output_tokens", "reasoning_effort", "image_detail"]
            guard rawContainer.allKeys.allSatisfy({ allowedKeys.contains($0.stringValue) }) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected field in strict identification metadata."))
            }
            max_output_tokens = try container.decode(Int.self, forKey: .max_output_tokens)
            reasoning_effort = try container.decode(String.self, forKey: .reasoning_effort)
            image_detail = try container.decode(String.self, forKey: .image_detail)
            guard max_output_tokens >= 1 && max_output_tokens <= 999999999 else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
            }
            guard reasoning_effort.utf16.count >= 1 && reasoning_effort.utf16.count <= 80 && reasoning_effort.range(of: "^[a-z][a-z0-9_.-]{0,79}$", options: .regularExpression) == (reasoning_effort.startIndex..<reasoning_effort.endIndex) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
            }
            guard image_detail.utf16.count >= 1 && image_detail.utf16.count <= 80 && image_detail.range(of: "^[a-z][a-z0-9_.-]{0,79}$", options: .regularExpression) == (image_detail.startIndex..<image_detail.endIndex) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: OpenAIGenerationCodingKeys.self)
            try container.encode(max_output_tokens, forKey: .max_output_tokens)
            try container.encode(reasoning_effort, forKey: .reasoning_effort)
            try container.encode(image_detail, forKey: .image_detail)
        }
    }

    let version: Int
    let provider: String
    let binding: String
    let model: String
    let variant: String
    let operation: String
    let policy_version: Int
    let prompt: String
    let schema: String
    let confidence: String
    let diagnostic_trigger: Double?
    let prompt_diagnostic_trigger: Double?
    let safety: String?
    let timeout_ms: Int
    let generation: OpenAIGeneration

    enum CodingKeys: String, CodingKey {
        case version
        case provider
        case binding
        case model
        case variant
        case operation
        case policy_version
        case prompt
        case schema
        case confidence
        case diagnostic_trigger
        case prompt_diagnostic_trigger
        case safety
        case timeout_ms
        case generation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawContainer = try decoder.container(keyedBy: IdentifyWireCodingKey.self)
        let allowedKeys: Set<String> = ["version", "provider", "binding", "model", "variant", "operation", "policy_version", "prompt", "schema", "confidence", "diagnostic_trigger", "prompt_diagnostic_trigger", "safety", "timeout_ms", "generation"]
        guard rawContainer.allKeys.allSatisfy({ allowedKeys.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected field in strict identification metadata."))
        }
        version = try container.decode(Int.self, forKey: .version)
        provider = try container.decode(String.self, forKey: .provider)
        binding = try container.decode(String.self, forKey: .binding)
        model = try container.decode(String.self, forKey: .model)
        variant = try container.decode(String.self, forKey: .variant)
        operation = try container.decode(String.self, forKey: .operation)
        policy_version = try container.decode(Int.self, forKey: .policy_version)
        prompt = try container.decode(String.self, forKey: .prompt)
        schema = try container.decode(String.self, forKey: .schema)
        confidence = try container.decode(String.self, forKey: .confidence)
        diagnostic_trigger = try container.decode(Double?.self, forKey: .diagnostic_trigger)
        prompt_diagnostic_trigger = try container.decode(Double?.self, forKey: .prompt_diagnostic_trigger)
        safety = try container.decode(String?.self, forKey: .safety)
        timeout_ms = try container.decode(Int.self, forKey: .timeout_ms)
        generation = try container.decode(OpenAIGeneration.self, forKey: .generation)
        guard version >= 2 && version <= 2 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard provider.utf16.count <= 80 && ["openai"].contains(provider) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard binding.utf16.count >= 1 && binding.utf16.count <= 80 && binding.range(of: "^[a-z][a-z0-9_.-]{0,79}$", options: .regularExpression) == (binding.startIndex..<binding.endIndex) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard model.utf16.count >= 1 && model.utf16.count <= 80 && model.range(of: "^[a-z][a-z0-9_.-]{0,79}$", options: .regularExpression) == (model.startIndex..<model.endIndex) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard variant.utf16.count >= 1 && variant.utf16.count <= 80 && ["multimodal", "description_compat", "vision_compat", "audio_compat"].contains(variant) && variant.range(of: "^[a-z][a-z0-9_.-]{0,79}$", options: .regularExpression) == (variant.startIndex..<variant.endIndex) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard operation.utf16.count >= 1 && operation.utf16.count <= 80 && ["scan_identification", "scan_audio_identification"].contains(operation) && operation.range(of: "^[a-z][a-z0-9_.-]{0,79}$", options: .regularExpression) == (operation.startIndex..<operation.endIndex) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard policy_version >= 1 && policy_version <= 999999999 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard prompt.utf16.count >= 1 && prompt.utf16.count <= 80 && prompt.range(of: "^[a-z][a-z0-9_.-]{0,79}$", options: .regularExpression) == (prompt.startIndex..<prompt.endIndex) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard schema.utf16.count >= 1 && schema.utf16.count <= 80 && schema.range(of: "^[a-z][a-z0-9_.-]{0,79}$", options: .regularExpression) == (schema.startIndex..<schema.endIndex) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard confidence.utf16.count >= 1 && confidence.utf16.count <= 80 && confidence.range(of: "^[a-z][a-z0-9_.-]{0,79}$", options: .regularExpression) == (confidence.startIndex..<confidence.endIndex) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        if let diagnostic_trigger {
            guard diagnostic_trigger >= 0 && diagnostic_trigger <= 1 else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
            }
        }
        if let prompt_diagnostic_trigger {
            guard prompt_diagnostic_trigger >= 0 && prompt_diagnostic_trigger <= 1 else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
            }
        }
        if let safety {
            guard safety.utf16.count >= 1 && safety.utf16.count <= 80 && safety.range(of: "^[a-z][a-z0-9_.-]{0,79}$", options: .regularExpression) == (safety.startIndex..<safety.endIndex) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
            }
        }
        guard timeout_ms >= 1 && timeout_ms <= 999999 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(provider, forKey: .provider)
        try container.encode(binding, forKey: .binding)
        try container.encode(model, forKey: .model)
        try container.encode(variant, forKey: .variant)
        try container.encode(operation, forKey: .operation)
        try container.encode(policy_version, forKey: .policy_version)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(schema, forKey: .schema)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(diagnostic_trigger, forKey: .diagnostic_trigger)
        try container.encode(prompt_diagnostic_trigger, forKey: .prompt_diagnostic_trigger)
        try container.encode(safety, forKey: .safety)
        try container.encode(timeout_ms, forKey: .timeout_ms)
        try container.encode(generation, forKey: .generation)
    }
}

enum IdentificationProvenanceDTO: Codable {
    case v1(IdentificationProvenanceV1DTO)
    case v2(IdentificationProvenanceV2DTO)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: IdentifyWireCodingKey.self)
        let version = try container.decode(Int.self, forKey: IdentifyWireCodingKey(stringValue: "version")!)
        switch version {
        case 1: self = .v1(try IdentificationProvenanceV1DTO(from: decoder))
        case 2: self = .v2(try IdentificationProvenanceV2DTO(from: decoder))
        default: throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported identification metadata version."))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .v1(let value): try value.encode(to: encoder)
        case .v2(let value): try value.encode(to: encoder)
        }
    }
}

struct PrimaryIdentificationDTO: Codable {
    let version: Int
    let resolution: String
    let scientific_name: String?
    let common_name: String?

    enum CodingKeys: String, CodingKey {
        case version
        case resolution
        case scientific_name
        case common_name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawContainer = try decoder.container(keyedBy: IdentifyWireCodingKey.self)
        let allowedKeys: Set<String> = ["version", "resolution", "scientific_name", "common_name"]
        guard rawContainer.allKeys.allSatisfy({ allowedKeys.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected field in strict identification metadata."))
        }
        version = try container.decode(Int.self, forKey: .version)
        resolution = try container.decode(String.self, forKey: .resolution)
        scientific_name = try container.decode(String?.self, forKey: .scientific_name)
        common_name = try container.decode(String?.self, forKey: .common_name)
        guard version >= 1 && version <= 1 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        guard ["species", "genus", "family", "unresolved_biological", "non_biological"].contains(resolution) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
        }
        if let scientific_name {
            guard scientific_name.utf16.count >= 1 && scientific_name.utf16.count <= 255 else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
            }
        }
        if let common_name {
            guard common_name.utf16.count >= 1 && common_name.utf16.count <= 255 else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid identification metadata value."))
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(scientific_name, forKey: .scientific_name)
        try container.encode(common_name, forKey: .common_name)
    }
}
// END GENERATED: Identify wire DTOs

enum IdentifySuccessEnvelopeValidator {
    /// Minimal client-side success boundary retained outside the generated DTO
    /// block. Required wire fields remain optional in Swift for rolling-version
    /// compatibility, so decoding alone cannot establish a usable result.
    static func isUsable(_ wrapper: EdgeResponseWrapper) -> Bool {
        guard wrapper.success != false,
              let scanId = wrapper.data.scan_id?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !scanId.isEmpty,
              scanId.count <= 128,
              let confidenceScore = wrapper.data.confidence_score,
              confidenceScore.isFinite,
              (0.0...1.0).contains(confidenceScore),
              PrimaryIdentificationResponseValidator.isValid(wrapper.data) else {
            return false
        }
        return true
    }
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
