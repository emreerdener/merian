struct SpeciesDictionaryRoute: Identifiable, Equatable, Hashable {
    let speciesId: String?
    let scientificName: String
    let entryPoint: SpeciesDictionaryEntryPoint

    init(
        scientificName: String,
        speciesId: String? = nil,
        entryPoint: SpeciesDictionaryEntryPoint = .unknown
    ) {
        self.speciesId = SpeciesDictionaryIdentity.canonicalSpeciesID(
            speciesId
        )
        self.scientificName = SpeciesDictionaryIdentity
            .normalizedScientificName(scientificName) ?? ""
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
