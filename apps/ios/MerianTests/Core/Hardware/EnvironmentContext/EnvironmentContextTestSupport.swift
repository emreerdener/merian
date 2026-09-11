import CoreLocation
import Foundation

@testable import Merian

@MainActor
final class EnvironmentLocationHardwareProbe {
    var authorizationStatus: CLAuthorizationStatus
    private(set) var configureCount = 0
    private(set) var authorizationRequestCount = 0
    private(set) var locationRequestCount = 0
    private(set) var startUpdatingCount = 0
    private(set) var stopUpdatingCount = 0
    private(set) var profiles:
        [(CLLocationAccuracy, CLLocationDistance)] = []

    init(authorizationStatus: CLAuthorizationStatus) {
        self.authorizationStatus = authorizationStatus
    }

    func hardware() -> EnvironmentLocationHardware {
        EnvironmentLocationHardware(
            authorizationStatus: { [weak self] in
                self?.authorizationStatus ?? .notDetermined
            },
            configure: { [weak self] _ in self?.configureCount += 1 },
            requestWhenInUseAuthorization: { [weak self] in
                self?.authorizationRequestCount += 1
            },
            requestLocation: { [weak self] in
                self?.locationRequestCount += 1
            },
            startUpdatingLocation: { [weak self] in
                self?.startUpdatingCount += 1
            },
            stopUpdatingLocation: { [weak self] in
                self?.stopUpdatingCount += 1
            },
            applyProfile: { [weak self] accuracy, distance in
                self?.profiles.append((accuracy, distance))
            }
        )
    }
}

actor EnvironmentContextWaitGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    var waiterCount: Int { waiters.count }

    func releaseFirst() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }

    func releaseAll() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

@MainActor
final class EnvironmentPlacemarkProbe {
    private(set) var locations: [CLLocation] = []
    var result: EnvironmentPlacemark?
    var waitGate: EnvironmentContextWaitGate?

    init(result: EnvironmentPlacemark?) {
        self.result = result
    }

    func resolve(_ location: CLLocation) async -> EnvironmentPlacemark? {
        locations.append(location)
        if let waitGate {
            await waitGate.wait()
        }
        return result
    }
}

@MainActor
final class EnvironmentWeatherProbe {
    private(set) var currentLocations: [CLLocation] = []
    private(set) var historicalRequests: [(CLLocation, Date)] = []
    var currentReading: EnvironmentWeatherReading?
    var historicalReading: EnvironmentWeatherReading?
    var currentThrows = false
    var historicalThrows = false
    var currentWaitGate: EnvironmentContextWaitGate?

    func loadCurrent(
        _ location: CLLocation
    ) async throws -> EnvironmentWeatherReading {
        currentLocations.append(location)
        if let currentWaitGate {
            await currentWaitGate.wait()
        }
        if currentThrows { throw EnvironmentContextTestError() }
        guard let currentReading else { throw EnvironmentContextTestError() }
        return currentReading
    }

    func loadHistorical(
        _ location: CLLocation,
        _ date: Date
    ) async throws -> EnvironmentWeatherReading? {
        historicalRequests.append((location, date))
        if historicalThrows { throw EnvironmentContextTestError() }
        return historicalReading
    }
}

func syntheticEnvironmentLocation(
    latitude: CLLocationDegrees = 10,
    longitude: CLLocationDegrees = 20,
    horizontalAccuracy: CLLocationAccuracy = 10
) -> CLLocation {
    CLLocation(
        coordinate: CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        ),
        altitude: 0,
        horizontalAccuracy: horizontalAccuracy,
        verticalAccuracy: 0,
        timestamp: Date(timeIntervalSince1970: 1_000)
    )
}

func environmentLocationsMatch(
    _ lhs: CLLocation?,
    _ rhs: CLLocation?
) -> Bool {
    guard let lhs, let rhs else { return lhs == nil && rhs == nil }
    return lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.horizontalAccuracy == rhs.horizontalAccuracy
}

struct EnvironmentContextTestError: Error {}

@MainActor
func waitForEnvironmentCondition(
    _ condition: @escaping @MainActor () async -> Bool
) async throws {
    for _ in 0..<200 {
        if await condition() { return }
        await Task.yield()
        try await Task.sleep(for: .milliseconds(5))
    }
    throw EnvironmentContextTestError()
}
