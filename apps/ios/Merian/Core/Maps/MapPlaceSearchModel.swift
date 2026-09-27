import MapKit
import Observation

@MainActor
@Observable
final class MapPlaceSearchModel {
    var query = ""
    private(set) var suggestions: [MapPlaceSuggestion] = []
    private(set) var results: [MapPlaceResult] = []
    private(set) var recents: [RecentPlace] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasSearched = false
    private(set) var selectedResult: MapPlaceResult?
    @ObservationIgnored private var resetGeneration = 0
    @ObservationIgnored private var owner: UUID?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var dependencies: MapPlaceSearchDependencies
    @ObservationIgnored private var store: RecentPlaceStore
    @ObservationIgnored private var retryAction: RetryAction = .query
    @ObservationIgnored private var isPresentationCurrent: @MainActor () -> Bool = { true }

    var historyResetGeneration: Int { store.resetGeneration }

    private enum RetryAction {
        case query, submit, suggestion(MapPlaceSuggestion), recent(RecentPlace)
    }

    func retry() {
        switch retryAction {
        case .query: queryChanged()
        case .submit: submit()
        case .suggestion(let suggestion): resolve(suggestion)
        case .recent(let recent): resolve(recent)
        }
    }

    init(dependencies: MapPlaceSearchDependencies? = nil, store: RecentPlaceStore = RecentPlaceStore()) {
        self.dependencies = dependencies ?? .live
        self.store = store
    }

    func configure(_ configuration: MapPlaceSearchConfiguration) {
        end()
        dependencies = configuration.dependencies
        store = configuration.history
    }

    func begin(owner: UUID?, isCurrent: @escaping @MainActor () -> Bool = { true }) {
        end()
        isPresentationCurrent = isCurrent
        resetGeneration = store.resetGeneration
        self.owner = owner
        recents = store.places(for: owner)
    }

    func isCurrent(owner: UUID?) -> Bool {
        self.owner == owner && resetGeneration == store.resetGeneration && isPresentationCurrent()
    }

    func end() {
        cancel()
        retryAction = .query
        query = ""
        suggestions = []
        results = []
        recents = []
        selectedResult = nil
        errorMessage = nil
        hasSearched = false
        owner = nil
        isPresentationCurrent = { false }
    }

    func queryChanged() {
        retryAction = .query
        cancel()
        suggestions = []
        results = []
        selectedResult = nil
        errorMessage = nil
        hasSearched = false
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        run {
            try await self.dependencies.debounce()
            try Task.checkCancellation()
            let suggestions = try await self.dependencies.suggest(text)
            return .suggestions(suggestions)
        }
    }

    func submit() {
        retryAction = .submit
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        run { .results(try await self.dependencies.search(text), selectsSingle: false) }
    }

    func resolve(_ suggestion: MapPlaceSuggestion) {
        retryAction = .suggestion(suggestion)
        run { .results(try await self.dependencies.resolve(suggestion), selectsSingle: true) }
    }

    func resolve(_ recent: RecentPlace) {
        retryAction = .recent(recent)
        run { .results(try await self.dependencies.search(recent.searchText), selectsSingle: true) }
    }

    func select(_ result: MapPlaceResult) {
        guard resetGeneration == store.resetGeneration, isPresentationCurrent() else { end(); return }
        guard CLLocationCoordinate2DIsValid(result.item.placemark.coordinate) else { return }
        cancel()
        store.record(result.label, for: owner)
        selectedResult = result
    }

    func remove(_ recent: RecentPlace) {
        store.remove(recent, for: owner)
        recents = store.places(for: owner)
    }

    func clearRecents() {
        cancel()
        store.clear(for: owner)
        recents = []
    }

    private enum Response {
        case suggestions([MapPlaceSuggestion])
        case results([MapPlaceResult], selectsSingle: Bool)
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Response) {
        cancel()
        let requestGeneration = generation
        isLoading = true
        errorMessage = nil
        suggestions = []
        results = []
        task = Task { [weak self] in
            do {
                let response = try await operation()
                guard let self, !Task.isCancelled, generation == requestGeneration else { return }
                guard resetGeneration == store.resetGeneration, isPresentationCurrent() else { end(); return }
                isLoading = false
                hasSearched = true
                switch response {
                case .suggestions(let values): suggestions = values
                case .results(let values, let selectsSingle):
                    results = values
                    if selectsSingle, values.count == 1, let value = values.first { select(value) }
                }
            } catch {
                guard let self, !Task.isCancelled, generation == requestGeneration else { return }
                guard resetGeneration == store.resetGeneration, isPresentationCurrent() else { end(); return }
                isLoading = false
                hasSearched = true
                let error = error as NSError
                if error.domain == MKErrorDomain, error.code == MKError.placemarkNotFound.rawValue {
                    errorMessage = nil
                } else if error.domain == NSURLErrorDomain, error.code == NSURLErrorNotConnectedToInternet {
                    errorMessage = "You’re offline. Connect to the internet to search for places."
                } else {
                    errorMessage = "Places couldn’t be loaded. Please try again."
                }
            }
        }
    }

    private func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isLoading = false
    }
}
