import CoreLocation

// MARK: - Environmental Telemetry Payload

/// Unified environmental snapshot captured at the moment of a scan.
struct EnvironmentContext {
    let location: CLLocation?
    var locationName: String?
    var weatherCondition: String?
    var weatherTemperature: Double?
    var captureDate: Date?
}
