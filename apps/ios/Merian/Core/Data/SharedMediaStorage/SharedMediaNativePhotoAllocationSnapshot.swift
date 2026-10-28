import Foundation
import SwiftData

/// Clean, exact received graph with an immutable allocation liability. This is
/// descriptive evidence, never create, execution or release authority.
@MainActor
struct SharedMediaNativePhotoAllocationSnapshot {
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Row = SharedMediaNativeReceivingIntentGraph.Row
    let row: Row
    let prepared: Intent.Prepared
    let received: Intent.Received
    let transaction: Intent.Transaction
    let allocation: SharedMediaNativePhotoAllocation
    let header: SharedMediaNativeAppEligibility.Header

    private init(row: Row, prepared: Intent.Prepared, received: Intent.Received,
                 allocation: SharedMediaNativePhotoAllocation,
                 header: SharedMediaNativeAppEligibility.Header) throws {
        self.row = row; self.prepared = prepared; self.received = received
        transaction = try received.reconstruct(prepared)
        self.allocation = allocation; self.header = header
    }

    static func read(_ row: Row, inventory: SharedMediaInventoryRecord,
                     context: ModelContext, checkpoint: () throws -> Void = {}) throws -> Self {
        try checkpoint(); try row.requireNoReleaseStart()
        guard !context.hasChanges, row.version == 2, row.phase == "received",
              let data = row.allocationData, let sha = row.allocationSHA256 else {
            throw SharedMediaStorageFailure.closed
        }
        let profile = try SharedMediaNativeAppEligibility.profile(inventory)
        guard row.cursor == row.id.uuidString.lowercased(), row.inventoryID == profile.inventoryID,
              row.inventoryGeneration == profile.generation, row.ownerID == profile.ownerID,
              let p = row.preparedData, let r = row.resultData,
              row.preparedSHA256 == SharedMediaAcquisitionEncoding.digest(p),
              row.resultSHA256 == SharedMediaAcquisitionEncoding.digest(r) else {
            throw SharedMediaStorageFailure.conflict
        }
        let prepared = try Intent.Prepared.decode(p)
        let received = try Intent.Received.decode(r, prepared: prepared)
        guard let allocation = try? SharedMediaNativePhotoAllocation.decode(data, sha256: sha) else {
            throw SharedMediaStorageFailure.closed
        }
        try allocation.claim.requireMatch(prepared: prepared, received: received)
        guard prepared.version == 2, prepared.profile == profile, prepared.package.id == row.id,
              prepared.package.generation == row.draftGeneration, prepared.operationID == row.operationID,
              row.revision == (try SharedMediaStoragePolicy.add(prepared.intentRevision ?? 0, 1)) else {
            throw SharedMediaStorageFailure.conflict
        }
        let value = try Self(row: row, prepared: prepared, received: received, allocation: allocation,
            header: currentHeader(profile, context: context))
        let rows = try SharedMediaNativeReceivingPhaseGraph.receivedRows(value.transaction, context: context)
        _ = try SharedMediaNativeConsumerGraph.validateAllocatedReceived(rows.consumer, allocation: value,
            context: context, checkpoint: checkpoint)
        try value.requireCurrent(context: context)
        return value
    }

    func consumerBytes(context: ModelContext, checkpoint: () throws -> Void) throws -> Int64 {
        try requireCurrent(context: context)
        let rows = try SharedMediaNativeReceivingPhaseGraph.receivedRows(transaction, context: context)
        _ = try SharedMediaNativeConsumerGraph.validateAllocatedReceived(rows.consumer, allocation: self,
            context: context, checkpoint: checkpoint)
        return Int64(rows.consumer.cohortData.count)
    }

    func requireCurrent(context: ModelContext) throws {
        guard !context.hasChanges,
              let saved = try SharedMediaNativeReceivingPhaseGraph.row(row.id, in: context), Row(saved) == row,
              try Self.currentHeader(prepared.profile, context: context) == header else {
            throw SharedMediaStorageFailure.stale
        }
    }

    func requireConsumerLink(_ consumer: SharedMediaConsumerRecord, value: SharedMediaNativeConsumerCohort,
                             context: ModelContext) throws {
        try requireCurrent(context: context)
        guard value == transaction.cohort, consumer.packageID == row.id,
              try SharedMediaNativeReceivingPhaseGraph.receivedRows(transaction, context: context)
                .consumer.persistentModelID == consumer.persistentModelID else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    private static func currentHeader(_ profile: SharedMediaNativeAppProfile,
                                      context: ModelContext) throws -> SharedMediaNativeAppEligibility.Header {
        try SharedMediaNativeAppEligibility.snapshot(context: context,
            scope: .init(inventoryID: profile.inventoryID, generation: profile.generation,
                ownerID: profile.ownerID, storeIdentity: profile.storeIdentity, rootBinding: profile.rootIdentity))
    }
}
