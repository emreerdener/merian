import CoreLocation

// MARK: - Environmental Telemetry Payload

/// Unified environmental snapshot captured at the moment of a scan.
struct EnvironmentContext {
    let location: CLLocation?
    var locationName: String? = nil
    var weatherCondition: String? = nil
    var weatherTemperature: Double? = nil
    var captureDate: Date? = nil
}
