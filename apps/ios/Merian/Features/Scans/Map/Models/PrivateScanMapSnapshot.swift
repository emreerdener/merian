import CoreLocation
import Foundation
import MapKit

struct PrivateScanMapPreviewPoint: Identifiable, Equatable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct PrivateScanMapPreviewSnapshot: Equatable, Sendable {
    static let empty = PrivateScanMapPreviewSnapshot(points: [])

    let points: [PrivateScanMapPreviewPoint]

    @MainActor
    init(records: [LocalScanRecord]) {
        points = records
            .compactMap(Self.point(for:))
            .sorted { $0.id < $1.id }
    }

    init(points: [PrivateScanMapPreviewPoint]) {
        self.points = points.sorted { $0.id < $1.id }
    }

    var fullExtentRegion: MKCoordinateRegion? {
        PrivateScanMapRegion.fitted(
            to: points.map(\.coordinate),
            padding: 1.25,
            minimumSpan: 0.2
        )
    }

    var identity: String {
        points.map { point in
            [
                point.id,
                String(point.latitude),
                String(point.longitude)
            ].joined(separator: "\u{1f}")
        }
        .joined(separator: "\u{1e}")
    }

    @MainActor
    private static func point(
        for record: LocalScanRecord
    ) -> PrivateScanMapPreviewPoint? {
        guard record.isBiological,
              let latitude = record.gpsLatitude,
              let longitude = record.gpsLongitude,
              PrivateScanMapRegion.isValidCoordinate(
                  latitude: latitude,
                  longitude: longitude
              ) else {
            return nil
        }

        return PrivateScanMapPreviewPoint(
            id: record.id,
            latitude: latitude,
            longitude: longitude
        )
    }
}

struct PrivateScanMapPoint: Identifiable, Equatable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    let commonName: String
    let scientificName: String
    let timestamp: Date
    let locationName: String?
    let category: SearchCategoryBucket
    let mediaFilters: Set<ScanMediaFilter>
    let thumbnail: ScanThumbnailPresentation

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func projected(
        id: String,
        latitude: Double,
        longitude: Double,
        commonName: String,
        scientificName: String,
        userIdentificationOverride: String?,
        timestamp: Date,
        locationName: String?,
        taxonomyKingdom: String?,
        taxonomyClass: String?,
        coverImagePath: String?,
        referenceImageUrl: String?,
        isLocallyArchived: Bool,
        canResolveReferenceImage: Bool,
        mediaSnapshot: CapturedMediaSnapshot
    ) -> PrivateScanMapPoint? {
        guard PrivateScanMapRegion.isValidCoordinate(
            latitude: latitude,
            longitude: longitude
        ) else {
            return nil
        }

        let mediaSummary = mediaSnapshot.summary
        var mediaFilters = Set<ScanMediaFilter>()
        if mediaSummary.hasVideo {
            mediaFilters.insert(.video)
        }
        if mediaSummary.hasImage || coverImagePath?.trimmedNonEmpty != nil {
            mediaFilters.insert(.image)
        }
        if mediaSummary.hasAudio {
            mediaFilters.insert(.audio)
        }

        let effectiveScientificName = userIdentificationOverride?.trimmedNonEmpty
            ?? scientificName
        return PrivateScanMapPoint(
            id: id,
            latitude: latitude,
            longitude: longitude,
            commonName: commonName,
            scientificName: effectiveScientificName,
            timestamp: timestamp,
            locationName: locationName?.trimmedNonEmpty,
            category: SearchCategoryBucket(
                kingdom: taxonomyKingdom?.lowercased() ?? "",
                className: taxonomyClass?.lowercased() ?? ""
            ),
            mediaFilters: mediaFilters,
            thumbnail: ScanThumbnailProjection.presentation(
                isBiological: true,
                isLocallyArchived: isLocallyArchived,
                scientificName: effectiveScientificName,
                coverImagePath: coverImagePath,
                referenceImageUrl: referenceImageUrl,
                mediaSnapshot: mediaSnapshot,
                canResolveReferenceImage: canResolveReferenceImage
            )
        )
    }
}

struct PrivateScanMapSnapshot: Equatable, Sendable {
    static let empty = PrivateScanMapSnapshot(points: [])

    let revision: UInt64
    let points: [PrivateScanMapPoint]

