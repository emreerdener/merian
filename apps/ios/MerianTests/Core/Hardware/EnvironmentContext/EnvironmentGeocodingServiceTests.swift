import Testing

@testable import Merian

@Suite("Environment geocoding service")
@MainActor
struct EnvironmentGeocodingServiceTests {
    @Test("Location and region projections share one cached placemark")
    func projectionsShareCache() async {
        let probe = EnvironmentPlacemarkProbe(
            result: EnvironmentPlacemark(
                locality: "Test City",
                administrativeArea: "TS",
                regionIdentifier: " us "
            )
        )
        let service = makeService(probe: probe)
        let location = syntheticEnvironmentLocation()

        #expect(await service.locationName(for: location) == "Test City, TS")
        #expect(await service.regionIdentifier(for: location) == "US")
        #expect(probe.locations.count == 1)
    }

    @Test("Equivalent concurrent coordinates coalesce into one request")
    func equivalentCoordinatesCoalesce() async throws {
        let gate = EnvironmentContextWaitGate()
        let probe = EnvironmentPlacemarkProbe(
            result: EnvironmentPlacemark(
                locality: "Coalesced City",
                administrativeArea: "CR",
                regionIdentifier: "ca"
            )
        )
        probe.waitGate = gate
        let service = makeService(probe: probe)
        let firstLocation = syntheticEnvironmentLocation(
            latitude: 10.0004,
            longitude: 20.0004
        )
        let equivalentLocation = syntheticEnvironmentLocation(
            latitude: 10.00049,
            longitude: 20.00049
        )

        let name = Task {
            await service.locationName(for: firstLocation)
        }
        let region = Task {
            await service.regionIdentifier(for: equivalentLocation)
        }
        try await waitForEnvironmentCondition {
            let waiterCount = await gate.waiterCount
            return probe.locations.count == 1 && waiterCount == 1
        }
        await gate.releaseFirst()

        #expect(await name.value == "Coalesced City, CR")
        #expect(await region.value == "CA")
        #expect(probe.locations.count == 1)
    }

    @Test("Failed placemarks are not cached")
    func failureIsRetryable() async {
        let probe = EnvironmentPlacemarkProbe(result: nil)
        let service = makeService(probe: probe)
        let location = syntheticEnvironmentLocation()

        #expect(await service.locationName(for: location) == nil)
        #expect(await service.locationName(for: location) == nil)
        #expect(probe.locations.count == 2)
    }

    @Test("Placemarks without a usable projection remain retryable")
    func emptyPlacemarkIsRetryable() async {
        let probe = EnvironmentPlacemarkProbe(
            result: EnvironmentPlacemark(
                locality: nil,
                administrativeArea: nil,
                regionIdentifier: nil
            )
        )
        let service = makeService(probe: probe)
        let location = syntheticEnvironmentLocation()

        #expect(await service.locationName(for: location) == nil)
        probe.result = EnvironmentPlacemark(
            locality: "Recovered City",
            administrativeArea: "RC",
            regionIdentifier: "us"
        )
        #expect(
            await service.locationName(for: location) == "Recovered City, RC"
        )
        #expect(probe.locations.count == 2)
    }

    @Test("The coordinate cache remains bounded")
    func cacheEvictsOldestCoordinate() async {
        let probe = EnvironmentPlacemarkProbe(
            result: EnvironmentPlacemark(
                locality: "Cached City",
                administrativeArea: "CC",
                regionIdentifier: "us"
            )
        )
        let service = makeService(probe: probe, cacheLimit: 1)
        let first = syntheticEnvironmentLocation()
        let second = syntheticEnvironmentLocation(
            latitude: 11,
            longitude: 21
        )

        _ = await service.locationName(for: first)
        _ = await service.locationName(for: second)
        _ = await service.locationName(for: first)

        #expect(probe.locations.count == 3)
    }

    private func makeService(
        probe: EnvironmentPlacemarkProbe,
        cacheLimit: Int = 10
    ) -> EnvironmentGeocodingService {
        EnvironmentGeocodingService(
            dependencies: .init(resolvePlacemark: probe.resolve),
            cacheLimit: cacheLimit
        )
    }
}
