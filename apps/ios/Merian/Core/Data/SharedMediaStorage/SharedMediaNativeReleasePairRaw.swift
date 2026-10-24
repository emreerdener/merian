import Foundation
import SwiftData

/// Explicit scalar snapshots for the held-pair transaction. No reflection,
/// truncated descriptions or generic dirty graph audit; every persisted field
/// of each touched model is compared, including fields the writer preserves.
@MainActor
enum SharedMediaNativeReleasePairRaw {
    typealias Fields = [String: Data]
    static func value<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func fields(_ row: SharedMediaInventoryRecord) throws -> Fields {
        try [
            "id": value(row.id),
            "rootIdentity": value(row.rootIdentity),
            "storeIdentity": value(row.storeIdentity),
            "generation": value(row.generation),
            "revision": value(row.revision),
            "modeRaw": value(row.modeRaw),
            "phaseRaw": value(row.phaseRaw),
            "cursor": value(row.cursor)
        ]
    }
    static func fields(_ row: PhotoPreparationRecord) throws -> Fields {
        try [
            "accountingTierRaw": value(row.accountingTierRaw),
            "id": value(row.id),
            "ownerID": value(row.ownerID),
            "contractVersion": value(row.contractVersion),
            "draftID": value(row.draftID),
            "draftGeneration": value(row.draftGeneration),
            "revision": value(row.revision),
            "phaseRaw": value(row.phaseRaw),
            "supportingContextData": value(row.supportingContextData),
            "allocatedByteCount": value(row.allocatedByteCount),
            "retirementRequested": value(row.retirementRequested)
        ]
    }
    static func fields(_ row: SharedMediaPendingMembershipRecord) throws -> Fields {
        try [
            "id": value(row.id),
            "inventoryID": value(row.inventoryID),
            "inventoryGeneration": value(row.inventoryGeneration),
            "ownerID": value(row.ownerID),
            "draftGeneration": value(row.draftGeneration),
            "revision": value(row.revision),
            "membersData": value(row.membersData)
        ]
    }
    static func fields(_ row: SharedMediaReceivingIntentRecord) throws -> Fields {
        try [
            "id": value(row.id),
            "cursorKey": value(row.cursorKey),
            "schemaVersion": value(row.schemaVersion),
            "inventoryID": value(row.inventoryID),
            "inventoryGeneration": value(row.inventoryGeneration),
            "ownerID": value(row.ownerID),
            "draftGeneration": value(row.draftGeneration),
            "operationID": value(row.operationID),
            "phaseRaw": value(row.phaseRaw),
            "revision": value(row.revision),
            "preparedData": value(row.preparedData),
            "preparedSHA256": value(row.preparedSHA256),
            "resultData": value(row.resultData),
            "resultSHA256": value(row.resultSHA256),
            "releaseStartData": value(row.releaseStartData),
            "releaseStartSHA256": value(row.releaseStartSHA256)
        ]
    }
    static func fields(_ row: SharedMediaDerivativePairRecord) throws -> Fields {
        try [
            "id": value(row.id),
            "nonce": value(row.nonce),
            "contractVersion": value(row.contractVersion),
            "inventoryID": value(row.inventoryID),
            "inventoryGeneration": value(row.inventoryGeneration),
            "expectedInventoryRevision": value(row.expectedInventoryRevision),
            "ownerID": value(row.ownerID),
            "packageID": value(row.packageID),
            "draftGeneration": value(row.draftGeneration),
            "originalReferenceID": value(row.originalReferenceID),
            "originalReferenceRevision": value(row.originalReferenceRevision),
            "originalAssetID": value(row.originalAssetID),
            "originalAssetGeneration": value(row.originalAssetGeneration),
            "ordinal": value(row.ordinal),
            "expectedPackageRevision": value(row.expectedPackageRevision),
            "aiWorkID": value(row.aiWorkID),
            "displayWorkID": value(row.displayWorkID),
            "previousPairID": value(row.previousPairID),
            "phaseRaw": value(row.phaseRaw),
            "publishedRevision": value(row.publishedRevision)
        ]
    }
    static func fields(_ row: SharedMediaDerivativeWorkRecord) throws -> Fields {
        try [
            "id": value(row.id),
            "pairID": value(row.pairID),
            "roleRaw": value(row.roleRaw),
            "assetID": value(row.assetID),
            "assetGeneration": value(row.assetGeneration),
            "referenceID": value(row.referenceID),
            "leaseID": value(row.leaseID),
            "writerEpoch": value(row.writerEpoch),
            "byteCount": value(row.byteCount),
            "sha256": value(row.sha256),
            "contentType": value(row.contentType),
            "phaseRaw": value(row.phaseRaw),
            "writerStateRaw": value(row.writerStateRaw),
            "partialDevice": value(row.partialDevice),
            "partialInode": value(row.partialInode),
            "finalIdentity": value(row.finalIdentity),
            "retirementID": value(row.retirementID),
            "retirementPartialIdentity": value(row.retirementPartialIdentity),
            "retirementFinalIdentity": value(row.retirementFinalIdentity),
            "retirementParentIdentity": value(row.retirementParentIdentity),
            "retirementNamespaceIdentity": value(row.retirementNamespaceIdentity)
        ]
    }
    static func fields(_ row: SharedMediaAllocationRecord) throws -> Fields {
        try [
            "id": value(row.id),
            "inventoryID": value(row.inventoryID),
            "accountID": value(row.accountID),
            "packageID": value(row.packageID),
            "namespaceRaw": value(row.namespaceRaw),
            "fileToken": value(row.fileToken),
            "poolRaw": value(row.poolRaw),
            "stateRaw": value(row.stateRaw),
            "materializedBytes": value(row.materializedBytes),
            "reservedBytes": value(row.reservedBytes),
            "physicalIdentity": value(row.physicalIdentity)
        ]
    }
    static func fields(_ row: PhotoPreparationLease) throws -> Fields {
        try [
            "id": value(row.id),
            "packageID": value(row.packageID),
            "assetID": value(row.assetID),
            "ownerID": value(row.ownerID),
            "processEpoch": value(row.processEpoch),
            "purposeRaw": value(row.purposeRaw),
            "partialFileToken": value(row.partialFileToken),
            "finalFileToken": value(row.finalFileToken),
            "reservedByteCount": value(row.reservedByteCount),
            "allocatedByteCount": value(row.allocatedByteCount),
            "writerStateRaw": value(row.writerStateRaw),
            "sourceIdentity": value(row.sourceIdentity),
            "terminalProof": value(row.terminalProof)
        ]
    }
    static func fields(_ row: SharedMediaLeaseRecord) throws -> Fields {
        try [
            "id": value(row.id),
            "allocationID": value(row.allocationID),
            "processEpoch": value(row.processEpoch),
            "purposeRaw": value(row.purposeRaw),
            "stateRaw": value(row.stateRaw)
        ]
    }
    static func fields(_ row: PhotoPreparationAsset) throws -> Fields {
        try [
            "id": value(row.id),
            "ownerID": value(row.ownerID),
            "generation": value(row.generation),
            "fileToken": value(row.fileToken),
            "contentType": value(row.contentType),
            "byteCount": value(row.byteCount),
            "sha256": value(row.sha256),
            "acquisitionKindRaw": value(row.acquisitionKindRaw),
            "cleanupStateRaw": value(row.cleanupStateRaw)
        ]
    }
    static func fields(_ row: PhotoPreparationReference) throws -> Fields {
        try [
            "id": value(row.id),
            "packageID": value(row.packageID),
            "assetID": value(row.assetID),
            "ownerID": value(row.ownerID),
            "roleRaw": value(row.roleRaw),
            "ordinal": value(row.ordinal),
            "revision": value(row.revision),
            "isLive": value(row.isLive)
        ]
    }
    static func fields(_ row: SharedMediaReferenceRecord) throws -> Fields {
        try [
            "id": value(row.id),
            "allocationID": value(row.allocationID),
            "accountID": value(row.accountID),
            "ownerID": value(row.ownerID),
            "roleRaw": value(row.roleRaw),
            "stateRaw": value(row.stateRaw),
            "revision": value(row.revision)
        ]
    }
    static func fields(_ row: SharedMediaAssetReferenceCountRecord) throws -> Fields {
        try [
            "id": value(row.id),
            "assetGeneration": value(row.assetGeneration),
            "inventoryID": value(row.inventoryID),
            "inventoryGeneration": value(row.inventoryGeneration),
            "ownerID": value(row.ownerID),
            "liveCount": value(row.liveCount),
            "revision": value(row.revision),
            "retirementID": value(row.retirementID)
        ]
    }
}
