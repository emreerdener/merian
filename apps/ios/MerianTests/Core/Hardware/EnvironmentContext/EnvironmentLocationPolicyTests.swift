import CoreLocation
import Testing

@testable import Merian

@Suite("Environment location policy")
struct EnvironmentLocationPolicyTests {
    @Test("Authorization and prompt decisions are exhaustive")
    func authorizationDecisions() {
        #expect(
            EnvironmentLocationPolicy.isAuthorized(.authorizedWhenInUse)
        )
        #expect(EnvironmentLocationPolicy.isAuthorized(.authorizedAlways))
        #expect(!EnvironmentLocationPolicy.isAuthorized(.notDetermined))
        #expect(!EnvironmentLocationPolicy.isAuthorized(.denied))
        #expect(!EnvironmentLocationPolicy.isAuthorized(.restricted))

        #expect(
            EnvironmentLocationPolicy.shouldRequestAuthorization(
                for: .notDetermined,
                suppressesPrompt: false
            )
        )
        #expect(
            !EnvironmentLocationPolicy.shouldRequestAuthorization(
                for: .notDetermined,
                suppressesPrompt: true
            )
        )
        for status in [
            CLAuthorizationStatus.denied,
            .restricted,
            .authorizedWhenInUse,
            .authorizedAlways
        ] {
            #expect(
                !EnvironmentLocationPolicy.shouldRequestAuthorization(
                    for: status,
                    suppressesPrompt: false
                )
            )
        }
    }

    @Test("Accuracy admits the documented zero-through-thirty-meter range")
    func accuracyBoundary() {
        #expect(
            EnvironmentLocationPolicy.isUsable(
                syntheticEnvironmentLocation(horizontalAccuracy: 0)
            )
        )
        #expect(
            EnvironmentLocationPolicy.isAccurate(
                syntheticEnvironmentLocation(horizontalAccuracy: 0)
            )
        )
        #expect(
            EnvironmentLocationPolicy.isAccurate(
                syntheticEnvironmentLocation(horizontalAccuracy: 30)
            )
        )
        #expect(
            EnvironmentLocationPolicy.isUsable(
                syntheticEnvironmentLocation(horizontalAccuracy: 30.1)
            )
        )
        #expect(
            !EnvironmentLocationPolicy.isAccurate(
                syntheticEnvironmentLocation(horizontalAccuracy: -1)
            )
        )
        #expect(
            !EnvironmentLocationPolicy.isUsable(
                syntheticEnvironmentLocation(horizontalAccuracy: -1)
            )
        )
        #expect(
            !EnvironmentLocationPolicy.isAccurate(
                syntheticEnvironmentLocation(horizontalAccuracy: 30.1)
            )
        )
    }

    @Test("Geocode keys retain the established three-decimal precision")
    func geocodeKeyPrecision() {
        let first = syntheticEnvironmentLocation(
            latitude: 10.0004,
            longitude: 20.0004
        )
        let equivalent = syntheticEnvironmentLocation(
            latitude: 10.00049,
            longitude: 20.00049
        )
        let different = syntheticEnvironmentLocation(
            latitude: 10.001,
            longitude: 20.001
        )

        #expect(
            EnvironmentLocationPolicy.geocodeCacheKey(for: first) ==
                EnvironmentLocationPolicy.geocodeCacheKey(for: equivalent)
        )
        #expect(
            EnvironmentLocationPolicy.geocodeCacheKey(for: first) !=
                EnvironmentLocationPolicy.geocodeCacheKey(for: different)
        )
    }

    @Test("Placemark and region presentation preserves compatibility")
    func placemarkPresentation() {
        #expect(
            EnvironmentLocationPolicy.locationName(
                from: EnvironmentPlacemark(
                    locality: "Test City",
                    administrativeArea: "TS",
                    regionIdentifier: "us"
                )
            ) == "Test City, TS"
        )
        #expect(
            EnvironmentLocationPolicy.locationName(
                from: EnvironmentPlacemark(
                    locality: nil,
                    administrativeArea: "Test Region",
                    regionIdentifier: nil
                )
            ) == "Test Region"
        )
        #expect(
            EnvironmentLocationPolicy.normalizedRegionIdentifier(" us ") ==
                "US"
        )
        #expect(
            EnvironmentLocationPolicy.normalizedRegionIdentifier("   ") == nil
        )
        #expect(EnvironmentLocationPolicy.normalizedRegionIdentifier(nil) == nil)
    }
}
