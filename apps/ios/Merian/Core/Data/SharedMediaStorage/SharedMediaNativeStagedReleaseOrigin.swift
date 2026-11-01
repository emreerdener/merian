import Foundation
import SwiftData

/// Exact persisted request/origin association only. This witness does not prove
/// funding, global identity uniqueness, revision runway or permission to release.
/// The saved historical header supplies an unverified revision floor, not proof
/// that a staging transaction actually committed atomically at that header.
/// Its private initializer prevents a caller from bypassing canonical binding.
@MainActor
struct SharedMediaNativeStagedReleaseOrigin {
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Row = SharedMediaNativeReceivingIntentGraph.Row
    typealias Header = SharedMediaNativeAppEligibility.Header

    let row: Row
    let prepared: Intent.Prepared
    let received: Intent.Received
    let transaction: Intent.Transaction
    let request: SharedMediaNativeReleaseStartRequest
    let header: Header
    let recoveryPresentationData: Data?

    private init(row: Row, prepared: Intent.Prepared, received: Intent.Received,
                 transaction: Intent.Transaction, request: SharedMediaNativeReleaseStartRequest, header: Header, recoveryPresentationData: Data?) {
        self.row = row; self.prepared = prepared; self.received = received
        self.transaction = transaction; self.request = request; self.header = header
        self.recoveryPresentationData = recoveryPresentationData
    }

    static func read(_ row: Row, inventory: SharedMediaInventoryRecord,
                     context: ModelContext, checkpoint: () throws -> Void = {}) throws -> Self {
        try checkpoint(); try row.requireNoAllocation()
        guard !context.hasChanges, row.version == 2, row.phase == "received",
              let data = row.releaseStartData, let digest = row.releaseStartSHA256 else {
            throw SharedMediaStorageFailure.closed
        }
        let profile = try SharedMediaNativeAppEligibility.profile(inventory)
        let request = try SharedMediaNativeReleaseStartRequest.decode(data, sha256: digest)
        guard row.cursor == row.id.uuidString.lowercased(), row.inventoryID == profile.inventoryID,
              row.inventoryGeneration == profile.generation, row.ownerID == profile.ownerID,
              let p = row.preparedData, let r = row.resultData,
              row.preparedSHA256 == SharedMediaAcquisitionEncoding.digest(p),
              row.resultSHA256 == SharedMediaAcquisitionEncoding.digest(r) else {
            throw SharedMediaStorageFailure.conflict
        }
        let prepared = try Intent.Prepared.decode(p)
        let received = try Intent.Received.decode(r, prepared: prepared)
        try request.requireMatch(prepared: prepared, received: received)
        guard prepared.profile == profile, prepared.package.id == row.id,
              prepared.package.generation == row.draftGeneration, prepared.operationID == row.operationID,
              request.receivedRevision == row.revision else { throw SharedMediaStorageFailure.conflict }
        let header = try currentHeader(profile, context: context)
        let staged = try request.postStageHeader
        guard header.bootstrapID == staged.bootstrapID,
              header.bootstrapGeneration == staged.bootstrapGeneration,
              header.bootstrapContract == staged.bootstrapContract,
              header.bootstrapRevision == staged.bootstrapRevision,
              header.inventory.generation == staged.inventory.generation,
              header.inventory.phase == staged.inventory.phase, header.inventory.cursor == staged.inventory.cursor,
              header.inventory.revision >= staged.inventory.revision else { throw SharedMediaStorageFailure.stale }
        let transaction = try received.reconstruct(prepared)
        let rows = try SharedMediaNativeReceivingPhaseGraph.receivedRows(transaction, context: context)
        _ = try SharedMediaNativeReceivingRows.recoveryPresentation(rows.queue.recoveryPresentationData, prepared: prepared)
        let value = Self(row: row, prepared: prepared, received: received,
            transaction: transaction, request: request, header: header, recoveryPresentationData: rows.queue.recoveryPresentationData)
        _ = try SharedMediaNativeConsumerGraph.validateStagedReceived(rows.consumer, origin: value,
            context: context, checkpoint: checkpoint)
        try value.requireCurrent(context: context)
        return value
    }

    /// A witness is a snapshot, not a capability reusable after context changes.
    /// Re-fetch the complete row and header, including both sidecar columns.
    func requireCurrent(context: ModelContext) throws {
        guard !context.hasChanges,
              let saved = try SharedMediaNativeReceivingPhaseGraph.row(row.id, in: context), Row(saved) == row,
              try Self.currentHeader(prepared.profile, context: context) == header else {
            throw SharedMediaStorageFailure.stale
        }
        try SharedMediaNativeReceivingRows.requireRecoveryPresentation(recoveryPresentationData,
            request: transaction, in: context)
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

    private static func currentHeader(_ profile: SharedMediaNativeAppProfile, context: ModelContext) throws -> Header {
        try SharedMediaNativeAppEligibility.snapshot(context: context,
            scope: .init(inventoryID: profile.inventoryID, generation: profile.generation,
                ownerID: profile.ownerID, storeIdentity: profile.storeIdentity, rootBinding: profile.rootIdentity))
    }
}