    @MainActor
    init(records: [LocalScanRecord], revision: UInt64 = 0) {
        self.revision = revision
        points = records
            .compactMap(Self.point(for:))
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.id < rhs.id
            }
    }

    init(points: [PrivateScanMapPoint], revision: UInt64 = 0) {
        self.revision = revision
        self.points = points.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id < rhs.id
        }
    }

    var newestPoint: PrivateScanMapPoint? {
        points.first
    }

    var fullExtentRegion: MKCoordinateRegion? {
        PrivateScanMapRegion.fitted(
            to: points.map(\.coordinate),
            padding: 1.25,
            minimumSpan: 0.2
        )
    }

    var identity: String {
        points.map { point in
            let media = point.mediaFilters.map(\.rawValue).sorted().joined(separator: ",")
            return [
                point.id,
                String(point.latitude),
                String(point.longitude),
                String(point.timestamp.timeIntervalSince1970),
                point.commonName,
                point.scientificName,
                point.locationName ?? "",
                point.category.rawValue,
                media,
                point.thumbnail.imagePath ?? "",
                point.thumbnail.fallbackImageUrl ?? "",
                point.thumbnail.audioPath ?? "",
                point.thumbnail.hasVideo ? "1" : "0",
                point.thumbnail.hasAudio ? "1" : "0"
            ].joined(separator: "\u{1f}")
        }
        .joined(separator: "\u{1e}")
    }

    @MainActor
    private static func point(for record: LocalScanRecord) -> PrivateScanMapPoint? {
        guard record.isBiological,
              let latitude = record.gpsLatitude,
              let longitude = record.gpsLongitude,
              PrivateScanMapRegion.isValidCoordinate(
                  latitude: latitude,
                  longitude: longitude
              ) else {
            return nil
        }

        return PrivateScanMapPoint.projected(
            id: record.id,
            latitude: latitude,
            longitude: longitude,
            commonName: record.commonName,
            scientificName: record.scientificName,
            userIdentificationOverride: record.userIdentificationOverride,
            timestamp: record.timestamp,
            locationName: record.locationName,
            taxonomyKingdom: record.taxonomyKingdom,
            taxonomyClass: record.taxonomyClass,
            coverImagePath: record.coverImagePath,
            referenceImageUrl: record.referenceImageUrl,
            isLocallyArchived: record.isLocallyArchived,
            canResolveReferenceImage: ScanThumbnailBackfillCandidate(
                missingVisualFallbackFor: record
            ) != nil,
            mediaSnapshot: record.capturedMediaSnapshot
        )
    }
}

enum PrivateScanMapCollectionSearch {
    private static let aliases = [
        "scan map",
        "map",
        "private",
        "locations",
        "your scans"
    ]

    static func matches(_ query: String) -> Bool {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedQuery.isEmpty || aliases.contains {
            $0.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }
}

enum PrivateScanMapRegion {
    static func isValidCoordinate(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite
            && longitude.isFinite
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
            && !(latitude == 0 && longitude == 0)
    }

