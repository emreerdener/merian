import CoreLocation
import MapKit
import UIKit

extension SpeciesDictionaryRegionMapViewModel.Dependencies {
    static let live = Self { query, width, height, isDark in
        await SpeciesRegionMapSnapshotService.loadSnapshot(
            query: query,
            width: width,
            height: height,
            isDark: isDark
        )
    }
}

private enum SpeciesRegionMapSnapshotService {
    @MainActor
    static func loadSnapshot(
        query: String,
        width: CGFloat,
        height: CGFloat,
        isDark: Bool
    ) async -> UIImage? {
        let geocoder = CLGeocoder()
        let placemark = (try? await geocoder.geocodeAddressString(query))?.first
        let coordinate = placemark?.location?.coordinate

        let options = MKMapSnapshotter.Options()
        if let placemark, let coordinate {
            options.region = snapshotRegion(
                for: placemark,
                coordinate: coordinate
            )
        } else {
            options.region = defaultFallbackRegion
        }
        options.size = CGSize(
            width: max(width, 240),
            height: max(height, 140)
        )
        options.scale = UIScreen.main.scale
        options.showsBuildings = false
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(
            userInterfaceStyle: isDark ? .dark : .light
        )

        let snapshotter = MKMapSnapshotter(options: options)
        return await withCheckedContinuation { continuation in
            snapshotter.start(
                with: DispatchQueue.global(qos: .userInitiated)
            ) { snapshot, _ in
                continuation.resume(returning: snapshot?.image)
            }
        }
    }

    private static func snapshotRegion(
        for placemark: CLPlacemark,
        coordinate: CLLocationCoordinate2D
    ) -> MKCoordinateRegion {
        let radius = (placemark.region as? CLCircularRegion)?.radius ?? 650_000
        let clampedRadius = min(max(radius, 80_000), 4_500_000)
        let latitudeDelta = min(
            max((clampedRadius / 111_000) * 2.2, 0.45),
            60
        )
        let longitudeScale = max(
            cos(coordinate.latitude * .pi / 180),
            0.24
        )
        let longitudeDelta = min(
            max(latitudeDelta / longitudeScale, 0.45),
            80
        )

        return MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            )
        )
    }

    private static let defaultFallbackRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(
            latitude: 39.8283,
            longitude: -98.5795
        ),
        span: MKCoordinateSpan(latitudeDelta: 28, longitudeDelta: 54)
    )
}
