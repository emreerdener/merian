import Foundation
import SwiftData

@ModelActor
actor PrivateScanMapDatabaseActor {
    func fetchRecordProjections() throws -> [PrivateScanMapRecordProjection] {
        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.isBiological == true },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        return try modelContext.fetch(descriptor).compactMap { record in
            guard let latitude = record.gpsLatitude,
                  let longitude = record.gpsLongitude,
                  PrivateScanMapRegion.isValidCoordinate(
                      latitude: latitude,
                      longitude: longitude
                  ) else {
                return nil
            }

            let mediaSource: PrivateScanMapMediaSource
            if let capturedMediaJSON = record.capturedMediaJSON {
                mediaSource = .json(capturedMediaJSON)
            } else {
                mediaSource = .items(record.serializedCapturedMediaItems)
            }

            return PrivateScanMapRecordProjection(
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
                mediaSource: mediaSource
            )
        }
    }

    func fetchReferenceFallbackCandidates(
        scanIds: [String]
    ) throws -> [ScanThumbnailBackfillCandidate] {
        var candidates: [ScanThumbnailBackfillCandidate] = []
        candidates.reserveCapacity(scanIds.count)

        for scanId in scanIds {
            var descriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate { $0.id == scanId }
            )
            descriptor.fetchLimit = 1
            guard let record = try modelContext.fetch(descriptor).first,
                  let candidate = ScanThumbnailBackfillCandidate(
                      missingVisualFallbackFor: record
                  ) else {
                continue
            }
            candidates.append(candidate)
        }

        return candidates
    }
}
