import Foundation

/// Historical completion postconditions. Later sharing may change current
/// counters/revisions; it must never rewrite this result or repeat completion.
struct SharedMediaAcquisitionResult: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case originalResult = "nativeOriginalResultV1" }
    // Reserved inside the existing combined metadata allowance, not extra space.
    static let reservedEncodingBytes = 8 * 1_024
    let format: Format
    let version: Int
    let requestFingerprint: String
    let operationID: UUID
    let assetID: UUID
    let assetGeneration: UUID
    let referenceID: UUID
    let leaseID: UUID
    let referenceRevision: Int64
    let counterLiveCount: Int64
    let counterRevision: Int64
    let leaseClosed: Bool
    let acquisitionWorkRemoved: Bool
    let inventoryRevision: Int64
    let packageRevision: Int64
    let membershipRevision: Int64
    let byteCount: Int64
    let sha256: String
    let contentType: String
    let descriptor: SharedMediaPhotoRetirementIdentity

    init(request: SharedMediaAcquisitionIntent, inventoryRevision: Int64,
         packageRevision: Int64, membershipRevision: Int64, byteCount: Int64,
         sha256: String, contentType: String, descriptor: SharedMediaPhotoRetirementIdentity) throws {
        format = .originalResult; version = 1
        requestFingerprint = try request.fingerprint()
        operationID = request.operationID; assetID = request.assetID
        assetGeneration = request.assetGeneration; referenceID = request.referenceID
        leaseID = request.operationID; referenceRevision = 0
        counterLiveCount = 1; counterRevision = 0
        leaseClosed = true; acquisitionWorkRemoved = true
        self.inventoryRevision = inventoryRevision; self.packageRevision = packageRevision
        self.membershipRevision = membershipRevision; self.byteCount = byteCount
        self.sha256 = sha256; self.contentType = contentType; self.descriptor = descriptor
        try validate(request: request)
    }

    func validate(request: SharedMediaAcquisitionIntent) throws {
        try request.validate()
        let minimumPackageRevision: Int64
        switch request.packageExpectation {
        case .absent: minimumPackageRevision = 1
        case .revision(let revision): minimumPackageRevision = revision + 2
        }
        guard version == 1, requestFingerprint == (try request.fingerprint()),
              operationID == request.operationID, assetID == request.assetID,
              assetGeneration == request.assetGeneration, referenceID == request.referenceID,
              leaseID == request.operationID, referenceRevision == 0,
              counterLiveCount == 1, counterRevision == 0,
              leaseClosed, acquisitionWorkRemoved,
              inventoryRevision >= request.expectedInventoryRevision + 2,
              packageRevision >= minimumPackageRevision, membershipRevision >= 1,
              byteCount > 0, byteCount <= request.maximumBytes,
              SharedMediaAcquisitionEncoding.isHash(sha256),
              !contentType.isEmpty, contentType.utf8.count <= 128 else { throw SharedMediaStorageFailure.conflict }
        // Reuse the existing descriptor grammar, not its retirement authority.
        _ = try SharedMediaNativeRetirementIdentity(retirementID: request.operationID,
            assetID: assetID, assetGeneration: assetGeneration, inventoryID: request.inventoryID,
            inventoryGeneration: request.inventoryGeneration, ownerID: request.ownerID, proof: descriptor)
        guard Int64(descriptor.file.split(separator: ":")[2]) == byteCount else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    func encoded(request: SharedMediaAcquisitionIntent) throws -> Data {
        try validate(request: request)
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: Self.reservedEncodingBytes)
    }

    static func decode(_ bytes: Data, request: SharedMediaAcquisitionIntent) throws -> Self {
        let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: reservedEncodingBytes)
        guard try value.encoded(request: request) == bytes else { throw SharedMediaStorageFailure.conflict }
        return value
    }
}
