import Foundation

struct SpeciesDictionaryResponse: Decodable {
    let schemaVersion: Int?
    let data: SpeciesDictionaryEntry

    var effectiveSchemaVersion: Int { schemaVersion ?? 0 }
}

struct SpeciesDictionaryEntry: Decodable, Equatable, Identifiable {
    let id: String
    let scientificName: String
    let commonName: String
    let alternativeCommonNames: [String]
    let taxonomy: SpeciesDictionaryTaxonomy?
    let hazardType: String?
    let iucnRedListStatus: String?
    let wikipediaUrl: String?
    let wikipediaOverview: String?
    let habitatDescription: String?
    let gbifTaxonKey: Int?
    let groupTags: [String]
    let referenceImages: [SpeciesDictionaryReferenceImage]
    let similarSpecies: [SpeciesDictionarySimilarSpecies]

    var taxonomyData: TaxonomyData? {
        guard let taxonomy else { return nil }
        let data = TaxonomyData(
            kingdom: taxonomy.kingdom,
            phylum: taxonomy.phylum,
            className: taxonomy.className,
            order: taxonomy.order,
            family: taxonomy.family,
            genus: taxonomy.genus
        )

        let values = [
            data.kingdom,
            data.phylum,
            data.className,
            data.order,
            data.family,
            data.genus
        ]

        return values.contains { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ? data : nil
    }

    var similarSpeciesData: SimilarSpecies? {
        let entries = similarSpecies.compactMap { item -> SimilarSpeciesEntry? in
            let scientificName = item.scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !scientificName.isEmpty else { return nil }
            return SimilarSpeciesEntry(
                scientificName: scientificName,
                commonName: item.commonName,
                referenceImageUrl: item.referenceImageUrl,
                iucnRedListStatus: item.iucnRedListStatus,
                speciesId: item.speciesId,
                similarityReason: item.reason,
                visualTraits: item.visualTraits,
                similarityConfidence: item.confidence,
                relationshipSource: item.source,
                reviewStatus: item.reviewStatus,
                isBidirectional: item.isBidirectional,
                sortOrder: item.sortOrder
            )
        }

        return entries.isEmpty ? nil : SimilarSpecies(entries: entries)
    }
}

struct SpeciesDictionaryTaxonomy: Decodable, Equatable {
    let kingdom: String?
    let phylum: String?
    let className: String?
    let order: String?
    let family: String?
    let genus: String?

    private enum CodingKeys: String, CodingKey {
        case kingdom
        case phylum
        case className = "class"
        case order
        case family
        case genus
    }
}

struct SpeciesDictionaryReferenceImage: Decodable, Equatable, Identifiable {
    enum Source: String, Decodable, Equatable {
        case wikipedia
        case gbif

        var label: String {
            switch self {
            case .wikipedia:
                return "Wikipedia"
            case .gbif:
                return "GBIF"
            }
        }
    }

    let url: String
    let source: Source
    let license: String?
    let attribution: String?
    let width: Int?
    let height: Int?

    var id: String { url }
}

struct SpeciesDictionarySimilarSpecies: Decodable, Equatable, Identifiable {
    let speciesId: String?
    let scientificName: String
    let commonName: String?
    let referenceImageUrl: String?
    let iucnRedListStatus: String?
    let reason: String?
    let visualTraits: [String]
    let confidence: Double?
    let source: String?
    let reviewStatus: String?
    let isBidirectional: Bool?
    let sortOrder: Int?

    var id: String { speciesId ?? scientificName }

    private enum CodingKeys: String, CodingKey {
        case speciesId
        case scientificName
        case commonName
        case referenceImageUrl
        case iucnRedListStatus
        case reason
        case visualTraits
        case confidence
        case source
        case reviewStatus
        case isBidirectional
        case sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speciesId = try container.decodeIfPresent(String.self, forKey: .speciesId)
        scientificName = try container.decode(String.self, forKey: .scientificName)
        commonName = try container.decodeIfPresent(String.self, forKey: .commonName)
        referenceImageUrl = try container.decodeIfPresent(String.self, forKey: .referenceImageUrl)
        iucnRedListStatus = try container.decodeIfPresent(String.self, forKey: .iucnRedListStatus)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        visualTraits = try container.decodeIfPresent([String].self, forKey: .visualTraits) ?? []
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        reviewStatus = try container.decodeIfPresent(String.self, forKey: .reviewStatus)
        isBidirectional = try container.decodeIfPresent(Bool.self, forKey: .isBidirectional)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
    }
}

struct SpeciesDictionaryRoute: Identifiable, Equatable {
    let speciesId: String?
    let scientificName: String

    init(scientificName: String, speciesId: String? = nil) {
        self.speciesId = speciesId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.scientificName = scientificName
    }

    var id: String { speciesId ?? scientificName }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
