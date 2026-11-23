import CoreLocation
import Foundation

@MainActor
struct EnvironmentLocationHardware {
    let authorizationStatus: @MainActor () -> CLAuthorizationStatus
    let configure:
        @MainActor (_ delegate: any CLLocationManagerDelegate) -> Void
    let requestWhenInUseAuthorization: @MainActor () -> Void
    let requestLocation: @MainActor () -> Void
    let startUpdatingLocation: @MainActor () -> Void
    let stopUpdatingLocation: @MainActor () -> Void
    let applyProfile:
        @MainActor (
            _ desiredAccuracy: CLLocationAccuracy,
            _ distanceFilter: CLLocationDistance
        ) -> Void

    #if DEBUG
    private static let unitTesting = Self(
        authorizationStatus: { .denied }, configure: { _ in },
        requestWhenInUseAuthorization: {}, requestLocation: {},
        startUpdatingLocation: {}, stopUpdatingLocation: {},
        applyProfile: { _, _ in }
    )
    #endif

    static var live: Self {
        let manager = CLLocationManager()
        return Self(
            authorizationStatus: { manager.authorizationStatus },
            configure: { delegate in
                manager.delegate = delegate
                manager.desiredAccuracy =
                    EnvironmentLocationPolicy.composingAccuracy
                manager.distanceFilter =
                    EnvironmentLocationPolicy.composingDistanceFilter
                manager.pausesLocationUpdatesAutomatically = true
            },
            requestWhenInUseAuthorization: {
                manager.requestWhenInUseAuthorization()
            },
            requestLocation: { manager.requestLocation() },
            startUpdatingLocation: { manager.startUpdatingLocation() },
            stopUpdatingLocation: { manager.stopUpdatingLocation() },
            applyProfile: { desiredAccuracy, distanceFilter in
                manager.desiredAccuracy = desiredAccuracy
                manager.distanceFilter = distanceFilter
            }
        )
    }

    #if DEBUG
    @MainActor static func debugHardware(
        isRunningUnitTests: Bool,
        environment: [String: String],
        arguments: [String],
        live: @MainActor () -> EnvironmentLocationHardware
    ) -> EnvironmentLocationHardware {
        let isCaptureReviewFixture = environment["UITesting"] == "true"
            && arguments.contains("-seedStagedAudioReviewFlow")
            && arguments.contains("-mockCaptureReviewLocation")
        return isRunningUnitTests || isCaptureReviewFixture ? .unitTesting : live()
    }
    #endif
}
