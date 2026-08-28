import Foundation
import MapKit
@testable import Merian
import Testing

@Suite("Private Scan Map clustering")
struct PrivateScanMapClusteringTests {
    @Test("Clustering is deterministic at 56 points and bounded for large libraries")
    func deterministicClustering() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 12, longitude: 45),
            span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4)
        )
        let viewport = CGSize(width: 390, height: 844)
        let points = (0..<5_000).map { index in
            let row = index / 100
            let column = index % 100
            return makePoint(
                id: "large-\(index)",
                latitude: 10.1 + (Double(row) * 0.075),
                longitude: 43.1 + (Double(column) * 0.038)
            )
        }

        let first = PrivateScanMapClusterer.annotations(
            points: points,
            region: region,
            viewportSize: viewport
        )
        let second = PrivateScanMapClusterer.annotations(
            points: Array(points.reversed()),
            region: region,
            viewportSize: viewport
        )

        #expect(first == second)
        #expect(first.count <= 112)
        let representedPointCount = first.reduce(0) { count, annotation in
            switch annotation {
            case .point:
                return count + 1
            case .cluster(let cluster):
                return count + cluster.count
            }
        }
        #expect(representedPointCount == points.count)
    }

    @Test("Collections preview clustering stays deterministic for large libraries")
    func deterministicPreviewClustering() throws {
        let points = (0..<5_000).map { index in
            let row = index / 100
            let column = index % 100
            return PrivateScanMapPreviewPoint(
                id: "preview-large-\(index)",
                latitude: 10.1 + (Double(row) * 0.075),
                longitude: 43.1 + (Double(column) * 0.038)
            )
        }
        let snapshot = PrivateScanMapPreviewSnapshot(points: points)
        let region = try #require(snapshot.fullExtentRegion)
        let viewport = CGSize(width: 390, height: 292.5)

        let first = PrivateScanMapClusterer.previewAnnotations(
            points: snapshot.points,
            region: region,
            viewportSize: viewport
        )
        let second = PrivateScanMapClusterer.previewAnnotations(
            points: Array(snapshot.points.reversed()),
            region: region,
            viewportSize: viewport
        )

        #expect(first == second)
        #expect(first.count <= 63)
        let representedPointCount = first.reduce(0) { count, annotation in
            switch annotation {
            case .point:
                return count + 1
            case .cluster(let cluster):
                return count + cluster.count
            }
        }
        #expect(representedPointCount == points.count)
    }

    @Test("Clustering defers annotations until map layout has a viewport")
    func zeroSizedViewportDefersAnnotations() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 12, longitude: 45),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
        let interactive = PrivateScanMapClusterer.annotations(
            points: [makePoint(id: "interactive", latitude: 12, longitude: 45)],
            region: region,
            viewportSize: .zero
        )
        let preview = PrivateScanMapClusterer.previewAnnotations(
            points: [
                PrivateScanMapPreviewPoint(
                    id: "preview",
                    latitude: 12,
                    longitude: 45
                )
            ],
            region: region,
            viewportSize: .zero
        )

        #expect(interactive.isEmpty)
        #expect(preview.isEmpty)
    }

    @Test("Spatial index keeps antimeridian candidates without false positives")
    func spatialIndexAntimeridianCandidates() {
        let index = PrivateScanMapSpatialIndex(points: [
            makePoint(id: "east", latitude: 10, longitude: 179.5),
            makePoint(id: "west", latitude: 10, longitude: -179.5),
            makePoint(id: "far", latitude: 10, longitude: 120)
        ])
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 10, longitude: 180),
            span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4)
        )

        #expect(Set(index.candidates(in: region).map(\.id)) == ["east", "west"])
    }

    private func makePoint(
        id: String,
        latitude: Double,
        longitude: Double
    ) -> PrivateScanMapPoint {
        PrivateScanMapPoint(
            id: id,
            latitude: latitude,
            longitude: longitude,
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
