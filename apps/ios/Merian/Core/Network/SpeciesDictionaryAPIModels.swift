import Foundation

struct SpeciesDictionaryResponse: Decodable {
    let schemaVersion: Int?
    let data: SpeciesDictionaryEntry

    var effectiveSchemaVersion: Int { schemaVersion ?? 0 }
}

struct SpeciesDictionaryCatalogResponse: Decodable {
    let schemaVersion: Int?
    let data: [SpeciesDictionaryCatalogItem]
    let nextCursor: SpeciesDictionaryCatalogCursor?

    var effectiveSchemaVersion: Int { schemaVersion ?? 0 }
}

struct SpeciesDictionaryOverviewResponse: Decodable {
    let schemaVersion: Int?
    let data: SpeciesDictionaryOverview

    var effectiveSchemaVersion: Int { schemaVersion ?? 0 }
}

enum SpeciesDictionaryCatalogCategory: String, Codable, Equatable, Hashable {
    case all
    case region
    case group
    case recentlyAdded = "recently_added"
}

enum SpeciesDictionaryOverviewCategoryID: String, Decodable, Equatable, Hashable {
    case all
    case yourRegion = "your_region"
    // Decode-only compatibility for overview responses deployed before the
    // retired Tree surface was removed. Current servers do not emit this ID.
    case taxonomy
    case recentlyAdded = "recently_added"
}

struct SpeciesDictionaryCatalogCursor: Codable, Equatable, Hashable {
    let scientificName: String
    let speciesId: String
    let createdAt: String?

    init(scientificName: String, speciesId: String) {
        self.init(scientificName: scientificName, speciesId: speciesId, createdAt: nil)
    }

    init(scientificName: String, speciesId: String, createdAt: String?) {
        self.scientificName = scientificName
        self.speciesId = speciesId
        self.createdAt = createdAt
    }
}

struct SpeciesDictionaryCatalogItem: Decodable, Equatable, Identifiable, Hashable {
    let id: String
    let scientificName: String
    let commonName: String
    let contentQuality: SpeciesDictionaryContentQuality?
    let taxonomy: SpeciesDictionaryTaxonomy?
    let iucnRedListStatus: String?
    let hazardType: String?
    let groupTags: [String]
    let referenceImageUrl: String?
}

struct SpeciesDictionaryOverview: Decodable, Equatable {
    let featuredSpecies: SpeciesDictionaryFeaturedSpecies?
    let categories: [SpeciesDictionaryCategorySummary]
    let groups: [SpeciesDictionaryGroupSummary]
    let regions: [SpeciesDictionaryRegionSummary]

    private enum CodingKeys: String, CodingKey {
        case featuredSpecies
        case categories
        case groups
        case regions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        featuredSpecies = try container.decodeIfPresent(SpeciesDictionaryFeaturedSpecies.self, forKey: .featuredSpecies)
        categories = try container.decode([SpeciesDictionaryCategorySummary].self, forKey: .categories)
        groups = try container.decodeIfPresent([SpeciesDictionaryGroupSummary].self, forKey: .groups) ?? []
        regions = try container.decode([SpeciesDictionaryRegionSummary].self, forKey: .regions)
    }
}

struct SpeciesDictionaryFeaturedSpecies: Decodable, Equatable, Identifiable, Hashable {
    let id: String
    let scientificName: String
    let commonName: String
    let overview: String?
    let referenceImageUrl: String?
}

struct SpeciesDictionaryCategorySummary: Decodable, Equatable, Identifiable, Hashable {
    let id: SpeciesDictionaryOverviewCategoryID
    let title: String
    let subtitle: String?
    let count: Int
    let referenceImageUrl: String?
    let region: String?
    let regionCode: String?
}

struct SpeciesDictionaryGroupSummary: Decodable, Equatable, Identifiable, Hashable {
    let id: String
    let title: String
    let count: Int
    let referenceImageUrl: String?
}

struct SpeciesDictionaryRegionSummary: Decodable, Equatable, Identifiable, Hashable {
    let id: String
    let title: String
    let count: Int
    let referenceImageUrl: String?
    let code: String?
}

struct SpeciesDictionaryEntry: Decodable, Equatable, Identifiable {
    let id: String
    let scientificName: String
    let commonName: String
    let contentQuality: SpeciesDictionaryContentQuality?
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
}

enum SpeciesDictionaryContentQuality: String, Decodable, Equatable, Hashable {
    case complete
    case sparse
    case needsEnrichment = "needs_enrichment"
}

struct SpeciesDictionaryTaxonomy: Decodable, Equatable, Hashable {
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

struct SpeciesDictionaryReferenceImage: Decodable, Equatable, Sendable {
    enum Source: Decodable, Equatable, Sendable {
        case wikipedia
        case gbif
        case merian
        case unknown(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            switch rawValue {
            case "wikipedia":
                self = .wikipedia
            case "gbif":
                self = .gbif
            case "merian":
                self = .merian
            default:
                self = .unknown(rawValue)
            }
        }
    }

    let url: String
    let source: Source
    let license: String?
    let attribution: String?
    let authorUserId: String?
    let authorUsername: String?
    let width: Int?
    let height: Int?

    init(
        url: String,
        source: Source,
        license: String?,
        attribution: String?,
        authorUserId: String? = nil,
        authorUsername: String? = nil,
        width: Int?,
        height: Int?
    ) {
        self.url = url
        self.source = source
        self.license = license
        self.attribution = attribution
        self.authorUserId = authorUserId
        self.authorUsername = authorUsername
        self.width = width
        self.height = height
    }
}

struct SpeciesDictionarySimilarSpecies: Decodable, Equatable {
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
