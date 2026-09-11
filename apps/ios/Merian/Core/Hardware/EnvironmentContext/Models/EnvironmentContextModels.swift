import CoreLocation
import Foundation

// MARK: - Environmental Telemetry Payload

/// Unified environmental snapshot captured at the moment of a scan.
struct EnvironmentContext {
    let location: CLLocation?
    var locationName: String?
    var weatherCondition: String?
    var weatherTemperature: Double?
    var captureDate: Date?
}

struct EnvironmentPlacemark: Equatable, Sendable {
    let locality: String?
    let administrativeArea: String?
    let regionIdentifier: String?
}

struct EnvironmentWeatherReading: Equatable, Sendable {
    let condition: String
    let temperatureFahrenheit: Double
}

struct EnvironmentLocationSnapshot {
    let authorizationStatus: CLAuthorizationStatus
    let cachedLocation: CLLocation?
    let fallbackInaccurateLocation: CLLocation?

    var isAuthorized: Bool {
        EnvironmentLocationPolicy.isAuthorized(authorizationStatus)
    }

    var lastKnownLocation: CLLocation? {
        cachedLocation ?? fallbackInaccurateLocation
    }
}
