import CoreLocation
import Foundation

enum EnvironmentLocationPolicy {
    static let composingAccuracy = kCLLocationAccuracyHundredMeters
    static let shutterAccuracy = kCLLocationAccuracyBest
    static let composingDistanceFilter: CLLocationDistance = 100
    static let shutterDistanceFilter = kCLDistanceFilterNone
    static let accurateHorizontalDistance: CLLocationAccuracy = 30
    static let locationTimeoutNanoseconds: UInt64 = 2_000_000_000
    static let geocodeCacheLimit = 200

    static func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    static func shouldRequestAuthorization(
        for status: CLAuthorizationStatus,
        suppressesPrompt: Bool
    ) -> Bool {
        status == .notDetermined && !suppressesPrompt
    }

    static func isUsable(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0
    }

    static func isAccurate(_ location: CLLocation) -> Bool {
        isUsable(location) &&
            location.horizontalAccuracy <= accurateHorizontalDistance
    }

    static func geocodeCacheKey(for location: CLLocation) -> String {
        String(
            format: "%.3f,%.3f",
            location.coordinate.latitude,
            location.coordinate.longitude
        )
    }

    static func locationName(from placemark: EnvironmentPlacemark?) -> String? {
        guard let placemark else { return nil }
        if let city = placemark.locality,
           let administrativeArea = placemark.administrativeArea {
            return "\(city), \(administrativeArea)"
        }
        return placemark.administrativeArea
    }

    static func hasUsableProjection(_ placemark: EnvironmentPlacemark) -> Bool {
        locationName(from: placemark) != nil ||
            normalizedRegionIdentifier(placemark.regionIdentifier) != nil
    }

    static func normalizedRegionIdentifier(_ value: String?) -> String? {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return normalized?.isEmpty == false ? normalized : nil
    }
}
