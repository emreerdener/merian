import Foundation

/// Retain this exact request across uncertain local saves. It is not a file or
/// account capability. Mutable execution state never changes these fields.
struct SharedMediaInboxHandoffRequest: Codable, Equatable, Sendable {
    let id: UUID
    let nonce: UUID
    let source: SharedMediaInboxHandle
    let inventoryGeneration: UUID
    let expectedInventoryRevision: Int64
    let ownerID: UUID
    let packageID: UUID
    let draftGeneration: UUID
    let assetID: UUID
    let assetGeneration: UUID
    let referenceID: UUID
    let leaseID: UUID
    let sourceHoldID: UUID
    let ordinal: Int64
    let byteCount: Int64
    let sha256: String

    var handle: PhotoOriginalReference {
        .init(ownerID: ownerID, packageID: packageID, referenceID: referenceID,
            assetID: assetID, assetGeneration: assetGeneration,
            draftGeneration: draftGeneration, referenceRevision: 0)
    }

    func intent(epoch: UUID) -> PhotoPreparationIntent {
        .init(leaseID: leaseID, ownerID: ownerID, packageID: packageID,
            assetID: assetID, assetGeneration: assetGeneration, referenceID: referenceID,
            draftGeneration: draftGeneration, processEpoch: epoch, role: .original,
            ordinal: ordinal, acquisitionKind: "sharedInbox", maximumBytes: byteCount,
            sourceByteLiability: byteCount, sourceIdentity: source.id.uuidString.lowercased())
    }

    func validate() throws {
        guard source.revision >= 0, expectedInventoryRevision >= 0,
              (0..<2).contains(ordinal), byteCount > 0, byteCount <= PhotoPreparationPolicy.original,
              sha256.count == 64, sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
              Set([id, nonce, source.id, sourceHoldID, assetID, referenceID, leaseID]).count == 7 else {
            throw SharedMediaStorageFailure.invalid
        }
    }
}

struct SharedMediaInboxHandoff: Equatable, Sendable {
    let request: SharedMediaInboxHandoffRequest
    let phase: String
    let writerEpoch: UUID
    let writerState: String
    let device: Int64?
    let inode: Int64?
    let finalIdentity: String?
    var detached: Bool { ["detached", "detachedRetiring"].contains(phase) }
    var completed: Bool { ["completed", "sourceRetiring"].contains(phase) }
}

enum SharedMediaInboxHandoffRecovery: Equatable, Sendable {
    case completed(SharedMediaInboxHandoffRequest, PhotoOriginalReference)
    case incomplete(SharedMediaInboxHandoffRequest)
    case detached(SharedMediaInboxHandoffRequest)
    case conflict(SharedMediaInboxHandoffRequest)
}

enum SharedMediaInboxHandoffBoundary: Sendable, Equatable {
    case beforeMetadataSave, afterMetadataSave, beforeFreezeSave, afterFreezeSave
    case beforePairPlanSave, afterPairPlanSave, beforePairPublishSave, afterPairPublishSave
    case beforeReservationSave, afterReservationSave
    case afterPartialCreate, beforeIdentitySave, afterIdentitySave, duringWrite, afterRename
    case beforeCompletionSave, afterCompletionSave
    case beforeClosureSave, afterClosureSave, beforeAbandonSave, afterAbandonSave
    case beforeRetirementSave, afterRetirementSave, afterUnlink, beforeReleaseSave, afterReleaseSave
}

// The full domain name distinguishes this state or capability from adjacent storage boundaries.
// swiftlint:disable:next type_name
struct SharedMediaInboxDestinationRetirementIdentity: Codable, Equatable, Sendable {
    let partial: String
    let final: String
    let parent: String
    let namespace: String
    func encoded() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard data.count <= 512, let value = String(data: data, encoding: .utf8) else { throw SharedMediaStorageFailure.invalid }
        return value
    }
    static func decode(_ value: String) throws -> Self {
        guard value.utf8.count <= 512 else { throw SharedMediaStorageFailure.invalid }
        return try JSONDecoder().decode(Self.self, from: Data(value.utf8))
    }
}
