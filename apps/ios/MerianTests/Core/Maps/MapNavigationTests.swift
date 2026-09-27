import CoreLocation
import MapKit
@testable import Merian
import Testing

@MainActor
@Suite("Map navigation")
struct MapNavigationTests {
    @Test func dismissedSearchRejectsDelayedResults() async throws {
        let pending = PendingPlaceResults()
        let model = MapPlaceSearchModel(dependencies: dependencies(search: pending.wait))
        model.begin(owner: UUID())
        model.query = "Synthetic park"
        model.submit()
        await pending.started()
        model.end()
        pending.resume([result()])
        await drain()
        #expect(model.results.isEmpty)
        #expect(model.selectedResult == nil)
        #expect(!model.isLoading)
    }

    @Test func newerQueryAndAccountSwitchRejectPreviousResults() async {
        let pending = PendingPlaceResults()
        let model = MapPlaceSearchModel(dependencies: dependencies(search: pending.wait))
        model.begin(owner: UUID())
        model.query = "First query"
        model.submit()
        await pending.started()
        model.query = ""
        model.queryChanged()
        model.begin(owner: UUID())
        pending.resume([result()])
        await drain()
        #expect(model.results.isEmpty)
        #expect(model.recents.isEmpty)
    }

    @Test func accountPurgeCannotBeUndoneByDelayedResolution() async throws {
        let name = "merian.tests.search-purge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = RecentPlaceStore(defaults: defaults)
        let pending = PendingPlaceResults()
        let model = MapPlaceSearchModel(dependencies: dependencies(search: pending.wait), store: store)
        let owner = UUID()
        model.begin(owner: owner)
        model.resolve(RecentPlace(title: "Synthetic park", subtitle: "Test region"))
        await pending.started()
        #expect(AccountScopedPreferences.purgeAndVerify(userDefaults: defaults))
        pending.resume([result()])
        await drain()
        #expect(model.selectedResult == nil)
        #expect(store.places(for: owner).isEmpty)
    }

    @Test func recentAmbiguityRequiresSelectionAndFailureKeepsCameraUnselected() async {
        let model = MapPlaceSearchModel(dependencies: dependencies(search: { _ in [result(), result()] }))
        model.begin(owner: nil)
        model.resolve(RecentPlace(title: "Synthetic park", subtitle: "Test region"))
        await drain()
        #expect(model.results.count == 2)
        #expect(model.selectedResult == nil)
        if let first = model.results.first { model.select(first) }
        #expect(model.selectedResult != nil)
        let failing = MapPlaceSearchModel(dependencies: dependencies(search: { _ in
            throw URLError(.notConnectedToInternet)
        }))
        failing.begin(owner: nil)
        failing.query = "Synthetic park"
        failing.submit()
        await drain()
        #expect(failing.errorMessage?.contains("offline") == true)
        #expect(failing.selectedResult == nil)
    }

    @Test func presentationInvalidationRejectsAResolvedPlaceBeforeViewUpdates() async {
        let pending = PendingPlaceResults()
        let model = MapPlaceSearchModel(dependencies: dependencies(search: pending.wait))
        var isCurrent = true
        model.begin(owner: nil, isCurrent: { isCurrent })
        model.resolve(RecentPlace(title: "Synthetic park", subtitle: "Test region"))
        await pending.started()
        isCurrent = false
        pending.resume([result()])
        await drain()
        #expect(model.selectedResult == nil)
        #expect(model.results.isEmpty)
    }

    @Test func debounceAndQueryReplacementRetireOlderSuggestions() async {
        let gate = PendingPlaceResults()
        var suggestionQueries: [String] = []
        var deps = dependencies(search: { _ in [] })
        deps.debounce = { _ = await gate.wait("") }
        deps.suggest = { query in
            suggestionQueries.append(query)
            return []
        }
        let model = MapPlaceSearchModel(dependencies: deps)
        model.begin(owner: nil)
        model.query = "Old query"
        model.queryChanged()
        await gate.started()
        #expect(suggestionQueries.isEmpty)
        model.query = ""
        model.queryChanged()
        gate.resume([])
        await drain()
        #expect(suggestionQueries.isEmpty)
        #expect(model.suggestions.isEmpty)
        #expect(!model.hasSearched)
    }

    @Test func lateLocateCannotOverrideSearchOrUserMovement() async {
        let pending = PendingLocation()
        let model = MapNavigationModel()
        var applied = false
        model.locate(request: pending.wait, authorization: { .authorizedWhenInUse }) { _ in applied = true }
        await pending.started()
        model.openSearch(owner: nil)
        pending.resume(CLLocation(latitude: 1, longitude: 1)) // Synthetic ocean location.
        await drain()
        #expect(!applied)
        #expect(!model.isLocating)
        #expect(model.isSearchPresented)
    }

    @Test func deniedAndUnavailableLocationLeaveCameraUntouched() async {
        for status in [CLAuthorizationStatus.denied, .restricted, .authorizedWhenInUse] {
            let model = MapNavigationModel()
            var applied = false
            model.locate(request: { nil }, authorization: { status }) { _ in applied = true }
            await drain()
            #expect(!applied)
            #expect(model.locationAlert == (status == .denied ? .denied : .unavailable))
        }
    }

    private func dependencies(
        search: @escaping @MainActor (String) async throws -> [MapPlaceResult]
    ) -> MapPlaceSearchDependencies {
        MapPlaceSearchDependencies(suggest: { _ in [] }, resolve: { _ in try await search("") },
                                   search: search, debounce: {})
    }

    private func result() -> MapPlaceResult {
        // Deliberately synthetic ocean coordinate, never a personal address.
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1)))
        return MapPlaceResult(label: RecentPlace(title: "Synthetic park", subtitle: "Test region"), item: item)
    }

    private func drain() async { for _ in 0..<20 { await Task.yield() } }
}

@MainActor
private final class PendingPlaceResults {
    private var continuation: CheckedContinuation<[MapPlaceResult], Never>?
    func wait(_ query: String) async -> [MapPlaceResult] {
        await withCheckedContinuation { continuation = $0 }
    }
    func started() async { while continuation == nil { await Task.yield() } }
    func resume(_ results: [MapPlaceResult]) { continuation?.resume(returning: results); continuation = nil }
}

@MainActor
private final class PendingLocation {
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    func wait() async -> CLLocation? { await withCheckedContinuation { continuation = $0 } }
    func started() async { while continuation == nil { await Task.yield() } }
    func resume(_ location: CLLocation?) { continuation?.resume(returning: location); continuation = nil }
}
