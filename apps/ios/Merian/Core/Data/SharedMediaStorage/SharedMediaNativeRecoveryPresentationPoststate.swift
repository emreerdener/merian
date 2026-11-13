import Foundation
import SwiftData

/// Transaction-bound queue/inventory proof, not save or presentation authority.
/// It starts from a fully validated nil receiving set. Only exact successors of
/// that set can be read with positive bytes; ordinary readers remain nil-only.
@MainActor
// The full domain name distinguishes this state or capability from adjacent storage boundaries.
// swiftlint:disable:next type_name
struct SharedMediaNativeRecoveryPresentationPoststate {
    typealias Rows = SharedMediaNativeReceivingRows
    typealias Raw = SharedMediaNativeReceivingTerminalRaw
    typealias Fields = SharedMediaNativeReleasePairRaw.Fields
    typealias Inventory = SharedMediaNativeReleaseStagePoststate.Inventory
    let transaction: SharedMediaNativeReceivingIntent.Transaction
    private let slot: SharedMediaNativeReceivingIntentGraph.Row
    private let beforeInventory: Inventory
    private let queueID: PersistentIdentifier, inventoryID: PersistentIdentifier, slotID: PersistentIdentifier
    private let quartetIDs: Set<PersistentIdentifier>
    private let consumer: Fields, job: Fields, event: Fields
    private let beforeQueue: Fields, afterQueue: Fields
    private let reservation: AnalysisRecoveryPresentation.Reservation?
    let successor: AnalysisRecoveryPresentation
    var visibleAllowance: Duration? { reservation?.visibleAllowance }

    init(prepared: SharedMediaNativeReceivingIntent.Prepared, reservationID: UUID,
         context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        try self.init(prepared: prepared, start: .reserve(reservationID), context: context, inventory: inventory)
    }
    static func forfeiting(prepared: SharedMediaNativeReceivingIntent.Prepared,
                           context: ModelContext, inventory: SharedMediaInventoryRecord) throws -> Self {
        try .init(prepared: prepared, start: .forfeit, context: context, inventory: inventory)
    }
    private enum Start { case reserve(UUID), forfeit }
    private init(prepared: SharedMediaNativeReceivingIntent.Prepared, start: Start,
                 context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard !context.hasChanges, prepared.profile == (try SharedMediaNativeAppEligibility.profile(inventory)) else {
            throw SharedMediaStorageFailure.stale
        }
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
        guard let witness = witnesses[prepared.package.id] else { throw SharedMediaStorageFailure.stale }
        let saved: SharedMediaNativeReceivingIntent.Prepared
        switch witness {
        case .generic(let value):
            guard case .received(let p, _, let t) = value.slot else { throw SharedMediaStorageFailure.closed }
            saved = p; transaction = t; slot = value.row
        case .initial(let value):
            guard value.initialPin != nil else { throw SharedMediaStorageFailure.closed }
            saved = value.prepared; transaction = value.transaction; slot = value.row
        case .allocating(let value):
            saved = value.prepared; transaction = value.transaction; slot = value.row
        case .staged, .releasing: throw SharedMediaStorageFailure.closed
        }
        guard try saved.encoded() == prepared.encoded() else { throw SharedMediaStorageFailure.stale }
        let identity = AnalysisRecoveryPresentation.Identity(ownerID: prepared.profile.ownerID,
            observationID: prepared.observationID, operationID: prepared.operationID)
        let rows: Rows.Set, receipt: AnalysisRecoveryPresentation.Reservation?, next: AnalysisRecoveryPresentation
        switch start {
        case .reserve(let id):
            guard let saved = try Rows.read(transaction, in: context, absent: false) else { throw SharedMediaStorageFailure.stale }
            rows = saved
            let reserved = try AnalysisRecoveryPresentation.initial(for: identity).reserve(id: id)
            receipt = reserved; next = reserved.reserved
        case .forfeit:
            rows = try Rows.readObserved(transaction, in: context)
            guard let bytes = rows.queue.recoveryPresentationData else { throw SharedMediaStorageFailure.stale }
            next = try AnalysisRecoveryPresentation.decode(bytes, identity: identity).forfeitingUnownedReservation()
            receipt = nil
        }
        try SharedMediaNativeReceivingCleanGraph.requirePresentationReplacementRunway(inventoryRevision: inventory.revision,
            packageID: prepared.package.id, presentationAdvances: next.remainingTransitions, saveAdvances: 1,
            witnesses: witnesses, historical: SharedMediaNativeTerminalScan.read(
                container: context.container, inventoryID: inventory.id))
        guard let slotRow = try SharedMediaNativeReceivingPhaseGraph.row(slot.id, in: context) else { throw SharedMediaStorageFailure.stale }
        slotID = slotRow.persistentModelID; quartetIDs = rows.identities
        beforeInventory = .init(inventory); inventoryID = inventory.persistentModelID; queueID = rows.queue.persistentModelID
        consumer = try Raw.fields(rows.consumer); job = try Raw.fields(rows.job); event = try Raw.fields(rows.event)
        beforeQueue = try Raw.fields(rows.queue)
        afterQueue = try Self.replacingPresentation(beforeQueue, with: next)
        reservation = receipt; successor = next
    }

