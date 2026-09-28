import MapKit

enum ExploreMapCameraPolicy {
    static let thumbnailZoomLevel = 11.5
    static let maximumZoomLevel = 20.0

    static func locateRegion(
        for location: CLLocation,
        currentRegion: MKCoordinateRegion?
    ) -> MKCoordinateRegion {
        var widthMeters = 1_000.0
        if let currentRegion {
            let currentWidth = currentRegion.span.longitudeDelta / 360 * MKMapSize.world.width
                * MKMetersPerMapPointAtLatitude(currentRegion.center.latitude)
            if currentWidth.isFinite, currentWidth > 0 {
                widthMeters = min(widthMeters, currentWidth)
            }
        }
        // Horizontal accuracy is a radius; keep its full diameter in the requested view.
        if location.horizontalAccuracy.isFinite, location.horizontalAccuracy > 0 {
            widthMeters = max(widthMeters, location.horizontalAccuracy * 2)
        }
        return MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: widthMeters,
            longitudinalMeters: widthMeters
        )
    }

    static func zoomLevel(for region: MKCoordinateRegion) -> Double {
        zoomLevel(longitudeDelta: region.span.longitudeDelta)
    }

    static func zoomLevel(longitudeDelta: Double) -> Double {
        let normalizedDelta = max(longitudeDelta, 0.000_01)
        return max(0, min(log2(360 / normalizedDelta), maximumZoomLevel))
    }
}
