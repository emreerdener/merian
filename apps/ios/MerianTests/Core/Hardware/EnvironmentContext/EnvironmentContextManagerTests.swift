import CoreLocation
import Foundation
import Testing

@testable import Merian

@Suite("Environment context manager")
@MainActor
struct EnvironmentContextManagerTests {
    @Test("Stable static policy wrappers retain their compatibility behavior")
    func staticPolicyWrappersRemainCompatible() {
        #expect(
            EnvironmentContextManager.allowsPassiveRegionResolution(
                for: .authorizedWhenInUse
            )
        )
        #expect(
            EnvironmentContextManager.allowsPassiveRegionResolution(
                for: .authorizedAlways
            )
        )
        #expect(
            !EnvironmentContextManager.allowsPassiveRegionResolution(
                for: .denied
            )
        )
        #expect(
            EnvironmentContextManager.shouldRequestLocationAuthorization(
                for: .notDetermined,
                suppressesLocationPermissionPrompt: false
            )
        )
        #expect(
            !EnvironmentContextManager.shouldRequestLocationAuthorization(
                for: .notDetermined,
                suppressesLocationPermissionPrompt: true
            )
        )
        #expect(
            EnvironmentContextManager.normalizedRegionIdentifier(" ca ") ==
                "CA"
        )
        #expect(EnvironmentContextManager.normalizedRegionIdentifier(" ") == nil)
    }

    @Test("Observable location state mirrors the focused controller")
    func controllerStateIsProjected() {
        let fixture = makeFixture(authorizationStatus: .notDetermined)
        #expect(!fixture.manager.isAuthorized)
        #expect(
            fixture.manager.locationAuthorizationStatus == .notDetermined
        )

        fixture.locationProbe.authorizationStatus = .authorizedWhenInUse
        fixture.locationController.receiveAuthorizationStatus(
            .authorizedWhenInUse
        )
        let fallback = syntheticEnvironmentLocation(horizontalAccuracy: 80)
        fixture.locationController.receiveLocations([fallback])

        #expect(fixture.manager.isAuthorized)
        #expect(
            fixture.manager.locationAuthorizationStatus ==
                .authorizedWhenInUse
        )
        #expect(fixture.manager.fallbackInaccurateLocation === fallback)
        #expect(fixture.manager.lastKnownLocation === fallback)
    }

    @Test("Unauthorized context performs no geocode or weather work")
    func unauthorizedContextHasNoServiceEffects() async {
        let fixture = makeFixture(authorizationStatus: .denied)

        let context = await fixture.manager.fetchDeferredContext()

        #expect(context.location == nil)
        #expect(context.locationName == nil)
        #expect(context.weatherCondition == nil)
        #expect(context.weatherTemperature == nil)
        #expect(fixture.placemarkProbe.locations.isEmpty)
        #expect(fixture.weatherProbe.currentLocations.isEmpty)
        #expect(fixture.locationProbe.locationRequestCount == 0)
    }

    @Test("Deferred geocoding and current weather start concurrently")
    func deferredContextStartsIndependentWorkConcurrently() async throws {
        let geocodeGate = EnvironmentContextWaitGate()
        let weatherGate = EnvironmentContextWaitGate()
        let fixture = makeFixture(
            authorizationStatus: .authorizedWhenInUse,
            geocodeGate: geocodeGate,
            weatherGate: weatherGate
        )
        let location = syntheticEnvironmentLocation()

        let request = Task {
            await fixture.manager.fetchDeferredContext(
                preLockedLocation: location
            )
        }
        try await waitForEnvironmentCondition {
            let geocodeWaiters = await geocodeGate.waiterCount
            let weatherWaiters = await weatherGate.waiterCount
            return geocodeWaiters == 1 && weatherWaiters == 1
        }
        await geocodeGate.releaseFirst()
        await weatherGate.releaseFirst()
        let context = await request.value

        #expect(context.location === location)
        #expect(context.locationName == "Test City, TS")
        #expect(context.weatherCondition == "Clear")
        #expect(context.weatherTemperature == 72)
        #expect(fixture.placemarkProbe.locations.count == 1)
        #expect(fixture.weatherProbe.currentLocations.count == 1)
    }

    @Test("Weather failure preserves the independently resolved location name")
    func weatherFailurePreservesGeocode() async {
        let fixture = makeFixture(
            authorizationStatus: .authorizedWhenInUse
        )
        fixture.weatherProbe.currentThrows = true
        let location = syntheticEnvironmentLocation()

        let context = await fixture.manager.fetchDeferredContext(
            preLockedLocation: location
        )

        #expect(context.location === location)
        #expect(context.locationName == "Test City, TS")
        #expect(context.weatherCondition == nil)
        #expect(context.weatherTemperature == nil)
    }

    @Test("Historical context preserves capture date when weather is absent")
    func historicalContextWithoutWeather() async {
        let fixture = makeFixture(
            authorizationStatus: .authorizedWhenInUse
        )
        fixture.weatherProbe.historicalReading = nil
        let location = syntheticEnvironmentLocation()
        let date = Date(timeIntervalSince1970: 2_000)

        let context = await fixture.manager.fetchHistoricalContext(
            location: location,
            date: date
        )

        #expect(context.location === location)
        #expect(context.locationName == "Test City, TS")
        #expect(context.weatherCondition == nil)
        #expect(context.weatherTemperature == nil)
        #expect(context.captureDate == date)
        #expect(fixture.weatherProbe.historicalRequests.count == 1)
    }

    @Test("Passive location projections never request authorization")
    func passiveLocationProjectionUsesCachedFix() async {
        let fixture = makeFixture(
            authorizationStatus: .authorizedWhenInUse,
            displayLocationName: { value in value.map { "Public: \($0)" } }
        )
        let location = syntheticEnvironmentLocation()
        fixture.locationController.receiveLocations([location])

        let region = await fixture.manager
            .currentAuthorizedRegionIdentifier()
        let locationName = await fixture.manager.currentAuthorizedLocationName()

        #expect(region == "US")
        #expect(locationName == "Public: Test City, TS")
        #expect(fixture.locationProbe.authorizationRequestCount == 0)
        #expect(fixture.locationProbe.locationRequestCount == 0)
        #expect(fixture.placemarkProbe.locations.count == 1)
    }

    private struct Fixture {
        let manager: EnvironmentContextManager
        let locationController: EnvironmentLocationController
        let locationProbe: EnvironmentLocationHardwareProbe
        let placemarkProbe: EnvironmentPlacemarkProbe
        let weatherProbe: EnvironmentWeatherProbe
    }

    private func makeFixture(
        authorizationStatus: CLAuthorizationStatus,
        geocodeGate: EnvironmentContextWaitGate? = nil,
        weatherGate: EnvironmentContextWaitGate? = nil,
        displayLocationName: @escaping @MainActor (String?) -> String? = {
            $0
        }
    ) -> Fixture {
        let locationProbe = EnvironmentLocationHardwareProbe(
            authorizationStatus: authorizationStatus
        )
        let locationController = EnvironmentLocationController(
            dependencies: .init(
                hardware: locationProbe.hardware(),
                waitForLocationTimeout: {
                    try? await Task.sleep(for: .seconds(60))
                }
            )
        )
        let placemarkProbe = EnvironmentPlacemarkProbe(
            result: EnvironmentPlacemark(
                locality: "Test City",
                administrativeArea: "TS",
                regionIdentifier: "us"
            )
        )
        placemarkProbe.waitGate = geocodeGate
        let geocodingService = EnvironmentGeocodingService(
            dependencies: .init(
                resolvePlacemark: placemarkProbe.resolve
            ),
            cacheLimit: 10
        )
        let weatherProbe = EnvironmentWeatherProbe()
        weatherProbe.currentReading = EnvironmentWeatherReading(
            condition: "Clear",
            temperatureFahrenheit: 72
        )
        weatherProbe.historicalReading = EnvironmentWeatherReading(
            condition: "Cloudy",
            temperatureFahrenheit: 64
        )
        weatherProbe.currentWaitGate = weatherGate
        let manager = EnvironmentContextManager(
            dependencies: .init(
                locationController: locationController,
                geocodingService: geocodingService,
                weatherService: EnvironmentWeatherService(
                    current: weatherProbe.loadCurrent,
                    historical: weatherProbe.loadHistorical
                ),
                suppressesLocationPermissionPrompt: { false },
                displayLocationName: displayLocationName
            )
        )
        return Fixture(
            manager: manager,
            locationController: locationController,
            locationProbe: locationProbe,
            placemarkProbe: placemarkProbe,
            weatherProbe: weatherProbe
        )
    }
}
