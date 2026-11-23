import Foundation

/// Strict read-only interpretation of the currently defined V70 envelopes.
/// It deliberately grants no graph qualification, ownership, I/O or cleanup.
/// All production transfer guards remain closed until the complete lifecycle
/// and atomic queue participant are integrated. Unknown later phases fail closed.
@MainActor
enum SharedMediaOrdinaryHoldReceipt {
    enum State: Equatable, Sendable {
        case reserved(SharedMediaOrdinaryHoldRequest)
        case accepted(SharedMediaOrdinaryHoldRequest, SharedMediaOrdinaryHoldAcceptance)
    }

    struct Snapshot: Equatable, Sendable {
        let state: State
        let metadataBytes: Int64
    }

    static func read(_ row: SharedMediaOrdinaryTransferRecord) throws -> Snapshot {
        let bytes = try SharedMediaOrdinaryHoldEncoding.metadataBytes([
            (row.requestData, row.requestSHA256), (row.completionData, row.completionSHA256),
            (row.acceptanceData, row.acceptanceSHA256), (row.retirementData, row.retirementSHA256)
        ])
        let request = try SharedMediaOrdinaryHoldRequest.decode(row.requestData, sha256: row.requestSHA256)
        guard row.schemaVersion == 1, row.id == request.id, row.cursorKey == request.id.uuidString.lowercased(),
              row.inventoryID == request.profile.inventoryID, row.inventoryGeneration == request.profile.generation,
              row.ownerID == request.profile.ownerID, row.writerEpoch == request.writerEpoch,
              row.sourceAssetID == request.source.assetID, row.sourceReferenceID == request.source.referenceID,
              row.recipientScanID == request.recipient.scanID, row.submissionGeneration == request.recipient.submissionGeneration,
              row.completionData == nil, row.completionSHA256 == nil,
              row.retirementData == nil, row.retirementSHA256 == nil else { throw SharedMediaStorageFailure.conflict }
        switch row.phaseRaw {
        case "reserved":
            guard row.revision == 0, row.acceptanceData == nil, row.acceptanceSHA256 == nil else {
                throw SharedMediaStorageFailure.conflict
            }
            return .init(state: .reserved(request), metadataBytes: bytes)
        case "accepted":
            guard row.revision == 1, let data = row.acceptanceData, let digest = row.acceptanceSHA256 else {
                throw SharedMediaStorageFailure.conflict
            }
            let acceptance = try SharedMediaOrdinaryHoldAcceptance.decode(data, sha256: digest, request: request)
            return .init(state: .accepted(request, acceptance), metadataBytes: bytes)
        default: throw SharedMediaStorageFailure.conflict
        }
    }
}
