import Foundation
import MapKit

struct PrivateScanMapViewportProjection: Equatable, Sendable {
    static let empty = PrivateScanMapViewportProjection(
        visiblePoints: [],
        annotations: []
    )

    let visiblePoints: [PrivateScanMapPoint]
    let annotations: [PrivateScanMapAnnotation]
}

struct PrivateScanMapSpatialIndex: Sendable {
    private struct Bucket: Hashable, Sendable {
        let latitude: Int
        let longitude: Int

        var center: CLLocationCoordinate2D {
            CLLocationCoordinate2D(
                latitude: Double(latitude) - 89.5,
                longitude: Double(longitude) - 179.5
            )
        }
    }

    private let points: [PrivateScanMapPoint]
    private let pointIndicesByBucket: [Bucket: [Int]]

    init(points: [PrivateScanMapPoint]) {
        self.points = points
        var buckets: [Bucket: [Int]] = [:]
        buckets.reserveCapacity(min(points.count, 4_096))

        for (index, point) in points.enumerated() {
            let bucket = Bucket(
                latitude: Self.latitudeBucket(point.latitude),
                longitude: Self.longitudeBucket(point.longitude)
            )
            buckets[bucket, default: []].append(index)
        }
        pointIndicesByBucket = buckets
    }

    func candidates(in region: MKCoordinateRegion) -> [PrivateScanMapPoint] {
        guard !points.isEmpty else { return [] }
        if region.span.latitudeDelta >= 179,
           region.span.longitudeDelta >= 359 {
            return points
        }

        let paddedRegion = MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: min(region.span.latitudeDelta + 1.000_002, 180),
                longitudeDelta: min(region.span.longitudeDelta + 1.000_002, 360)
            )
        )
        var included = Array(repeating: false, count: points.count)
        for (bucket, indices) in pointIndicesByBucket where
            PrivateScanMapRegion.contains(bucket.center, in: paddedRegion) {
            for index in indices {
                included[index] = true
            }
        }

        return points.indices.compactMap { index in
            included[index] ? points[index] : nil
        }
    }

    private static func latitudeBucket(_ latitude: Double) -> Int {
        min(max(Int(floor(latitude + 90)), 0), 179)
    }

    private static func longitudeBucket(_ longitude: Double) -> Int {
        let shifted = (longitude + 180).truncatingRemainder(dividingBy: 360)
        let normalized = shifted >= 0 ? shifted : shifted + 360
        return min(max(Int(floor(normalized)), 0), 359)
    }
}

actor PrivateScanMapViewportProjector {
    private var cachedDatasetGeneration: UInt64?
    private var cachedSpatialIndex = PrivateScanMapSpatialIndex(points: [])

    func project(
        datasetGeneration: UInt64,
        points: [PrivateScanMapPoint],
        region: MKCoordinateRegion?,
        viewportSize: CGSize
    ) -> PrivateScanMapViewportProjection {
        guard !Task.isCancelled else { return .empty }

        if cachedDatasetGeneration != datasetGeneration {
            let spatialIndex = PrivateScanMapSpatialIndex(points: points)
            guard !Task.isCancelled else { return .empty }
            cachedSpatialIndex = spatialIndex
            cachedDatasetGeneration = datasetGeneration
        }

        guard let region else { return .empty }
        let candidates = cachedSpatialIndex.candidates(in: region)
        guard !Task.isCancelled else { return .empty }

        let visiblePoints = candidates.filter {
            PrivateScanMapRegion.contains($0.coordinate, in: region)
        }
        let annotations = PrivateScanMapClusterer.annotations(
            points: visiblePoints,
            region: region,
            viewportSize: viewportSize
        )
        guard !Task.isCancelled else { return .empty }

        return PrivateScanMapViewportProjection(
            visiblePoints: visiblePoints,
            annotations: annotations
        )
    }

    func reset() {
        cachedDatasetGeneration = nil
        cachedSpatialIndex = PrivateScanMapSpatialIndex(points: [])
    }
}