    static func centered(
        on coordinate: CLLocationCoordinate2D,
        span: Double
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: span,
                longitudeDelta: span
            )
        )
    }

    static func fitted(
        to coordinates: [CLLocationCoordinate2D],
        padding: Double,
        minimumSpan: Double
    ) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }

        let latitudes = coordinates.map(\.latitude)
        guard let minimumLatitude = latitudes.min(),
              let maximumLatitude = latitudes.max() else {
            return nil
        }

        let longitudeArc = shortestLongitudeArc(
            coordinates.map(\.longitude)
        )
        let latitudeSpan = min(
            max((maximumLatitude - minimumLatitude) * padding, minimumSpan),
            180
        )
        let longitudeSpan = min(
            max(longitudeArc.span * padding, minimumSpan),
            360
        )

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: longitudeArc.center
            ),
            span: MKCoordinateSpan(
                latitudeDelta: latitudeSpan,
                longitudeDelta: longitudeSpan
            )
        )
    }

    static func contains(
        _ coordinate: CLLocationCoordinate2D,
        in region: MKCoordinateRegion
    ) -> Bool {
        let latitudeHalfSpan = region.span.latitudeDelta / 2
        guard coordinate.latitude >= region.center.latitude - latitudeHalfSpan,
              coordinate.latitude <= region.center.latitude + latitudeHalfSpan else {
            return false
        }

        guard region.span.longitudeDelta < 360 else { return true }
        return wrappedLongitudeDistance(
            coordinate.longitude,
            region.center.longitude
        ) <= (region.span.longitudeDelta / 2) + 0.000_000_1
    }

    static func positiveLongitudeDistance(from start: Double, to end: Double) -> Double {
        let delta = (normalizedLongitude360(end) - normalizedLongitude360(start))
            .truncatingRemainder(dividingBy: 360)
        return delta >= 0 ? delta : delta + 360
    }

    private static func shortestLongitudeArc(_ longitudes: [Double]) -> (
        center: Double,
        span: Double
    ) {
        let sorted = longitudes.map(normalizedLongitude360).sorted()
        guard let first = sorted.first else { return (0, 0) }
        guard sorted.count > 1 else {
            return (normalizedLongitude180(first), 0)
        }

        var largestGap = -Double.infinity
        var largestGapStartIndex = 0

        for index in sorted.indices {
            let next = index == sorted.index(before: sorted.endIndex)
                ? first + 360
                : sorted[index + 1]
            let gap = next - sorted[index]
            if gap > largestGap {
                largestGap = gap
                largestGapStartIndex = index
            }
        }

        let arcStartIndex = (largestGapStartIndex + 1) % sorted.count
        let arcStart = sorted[arcStartIndex]
        var arcEnd = sorted[largestGapStartIndex]
        if arcEnd < arcStart {
            arcEnd += 360
        }

        let span = arcEnd - arcStart
        return (
            center: normalizedLongitude180(arcStart + (span / 2)),
            span: span
        )
    }

    private static func wrappedLongitudeDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let delta = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(delta, 360 - delta)
    }

    private static func normalizedLongitude360(_ longitude: Double) -> Double {
        let normalized = longitude.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }

    private static func normalizedLongitude180(_ longitude: Double) -> Double {
        let normalized = normalizedLongitude360(longitude)
        return normalized > 180 ? normalized - 360 : normalized
    }
}

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
        let latitude: Double
        let longitude: Double
        let points: [Point]
    }

    static func annotations(
        points: [PrivateScanMapPoint],
        region: MKCoordinateRegion,
        viewportSize: CGSize,
        cellSize: CGFloat = interactiveCellSize
    ) -> [PrivateScanMapAnnotation] {
        clusterGroups(
            points: points,
            region: region,
            viewportSize: viewportSize,
            cellSize: cellSize,
            identifier: \.id,
            coordinate: \.coordinate
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
                latitude: group.latitude,
                longitude: group.longitude,
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
        clusterGroups(
            points: points,
            region: region,
            viewportSize: viewportSize,
            cellSize: cellSize,
            identifier: \.id,
            coordinate: \.coordinate,
            areInIncreasingOrder: { $0.id < $1.id }
        )
        .map { group in
            guard let clusterIdentity = group.clusterIdentity else {
                return .point(group.points[0])
            }
            return .cluster(PrivateScanMapPreviewCluster(
                id: clusterIdentity,
                latitude: group.latitude,
                longitude: group.longitude,
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
        areInIncreasingOrder: (Point, Point) -> Bool
    ) -> [ClusterGroup<Point>] {
        guard viewportSize.width > 0,
              viewportSize.height > 0,
              cellSize > 0 else {
            return []
        }

        let visiblePoints = points.filter {
            PrivateScanMapRegion.contains($0[keyPath: coordinate], in: region)
        }
        let columnCount = max(Int(ceil(viewportSize.width / cellSize)), 1)
        let rowCount = max(Int(ceil(viewportSize.height / cellSize)), 1)
        let westLongitude = region.center.longitude - (region.span.longitudeDelta / 2)
        let southLatitude = region.center.latitude - (region.span.latitudeDelta / 2)

        var grouped: [Bucket: [Point]] = [:]
        grouped.reserveCapacity(min(visiblePoints.count, columnCount * rowCount))

        for point in visiblePoints {
            let pointCoordinate = point[keyPath: coordinate]
            let longitudeFraction: Double
            if region.span.longitudeDelta >= 360 {
                longitudeFraction = PrivateScanMapRegion.positiveLongitudeDistance(
                    from: westLongitude,
                    to: pointCoordinate.longitude
                ) / 360
            } else {
                longitudeFraction = PrivateScanMapRegion.positiveLongitudeDistance(
                    from: westLongitude,
                    to: pointCoordinate.longitude
                ) / max(region.span.longitudeDelta, 0.000_000_1)
            }
            let latitudeFraction = (pointCoordinate.latitude - southLatitude)
                / max(region.span.latitudeDelta, 0.000_000_1)

            let column = min(
                max(Int(floor(longitudeFraction * Double(columnCount))), 0),
                columnCount - 1
            )
            let row = min(
                max(Int(floor((1 - latitudeFraction) * Double(rowCount))), 0),
                rowCount - 1
            )
            grouped[Bucket(column: column, row: row), default: []].append(point)
        }

        return grouped
            .map { bucket, bucketPoints in
                let sortedPoints = bucketPoints.sorted(by: areInIncreasingOrder)
                let pointIdentity = sortedPoints[0][keyPath: identifier]
                let coordinate = averageCoordinate(
                    of: sortedPoints,
                    coordinate: coordinate
                )
                guard sortedPoints.count > 1 else {
                    return ClusterGroup(
                        sortIdentity: "point:\(pointIdentity)",
                        clusterIdentity: nil,
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude,
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
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    points: sortedPoints
                )
            }
            .sorted { $0.sortIdentity < $1.sortIdentity }
    }

    private static func averageCoordinate<Point>(
        of points: [Point],
        coordinate: KeyPath<Point, CLLocationCoordinate2D>
    ) -> CLLocationCoordinate2D {
        let latitude = points.reduce(0) {
            $0 + $1[keyPath: coordinate].latitude
        } / Double(points.count)
        let longitudeVectors = points.reduce(into: (x: 0.0, y: 0.0)) { result, point in
            let radians = point[keyPath: coordinate].longitude * .pi / 180
            result.x += cos(radians)
            result.y += sin(radians)
        }
        let longitude: Double
        if abs(longitudeVectors.x) < 0.000_000_1,
           abs(longitudeVectors.y) < 0.000_000_1 {
            longitude = points[0][keyPath: coordinate].longitude
        } else {
            longitude = atan2(longitudeVectors.y, longitudeVectors.x) * 180 / .pi
        }

        return CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
