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
        if mediaSummary.hasImage || normalizedText(coverImagePath) != nil {
            mediaFilters.insert(.image)
        }
        if mediaSummary.hasAudio {
            mediaFilters.insert(.audio)
        }

        let effectiveScientificName = normalizedText(userIdentificationOverride)
            ?? scientificName
        return PrivateScanMapPoint(
            id: id,
            latitude: latitude,
            longitude: longitude,
            commonName: commonName,
            scientificName: effectiveScientificName,
            timestamp: timestamp,
            locationName: normalizedText(locationName),
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

    private static func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
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
            .sorted(by: Self.ordersBefore)
    }

    init(points: [PrivateScanMapPoint], revision: UInt64 = 0) {
        self.revision = revision
        self.points = points.sorted(by: Self.ordersBefore)
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

    private static func ordersBefore(
        _ lhs: PrivateScanMapPoint,
        _ rhs: PrivateScanMapPoint
    ) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp > rhs.timestamp
        }
        return lhs.id < rhs.id
    }
}
