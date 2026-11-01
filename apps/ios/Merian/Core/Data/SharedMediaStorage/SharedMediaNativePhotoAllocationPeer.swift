import Foundation
import SwiftData

/// Immutable peer evidence minted from a clean allocation snapshot. A writer's
/// exact poststate still owns every permitted mutation; this grants none.
struct SharedMediaNativePhotoAllocationPeer: Equatable, Sendable {
    typealias Facts = SharedMediaNativeAppMetadataFacts
    typealias Row = SharedMediaNativeReceivingIntentGraph.Row
    let row: Row
    let prepared: SharedMediaNativeReceivingIntent.Prepared
    let received: SharedMediaNativeReceivingIntent.Received
    let transaction: SharedMediaNativeReceivingIntent.Transaction
    let allocation: SharedMediaNativePhotoAllocation
    let recoveryPresentationData: Data?
    private let package: Facts.Package
    private let member: Facts.Member
    private let consumer: Facts.Consumer

    @MainActor init(_ snapshot: SharedMediaNativePhotoAllocationSnapshot, context: ModelContext) throws {
        try snapshot.requireCurrent(context: context)
        let rows = try SharedMediaNativeReceivingPhaseGraph.receivedRows(snapshot.transaction, context: context)
        let id = snapshot.row.id
        let packageRow = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
        let membership = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        row = snapshot.row; prepared = snapshot.prepared; received = snapshot.received
        transaction = snapshot.transaction; allocation = snapshot.allocation
        recoveryPresentationData = snapshot.recoveryPresentationData
        package = Facts.Package(packageRow); member = Facts.Member(membership); consumer = Facts.Consumer(rows.consumer)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        // The clean constructor derives decoded values from exact row bytes.
        lhs.row == rhs.row && lhs.package == rhs.package && lhs.member == rhs.member && lhs.consumer == rhs.consumer && lhs.recoveryPresentationData == rhs.recoveryPresentationData
    }

    var consumerBytes: Int64 { Int64(consumer.cohort.count) }

    @MainActor func requireUnchanged(_ context: ModelContext) throws {
        let id = row.id
        guard let saved = try SharedMediaNativeReceivingPhaseGraph.row(id, in: context), Row(saved) == row else {
            throw SharedMediaStorageFailure.conflict
        }
        let rows = try SharedMediaNativeReceivingPhaseGraph.receivedRows(transaction, context: context)
        let packageRow = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
        let membership = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        guard Facts.Package(packageRow) == package, Facts.Member(membership) == member,
              Facts.Consumer(rows.consumer) == consumer, rows.queue.recoveryPresentationData == recoveryPresentationData else { throw SharedMediaStorageFailure.conflict }
    }

    /// Clean reads validate every allocated peer. Dirty reads can only preserve
    /// the exact clean baseline carried by their already-validated writer seal.
    @MainActor static func rows(_ context: ModelContext, profile: SharedMediaNativeAppProfile,
                                preserving: [UUID: Self]?) throws -> (rows: [UUID: Row], peers: [UUID: Self]) {
        let id = profile.inventoryID
        var query = FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.inventoryID == id })
        query.fetchLimit = PhotoPreparationPolicy.maximumPackages + 1; query.includePendingChanges = true
        let members = try context.fetch(query)
        guard members.count <= PhotoPreparationPolicy.maximumPackages else { throw SharedMediaStorageFailure.capacity }
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        var rows: [UUID: Row] = [:], peers: [UUID: Self] = [:]
        for member in members {
            guard member.ownerID == profile.ownerID, member.inventoryGeneration == profile.generation else {
                throw SharedMediaStorageFailure.conflict
            }
            guard let saved = try SharedMediaNativeReceivingPhaseGraph.row(member.id, in: context) else { continue }
            let row = Row(saved)
            guard rows.updateValue(row, forKey: row.id) == nil else { throw SharedMediaStorageFailure.conflict }
            if row.allocationData != nil || row.allocationSHA256 != nil {
                if context.hasChanges {
                    guard let peer = preserving?[row.id] else { throw SharedMediaStorageFailure.closed }
                    try peer.requireUnchanged(context); peers[row.id] = peer
                } else {
                    peers[row.id] = try Self(.read(row, inventory: inventory, context: context), context: context)
                }
            } else { _ = try SharedMediaNativeReceivingSlot.decode(row, profile: profile) }
        }
        if let preserving {
            guard peers == preserving else { throw SharedMediaStorageFailure.conflict }
        }
        return (rows, peers)
    }

    /// Other slots continue through their ordinary generic decoder. Allocation
    /// slots remain opaque to generic mutation and retain their remaining save.
    @MainActor static func pending(_ context: ModelContext, inventory: SharedMediaInventoryRecord,
                                   preserving peers: [UUID: Self]) throws -> [UUID: SharedMediaNativeReceivingPhaseGraph.Witness] {
        let profile = try SharedMediaNativeAppEligibility.profile(inventory)
        let values = try rows(context, profile: profile, preserving: peers)
        var result: [UUID: SharedMediaNativeReceivingPhaseGraph.Witness] = [:], identities = Set<UUID>()
        var remaining: Int64 = 0
        for row in values.rows.values {
            let witness: SharedMediaNativeReceivingPhaseGraph.Witness
            if let peer = peers[row.id] {
                witness = .init(row: row, slot: .received(peer.prepared, peer.received, peer.transaction), states: [], recoveryPresentationData: peer.recoveryPresentationData)
                remaining = try SharedMediaStoragePolicy.add(remaining, peer.allocation.remainingAdvances)
            } else { witness = try SharedMediaNativeReceivingPhaseGraph.validate(row, context: context, inventory: inventory) }
            remaining = try SharedMediaStoragePolicy.add(remaining, witness.recoveryPresentation?.remainingTransitions ?? 0)
            let ids = SharedMediaNativeReceivingCleanGraph.Witness.generic(witness).identities
            for id in ids { guard identities.insert(id).inserted else { throw SharedMediaStorageFailure.conflict } }
            result[row.id] = witness
        }
        let terminal = try SharedMediaNativeTerminalScan.read(container: context.container, inventoryID: inventory.id).consumptionAdvances
        _ = try SharedMediaStoragePolicy.add(inventory.revision, PhotoPreparationPolicy.add([remaining, terminal]))
        return result
    }
}
