import Foundation
import SwiftData

/// Seals the canonical staged-to-initial-Progress replacement; all other raw
/// receiving/inventory fields and every other persistent object stay unchanged.
@MainActor
struct SharedMediaNativeReleaseStartPoststate {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    private let slot: SharedMediaNativeReceivingIntentGraph.Row
    private let inventory: SharedMediaNativeReleaseStagePoststate.Inventory
    private let slotID: PersistentIdentifier, inventoryID: PersistentIdentifier
    private let progress: Values.Progress, bytes: Data, digest: String

    init(snapshot: SharedMediaNativeReceivedReleaseSnapshot.StagedSnapshot,
         context: ModelContext, row: SharedMediaReceivingIntentRecord, inventory: SharedMediaInventoryRecord) throws {
        try snapshot.origin.requireCurrent(context: context)
        guard !context.hasChanges, snapshot.origin.row == .init(row),
              inventory.revision == snapshot.origin.header.inventory.revision else { throw SharedMediaStorageFailure.stale }
        slot = .init(row); self.inventory = .init(inventory)
        try slot.requireNoAllocation()
        slotID = row.persistentModelID; inventoryID = inventory.persistentModelID
        progress = snapshot.components.progress; bytes = try progress.encoded()
        digest = SharedMediaAcquisitionEncoding.digest(bytes)
        guard progress == (try Values.Progress(plan: progress.plan)),
              progress.plan.preHeader == snapshot.origin.header else { throw SharedMediaStorageFailure.conflict }
    }
    func validate(_ context: ModelContext, row: SharedMediaReceivingIntentRecord, inventory: SharedMediaInventoryRecord) throws {
        guard context.insertedModelsArray.isEmpty, context.deletedModelsArray.isEmpty,
              Set(context.changedModelsArray.map(\.persistentModelID)) == [slotID, inventoryID],
              row.persistentModelID == slotID, inventory.persistentModelID == inventoryID else {
            throw SharedMediaStorageFailure.conflict
        }
        try self.inventory.requireSuccessor(inventory)
        let after = SharedMediaNativeReceivingIntentGraph.Row(row)
        try after.requireNoAllocation()
        guard after.id == slot.id, after.inventoryID == slot.inventoryID,
              after.inventoryGeneration == slot.inventoryGeneration, after.ownerID == slot.ownerID,
              after.draftGeneration == slot.draftGeneration, after.operationID == slot.operationID,
              after.cursor == slot.cursor, after.version == slot.version,
              after.phase == "releasing", after.revision == (try progress.plan.releasingRevision),
              after.preparedData == nil, after.preparedSHA256 == slot.preparedSHA256,
              after.resultData == bytes, after.resultSHA256 == digest,
              after.releaseStartData == nil, after.releaseStartSHA256 == nil else { throw SharedMediaStorageFailure.conflict }
    }
    func requirePredecessor(row: SharedMediaReceivingIntentRecord, inventory: SharedMediaInventoryRecord) throws {
        guard SharedMediaNativeReceivingIntentGraph.Row(row) == slot,
              SharedMediaNativeReleaseStagePoststate.Inventory(inventory) == self.inventory else {
            throw SharedMediaStorageFailure.stale
        }
    }
}
