import MapKit

struct MapPlaceSearchConfiguration {
    let dependencies: MapPlaceSearchDependencies
    let history: RecentPlaceStore
}

struct MapPlaceSuggestion: Identifiable {
    let id = UUID()
    let label: RecentPlace
    let completion: MKLocalSearchCompletion?
}

struct MapPlaceResult: Identifiable {
    let id = UUID()
    let label: RecentPlace
    let item: MKMapItem
}

@MainActor
struct MapPlaceSearchDependencies {
    var suggest: (String) async throws -> [MapPlaceSuggestion]
    var resolve: (MapPlaceSuggestion) async throws -> [MapPlaceResult]
    var search: (String) async throws -> [MapPlaceResult]
    var debounce: () async throws -> Void

    static var live: Self {
        Self(
            suggest: { query in try await MapCompletionRequest().results(for: query) },
            resolve: { suggestion in
                let request = suggestion.completion.map { MKLocalSearch.Request(completion: $0) }
                    ?? MKLocalSearch.Request()
                if suggestion.completion == nil { request.naturalLanguageQuery = suggestion.label.searchText }
                return try await MapPlaceSearchService.results(for: request)
            },
            search: { query in
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                return try await MapPlaceSearchService.results(for: request)
            },
            debounce: { try await Task.sleep(for: .milliseconds(300)) }
        )
    }
}

@MainActor
private enum MapPlaceSearchService {
    static func results(for request: MKLocalSearch.Request) async throws -> [MapPlaceResult] {
        request.resultTypes = [.address, .pointOfInterest]
        let search = MKLocalSearch(request: request)
        let response = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await search.start()
        } onCancel: {
            Task { @MainActor in search.cancel() }
        }
        try Task.checkCancellation()
        return response.mapItems.filter {
            CLLocationCoordinate2DIsValid($0.placemark.coordinate)
        }.map { item in
            MapPlaceResult(
                label: RecentPlace(
                    title: item.name ?? "Location",
                    subtitle: item.placemark.title ?? ""
                ),
                item: item
            )
        }
    }
}

/// One completer per request makes delegate callbacks unambiguous after cancellation.
@MainActor
private final class MapCompletionRequest: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var continuation: CheckedContinuation<[MapPlaceSuggestion], Error>?

    func results(for query: String) async throws -> [MapPlaceSuggestion] {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                completer.delegate = self
                completer.resultTypes = [.address, .pointOfInterest]
                completer.queryFragment = query
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            finish(.success(self.completer.results.map {
                MapPlaceSuggestion(label: RecentPlace(title: $0.title, subtitle: $0.subtitle), completion: $0)
            }))
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.finish(.failure(error)) }
    }

    private func finish(_ result: Result<[MapPlaceSuggestion], Error>) {
        let pending = continuation
        continuation = nil
        completer.delegate = nil
        completer.cancel()
        pending?.resume(with: result)
    }
}
