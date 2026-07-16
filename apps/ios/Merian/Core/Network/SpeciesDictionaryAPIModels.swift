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

struct SpeciesDictionaryTreeResponse: Decodable {
    let schemaVersion: Int?
    let data: SpeciesDictionaryTreePayload

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
    case taxonomy
    case recentlyAdded = "recently_added"
}

enum SpeciesDictionaryTreeScope: String, CaseIterable, Codable, Equatable, Hashable {
    case allSpecies = "all_species"
    case myScans = "my_scans"

    var title: String {
        switch self {
        case .allSpecies: "All species"
        case .myScans: "My scans"
        }
    }
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

    var dictionaryRoute: SpeciesDictionaryRoute {
        SpeciesDictionaryRoute(
            scientificName: scientificName,
            speciesId: id,
            entryPoint: .exploreDictionaryCatalog
        )
    }
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

    var dictionaryRoute: SpeciesDictionaryRoute {
        SpeciesDictionaryRoute(
            scientificName: scientificName,
            speciesId: id,
            entryPoint: .exploreDictionaryCatalog
        )
    }
}

struct SpeciesDictionaryCategorySummary: Decodable, Equatable, Identifiable, Hashable {
    let id: SpeciesDictionaryOverviewCategoryID
    let title: String
    let subtitle: String?
    let count: Int
    let referenceImageUrl: String?
    let region: String?
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
}

struct SpeciesDictionaryTreePayload: Decodable, Equatable {
    let nodes: [SpeciesDictionaryTreeNodePayload]
    let edges: [SpeciesDictionaryTreeEdgePayload]
}

enum SpeciesDictionaryTreeRank: String, CaseIterable, Decodable, Equatable, Hashable {
    case kingdom
    case phylum
    case className = "class"
    case order
    case family
    case genus
    case species

    var title: String {
        switch self {
        case .kingdom: "Kingdom"
        case .phylum: "Phylum"
        case .className: "Class"
        case .order: "Order"
        case .family: "Family"
        case .genus: "Genus"
        case .species: "Species"
        }
    }

    var sortIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

struct SpeciesDictionaryTreeNodePayload: Decodable, Equatable, Identifiable, Hashable {
    let id: String
    let rank: SpeciesDictionaryTreeRank
    let title: String
    let subtitle: String?
    let parentId: String?
    let speciesCount: Int
    let childCount: Int
    let lineage: SpeciesDictionaryTaxonomy?
    let representativeSpecies: SpeciesDictionaryTreeSpecies?
    let species: SpeciesDictionaryTreeSpecies?
}

struct SpeciesDictionaryTreeEdgePayload: Decodable, Equatable, Identifiable, Hashable {
    let from: String
    let to: String

    var id: String { "\(from)->\(to)" }
}

struct SpeciesDictionaryTreeSpecies: Decodable, Equatable, Identifiable, Hashable {
    let id: String
    let scientificName: String
    let commonName: String
    let contentQuality: SpeciesDictionaryContentQuality?
    let taxonomy: SpeciesDictionaryTaxonomy?
    let iucnRedListStatus: String?
    let hazardType: String?
    let groupTags: [String]
    let referenceImageUrl: String?

    var dictionaryRoute: SpeciesDictionaryRoute {
        SpeciesDictionaryRoute(
            scientificName: scientificName,
            speciesId: id,
            entryPoint: .exploreDictionaryCatalog
        )
    }
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

    var effectiveContentQuality: SpeciesDictionaryContentQuality {
        if let contentQuality { return contentQuality }

        let signalCount = [
            !referenceImages.isEmpty,
            (wikipediaOverview?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) >= 60,
            habitatDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil || gbifTaxonKey != nil,
            taxonomy?.hasMeaningfulContent == true
        ].filter { $0 }.count

        if signalCount == 4 { return .complete }
        if signalCount >= 2 { return .sparse }
        return .needsEnrichment
    }

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

enum SpeciesDictionaryContentQuality: String, Decodable, Equatable, Hashable {
    case complete
    case sparse
    case needsEnrichment = "needs_enrichment"

    var telemetryValue: String { rawValue }
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

    var hasMeaningfulContent: Bool {
        [
            kingdom,
            phylum,
            className,
            order,
            family,
            genus
        ].compactMap { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }.count >= 2
    }
}

struct SpeciesDictionaryReferenceImage: Decodable, Equatable, Identifiable {
    enum Source: Decodable, Equatable {
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

        var label: String {
            switch self {
            case .wikipedia:
                return "Wikipedia"
            case .gbif:
                return "GBIF"
            case .merian:
                return "Naturebook"
            case .unknown:
                return "Reference"
            }
        }

        var rawValue: String {
            switch self {
            case .wikipedia:
                return "wikipedia"
            case .gbif:
                return "gbif"
            case .merian:
                return "merian"
            case .unknown(let value):
                return value
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

    var attributionCaption: String? {
        [
            attribution?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            license?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
        .nilIfEmpty
    }
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

struct SpeciesDictionaryRoute: Identifiable, Equatable, Hashable {
    let speciesId: String?
    let scientificName: String
    let entryPoint: SpeciesDictionaryEntryPoint

    init(
        scientificName: String,
        speciesId: String? = nil,
        entryPoint: SpeciesDictionaryEntryPoint = .unknown
    ) {
        self.speciesId = speciesId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.scientificName = scientificName
        self.entryPoint = entryPoint
    }

    var id: String { speciesId ?? scientificName }
}

enum SpeciesDictionaryEntryPoint: String, Equatable, Hashable {
    case insightSimilarSpecies = "insight_similar_species"
    case exploreDetailDictionary = "explore_detail_dictionary"
    case exploreDetailSimilarSpecies = "explore_detail_similar_species"
    case exploreDictionaryCatalog = "explore_dictionary_catalog"
    case speciesDictionarySimilarSpecies = "species_dictionary_similar_species"
    case search
    case deepLink = "deep_link"
    case web
    case unknown
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
