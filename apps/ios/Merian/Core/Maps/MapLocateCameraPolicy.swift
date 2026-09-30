import MapKit

enum MapLocateCameraPolicy {
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
}
