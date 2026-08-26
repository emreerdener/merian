import MapKit

extension MKCoordinateRegion {
    var exploreMapNorthLatitude: Double {
        min(center.latitude + (span.latitudeDelta / 2), 90)
    }

    var exploreMapSouthLatitude: Double {
        max(center.latitude - (span.latitudeDelta / 2), -90)
    }

    var exploreMapEastLongitude: Double {
        wrappedExploreMapLongitude(center.longitude + (span.longitudeDelta / 2))
    }

    var exploreMapWestLongitude: Double {
        wrappedExploreMapLongitude(center.longitude - (span.longitudeDelta / 2))
    }

    func expandedForExploreMap(by factor: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: min(span.latitudeDelta * factor, 180),
                longitudeDelta: min(span.longitudeDelta * factor, 360)
            )
        )
    }

    func containsForExploreMap(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let containsLatitude = coordinate.latitude >= exploreMapSouthLatitude
            && coordinate.latitude <= exploreMapNorthLatitude
        guard containsLatitude else { return false }

        if exploreMapWestLongitude <= exploreMapEastLongitude {
            return coordinate.longitude >= exploreMapWestLongitude
                && coordinate.longitude <= exploreMapEastLongitude
        }

        return coordinate.longitude >= exploreMapWestLongitude
            || coordinate.longitude <= exploreMapEastLongitude
    }

    private func wrappedExploreMapLongitude(_ value: Double) -> Double {
        switch value {
        case let longitude where longitude > 180:
            return longitude - 360
        case let longitude where longitude < -180:
            return longitude + 360
        default:
            return value
        }
    }
}
