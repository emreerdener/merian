import CoreLocation
import Foundation

/// Sendable value projection used only while racing deferred context against
/// the submission grace deadline. It preserves every location field consumed
/// by `CaptureTelemetry` without transferring `CLLocation` across tasks.
struct CaptureSubmissionContextSnapshot: Sendable {
    let latitude: CLLocationDegrees?
    let longitude: CLLocationDegrees?
    let altitude: CLLocationDistance?
    let horizontalAccuracy: CLLocationAccuracy?
    let verticalAccuracy: CLLocationAccuracy?
    let timestamp: Date?
    let locationName: String?
    let weatherCondition: String?
    let weatherTemperature: Double?
    let captureDate: Date?

    init(_ context: EnvironmentContext) {
        latitude = context.location?.coordinate.latitude
        longitude = context.location?.coordinate.longitude
        altitude = context.location?.altitude
        horizontalAccuracy = context.location?.horizontalAccuracy
        verticalAccuracy = context.location?.verticalAccuracy
        timestamp = context.location?.timestamp
        locationName = context.locationName
        weatherCondition = context.weatherCondition
        weatherTemperature = context.weatherTemperature
        captureDate = context.captureDate
    }

    func makeEnvironmentContext() -> EnvironmentContext {
        let location: CLLocation?
        if let latitude,
           let longitude,
           let altitude,
           let horizontalAccuracy,
           let verticalAccuracy,
           let timestamp {
            location = CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: latitude,
                    longitude: longitude
                ),
                altitude: altitude,
                horizontalAccuracy: horizontalAccuracy,
                verticalAccuracy: verticalAccuracy,
                timestamp: timestamp
            )
        } else {
            location = nil
        }

        return EnvironmentContext(
            location: location,
            locationName: locationName,
            weatherCondition: weatherCondition,
            weatherTemperature: weatherTemperature,
            captureDate: captureDate
        )
    }
}
