import MapKit

enum ExploreMapCameraPolicy {
    static let thumbnailZoomLevel = 11.5
    static let maximumZoomLevel = 20.0

    static func zoomLevel(for region: MKCoordinateRegion) -> Double {
        zoomLevel(longitudeDelta: region.span.longitudeDelta)
    }

    static func zoomLevel(longitudeDelta: Double) -> Double {
        let normalizedDelta = max(longitudeDelta, 0.000_01)
        return max(0, min(log2(360 / normalizedDelta), maximumZoomLevel))
    }
}
