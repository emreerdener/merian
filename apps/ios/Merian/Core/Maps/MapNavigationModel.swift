import CoreLocation
import MapKit
import Observation

@MainActor
@Observable
final class MapNavigationModel {
    enum LocationAlert: String, Identifiable {
        case denied, unavailable
        var id: String { rawValue }
    }

    let search: MapPlaceSearchModel
    var isSearchPresented = false
    var locationAlert: LocationAlert?
    private(set) var isLocating = false
    private(set) var generation = 0
    @ObservationIgnored private var locationTask: Task<Void, Never>?

    init(search: MapPlaceSearchModel? = nil) {
        self.search = search ?? MapPlaceSearchModel()
    }

    func openSearch(owner: UUID?, isCurrent: @escaping @MainActor () -> Bool = { true }) {
        cancelNavigation()
        search.begin(owner: owner, isCurrent: isCurrent)
        isSearchPresented = true
    }

    func cancelNavigation() {
        generation += 1
        locationTask?.cancel()
        locationTask = nil
        isLocating = false
    }

    func reset() {
        cancelNavigation()
        isSearchPresented = false
        locationAlert = nil
        search.end()
    }

    func locate(
        request: @escaping @MainActor () async -> CLLocation?,
        authorization: @escaping @MainActor () -> CLAuthorizationStatus,
        isCurrent: @escaping @MainActor () -> Bool = { true },
        onLocation: @escaping @MainActor (CLLocation) -> Void
    ) {
        guard !isLocating else { return }
        cancelNavigation()
        let admittedGeneration = generation
        let historyGeneration = search.historyResetGeneration
        isLocating = true
        locationTask = Task { [weak self] in
            let location = await request()
            guard let self, !Task.isCancelled, generation == admittedGeneration else { return }
            isLocating = false
            guard isCurrent(), historyGeneration == search.historyResetGeneration else { return }
            guard let location, CLLocationCoordinate2DIsValid(location.coordinate) else {
                locationAlert = authorization() == .denied ? .denied : .unavailable
                return
            }
            onLocation(location)
        }
    }
}
