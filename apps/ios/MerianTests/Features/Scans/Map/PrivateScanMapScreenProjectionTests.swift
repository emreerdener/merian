import CoreLocation
import Foundation
import MapKit
@testable import Merian
import Testing

@Suite("Private Scan Map screen projection")
struct PrivateScanMapScreenProjectionTests {
    @Test("Interactive clusters use exact 56-point cell boundaries")
    func interactiveCellBoundary() throws {
        let viewport = CGSize(width: 112, height: 112)
        let region = testRegion
        let projection = try #require(
            PrivateScanMapScreenProjection(
                region: region,
                viewportSize: viewport
            )
        )
        let points = [
            makePoint(
                id: "left",
                coordinate: projection.coordinate(
                    at: CGPoint(x: 55, y: 28)
                )
            ),
            makePoint(
                id: "right",
                coordinate: projection.coordinate(
                    at: CGPoint(x: 57, y: 28)
                )
            )
        ]

        let annotations = PrivateScanMapClusterer.annotations(
            points: points,
            region: region,
            viewportSize: viewport
        )

        #expect(annotations.count == 2)
    }

    @Test("High-latitude rows follow Web Mercator screen space")
    func highLatitudeCellBoundary() throws {
        let viewport = CGSize(width: 112, height: 112)
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 75, longitude: 20),
            span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 4)
        )
        let projection = try #require(
            PrivateScanMapScreenProjection(
                region: region,
                viewportSize: viewport
            )
        )
        let north = projection.coordinate(at: CGPoint(x: 28, y: 55))
        let south = projection.coordinate(at: CGPoint(x: 28, y: 57))

        let annotations = PrivateScanMapClusterer.annotations(
            points: [
                makePoint(id: "north", coordinate: north),
                makePoint(id: "south", coordinate: south)
            ],
            region: region,
            viewportSize: viewport
        )

        #expect(annotations.count == 2)
        #expect(north.latitude > south.latitude)
    }

    @Test("Antimeridian screen cells remain wrapped and deterministic")
    func antimeridianCellBoundary() throws {
        let viewport = CGSize(width: 112, height: 112)
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 12, longitude: 180),
            span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4)
        )
        let projection = try #require(
            PrivateScanMapScreenProjection(
                region: region,
                viewportSize: viewport
            )
        )
        let east = projection.coordinate(at: CGPoint(x: 55, y: 28))
        let west = projection.coordinate(at: CGPoint(x: 57, y: 28))

        let annotations = PrivateScanMapClusterer.annotations(
            points: [
                makePoint(id: "east", coordinate: east),
                makePoint(id: "west", coordinate: west)
            ],
            region: region,
            viewportSize: viewport
        )

        #expect(east.longitude > 0)
        #expect(west.longitude < 0)
        #expect(annotations.count == 2)
    }

    @Test("Cluster anchors average projected rather than degree coordinates")
    func projectedClusterAnchor() throws {
        let viewport = CGSize(width: 112, height: 112)
        let region = testRegion
        let projection = try #require(
            PrivateScanMapScreenProjection(
                region: region,
                viewportSize: viewport
            )
        )
        let annotations = PrivateScanMapClusterer.annotations(
            points: [
                makePoint(
                    id: "a",
                    coordinate: projection.coordinate(
                        at: CGPoint(x: 10, y: 10)
                    )
                ),
                makePoint(
                    id: "b",
                    coordinate: projection.coordinate(
                        at: CGPoint(x: 30, y: 30)
                    )
                )
            ],
            region: region,
            viewportSize: viewport,
            cellSize: 112
        )
        let annotation = try #require(annotations.first)
        guard case .cluster(let cluster) = annotation else {
            Issue.record("Expected one projected cluster")
            return
        }
        let anchor = projection.point(for: cluster.coordinate)

        #expect(abs(anchor.x - 20) < 0.01)
        #expect(abs(anchor.y - 20) < 0.01)
    }

    @Test("Polar saved coordinates clamp only in rendering projection")
    func polarClamping() {
        #expect(
            PrivateScanMapScreenProjection.clampedLatitude(90)
                == PrivateScanMapScreenProjection.maximumMercatorLatitude
        )
        #expect(
            PrivateScanMapScreenProjection.clampedLatitude(-90)
                == -PrivateScanMapScreenProjection.maximumMercatorLatitude
        )
        #expect(PrivateScanMapRegion.isValidCoordinate(latitude: 90, longitude: 1))
    }

    private var testRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 12, longitude: 45),
            span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4)
        )
    }

    private func makePoint(
        id: String,
        coordinate: CLLocationCoordinate2D
    ) -> PrivateScanMapPoint {
        PrivateScanMapPoint(
            id: id,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            commonName: "Scan \(id)",
            scientificName: "Species \(id)",
            timestamp: Date(timeIntervalSince1970: 100),
            locationName: nil,
            category: .birds,
            mediaFilters: [.image],
            thumbnail: ScanThumbnailPresentation(
                imagePath: nil,
                fallbackImageUrl: nil,
                audioPath: nil,
                hasVideo: false,
                hasAudio: false,
                placeholderStyle: .archived
            )
        )
    }
}
