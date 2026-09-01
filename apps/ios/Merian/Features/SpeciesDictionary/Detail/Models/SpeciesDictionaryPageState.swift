enum SpeciesDictionaryPageState: Equatable {
    case idle
    case loading
    case loaded(SpeciesDictionaryEntry)
    case notFound
    case error(String)
}
