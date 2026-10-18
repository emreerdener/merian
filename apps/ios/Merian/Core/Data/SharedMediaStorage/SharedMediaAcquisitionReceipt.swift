import Foundation

/// Closed interpretation of a raw V64 row. This value does not validate the
/// current ownership graph or filesystem and grants no operational capability.
enum SharedMediaAcquisitionReceipt: Equatable, Sendable {
    case reserved(SharedMediaAcquisitionIntent)
    case held(SharedMediaAcquisitionIntent)
    case completed(SharedMediaAcquisitionIntent, SharedMediaAcquisitionResult)
    case released(TerminalIdentity)

    struct TerminalIdentity: Equatable, Sendable {
        let operationID: UUID
        let inventoryID: UUID
        let inventoryGeneration: UUID
        let ownerID: UUID
        let requestFingerprint: String
    }

    /// Cold row-originated recovery, including terminal rows that deliberately
    /// retain no full request. Callers must still validate their lookup scope.
    @MainActor
    static func read(_ row: SharedMediaAcquisitionReceiptRecord) throws -> Self {
        guard row.schemaVersion == 1, SharedMediaAcquisitionEncoding.isHash(row.requestFingerprint) else {
            throw SharedMediaStorageFailure.conflict
        }
        if row.phaseRaw == "terminal" {
            guard row.revision == 2, row.terminalOutcomeRaw == "released",
                  row.requestData == nil, row.resultData == nil,
                  row.packageID == nil, row.assetID == nil else { throw SharedMediaStorageFailure.conflict }
            return .released(.init(operationID: row.id, inventoryID: row.inventoryID,
                inventoryGeneration: row.inventoryGeneration, ownerID: row.ownerID,
                requestFingerprint: row.requestFingerprint))
        }
        guard let bytes = row.requestData else { throw SharedMediaStorageFailure.conflict }
        let request = try SharedMediaAcquisitionIntent.decode(bytes)
        guard row.id == request.operationID, row.inventoryID == request.inventoryID,
              row.inventoryGeneration == request.inventoryGeneration, row.ownerID == request.ownerID,
              row.requestFingerprint == SharedMediaAcquisitionEncoding.digest(bytes),
              row.packageID == request.packageID, row.assetID == request.assetID,
              row.terminalOutcomeRaw == nil else {
            throw SharedMediaStorageFailure.conflict
        }
        switch row.phaseRaw {
        case "reserved":
            guard row.revision == 0, row.resultData == nil else { throw SharedMediaStorageFailure.conflict }
            return .reserved(request)
        case "held":
            guard row.revision == 1, row.resultData == nil else { throw SharedMediaStorageFailure.conflict }
            return .held(request)
        case "completed":
            guard row.revision == 1, let result = row.resultData else { throw SharedMediaStorageFailure.conflict }
            return .completed(request, try SharedMediaAcquisitionResult.decode(result, request: request))
        default: throw SharedMediaStorageFailure.conflict
        }
    }

    /// Admission/replay matching is additional to persisted-state recovery.
    /// Neither a match nor a decoded reservation authorizes another writer.
    @MainActor
    static func read(_ row: SharedMediaAcquisitionReceiptRecord,
                     expected request: SharedMediaAcquisitionIntent) throws -> Self {
        let bytes = try request.encoded()
        let value = try read(row)
        guard row.id == request.operationID, row.inventoryID == request.inventoryID,
              row.inventoryGeneration == request.inventoryGeneration, row.ownerID == request.ownerID,
              row.requestFingerprint == SharedMediaAcquisitionEncoding.digest(bytes),
              row.phaseRaw == "terminal" || row.requestData == bytes else { throw SharedMediaStorageFailure.conflict }
        return value
    }

    /// Encoding headroom only. The transaction owner must derive all receipt
    /// charges from the authoritative graph and project combined memberships.
    static func metadataCharge(request: SharedMediaAcquisitionIntent,
                               result: SharedMediaAcquisitionResult?) throws -> Int64 {
        let requestBytes = try request.encoded().count
        let resultBytes = try result?.encoded(request: request).count ?? SharedMediaAcquisitionResult.reservedEncodingBytes
        return try PhotoPreparationPolicy.add([Int64(requestBytes), Int64(resultBytes)])
    }
}
