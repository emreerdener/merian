import CoreLocation
import Foundation
import MapKit

enum PrivateScanMapClusterer {
    static let interactiveCellSize: CGFloat = 56
    static let previewCellSize: CGFloat = 44

    private struct Bucket: Hashable {
        let column: Int
        let row: Int
    }

    private struct ClusterGroup<Point> {
        let sortIdentity: String
        let clusterIdentity: String?
        let coordinate: CLLocationCoordinate2D
        let points: [Point]
    }

    static func annotations(
        points: [PrivateScanMapPoint],
        region: MKCoordinateRegion,
        viewportSize: CGSize,
        cellSize: CGFloat = interactiveCellSize
    ) -> [PrivateScanMapAnnotation] {
        guard let projection = PrivateScanMapScreenProjection(
            region: region,
            viewportSize: viewportSize
        ) else {
            return []
        }
        return clusterGroups(
            points: points,
            region: region,
            viewportSize: viewportSize,
            cellSize: cellSize,
            identifier: \.id,
            coordinate: \.coordinate,
            screenPoint: projection.point(for:),
            averageCoordinate: projection.averageCoordinate
        ) { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id < rhs.id
        }
        .map { group in
            guard let clusterIdentity = group.clusterIdentity else {
                return .point(group.points[0])
            }
            return .cluster(PrivateScanMapCluster(
                id: clusterIdentity,
                latitude: group.coordinate.latitude,
                longitude: group.coordinate.longitude,
                points: group.points
            ))
        }
    }

    static func previewAnnotations(
        points: [PrivateScanMapPreviewPoint],
        region: MKCoordinateRegion,
        viewportSize: CGSize,
        cellSize: CGFloat = previewCellSize
    ) -> [PrivateScanMapPreviewAnnotation] {
        guard let projection = PrivateScanMapScreenProjection(
            region: region,
            viewportSize: viewportSize
        ) else {
            return []
        }
        return previewAnnotations(
            points: points,
            region: region,
            viewportSize: viewportSize,
            cellSize: cellSize,
            screenPoint: projection.point(for:),
            averageCoordinate: projection.averageCoordinate
        )
    }

    static func previewAnnotations(
        points: [PrivateScanMapPreviewPoint],
        region: MKCoordinateRegion,
        viewportSize: CGSize,
        cellSize: CGFloat = previewCellSize,
        screenPoint: (CLLocationCoordinate2D) -> CGPoint
    ) -> [PrivateScanMapPreviewAnnotation] {
        guard let projection = PrivateScanMapScreenProjection(
            region: region,
            viewportSize: viewportSize
        ) else {
            return []
        }
        return previewAnnotations(
            points: points,
            region: region,
            viewportSize: viewportSize,
            cellSize: cellSize,
            screenPoint: screenPoint,
            averageCoordinate: projection.averageCoordinate
        )
    }

    private static func previewAnnotations(
        points: [PrivateScanMapPreviewPoint],
        region: MKCoordinateRegion,
        viewportSize: CGSize,
        cellSize: CGFloat,
        screenPoint: (CLLocationCoordinate2D) -> CGPoint,
        averageCoordinate: ([CLLocationCoordinate2D]) -> CLLocationCoordinate2D
    ) -> [PrivateScanMapPreviewAnnotation] {
        clusterGroups(
            points: points,
            region: region,
            viewportSize: viewportSize,
            cellSize: cellSize,
            identifier: \.id,
            coordinate: \.coordinate,
            screenPoint: screenPoint,
            averageCoordinate: averageCoordinate,
            areInIncreasingOrder: { $0.id < $1.id }
        )
        .map { group in
            guard let clusterIdentity = group.clusterIdentity else {
                return .point(group.points[0])
            }
            return .cluster(PrivateScanMapPreviewCluster(
                id: clusterIdentity,
                latitude: group.coordinate.latitude,
                longitude: group.coordinate.longitude,
                count: group.points.count
            ))
        }
    }

    private static func clusterGroups<Point>(
        points: [Point],
        region: MKCoordinateRegion,
        viewportSize: CGSize,
        cellSize: CGFloat,
        identifier: KeyPath<Point, String>,
        coordinate: KeyPath<Point, CLLocationCoordinate2D>,
        screenPoint: (CLLocationCoordinate2D) -> CGPoint,
        averageCoordinate: ([CLLocationCoordinate2D]) -> CLLocationCoordinate2D,
        areInIncreasingOrder: (Point, Point) -> Bool
    ) -> [ClusterGroup<Point>] {
        guard viewportSize.width.isFinite,
              viewportSize.height.isFinite,
              viewportSize.width > 0,
              viewportSize.height > 0,
              cellSize.isFinite,
              cellSize > 0 else {
            return []
        }

        let visiblePoints = points.filter {
            PrivateScanMapRegion.contains($0[keyPath: coordinate], in: region)
        }
        let columnCount = max(Int(ceil(viewportSize.width / cellSize)), 1)
        let rowCount = max(Int(ceil(viewportSize.height / cellSize)), 1)
        var grouped: [Bucket: [Point]] = [:]
        grouped.reserveCapacity(min(visiblePoints.count, columnCount * rowCount))

        for point in visiblePoints {
            let projectedPoint = screenPoint(point[keyPath: coordinate])
            guard projectedPoint.x.isFinite, projectedPoint.y.isFinite else {
                continue
            }
            let column = min(
                max(Int(floor(projectedPoint.x / cellSize)), 0),
                columnCount - 1
            )
            let row = min(
                max(Int(floor(projectedPoint.y / cellSize)), 0),
                rowCount - 1
            )
            grouped[Bucket(column: column, row: row), default: []].append(point)
        }

        return grouped
            .map { bucket, bucketPoints in
                let sortedPoints = bucketPoints.sorted(by: areInIncreasingOrder)
                let pointIdentity = sortedPoints[0][keyPath: identifier]
                let center = averageCoordinate(
                    sortedPoints.map { $0[keyPath: coordinate] }
                )
                guard sortedPoints.count > 1 else {
                    return ClusterGroup(
                        sortIdentity: "point:\(pointIdentity)",
                        clusterIdentity: nil,
                        coordinate: center,
                        points: sortedPoints
                    )
                }

                let memberIdentity = sortedPoints
                    .map { $0[keyPath: identifier] }
                    .joined(separator: ",")
                let clusterIdentity =
                    "\(bucket.column):\(bucket.row):\(memberIdentity)"
                return ClusterGroup(
                    sortIdentity: "cluster:\(clusterIdentity)",
                    clusterIdentity: clusterIdentity,
                    coordinate: center,
                    points: sortedPoints
                )
            }
            .sorted { $0.sortIdentity < $1.sortIdentity }
    }
}
