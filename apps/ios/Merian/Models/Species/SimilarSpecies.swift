import Foundation

struct SimilarSpeciesEntry: Codable, Sendable {
    let speciesId: String?
    let scientificName: String
    let commonName: String?
    let referenceImageUrl: String?
    let iucnRedListStatus: String?
    let similarityReason: String?
    let visualTraits: [String]
    let similarityConfidence: Double?
    let relationshipSource: String?
    let reviewStatus: String?
    let isBidirectional: Bool?
    let sortOrder: Int?

    init(
        scientificName: String,
        commonName: String?,
        referenceImageUrl: String?,
        iucnRedListStatus: String?,
        speciesId: String? = nil,
        similarityReason: String? = nil,
        visualTraits: [String] = [],
        similarityConfidence: Double? = nil,
        relationshipSource: String? = nil,
        reviewStatus: String? = nil,
        isBidirectional: Bool? = nil,
        sortOrder: Int? = nil
    ) {
        self.speciesId = speciesId
        self.scientificName = scientificName
        self.commonName = commonName
        self.referenceImageUrl = ExternalReferenceImagePolicy.sanitizedURL(
            referenceImageUrl
        )
        self.iucnRedListStatus = iucnRedListStatus
        self.similarityReason = similarityReason
        self.visualTraits = visualTraits
        self.similarityConfidence = similarityConfidence
        self.relationshipSource = relationshipSource
        self.reviewStatus = reviewStatus
        self.isBidirectional = isBidirectional
        self.sortOrder = sortOrder
    }

    private enum CodingKeys: String, CodingKey {
        case speciesId
        case scientificName
        case commonName
        case referenceImageUrl
        case iucnRedListStatus
        case similarityReason = "reason"
        case visualTraits
        case similarityConfidence = "confidence"
        case relationshipSource = "source"
        case reviewStatus
        case isBidirectional
        case sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speciesId = try container.decodeIfPresent(String.self, forKey: .speciesId)
        scientificName = try container.decode(String.self, forKey: .scientificName)
        commonName = try container.decodeIfPresent(String.self, forKey: .commonName)
        referenceImageUrl = ExternalReferenceImagePolicy.sanitizedURL(
            try container.decodeIfPresent(String.self, forKey: .referenceImageUrl)
        )
        iucnRedListStatus = try container.decodeIfPresent(
            String.self,
            forKey: .iucnRedListStatus
        )
        similarityReason = try container.decodeIfPresent(
            String.self,
            forKey: .similarityReason
        )
        visualTraits = try container.decodeIfPresent(
            [String].self,
            forKey: .visualTraits
        ) ?? []
        similarityConfidence = try container.decodeIfPresent(
            Double.self,
            forKey: .similarityConfidence
        )
        relationshipSource = try container.decodeIfPresent(
            String.self,
            forKey: .relationshipSource
        )
        reviewStatus = try container.decodeIfPresent(String.self, forKey: .reviewStatus)
        isBidirectional = try container.decodeIfPresent(Bool.self, forKey: .isBidirectional)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(speciesId, forKey: .speciesId)
        try container.encode(scientificName, forKey: .scientificName)
        try container.encodeIfPresent(commonName, forKey: .commonName)
        try container.encodeIfPresent(referenceImageUrl, forKey: .referenceImageUrl)
        try container.encodeIfPresent(iucnRedListStatus, forKey: .iucnRedListStatus)
        try container.encodeIfPresent(similarityReason, forKey: .similarityReason)
        if !visualTraits.isEmpty {
            try container.encode(visualTraits, forKey: .visualTraits)
        }
        try container.encodeIfPresent(
            similarityConfidence,
            forKey: .similarityConfidence
        )
        try container.encodeIfPresent(relationshipSource, forKey: .relationshipSource)
        try container.encodeIfPresent(reviewStatus, forKey: .reviewStatus)
        try container.encodeIfPresent(isBidirectional, forKey: .isBidirectional)
        try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
    }

    static func normalizeScientificName(_ value: String?) -> String {
        value?
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased() ?? ""
    }

    func displayCommonName(comparedTo currentCommonName: String?) -> String? {
        guard let commonName = commonName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !commonName.isEmpty else {
            return nil
        }

        let currentCommon = currentCommonName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard commonName.caseInsensitiveCompare(currentCommon) != .orderedSame else {
            return nil
        }
        return commonName
    }
}

struct SimilarSpecies: Sendable {
    let entries: [SimilarSpeciesEntry]

    /// Backwards-compatible accessor returning scientific names in entry order.
    var lookalikes: [String] { entries.map(\.scientificName) }

    func filteredEntries(
        excludingScientificName scientificName: String?,
        excludingSpeciesId speciesId: String? = nil
    ) -> [SimilarSpeciesEntry] {
        let excludedScientificName = SimilarSpeciesEntry.normalizeScientificName(
            scientificName
        )
        let excludedSpeciesId = SpeciesDictionaryIdentity.canonicalSpeciesID(speciesId)
        var seenSpeciesIds = Set<String>()
        var seenScientificNames = Set<String>()

        return entries.compactMap { entry in
            let normalizedScientificName = SimilarSpeciesEntry
                .normalizeScientificName(entry.scientificName)
            guard !normalizedScientificName.isEmpty else { return nil }
            guard normalizedScientificName != excludedScientificName else { return nil }

            let entrySpeciesId = SpeciesDictionaryIdentity.canonicalSpeciesID(
                entry.speciesId
            )
            if let entrySpeciesId {
                guard entrySpeciesId != excludedSpeciesId,
                      !seenSpeciesIds.contains(entrySpeciesId) else {
                    return nil
                }
            }

            guard seenScientificNames.insert(normalizedScientificName).inserted else {
                return nil
            }
            if let entrySpeciesId { seenSpeciesIds.insert(entrySpeciesId) }
            return entry
        }
    }
}
