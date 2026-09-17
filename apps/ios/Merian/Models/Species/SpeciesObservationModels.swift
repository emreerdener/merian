import Foundation

struct PetIdentification: Codable, Equatable, Hashable, Sendable {
    let speciesGroup: String
    let label: String
    let labelType: String
    let confidenceScore: Double
    let evidence: [String]

    private enum CodingKeys: String, CodingKey {
        case speciesGroup
        case label
        case labelType
        case confidenceScore
        case evidence
    }

    private enum SnakeCodingKeys: String, CodingKey {
        case speciesGroup = "species_group"
        case label
        case labelType = "label_type"
        case confidenceScore = "confidence_score"
        case evidence
    }

    init(
        speciesGroup: String,
        label: String,
        labelType: String,
        confidenceScore: Double,
        evidence: [String]
    ) {
        self.speciesGroup = speciesGroup
        self.label = label
        self.labelType = labelType
        self.confidenceScore = confidenceScore
        self.evidence = evidence
    }

    init(from decoder: Decoder) throws {
        let camelContainer = try decoder.container(keyedBy: CodingKeys.self)
        let snakeContainer = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.speciesGroup = try camelContainer.decodeIfPresent(
            String.self,
            forKey: .speciesGroup
        ) ?? snakeContainer.decode(String.self, forKey: .speciesGroup)
        self.label = try camelContainer.decode(String.self, forKey: .label)
        self.labelType = try camelContainer.decodeIfPresent(
            String.self,
            forKey: .labelType
        ) ?? snakeContainer.decode(String.self, forKey: .labelType)
        self.confidenceScore = try camelContainer.decodeIfPresent(
            Double.self,
            forKey: .confidenceScore
        ) ?? snakeContainer.decode(Double.self, forKey: .confidenceScore)
        self.evidence = try camelContainer.decodeIfPresent(
            [String].self,
            forKey: .evidence
        ) ?? snakeContainer.decode([String].self, forKey: .evidence)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SnakeCodingKeys.self)
        try container.encode(speciesGroup, forKey: .speciesGroup)
        try container.encode(label, forKey: .label)
        try container.encode(labelType, forKey: .labelType)
        try container.encode(confidenceScore, forKey: .confidenceScore)
        try container.encode(evidence, forKey: .evidence)
    }

    var isDisplayable: Bool {
        confidenceScore >= 0.70 &&
            !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct TaxonomyData: Sendable {
    let kingdom: String?
    let phylum: String?
    let className: String?
    let order: String?
    let family: String?
    let genus: String?

    static func normalizeComponent(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.caseInsensitiveCompare("unknown") != .orderedSame else {
            return nil
        }
        return trimmed
    }

    var hasUsableLookalikeValidation: Bool {
        Self.normalizeComponent(kingdom) != nil &&
            (Self.normalizeComponent(order) != nil ||
                Self.normalizeComponent(family) != nil)
    }
}

struct InsightData: Sendable {
    /// Per-scan AI vision reasoning — unique to the specific photo submitted.
    let aiReasoning: String
    /// AI-classified hazard type: `none`, `poisonous`, `venomous`, `allergenic`, or `irritant`.
    let hazardType: String
    var isHazardous: Bool { hazardType != "none" }
}

/// A single alternative species the model actively considered during identification.
/// Scan-specific uncertainty rather than a fixed species-level lookalike.
struct IdentificationCandidate: Codable, Sendable {
    let scientificName: String
    let commonName: String?
    let confidenceScore: Double
    let distinguishingFeature: String?

    init(
        scientificName: String,
        commonName: String? = nil,
        confidenceScore: Double,
        distinguishingFeature: String? = nil
    ) {
        self.scientificName = scientificName
        self.commonName = commonName
        self.confidenceScore = confidenceScore
        self.distinguishingFeature = distinguishingFeature
    }
}
