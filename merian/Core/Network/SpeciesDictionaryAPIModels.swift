import Foundation

struct SpeciesDictionaryResponse: Decodable {
    let data: SpeciesDictionaryEntry
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
                speciesId: item.speciesId
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

    var id: String { url }
}

struct SpeciesDictionarySimilarSpecies: Decodable, Equatable, Identifiable {
    let speciesId: String?
    let scientificName: String
    let commonName: String?
    let referenceImageUrl: String?
    let iucnRedListStatus: String?

    var id: String { speciesId ?? scientificName }
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
