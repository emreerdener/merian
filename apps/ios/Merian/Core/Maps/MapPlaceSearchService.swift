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
    let region: MKCoordinateRegion?

    init(label: RecentPlace, item: MKMapItem, region: MKCoordinateRegion? = nil) {
        self.label = label
        self.item = item
        self.region = MapPlaceViewport.region(for: item, responseRegion: region)
    }
}

enum MapPlaceViewport {
    static func region(for item: MKMapItem, responseRegion: MKCoordinateRegion?) -> MKCoordinateRegion? {
        let coordinate = item.placemark.coordinate
        if let responseRegion, isValid(responseRegion, containing: coordinate) {
            return padded(responseRegion)
        }
        guard let circle = item.placemark.region as? CLCircularRegion,
              CLLocationCoordinate2DIsValid(circle.center),
              circle.radius.isFinite, circle.radius > 0 else { return nil }
        let diameter = circle.radius * 2
        guard diameter.isFinite else { return nil }
        let region = MKCoordinateRegion(
            center: circle.center,
            latitudinalMeters: diameter,
            longitudinalMeters: diameter
        )
        return isValid(region, containing: coordinate) ? padded(region) : nil
    }

    private static func isValid(_ region: MKCoordinateRegion, containing coordinate: CLLocationCoordinate2D) -> Bool {
        guard CLLocationCoordinate2DIsValid(coordinate), CLLocationCoordinate2DIsValid(region.center),
              region.span.latitudeDelta.isFinite, region.span.longitudeDelta.isFinite,
              region.span.latitudeDelta > 0, region.span.latitudeDelta <= 180,
              region.span.longitudeDelta > 0, region.span.longitudeDelta <= 360 else { return false }
        let longitudeDistance = abs(coordinate.longitude - region.center.longitude)
            .truncatingRemainder(dividingBy: 360)
        return abs(coordinate.latitude - region.center.latitude) <= region.span.latitudeDelta / 2
            && min(longitudeDistance, 360 - longitudeDistance) <= region.span.longitudeDelta / 2
    }

    private static func padded(_ region: MKCoordinateRegion) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: min(region.span.latitudeDelta * 1.1, 180),
                longitudeDelta: min(region.span.longitudeDelta * 1.1, 360)
            )
        )
    }

    static func results(items: [MKMapItem], boundingRegion: MKCoordinateRegion) -> [MapPlaceResult] {
        items.filter { CLLocationCoordinate2DIsValid($0.placemark.coordinate) }.map { item in
            MapPlaceResult(
                label: RecentPlace(title: item.name ?? "Location", subtitle: item.placemark.title ?? ""),
                item: item,
                // A multi-result response encloses every match, not the selected place.
                region: items.count == 1 ? boundingRegion : nil
            )
        }
    }
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
        return MapPlaceViewport.results(items: response.mapItems, boundingRegion: response.boundingRegion)
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
