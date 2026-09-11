import CoreLocation
import Foundation
import Observation

// MARK: - Environment Context Facade

/// Lazily retrieves GPS and WeatherKit data only when triggered by a scan.
/// Follows a deferred context-fetch model to minimize battery impact.
@MainActor
@Observable
final class EnvironmentContextManager: NSObject {
    struct Dependencies {
        let locationController: EnvironmentLocationController
        let geocodingService: EnvironmentGeocodingService
        let weatherService: EnvironmentWeatherService
        let suppressesLocationPermissionPrompt: @MainActor () -> Bool
        let displayLocationName: @MainActor (String?) -> String?

        @MainActor static var live: Self {
            Self(
                locationController: EnvironmentLocationController(),
                geocodingService: EnvironmentGeocodingService(),
                weatherService: .live,
                suppressesLocationPermissionPrompt: {
                    UITestSeedCoordinator.isLocationPermissionPromptSuppressed
                },
                displayLocationName: ExploreLocationPrivacy.displayLabel
            )
        }
    }

    static let shared = EnvironmentContextManager(dependencies: .live)

    @ObservationIgnored private let dependencies: Dependencies
    private(set) var isAuthorized: Bool
    private(set) var locationAuthorizationStatus: CLAuthorizationStatus
    private(set) var cachedLocation: CLLocation?
    private(set) var fallbackInaccurateLocation: CLLocation?

    /// Best currently authorized location: accurate lock preferred, then the
    /// latest coarse fallback. Cached coordinates remain private while access
    /// is not authorized.
    var lastKnownLocation: CLLocation? {
        guard isAuthorized else { return nil }
        return cachedLocation ?? fallbackInaccurateLocation
    }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        let initialSnapshot = dependencies.locationController.snapshot
        isAuthorized = initialSnapshot.isAuthorized
        locationAuthorizationStatus = initialSnapshot.authorizationStatus
        cachedLocation = initialSnapshot.cachedLocation
        fallbackInaccurateLocation =
            initialSnapshot.fallbackInaccurateLocation
        super.init()

        dependencies.locationController.setSnapshotHandler { [weak self] in
            self?.apply($0)
        }
    }

    nonisolated static func shouldRequestLocationAuthorization(
        for status: CLAuthorizationStatus,
        suppressesLocationPermissionPrompt: Bool
    ) -> Bool {
        EnvironmentLocationPolicy.shouldRequestAuthorization(
            for: status,
            suppressesPrompt: suppressesLocationPermissionPrompt
        )
    }

    nonisolated static func allowsPassiveRegionResolution(
        for status: CLAuthorizationStatus
    ) -> Bool {
        EnvironmentLocationPolicy.isAuthorized(status)
    }

    nonisolated static func normalizedRegionIdentifier(
        _ value: String?
    ) -> String? {
        EnvironmentLocationPolicy.normalizedRegionIdentifier(value)
    }

    func validatePermissions() {
        dependencies.locationController.validatePermissions(
            suppressesPrompt:
                dependencies.suppressesLocationPermissionPrompt()
        )
    }

    func requestLocationAuthorizationIfNeeded() async
        -> CLAuthorizationStatus {
        await dependencies.locationController.requestAuthorizationIfNeeded(
            suppressesPrompt:
                dependencies.suppressesLocationPermissionPrompt()
        )
    }

    func requestCurrentLocation() async -> CLLocation? {
        await dependencies.locationController.requestCurrentLocation(
            suppressesPrompt:
                dependencies.suppressesLocationPermissionPrompt()
        )
    }

    /// Resolves the user's physical ISO country/region code only when location
    /// access is already authorized. Passive surfaces never present a prompt.
    func currentAuthorizedRegionIdentifier() async -> String? {
        guard let location = await dependencies.locationController
            .currentAuthorizedLocation() else { return nil }
        return await dependencies.geocodingService.regionIdentifier(
            for: location
        )
    }

    /// Resolves a privacy-filtered city/administrative-area label only when
    /// location access is already authorized. Passive surfaces never prompt.
    func currentAuthorizedLocationName() async -> String? {
        guard let location = await dependencies.locationController
            .currentAuthorizedLocation() else { return nil }
        let locationName = await dependencies.geocodingService.locationName(
            for: location
        )
        return dependencies.displayLocationName(locationName)
    }

    func startLiveLocationTracking() {
        dependencies.locationController.startLiveLocationTracking()
    }

    func stopLiveLocationTracking() {
        dependencies.locationController.stopLiveLocationTracking()
    }

    /// Fetches environment context pinned to the moment of the shutter press.
    func fetchDeferredContext(
        preLockedLocation: CLLocation? = nil
    ) async -> EnvironmentContext {
        guard isAuthorized else {
            return EnvironmentContext(location: preLockedLocation)
        }

        let location: CLLocation
        if let preLockedLocation {
            location = preLockedLocation
        } else {
            let currentLocation = await dependencies.locationController
                .requestSingleLocation()
            guard isAuthorized else {
                return EnvironmentContext(location: nil)
            }
            if let currentLocation {
                location = currentLocation
            } else if let lastKnownLocation {
                location = lastKnownLocation
            } else {
                return EnvironmentContext(location: nil)
            }
        }

        async let locationName = dependencies.geocodingService.locationName(
            for: location
        )
        do {
            let weather = try await dependencies.weatherService.current(
                location
            )
            return EnvironmentContext(
                location: location,
                locationName: await locationName,
                weatherCondition: weather.condition,
                weatherTemperature: weather.temperatureFahrenheit
            )
        } catch {
            return EnvironmentContext(
                location: location,
                locationName: await locationName
            )
        }
    }

    /// Fetches historical context for gallery media at its creation date.
    func fetchHistoricalContext(
        location: CLLocation,
        date: Date
    ) async -> EnvironmentContext {
        let locationName = await dependencies.geocodingService.locationName(
            for: location
        )
        do {
            let weather = try await dependencies.weatherService.historical(
                location,
                date
            )
            return EnvironmentContext(
                location: location,
                locationName: locationName,
                weatherCondition: weather?.condition,
                weatherTemperature: weather?.temperatureFahrenheit,
                captureDate: date
            )
        } catch {
            return EnvironmentContext(
                location: location,
                locationName: locationName,
                captureDate: date
            )
        }
    }

    private func apply(_ snapshot: EnvironmentLocationSnapshot) {
        locationAuthorizationStatus = snapshot.authorizationStatus
        isAuthorized = snapshot.isAuthorized
        cachedLocation = snapshot.cachedLocation
        fallbackInaccurateLocation = snapshot.fallbackInaccurateLocation
    }
}
