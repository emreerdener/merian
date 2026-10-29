import Foundation
import SwiftData

/// Exact sidecar/inventory write set. Receiving revision and every immutable
/// submission byte remain unchanged. Construct only on an audited clean view.
@MainActor
struct SharedMediaNativePhotoAllocationPoststate {
    private let before: SharedMediaNativeReceivingIntentGraph.Row
    private let inventory: SharedMediaNativeReleaseStagePoststate.Inventory
    private let rowID: PersistentIdentifier, inventoryID: PersistentIdentifier
    private let bytes: Data, digest: String

    init(row: SharedMediaReceivingIntentRecord, inventory: SharedMediaInventoryRecord,
         after: SharedMediaNativePhotoAllocation, context: ModelContext) throws {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        before = .init(row); try before.requireNoReleaseStart()
        guard before.phase == "received", before.version == 2,
              after.claim.profile == (try SharedMediaNativeAppEligibility.profile(inventory)),
              after.claim.packageID == before.id,
              after.claim.preparedSHA256 == before.preparedSHA256,
              after.claim.receivedSHA256 == before.resultSHA256 else { throw SharedMediaStorageFailure.conflict }
        if let old = before.allocationData, let sha = before.allocationSHA256 {
            let predecessor = try SharedMediaNativePhotoAllocation.decode(old, sha256: sha)
            try predecessor.requireSuccessor(after)
        } else {
            try before.requireNoAllocation()
            guard after.receipt == nil, after.roleMapping == nil, after.transferReservation == nil else { throw SharedMediaStorageFailure.closed }
        }
        self.inventory = .init(inventory); rowID = row.persistentModelID; inventoryID = inventory.persistentModelID
        bytes = try after.encoded(); digest = SharedMediaAcquisitionEncoding.digest(bytes)
    }

    func validate(_ context: ModelContext, row: SharedMediaReceivingIntentRecord, inventory: SharedMediaInventoryRecord) throws {
        guard context.insertedModelsArray.isEmpty, context.deletedModelsArray.isEmpty,
              Set(context.changedModelsArray.map(\.persistentModelID)) == [rowID, inventoryID],
              row.persistentModelID == rowID, inventory.persistentModelID == inventoryID else {
            throw SharedMediaStorageFailure.conflict
        }
        try self.inventory.requireSuccessor(inventory)
        let after = SharedMediaNativeReceivingIntentGraph.Row(row)
        guard after.id == before.id, after.inventoryID == before.inventoryID,
              after.inventoryGeneration == before.inventoryGeneration, after.ownerID == before.ownerID,
              after.draftGeneration == before.draftGeneration, after.operationID == before.operationID,
              after.cursor == before.cursor, after.phase == before.phase, after.version == before.version,
              after.revision == before.revision, after.preparedData == before.preparedData,
              after.preparedSHA256 == before.preparedSHA256, after.resultData == before.resultData,
              after.resultSHA256 == before.resultSHA256, after.releaseStartData == before.releaseStartData,
              after.releaseStartSHA256 == before.releaseStartSHA256,
              after.allocationData == bytes, after.allocationSHA256 == digest else { throw SharedMediaStorageFailure.conflict }
    }

    func requirePredecessor(row: SharedMediaReceivingIntentRecord, inventory: SharedMediaInventoryRecord) throws {
        guard SharedMediaNativeReceivingIntentGraph.Row(row) == before,
              SharedMediaNativeReleaseStagePoststate.Inventory(inventory) == self.inventory else {
            throw SharedMediaStorageFailure.stale
        }
    }
}
