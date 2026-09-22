import Foundation
import Observation

@MainActor @Observable
final class SpeciesSearchViewModel {
    struct Dependencies {
        let search: (SpeciesSearchRequest) async throws -> SpeciesSearchResponse
        let errorMessage: (Error) -> String
        var starterCatalog: SpeciesDictionaryCatalogViewModel.Dependencies = .init(
            loadPage: { _ in .init(schemaVersion: 1, data: [], nextCursor: nil) },
            errorMessage: { _ in "Species suggestions are unavailable." }
        )
    }
    let starterCatalog: SpeciesDictionaryCatalogViewModel
    private(set) var suggestedPrompts: [String]
    private(set) var illustrationName = "bird-magnifier"
    private static let illustrationPool = [
        "bird-magnifier", "butterfly-monarch", "fern", "frog", "mushroom", "blue-bird"
    ]
    private static let promptPool = [
        "Small birds with red heads", "Orange and black butterflies", "Fungi that grow on trees",
        "Flowers with purple petals", "Beetles with metallic shells", "Birds with long beaks",
        "Plants with heart-shaped leaves", "Mushrooms with spotted caps", "Moths with patterned wings",
        "Frogs with striped backs", "Trees with peeling bark", "Insects that look like leaves"
    ]
    var draft = ""
    var resultsScrollID: String?
    private(set) var context: SpeciesSearchContext?
    private(set) var interpretation = ""
    private(set) var notice: String?
    private(set) var errorMessage: String?
    private(set) var species: [SpeciesSearchMatch] = []
    private(set) var sightings: [ExplorePost] = []
    private(set) var request: SpeciesSearchRequest?
    private(set) var isLoading = false
    private(set) var generation = UUID()
    private var loadedSections: Set<SpeciesSearchResultKind> = []
    private var cursors: [SpeciesSearchResultKind: SpeciesSearchCursor] = [:]
    private var isReplacement = false
    private var clarificationContext: SpeciesSearchContext?
    @ObservationIgnored private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        starterCatalog = SpeciesDictionaryCatalogViewModel(pageLimit: 6, dependencies: dependencies.starterCatalog)
        suggestedPrompts = Array(Self.promptPool.shuffled().prefix(3))
    }
    convenience init() { self.init(dependencies: .live) }
    var hasResults: Bool { context != nil }
    var needsClarification: Bool { clarificationContext != nil }
    func hasMore(_ kind: SpeciesSearchResultKind) -> Bool {
        cursors[kind] != nil && !isLoading && errorMessage == nil
    }
    func hasLoaded(_ kind: SpeciesSearchResultKind) -> Bool { loadedSections.contains(kind) }

    func submit(_ question: String? = nil) {
        let text = (question ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= 600 else { return }
        draft = text
        begin(question: text, context: clarificationContext ?? context, cursor: nil, replacement: true)
    }
    func retry() {
        guard let request else { return }
        begin(question: request.question, context: request.context, cursor: request.cursor,
              replacement: isReplacement, resultKind: request.resultKind)
    }
    func rotateIllustration() {
        illustrationName = Self.illustrationPool.filter { $0 != illustrationName }.randomElement() ?? illustrationName
    }
    func newSearch() {
        rotateIllustration()
        suggestedPrompts = Array(Self.promptPool.filter { !suggestedPrompts.contains($0) }.shuffled().prefix(3))
        generation = UUID()
        request = nil
        isLoading = false
        context = nil
        clarificationContext = nil
        draft = ""
        interpretation = ""
        notice = nil
        errorMessage = nil
        species = []
        sightings = []
        loadedSections = []
        cursors = [:]
        resultsScrollID = nil
    }
    func setGroup(_ group: SpeciesSearchGroup?) {
        guard var context = filterContext else { return }
        context.group = group
        guard !context.query.isEmpty || group != nil else { newSearch(); return }
        begin(question: nil, context: context, cursor: nil, replacement: true)
    }
    func setMedia(_ media: SpeciesSearchMedia?) {
        guard var context = filterContext else { return }
        context.media = media
        begin(question: nil, context: context, cursor: nil, replacement: true)
    }
    func loadMore(_ kind: SpeciesSearchResultKind) {
        guard hasMore(kind), let context, let cursor = cursors[kind] else { return }
        begin(question: nil, context: context, cursor: cursor, replacement: false, resultKind: kind)
    }
    private var filterContext: SpeciesSearchContext? {
        if isLoading, isReplacement, request?.question == nil { return request?.context ?? context }
        return context
    }
    private func begin(question: String?, context: SpeciesSearchContext?, cursor: SpeciesSearchCursor?, replacement: Bool,
                       resultKind: SpeciesSearchResultKind = .species) {
        generation = UUID()
        isReplacement = replacement
        errorMessage = nil
        if replacement { notice = nil }
        isLoading = true
        request = SpeciesSearchRequest(requestId: UUID().uuidString.lowercased(), question: question,
                                       context: context, resultKind: resultKind, cursor: cursor)
    }
    func execute() async {
        guard isLoading else { return }
        let token = generation
        // Both sections share one interpreted context and one cancellable task.
        while let request {
            let replaces = isReplacement
            do {
                try Task.checkCancellation()
                let response = try await dependencies.search(request)
                guard generation == token else { return }
                try Task.checkCancellation()
                if response.status != .results {
                    isLoading = false
                    notice = response.message
                    clarificationContext = response.status == .clarification ? response.context : nil
                    if response.status == .clarification && draft == request.question { draft = "" }
                    return
                }
                if replaces {
                    clarificationContext = nil
                    species = []
                    sightings = []
                    loadedSections = []
                    cursors = [:]
                    resultsScrollID = nil
                    context = response.context
                    interpretation = response.message
                }
                if request.cursor == nil {
                    if response.resultKind == .species {
                        species = response.species
                    } else {
                        sightings = response.sightings
                    }
                } else {
                    let speciesIDs = Set(species.map(\.id))
                    species += response.species.filter { !speciesIDs.contains($0.id) }
                    let postIDs = Set(sightings.map(\.id))
                    sightings += response.sightings.filter { !postIDs.contains($0.id) }
                }
                loadedSections.insert(response.resultKind)
                cursors[response.resultKind] = response.nextCursor
                if request.question != nil && draft == request.question { draft = "" }
                if let next = SpeciesSearchResultKind.allCases.first(where: { !loadedSections.contains($0) }),
                   let context {
                    // Context-only retrieval does not invoke interpretation again.
                    isReplacement = false
                    self.request = SpeciesSearchRequest(requestId: UUID().uuidString.lowercased(), question: nil,
                                                       context: context, resultKind: next, cursor: nil)
                } else {
                    self.request = nil
                    isLoading = false
                }
            } catch {
                guard generation == token else { return }
                isLoading = false
                errorMessage = Task.isCancelled ? "Search was interrupted. Please retry." : dependencies.errorMessage(error)
                return
            }
        }
    }
}
