import Foundation
import SwiftData

/// One fresh persistence boundary inside the retained receiving owner. Network
/// suspension occurs outside this operation and its coordinator locks.
@MainActor
final class SharedMediaNativeAppPhotoAllocationOperations {
    typealias Allocation = SharedMediaNativePhotoAllocation
    typealias Snapshot = SharedMediaNativePhotoAllocationSnapshot
    private let container: ModelContainer
    private let authority: SharedMediaNativeAppOperationAuthority
    private let expected: SharedMediaNativeAppEligibility.Header
    private let availableBytes: () throws -> Int64
    private let boundary: (SharedMediaNativeMetadataBoundary) throws -> Void
    private var consumed = false

    private init(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                 expected: SharedMediaNativeAppEligibility.Header, availableBytes: @escaping () throws -> Int64,
                 boundary: @escaping (SharedMediaNativeMetadataBoundary) throws -> Void) {
        self.container = container; self.authority = authority; self.expected = expected
        self.availableBytes = availableBytes; self.boundary = boundary
    }

    static func audited(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                        availableBytes: @escaping () throws -> Int64,
                        boundary: @escaping (SharedMediaNativeMetadataBoundary) throws -> Void) async throws -> Self {
        let expected = try authority.header(container)
        _ = try await SharedMediaNativeScopedAudit(app: container, profile: authority.profile, expected: expected.inventory,
            check: { guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale } },
            betweenPages: { await Task.yield() }).run()
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
        return Self(container: container, authority: authority, expected: expected,
            availableBytes: availableBytes, boundary: boundary)
    }

    /// Discovery never creates a new attempt or changes the saved candidate.
    func saved(_ prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> Allocation? {
        try validate(); guard prepared.profile == authority.profile else { throw SharedMediaStorageFailure.closed }
        let context = fresh(), inventory = try inventory(context)
        guard let witness = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)[prepared.package.id] else {
            throw SharedMediaStorageFailure.stale
        }
        switch witness {
        case .allocating(let snapshot):
            guard try snapshot.prepared.encoded() == prepared.encoded() else { throw SharedMediaStorageFailure.stale }
            return snapshot.allocation
        case .generic(let value):
            guard case .received(let p, _, _) = value.slot, try p.encoded() == prepared.encoded() else { throw SharedMediaStorageFailure.closed }
            return nil
        case .staged, .releasing: throw SharedMediaStorageFailure.closed
        }
    }

    func claim(_ prepared: SharedMediaNativeReceivingIntent.Prepared, attemptID: UUID) throws -> SharedMediaNativePhotoAllocationDispatch {
        if let saved = try saved(prepared) { return .init(allocation: saved, create: false) }
        let context = fresh(), inventory = try inventory(context)
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
        guard case .generic(let value) = witnesses[prepared.package.id],
              case .received(let p, let received, _) = value.slot, try p.encoded() == prepared.encoded() else { throw SharedMediaStorageFailure.stale }
        let allocation = Allocation(claim: try .init(prepared: p, received: received, attemptID: attemptID))
        let charge = try allocation.storageCharge
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context,
            inventory: inventory, ownerID: authority.profile.ownerID, format: .appV2)
        guard let old = budget.metadataByPackage[p.package.id],
              try PhotoPreparationPolicy.add([old, charge]) <= PhotoPreparationPolicy.metadata else {
            throw SharedMediaStorageFailure.capacity
        }
        let packageID = p.package.id
        let package = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        guard try PhotoPreparationPolicy.add([package.allocatedByteCount, old, charge]) <= PhotoPreparationPolicy.package else {
            throw SharedMediaStorageFailure.capacity
        }
        var totals = budget.totals
        try totals.includePhotoPhysical(materialized: 0, reserved: charge)
        try totals.checkAvailable(availableBytes())
        let terminal = try SharedMediaNativeTerminalScan.read(container: container, inventoryID: inventory.id).consumptionAdvances
        let remaining = try PhotoPreparationPolicy.add([2, terminal] + witnesses.values.map { try $0.remainingAdvances })
        _ = try SharedMediaStoragePolicy.add(inventory.revision, remaining)
        let acknowledged = try persist(allocation, prepared: prepared, context: context, inventory: inventory)
        // Exact readback of an uncertain acknowledgement deliberately mints no create authority.
        return .init(allocation: allocation, create: acknowledged)
    }

    func settle(_ reply: InitialPhotoAllocationReply, request: Allocation,
                prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> Allocation {
        guard let current = try saved(prepared), current.claim == request.claim else { throw SharedMediaStorageFailure.stale }
        if let receipt = request.receipt, current.receipt != receipt { throw SharedMediaStorageFailure.conflict }
        switch reply {
        case .held: return current
        case .allocated(let receipt):
            let after = try current.settling(receipt)
            guard after != current else { return current }
            let context = fresh(), inventory = try inventory(context)
            guard let row = try SharedMediaNativeReceivingPhaseGraph.row(prepared.package.id, in: context) else {
                throw SharedMediaStorageFailure.stale
            }
            let snapshot = try Snapshot.read(.init(row), inventory: inventory, context: context)
            guard snapshot.allocation == current else { throw SharedMediaStorageFailure.stale }
            guard try after.storageCharge <= current.storageCharge else { throw SharedMediaStorageFailure.capacity }
            _ = try persist(after, prepared: prepared, context: context, inventory: inventory)
            return after
        }
    }

    /// Returns true only for a successful save acknowledgement and exact fresh
    /// readback. Any ambiguity permanently spends this operation's create right.
    private func persist(_ allocation: Allocation, prepared: SharedMediaNativeReceivingIntent.Prepared,
                         context: ModelContext, inventory: SharedMediaInventoryRecord) throws -> Bool {
        try validate()
        guard !consumed, let row = try SharedMediaNativeReceivingPhaseGraph.row(prepared.package.id, in: context) else {
            throw SharedMediaStorageFailure.closed
        }
        let seal = try SharedMediaNativePhotoAllocationPoststate(row: row, inventory: inventory, after: allocation, context: context)
        do {
            row.allocationData = try allocation.encoded()
            row.allocationSHA256 = SharedMediaAcquisitionEncoding.digest(row.allocationData!)
            inventory.revision = try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)
            try seal.validate(context, row: row, inventory: inventory)
            try boundary(.beforeSave); try validate()
            let check = fresh(), currentInventory = try self.inventory(check)
            guard let currentRow = try SharedMediaNativeReceivingPhaseGraph.row(prepared.package.id, in: check) else {
                throw SharedMediaStorageFailure.stale
            }
            try seal.requirePredecessor(row: currentRow, inventory: currentInventory)
            // Recheck whole pending runway immediately before save, without an await.
            _ = try SharedMediaNativeReceivingCleanGraph.pending(check, inventory: currentInventory)
            try seal.validate(context, row: row, inventory: inventory); try validate()
            consumed = true
            do {
                try context.save(); try boundary(.afterSave)
            } catch {
                context.rollback()
                try readback(allocation, prepared: prepared)
                return false
            }
            try readback(allocation, prepared: prepared)
            return true
        } catch { context.rollback(); throw error }
    }

    private func readback(_ allocation: Allocation, prepared: SharedMediaNativeReceivingIntent.Prepared) throws {
        try boundary(.beforeReadback)
        let header = try authority.header(container)
        guard header == (try SharedMediaNativeAppMetadataFacts.successor(expected)) else { throw SharedMediaStorageFailure.stale }
        let context = fresh(), inventory = try inventory(context)
        guard let row = try SharedMediaNativeReceivingPhaseGraph.row(prepared.package.id, in: context) else { throw SharedMediaStorageFailure.stale }
        let snapshot = try Snapshot.read(.init(row), inventory: inventory, context: context)
        guard try snapshot.prepared.encoded() == prepared.encoded(), snapshot.allocation == allocation else { throw SharedMediaStorageFailure.stale }
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory,
            ownerID: authority.profile.ownerID, format: .appV2)
        guard try authority.header(container) == header else { throw SharedMediaStorageFailure.stale }
    }

    private func validate() throws {
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
    }
    private func fresh() -> ModelContext {
        let context = ModelContext(container); context.autosaveEnabled = false; return context
    }
    private func inventory(_ context: ModelContext) throws -> SharedMediaInventoryRecord {
        let id = authority.profile.inventoryID
        return try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
    }
}

/// Volatile, single-use disposition minted only by the acknowledged claim owner.
@MainActor
final class SharedMediaNativePhotoAllocationDispatch {
    let allocation: SharedMediaNativePhotoAllocation
    private let create: Bool
    private var consumed = false
    fileprivate init(allocation: SharedMediaNativePhotoAllocation, create: Bool) {
        self.allocation = allocation; self.create = create
    }
    func consume() throws -> InitialPhotoAllocationRequest {
        guard !consumed else { throw SharedMediaStorageFailure.closed }
        consumed = true
        return try .init(allocation: allocation, action: create ? .create : .status)
    }
}
