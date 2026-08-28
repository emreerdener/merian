import CoreLocation
import Foundation
import MapKit

struct PrivateScanMapCluster: Identifiable, Equatable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    let points: [PrivateScanMapPoint]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var count: Int {
        points.count
    }

    var focusRegion: MKCoordinateRegion? {
        PrivateScanMapRegion.fitted(
            to: points.map(\.coordinate),
            padding: 1.6,
            minimumSpan: 0.01
        )
    }
}

enum PrivateScanMapAnnotation: Identifiable, Equatable, Sendable {
    case point(PrivateScanMapPoint)
    case cluster(PrivateScanMapCluster)

    var id: String {
        switch self {
        case .point(let point):
            return "point:\(point.id)"
        case .cluster(let cluster):
            return "cluster:\(cluster.id)"
        }
    }
}

struct PrivateScanMapPreviewCluster: Identifiable, Equatable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    let count: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum PrivateScanMapPreviewAnnotation: Identifiable, Equatable, Sendable {
    case point(PrivateScanMapPreviewPoint)
    case cluster(PrivateScanMapPreviewCluster)

    var id: String {
        switch self {
        case .point(let point):
            return "point:\(point.id)"
        case .cluster(let cluster):
            return "cluster:\(cluster.id)"
        }
    }
}
