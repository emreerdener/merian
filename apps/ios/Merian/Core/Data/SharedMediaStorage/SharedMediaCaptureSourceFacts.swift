import CoreLocation
import Foundation

/// Private, immutable shutter/import facts. Restoring a draft never substitutes
/// the current location or time for missing historical facts. These values are
/// local journal context, not inference evidence or filesystem authority.
struct SharedMediaCaptureSourceFacts: Codable, Equatable, Sendable {
    let addedAt: Date
    let captureDate: Date?
    let latitude: Double?
    let longitude: Double?
    let elevation: Double?
    let locationName: String?
    let weatherCondition: String?
    let weatherTemperature: Double?
    let distance: Float?
    let zoom: Double?

    init(addedAt: Date, context: EnvironmentContext?, distance: Float? = nil, zoom: Double? = nil) {
        self.addedAt = addedAt; captureDate = context?.captureDate
        latitude = context?.location?.coordinate.latitude; longitude = context?.location?.coordinate.longitude
        elevation = context?.location.flatMap { (0...25).contains($0.verticalAccuracy) ? $0.altitude : nil }
        locationName = context?.locationName
        weatherCondition = context?.weatherCondition; weatherTemperature = context?.weatherTemperature
        self.distance = distance; self.zoom = zoom
    }

    func validate() throws {
        guard addedAt.timeIntervalSince1970.isFinite, captureDate?.timeIntervalSince1970.isFinite != false,
              [latitude, longitude, elevation, weatherTemperature, zoom].allSatisfy({ $0?.isFinite != false }),
              distance?.isFinite != false, (latitude == nil) == (longitude == nil),
              latitude.map({ (-90...90).contains($0) }) != false,
              longitude.map({ (-180...180).contains($0) }) != false,
              distance.map({ $0 >= 0 }) != false, zoom.map({ $0 > 0 }) != false,
              (locationName?.utf8.count ?? 0) <= 4096, (weatherCondition?.utf8.count ?? 0) <= 4096 else {
            throw SharedMediaStorageFailure.invalid
        }
    }

    var environmentContext: EnvironmentContext {
        let location: CLLocation?
        if let latitude, let longitude {
            location = CLLocation(coordinate: .init(latitude: latitude, longitude: longitude),
                altitude: elevation ?? 0, horizontalAccuracy: -1, verticalAccuracy: -1,
                timestamp: captureDate ?? addedAt)
        } else { location = nil }
        return .init(location: location, locationName: locationName, weatherCondition: weatherCondition,
            weatherTemperature: weatherTemperature, captureDate: captureDate)
    }

    /// Uses captured values directly rather than reconstructing sensors from a
    /// preview. Unknown import dates and elevation stay unknown on submission.
    var telemetry: CaptureTelemetry {
        .init(subjectDistanceInMeters: distance, gpsLatitude: latitude, gpsLongitude: longitude,
            gpsElevation: elevation, locationName: locationName, weatherCondition: weatherCondition,
            weatherTemperatureF: weatherTemperature, timeOfDay: nil,
            timestamp: captureDate.map { DateUtilities.iso8601Formatter.string(from: $0) },
            zoomFactor: zoom.map { CGFloat($0) }, estimatedSizeCm: nil)
    }
}
