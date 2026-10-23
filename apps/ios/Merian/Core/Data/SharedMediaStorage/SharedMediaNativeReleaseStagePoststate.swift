import Foundation
import SwiftData

/// Exact two-row replacement, constructed from a clean received predecessor.
/// It never routes a dirty context through the ordinary clean graph readers.
@MainActor
struct SharedMediaNativeReleaseStagePoststate {
    private let slot: SharedMediaNativeReceivingIntentGraph.Row
    private let inventory: Inventory
    private let slotID: PersistentIdentifier, inventoryID: PersistentIdentifier
    private let data: Data, digest: String

    struct Inventory: Equatable {
        let id: UUID, generation: UUID
        let rootIdentity: String, storeIdentity: String, mode: String, phase: String, cursor: String
        let revision: Int64
        init(_ value: SharedMediaInventoryRecord) {
            id = value.id; generation = value.generation; rootIdentity = value.rootIdentity
            storeIdentity = value.storeIdentity; mode = value.modeRaw; phase = value.phaseRaw
            cursor = value.cursor; revision = value.revision
        }
        func requireSuccessor(_ value: SharedMediaInventoryRecord) throws {
            guard id == value.id, generation == value.generation, rootIdentity == value.rootIdentity,
                  storeIdentity == value.storeIdentity, mode == value.modeRaw, phase == value.phaseRaw,
                  cursor == value.cursor, value.revision == (try SharedMediaStoragePolicy.add(revision, 1)) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
    }

    init(request: SharedMediaNativeReleaseStartRequest, snapshot: SharedMediaNativeReceivedReleaseSnapshot.ProspectiveStageSnapshot,
         context: ModelContext, row: SharedMediaReceivingIntentRecord, inventory: SharedMediaInventoryRecord) throws {
        guard !context.hasChanges, snapshot.request == request, snapshot.predecessor.slot == .init(row),
              snapshot.predecessor.header == request.stagePreHeader,
              request.profile == (try SharedMediaNativeAppEligibility.profile(inventory)),
              inventory.revision == request.stagePreHeader.inventory.revision else { throw SharedMediaStorageFailure.stale }
        slot = .init(row); try slot.requireNoReleaseStart()
        self.inventory = .init(inventory); slotID = row.persistentModelID; inventoryID = inventory.persistentModelID
        data = try request.encoded(); digest = SharedMediaAcquisitionEncoding.digest(data)
    }

    func validate(_ context: ModelContext, row: SharedMediaReceivingIntentRecord, inventory: SharedMediaInventoryRecord) throws {
        guard context.insertedModelsArray.isEmpty, context.deletedModelsArray.isEmpty,
              Set(context.changedModelsArray.map(\.persistentModelID)) == [slotID, inventoryID],
              row.persistentModelID == slotID, inventory.persistentModelID == inventoryID else {
            throw SharedMediaStorageFailure.conflict
        }
        try self.inventory.requireSuccessor(inventory)
        let after = SharedMediaNativeReceivingIntentGraph.Row(row)
        guard after.id == slot.id, after.inventoryID == slot.inventoryID,
              after.inventoryGeneration == slot.inventoryGeneration, after.ownerID == slot.ownerID,
              after.draftGeneration == slot.draftGeneration, after.operationID == slot.operationID,
              after.cursor == slot.cursor, after.phase == slot.phase, after.version == slot.version,
              after.revision == slot.revision, after.preparedData == slot.preparedData,
              after.preparedSHA256 == slot.preparedSHA256, after.resultData == slot.resultData,
              after.resultSHA256 == slot.resultSHA256, after.releaseStartData == data,
              after.releaseStartSHA256 == digest else { throw SharedMediaStorageFailure.conflict }
    }

    func requirePredecessor(row: SharedMediaReceivingIntentRecord, inventory: SharedMediaInventoryRecord) throws {
        guard SharedMediaNativeReceivingIntentGraph.Row(row) == slot, Inventory(inventory) == self.inventory else {
            throw SharedMediaStorageFailure.stale
        }
    }
}
