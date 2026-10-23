import Foundation
import SwiftData

/// Clean database classification only. A release witness cannot be passed to
/// generic receiving mutation facts. Budget and whole-store routing remain
/// separate consumers; this adapter grants no save, cleanup or execution right.
@MainActor
enum SharedMediaNativeReceivingCleanGraph {
    typealias Row = SharedMediaNativeReceivingIntentGraph.Row
    enum Witness {
        case generic(SharedMediaNativeReceivingPhaseGraph.Witness)
        case releasing(SharedMediaNativeReleaseMetadataSnapshot.Snapshot)

        var identities: [UUID] {
            switch self {
            case .generic(let witness):
                switch witness.slot {
                case .prepared(let p), .received(let p, _, _):
                    return [p.operationID, p.queueID, p.observationID, p.bindingID, p.generation, p.eventID]
                case .abandoned(let a):
                    return [a.operationID, a.queueID, a.observationID, a.bindingID, a.generation, a.eventID]
                }
            case .releasing(let snapshot):
                let p = snapshot.release.progress.plan
                return [p.operationID, p.queueID, p.observationID, p.bindingID, p.generation, p.eventID]
            }
        }
    }

    static func validate(_ row: Row, context: ModelContext, inventory: SharedMediaInventoryRecord,
                         checkpoint: () throws -> Void = {}) throws -> Witness {
        try row.requireNoReleaseStart()
        try Task.checkCancellation(); try checkpoint()
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        guard let saved = try SharedMediaNativeReceivingPhaseGraph.row(row.id, in: context),
              Row(saved) == row else { throw SharedMediaStorageFailure.stale }
        let result: Witness
        if row.phase == "releasing" {
            let snapshot = try SharedMediaNativeReleaseMetadataSnapshot.read(packageID: row.id,
                inventoryID: inventory.id, context: context, checkpoint: checkpoint)
            guard snapshot.release.slot == row, snapshot.inventoryRevision == inventory.revision else {
                throw SharedMediaStorageFailure.stale
            }
            result = .releasing(snapshot)
        } else {
            result = .generic(try SharedMediaNativeReceivingPhaseGraph.validate(row, context: context, inventory: inventory))
        }
        try Task.checkCancellation(); try checkpoint()
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        return result
    }

    /// Read raw pending membership roots before dispatch. Generic snapshots
    /// eagerly decode the slot and intentionally reject releasing states.
    /// Orphan/foreign raw slots still require a separate exhaustive paged audit.
    static func pending(_ context: ModelContext, inventory: SharedMediaInventoryRecord,
                        checkpoint: () throws -> Void = {}) throws -> [UUID: Witness] {
        try Task.checkCancellation(); try checkpoint()
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let profile = try SharedMediaNativeAppEligibility.profile(inventory), id = inventory.id
        var query = FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.inventoryID == id })
        query.fetchLimit = PhotoPreparationPolicy.maximumPackages + 1
        let members = try context.fetch(query)
        guard members.count <= PhotoPreparationPolicy.maximumPackages else { throw SharedMediaStorageFailure.capacity }
        var result: [UUID: Witness] = [:], identities = Set<UUID>(), packages = Set<UUID>()
        for member in members {
            try Task.checkCancellation(); try checkpoint()
            guard member.ownerID == profile.ownerID, member.inventoryGeneration == profile.generation,
                  packages.insert(member.id).inserted else { throw SharedMediaStorageFailure.conflict }
            if let saved = try SharedMediaNativeReceivingPhaseGraph.row(member.id, in: context) {
                let row = Row(saved)
                let witness = try validate(row, context: context, inventory: inventory, checkpoint: checkpoint)
                for identity in witness.identities {
                    guard identities.insert(identity).inserted else { throw SharedMediaStorageFailure.conflict }
                }
                result[row.id] = witness
            }
        }
        try Task.checkCancellation(); try checkpoint()
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        return result
    }
}
