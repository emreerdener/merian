import MapKit

enum ExploreMapCameraPolicy {
    static let thumbnailZoomLevel = 11.5
    static let maximumZoomLevel = 20.0

    /// Keep nearby viewports from reusing aggregates across an integer zoom boundary.
    static func zoomBucket(for region: MKCoordinateRegion) -> Int {
        Int(zoomLevel(for: region).rounded(.down))
    }

    static func zoomLevel(for region: MKCoordinateRegion) -> Double {
        zoomLevel(longitudeDelta: region.span.longitudeDelta)
    }

    static func zoomLevel(longitudeDelta: Double) -> Double {
        let normalizedDelta = max(longitudeDelta, 0.000_01)
        return max(0, min(log2(360 / normalizedDelta), maximumZoomLevel))
    }
}
