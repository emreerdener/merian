import Foundation

enum PrivateScanMapMediaSource: Equatable, Sendable {
    case json(String)
    case items([SerializedMediaItem])

    var snapshot: CapturedMediaSnapshot {
        switch self {
        case .json(let json):
            CapturedMediaSnapshot(jsonString: json)
        case .items(let items):
            CapturedMediaSnapshot(items: items)
        }
    }
}

struct PrivateScanMapRecordProjection: Equatable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    let commonName: String
    let scientificName: String
    let userIdentificationOverride: String?
    let timestamp: Date
    let locationName: String?
    let taxonomyKingdom: String?
    let taxonomyClass: String?
    let coverImagePath: String?
    let referenceImageUrl: String?
    let isLocallyArchived: Bool
    let canResolveReferenceImage: Bool
    let mediaSource: PrivateScanMapMediaSource

    var mapPoint: PrivateScanMapPoint? {
        PrivateScanMapPoint.projected(
            id: id,
            latitude: latitude,
            longitude: longitude,
            commonName: commonName,
            scientificName: scientificName,
            userIdentificationOverride: userIdentificationOverride,
            timestamp: timestamp,
            locationName: locationName,
            taxonomyKingdom: taxonomyKingdom,
            taxonomyClass: taxonomyClass,
            coverImagePath: coverImagePath,
            referenceImageUrl: referenceImageUrl,
            isLocallyArchived: isLocallyArchived,
            canResolveReferenceImage: canResolveReferenceImage,
            mediaSnapshot: mediaSource.snapshot
        )
    }
}

struct PrivateScanMapIndexSnapshot: Equatable, Sendable {
    static let empty = PrivateScanMapIndexSnapshot(
        revision: 0,
        spatialRevision: 0,
        previewSnapshot: .empty,
        interactiveSnapshot: .empty
    )

    let revision: UInt64
    let spatialRevision: UInt64
    let previewSnapshot: PrivateScanMapPreviewSnapshot
    let interactiveSnapshot: PrivateScanMapSnapshot
}
