struct SpeciesDictionaryDetailRequest: Equatable {
    let speciesId: String?
    let scientificName: String?

    init(speciesId: String?, scientificName: String?) {
        self.speciesId = SpeciesDictionaryIdentity.canonicalSpeciesID(
            speciesId
        )
        self.scientificName = SpeciesDictionaryIdentity
            .normalizedScientificName(scientificName)
    }
}

enum SpeciesDictionaryPageLoadFailure: Equatable {
    case notFound
    case message(String)
}

enum SpeciesDictionaryDetailTelemetryEvent: Equatable {
    case opened(entryPoint: String)
    case loaded(entryPoint: String, contentQuality: String)
    case notFound(entryPoint: String)
    case retry(entryPoint: String)
    case imageFallback(entryPoint: String, source: String)
    case fieldChatTapped(
        entryPoint: String,
        contentQuality: String,
        isPro: Bool
    )
}
