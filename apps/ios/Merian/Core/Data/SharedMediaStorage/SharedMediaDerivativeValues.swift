import Foundation

/// An immutable edit request, never a file, account, or inference capability.
struct SharedMediaDerivativeRequest: Codable, Equatable, Sendable {
    let id: UUID
    let nonce: UUID
    let inventoryID: UUID
    let inventoryGeneration: UUID
    let expectedInventoryRevision: Int64
    let original: PhotoOriginalReference
    let ordinal: Int64
    let expectedPackageRevision: Int64
    let previousPairID: UUID?
    let ai: SharedMediaDerivativeInput
    let display: SharedMediaDerivativeInput

    var inputs: [SharedMediaDerivativeInput] { [ai, display] }
    func validate() throws {
        try original.validate()
        guard expectedInventoryRevision >= 0, expectedPackageRevision >= 0,
              (0..<2).contains(ordinal), ai.role == "aiInput", display.role == "display",
              Set([id, nonce] + inputs.flatMap { [$0.id, $0.assetID, $0.referenceID, $0.leaseID] }).count == 10,
              previousPairID != id else { throw SharedMediaStorageFailure.invalid }
        for input in inputs { try input.validate() }
    }
}

struct SharedMediaDerivativeInput: Codable, Equatable, Sendable {
    let id: UUID
    let role: String
    let assetID: UUID
    let assetGeneration: UUID
    let referenceID: UUID
    let leaseID: UUID
    let byteCount: Int64
    let sha256: String
    let contentType: String

    func validate() throws {
        guard let role = PhotoPreparationRole(rawValue: role), role != .original,
              byteCount > 0, byteCount <= PhotoPreparationPolicy.limit(for: role),
              sha256.count == 64, sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
              !contentType.isEmpty, contentType.utf8.count <= 128 else { throw SharedMediaStorageFailure.invalid }
    }
}

struct SharedMediaDerivativePair: Equatable, Sendable {
    let request: SharedMediaDerivativeRequest
    let phase: String
    let publishedRevision: Int64?
    let work: [SharedMediaDerivativeWork]
}

struct SharedMediaDerivativeWork: Equatable, Sendable {
    let request: SharedMediaDerivativeRequest
    let input: SharedMediaDerivativeInput
    let writerEpoch: UUID
    let phase: String
    let writerState: String
    let device: Int64?
    let inode: Int64?
    let finalIdentity: String?
    let retirementID: UUID?
    let retirementPartial: String?
    let retirementFinal: String?
    let retirementParent: String?
    let retirementNamespace: String?

    var token: String {
        request.original.ownerID.uuidString.lowercased() + "/" +
            request.original.packageID.uuidString.lowercased() + "/" + input.assetID.uuidString.lowercased()
    }
    var file: PhotoPreparationFile {
        .init(assetID: input.assetID, generation: input.assetGeneration, token: token,
              byteCount: input.byteCount, sha256: input.sha256, contentType: input.contentType)
    }
}

struct SharedMediaDerivativeReceipt: Equatable, Sendable {
    let pairID: UUID
    let original: PhotoOriginalReference
    let publishedRevision: Int64
    let ai: PhotoPreparationFile
    let display: PhotoPreparationFile
}

enum SharedMediaDerivativeRecovery: Equatable, Sendable {
    case ready(SharedMediaDerivativeReceipt)
    case incomplete(SharedMediaDerivativeRequest)
    case conflict(SharedMediaDerivativeRequest)
}
