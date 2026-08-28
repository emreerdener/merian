import CoreLocation
import Foundation
import MapKit

enum PrivateScanMapRegion {
    static func isValidCoordinate(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite
            && longitude.isFinite
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
            && !(latitude == 0 && longitude == 0)
    }

    static func centered(
        on coordinate: CLLocationCoordinate2D,
        span: Double
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: span,
                longitudeDelta: span
            )
        )
    }

    static func fitted(
        to coordinates: [CLLocationCoordinate2D],
        padding: Double,
        minimumSpan: Double
    ) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }

        let latitudes = coordinates.map(\.latitude)
        guard let minimumLatitude = latitudes.min(),
              let maximumLatitude = latitudes.max() else {
            return nil
        }

        let longitudeArc = shortestLongitudeArc(
            coordinates.map(\.longitude)
        )
        let latitudeSpan = min(
            max((maximumLatitude - minimumLatitude) * padding, minimumSpan),
            180
        )
        let longitudeSpan = min(
            max(longitudeArc.span * padding, minimumSpan),
            360
        )

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: longitudeArc.center
            ),
            span: MKCoordinateSpan(
                latitudeDelta: latitudeSpan,
                longitudeDelta: longitudeSpan
            )
        )
    }

    static func contains(
        _ coordinate: CLLocationCoordinate2D,
        in region: MKCoordinateRegion
    ) -> Bool {
        let latitudeHalfSpan = region.span.latitudeDelta / 2
        guard coordinate.latitude >= region.center.latitude - latitudeHalfSpan,
              coordinate.latitude <= region.center.latitude + latitudeHalfSpan else {
            return false
        }

        guard region.span.longitudeDelta < 360 else { return true }
        return wrappedLongitudeDistance(
            coordinate.longitude,
            region.center.longitude
        ) <= (region.span.longitudeDelta / 2) + 0.000_000_1
    }

    static func positiveLongitudeDistance(from start: Double, to end: Double) -> Double {
        let delta = (normalizedLongitude360(end) - normalizedLongitude360(start))
            .truncatingRemainder(dividingBy: 360)
        return delta >= 0 ? delta : delta + 360
    }

    private static func shortestLongitudeArc(_ longitudes: [Double]) -> (
        center: Double,
        span: Double
    ) {
        let sorted = longitudes.map(normalizedLongitude360).sorted()
        guard let first = sorted.first else { return (0, 0) }
        guard sorted.count > 1 else {
            return (normalizedLongitude180(first), 0)
        }

        var largestGap = -Double.infinity
        var largestGapStartIndex = 0

        for index in sorted.indices {
            let next = index == sorted.index(before: sorted.endIndex)
                ? first + 360
                : sorted[index + 1]
            let gap = next - sorted[index]
            if gap > largestGap {
                largestGap = gap
                largestGapStartIndex = index
            }
        }

        let arcStartIndex = (largestGapStartIndex + 1) % sorted.count
        let arcStart = sorted[arcStartIndex]
        var arcEnd = sorted[largestGapStartIndex]
        if arcEnd < arcStart {
            arcEnd += 360
        }

        let span = arcEnd - arcStart
        return (
            center: normalizedLongitude180(arcStart + (span / 2)),
            span: span
        )
    }

    private static func wrappedLongitudeDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let delta = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(delta, 360 - delta)
    }

    private static func normalizedLongitude360(_ longitude: Double) -> Double {
        let normalized = longitude.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }

    private static func normalizedLongitude180(_ longitude: Double) -> Double {
        let normalized = normalizedLongitude360(longitude)
        return normalized > 180 ? normalized - 360 : normalized
    }
}
