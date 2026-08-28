import CoreLocation
import Foundation
import MapKit

/// Converts saved coordinates into the same Web-Mercator space MapKit uses.
///
/// Inclusion remains the responsibility of `PrivateScanMapRegion`; projection
/// clamps only rendering geometry at the Web-Mercator latitude limits.
struct PrivateScanMapScreenProjection: Sendable {
    static let maximumMercatorLatitude = 85.051_128_78

    private let viewportSize: CGSize
    private let westMapX: Double
    private let northMapY: Double
    private let mapWidth: Double
    private let mapHeight: Double

    init?(region: MKCoordinateRegion, viewportSize: CGSize) {
        guard viewportSize.width.isFinite,
              viewportSize.height.isFinite,
              viewportSize.width > 0,
              viewportSize.height > 0,
              region.center.latitude.isFinite,
              region.center.longitude.isFinite,
              region.span.latitudeDelta.isFinite,
              region.span.longitudeDelta.isFinite,
              region.span.latitudeDelta >= 0,
              region.span.longitudeDelta > 0 else {
            return nil
        }

        let halfLatitudeSpan = region.span.latitudeDelta / 2
        let northLatitude = Self.clampedLatitude(
            region.center.latitude + halfLatitudeSpan
        )
        let southLatitude = Self.clampedLatitude(
            region.center.latitude - halfLatitudeSpan
        )
        let westLongitude = region.center.longitude
            - (region.span.longitudeDelta / 2)
        let northPoint = MKMapPoint(CLLocationCoordinate2D(
            latitude: northLatitude,
            longitude: Self.normalizedLongitude(westLongitude)
        ))
        let southPoint = MKMapPoint(CLLocationCoordinate2D(
            latitude: southLatitude,
            longitude: Self.normalizedLongitude(westLongitude)
        ))

        self.viewportSize = viewportSize
        westMapX = northPoint.x
        northMapY = min(northPoint.y, southPoint.y)
        mapWidth = max(
            MKMapSize.world.width
                * min(region.span.longitudeDelta, 360) / 360,
            1
        )
        mapHeight = max(abs(southPoint.y - northPoint.y), 1)
    }

    func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
        let mapPoint = projectedMapPoint(for: coordinate)
        return CGPoint(
            x: ((mapPoint.x - westMapX) / mapWidth) * viewportSize.width,
            y: ((mapPoint.y - northMapY) / mapHeight) * viewportSize.height
        )
    }

    func coordinate(at point: CGPoint) -> CLLocationCoordinate2D {
        let mapX = westMapX
            + (Double(point.x / viewportSize.width) * mapWidth)
        let mapY = northMapY
            + (Double(point.y / viewportSize.height) * mapHeight)
        return MKMapPoint(
            x: Self.normalizedMapX(mapX),
            y: mapY
        ).coordinate
    }

    func averageCoordinate(
        _ coordinates: [CLLocationCoordinate2D]
    ) -> CLLocationCoordinate2D {
        guard !coordinates.isEmpty else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        let sum = coordinates.reduce(into: (x: 0.0, y: 0.0)) { result, coordinate in
            let mapPoint = projectedMapPoint(for: coordinate)
            result.x += mapPoint.x
            result.y += mapPoint.y
        }
        return MKMapPoint(
            x: Self.normalizedMapX(sum.x / Double(coordinates.count)),
            y: sum.y / Double(coordinates.count)
        ).coordinate
    }

    static func clampedLatitude(_ latitude: Double) -> Double {
        min(max(latitude, -maximumMercatorLatitude), maximumMercatorLatitude)
    }

    private func projectedMapPoint(
        for coordinate: CLLocationCoordinate2D
    ) -> MKMapPoint {
        let point = MKMapPoint(CLLocationCoordinate2D(
            latitude: Self.clampedLatitude(coordinate.latitude),
            longitude: Self.normalizedLongitude(coordinate.longitude)
        ))
        var unwrappedX = point.x
        if unwrappedX < westMapX {
            unwrappedX += MKMapSize.world.width
        }
        return MKMapPoint(x: unwrappedX, y: point.y)
    }

    private static func normalizedLongitude(_ longitude: Double) -> Double {
        let shifted = (longitude + 180).truncatingRemainder(dividingBy: 360)
        let normalized = shifted >= 0 ? shifted : shifted + 360
        return normalized - 180
    }

    private static func normalizedMapX(_ mapX: Double) -> Double {
        let normalized = mapX.truncatingRemainder(
            dividingBy: MKMapSize.world.width
        )
        return normalized >= 0 ? normalized : normalized + MKMapSize.world.width
    }
}
