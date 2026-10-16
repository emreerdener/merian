import Foundation

/// An assertion resolved against the ledger, never a path or permission to read a file.
struct PhotoOriginalReference: Codable, Hashable, Sendable {
    let contractVersion: String
    let ownerID: UUID
    let packageID: UUID
    let referenceID: UUID
    let assetID: UUID
    let assetGeneration: UUID
    let draftGeneration: UUID
    let referenceRevision: Int64

    func validate() throws {
        guard contractVersion == PhotoPreparationPolicy.contract, referenceRevision >= 0 else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
    }

    init(ownerID: UUID, packageID: UUID, referenceID: UUID, assetID: UUID,
         assetGeneration: UUID, draftGeneration: UUID, referenceRevision: Int64) {
        self.contractVersion = PhotoPreparationPolicy.contract
        self.ownerID = ownerID
        self.packageID = packageID
        self.referenceID = referenceID
        self.assetID = assetID
        self.assetGeneration = assetGeneration
        self.draftGeneration = draftGeneration
        self.referenceRevision = referenceRevision
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = try c.decode(String.self, forKey: .contractVersion)
        ownerID = try c.decode(UUID.self, forKey: .ownerID)
        packageID = try c.decode(UUID.self, forKey: .packageID)
        referenceID = try c.decode(UUID.self, forKey: .referenceID)
        assetID = try c.decode(UUID.self, forKey: .assetID)
        assetGeneration = try c.decode(UUID.self, forKey: .assetGeneration)
        draftGeneration = try c.decode(UUID.self, forKey: .draftGeneration)
        referenceRevision = try c.decode(Int64.self, forKey: .referenceRevision)
        try validate()
    }
}

struct PhotoPreparationSnapshot: Sendable {
    let originals: [PhotoOriginalReference]
    let expectedPackageRevision: Int64
    let supportingContexts: [ObservationContext]
}

struct PhotoPreparationReceipt: Equatable, Sendable {
    let packageID: UUID
    let revision: Int64
}

struct PhotoPreparationFile: Equatable, Sendable {
    let assetID: UUID
    let generation: UUID
    let token: String
    let byteCount: Int64
    let sha256: String
    let contentType: String
}

struct PhotoPreparationIntent: Sendable {
    let leaseID: UUID
    let ownerID: UUID
    let packageID: UUID
    let assetID: UUID
    let assetGeneration: UUID
    let referenceID: UUID
    let draftGeneration: UUID
    let processEpoch: UUID
    let role: PhotoPreparationRole
    let ordinal: Int64
    let acquisitionKind: String
    let maximumBytes: Int64
    var sourceByteLiability: Int64 = 0
    var sourceIdentity: String? = nil

    var fileToken: String { ownerID.uuidString.lowercased() + "/" + packageID.uuidString.lowercased() + "/" + assetID.uuidString.lowercased() }
}

enum PhotoPreparationRole: String, Sendable { case original, aiInput, display }
enum PhotoPreparationFailure: Error, Equatable {
    case busy, unavailable, invalidMedia, sizeLimit, storageLimit, missingMedia
    case inconsistentOwnership, staleGeneration, immutablePackage, cleanupPending
    case unsupportedComposition, accountChanged
}

struct PhotoPreparationDraft: Sendable {
    let packageID: UUID
    let draftGeneration: UUID
    let revision: Int64
    let phase: String
    let originals: [PhotoOriginalReference]
    let contexts: [ObservationContext]
    let needsAttention: Bool
    let presentation: [PhotoPreparationImagePresentation]
    let retainedSourceIdentities: [String]
}

/// Private, bounded presentation metadata; never sent to admission or inference.
struct PhotoPreparationImagePresentation: Codable, Sendable {
    let referenceID: UUID
    let addedAt: Date
    let isFromGallery: Bool
    let cropQuarterTurns: Int
    let cropScale: Double
    let cropOffsetX: Double
    let cropOffsetY: Double
    let focus: NormalizedImageFocusRegion?
    let latitude: Double?
    let longitude: Double?
    let locationName: String?
    let weatherCondition: String?
    let weatherTemperature: Double?
    let captureDate: Date?
}

struct PhotoPreparationDraftEnvelope: Codable, Sendable {
    let version: Int
    let contexts: [ObservationContext]
    let presentation: [PhotoPreparationImagePresentation]
}
