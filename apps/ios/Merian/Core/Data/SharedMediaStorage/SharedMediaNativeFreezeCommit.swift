import Foundation

/// Fresh native freeze contract. Historical nativeFreezeV2 retains its codec
/// meaning and never acquires this receipt's transition authority.
struct SharedMediaNativeFreezeCommit: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case receipt = "nativeFreezeV3" }
    let format: Format
    let operationID: UUID
    let inventoryID: UUID
    let inventoryGeneration: UUID
    let beforeInventoryRevision: Int64
    let beforePackageRevision: Int64
    let membershipRevision: Int64
    let previousEnvelopeSHA256: String
    let membershipSHA256: String
    let cohort: SharedMediaNativePreparationBlob
    var inventoryRevision: Int64 { get throws { try SharedMediaStoragePolicy.add(beforeInventoryRevision, 1) } }
    var packageRevision: Int64 { get throws { try SharedMediaStoragePolicy.add(beforePackageRevision, 1) } }

    func encoded() throws -> Data {
        guard beforeInventoryRevision >= 0, beforePackageRevision >= 0, membershipRevision >= 0,
              SharedMediaAcquisitionEncoding.isHash(previousEnvelopeSHA256),
              SharedMediaAcquisitionEncoding.isHash(membershipSHA256) else { throw SharedMediaStorageFailure.invalid }
        _ = try inventoryRevision; _ = try packageRevision
        try cohort.validate(); _ = try SharedMediaNativeFrozenCohort.decode(cohort.bytes)
        return try SharedMediaNativeDraftEnvelope.bytes(self)
    }
    static func decode(_ bytes: Data) throws -> Self {
        let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: Int(PhotoPreparationPolicy.metadata))
        guard try value.encoded() == bytes else { throw SharedMediaStorageFailure.conflict }; return value
    }
    static func validateHistoricalOrCurrent(_ bytes: Data) throws {
        struct Header: Decodable { let format: String }
        let header: Header = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: Int(PhotoPreparationPolicy.metadata))
        if header.format == Format.receipt.rawValue { _ = try decode(bytes) }
        else { _ = try SharedMediaNativeFreezeReceipt.decode(bytes) }
    }
}

/// Caller-retained value for exact save acknowledgement recovery. Neither the
/// request nor a returned receipt asserts present physical media availability.
struct SharedMediaNativeFreezeRequest: Codable, Equatable, Sendable {
    let commit: SharedMediaNativeFreezeCommit
    let previousEnvelope: Data
    let membership: Data
    func validate() throws {
        _ = try commit.encoded()
        guard SharedMediaAcquisitionEncoding.digest(previousEnvelope) == commit.previousEnvelopeSHA256,
              SharedMediaAcquisitionEncoding.digest(membership) == commit.membershipSHA256,
              case .preparation(let value) = try SharedMediaNativeDraftEnvelope.decode(previousEnvelope),
              value.frozen == nil, value.attempt == nil else { throw SharedMediaStorageFailure.conflict }
        _ = try SharedMediaMembership.decode(membership)
    }
}