    private init(previous: Self, rows: Rows.Set, inventory: SharedMediaInventoryRecord,
                 successor: AnalysisRecoveryPresentation, reservation: AnalysisRecoveryPresentation.Reservation?) throws {
        transaction = previous.transaction; slot = previous.slot
        beforeInventory = .init(inventory); inventoryID = previous.inventoryID; queueID = previous.queueID
        slotID = previous.slotID; quartetIDs = previous.quartetIDs
        consumer = previous.consumer; job = previous.job; event = previous.event
        beforeQueue = try Raw.fields(rows.queue)
        afterQueue = try Self.replacingPresentation(beforeQueue, with: successor)
        self.successor = successor; self.reservation = reservation
    }

    /// The original in-memory receipt is retained; decoded active bytes cannot
    /// construct a settlement. Callers must still acquire current owner authority.
    func settling(elapsed: Duration, context: ModelContext, inventory: SharedMediaInventoryRecord) throws -> Self {
        let rows = try requirePersisted(context, inventory: inventory)
        guard let reservation else { throw SharedMediaStorageFailure.closed }
        return try .init(previous: self, rows: rows, inventory: inventory,
            successor: reservation.settle(current: successor, elapsed: elapsed), reservation: nil)
    }

    func reserving(id: UUID, context: ModelContext, inventory: SharedMediaInventoryRecord) throws -> Self {
        let rows = try requirePersisted(context, inventory: inventory)
        let next = try successor.reserve(id: id)
        return try .init(previous: self, rows: rows, inventory: inventory, successor: next.reserved, reservation: next)
    }

    func requirePredecessor(_ context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard !context.hasChanges, Inventory(inventory) == beforeInventory else { throw SharedMediaStorageFailure.stale }
        _ = try checkedRows(context, inventory: inventory, expectedQueue: beforeQueue)
    }

    func validate(_ context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard context.insertedModelsArray.isEmpty, context.deletedModelsArray.isEmpty,
              Set(context.changedModelsArray.map(\.persistentModelID)) == [queueID, inventoryID] else {
            throw SharedMediaStorageFailure.conflict
        }
        try beforeInventory.requireSuccessor(inventory)
        _ = try checkedRows(context, inventory: inventory, expectedQueue: afterQueue)
    }

    @discardableResult
    func requirePersisted(_ context: ModelContext, inventory: SharedMediaInventoryRecord) throws -> Rows.Set {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        try beforeInventory.requireSuccessor(inventory)
        return try checkedRows(context, inventory: inventory, expectedQueue: afterQueue)
    }

    private func checkedRows(_ context: ModelContext, inventory: SharedMediaInventoryRecord, expectedQueue: Fields) throws -> Rows.Set {
        guard inventory.persistentModelID == inventoryID,
              let current = try SharedMediaNativeReceivingPhaseGraph.row(slot.id, in: context),
              current.persistentModelID == slotID, SharedMediaNativeReceivingIntentGraph.Row(current) == slot else { throw SharedMediaStorageFailure.stale }
        let rows = try Rows.readPresentation(in: context, proof: self)
        guard rows.queue.persistentModelID == queueID, try Raw.fields(rows.queue) == expectedQueue else {
            throw SharedMediaStorageFailure.stale
        }
        return rows
    }

    /// Called only by the collision-checked quartet reader. The exact sealed
    /// predecessor/successor is an explicit exception, never a general allow flag.
    func requireRows(_ rows: Rows.Set) throws {
        guard rows.identities == quartetIDs, try Raw.fields(rows.consumer) == consumer,
              try Raw.fields(rows.job) == job, try Raw.fields(rows.event) == event else { throw SharedMediaStorageFailure.stale }
        let fields = try Raw.fields(rows.queue)
        guard fields == beforeQueue || fields == afterQueue else { throw SharedMediaStorageFailure.stale }
    }

    private static func replacingPresentation(_ fields: Fields, with value: AnalysisRecoveryPresentation) throws -> Fields {
        var result = fields
        result["recoveryPresentationData"] = try SharedMediaNativeReleasePairRaw.value(Optional(value.encoded()))
        return result
    }
}
