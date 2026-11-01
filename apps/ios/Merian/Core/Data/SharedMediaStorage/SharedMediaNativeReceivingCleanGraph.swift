import Foundation
import SwiftData

/// Clean database classification only. A release witness cannot be passed to
/// generic receiving mutation facts. Budget and whole-store routing remain
/// separate consumers; this adapter grants no save, cleanup or execution right.
@MainActor
enum SharedMediaNativeReceivingCleanGraph {
    typealias Row = SharedMediaNativeReceivingIntentGraph.Row
    enum Witness {
        case allocating(SharedMediaNativePhotoAllocationSnapshot)
        case generic(SharedMediaNativeReceivingPhaseGraph.Witness)
        case releasing(SharedMediaNativeReleaseMetadataSnapshot.Snapshot)
        case staged(SharedMediaNativeReceivedReleaseSnapshot.StagedSnapshot)

        var identities: [UUID] {
            switch self {
            case .allocating(let snapshot):
                let p = snapshot.prepared
                return [p.operationID, p.queueID, p.observationID, p.bindingID, p.generation, p.eventID]
            case .generic(let witness):
                switch witness.slot {
                case .prepared(let p), .received(let p, _, _):
                    return [p.operationID, p.queueID, p.observationID, p.bindingID, p.generation, p.eventID]
                case .abandoned(let a):
                    return [a.operationID, a.queueID, a.observationID, a.bindingID, a.generation, a.eventID]
                }
            case .releasing(let snapshot):
                let p = snapshot.release.progress.plan
                return [p.operationID, p.queueID, p.observationID, p.bindingID, p.generation, p.eventID, p.releaseID]
            case .staged(let snapshot):
                let p = snapshot.origin.request
                return [p.operationID, p.queueID, p.observationID, p.bindingID, p.generation, p.eventID, p.releaseID]
            }
        }

        var packageID: UUID {
            switch self {
            case .allocating(let snapshot): return snapshot.row.id
            case .generic(let witness): return witness.row.id
            case .releasing(let snapshot): return snapshot.release.slot.id
            case .staged(let snapshot): return snapshot.origin.row.id
            }
        }

        /// Presentation survives execution transitions until atomic queue deletion.
        var presentationAdvances: Int64 {
            get throws {
                switch self {
                case .allocating(let snapshot):
                    return try SharedMediaNativeReceivingRows.recoveryPresentation(snapshot.recoveryPresentationData,
                        prepared: snapshot.prepared).remainingTransitions
                case .generic(let witness): return try witness.recoveryPresentation?.remainingTransitions ?? 0
                case .releasing(let snapshot):
                    return try SharedMediaNativeReceivingRows.recoveryPresentation(snapshot.recoveryPresentationData,
                        prepared: snapshot.release.origin.prepared).remainingTransitions
                case .staged(let snapshot): return try snapshot.components.recoveryPresentation.remainingTransitions
                }
            }
        }

        var remainingAdvances: Int64 {
            get throws {
                let execution: Int64
                switch self {
                case .allocating(let snapshot): execution = snapshot.allocation.remainingAdvances
                case .generic: execution = 0
                case .releasing(let snapshot): execution = try snapshot.release.progress.remainingAdvances
                case .staged(let snapshot): execution = try PhotoPreparationPolicy.add([1, snapshot.components.progress.remainingAdvances])
                }
                return try PhotoPreparationPolicy.add([execution, presentationAdvances])
            }
        }
    }

    static func validate(_ row: Row, context: ModelContext, inventory: SharedMediaInventoryRecord,
                         projectionMemo: SharedMediaNativeReleaseSurvivorProjection.Memo? = nil,
                         checkpoint: () throws -> Void = {}) throws -> Witness {
        try Task.checkCancellation(); try checkpoint()
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        guard let saved = try SharedMediaNativeReceivingPhaseGraph.row(row.id, in: context),
              Row(saved) == row else { throw SharedMediaStorageFailure.stale }
        let revision = inventory.revision
        let result: Witness
        if row.allocationData != nil || row.allocationSHA256 != nil {
            result = .allocating(try SharedMediaNativePhotoAllocationSnapshot.read(row,
                inventory: inventory, context: context, checkpoint: checkpoint))
        } else if row.releaseStartData != nil || row.releaseStartSHA256 != nil {
            let origin = try SharedMediaNativeStagedReleaseOrigin.read(row, inventory: inventory,
                context: context, checkpoint: checkpoint)
            result = .staged(try SharedMediaNativeReceivedReleaseSnapshot.readStaged(origin,
                context: context, projectionMemo: projectionMemo, checkpoint: checkpoint))
        } else if row.phase == "releasing" {
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
        guard !context.hasChanges, inventory.revision == revision,
              let final = try SharedMediaNativeReceivingPhaseGraph.row(row.id, in: context), Row(final) == row else {
            throw SharedMediaStorageFailure.stale
        }
        if case .staged(let snapshot) = result { try snapshot.origin.requireCurrent(context: context) }
        return result
    }

    /// Read raw pending membership roots before dispatch. Generic snapshots
    /// eagerly decode the slot and intentionally reject releasing states.
    /// Orphan/foreign raw slots still require a separate exhaustive paged audit.
    static func pending(_ context: ModelContext, inventory: SharedMediaInventoryRecord,
                        projectionMemo: SharedMediaNativeReleaseSurvivorProjection.Memo? = nil,
                        checkpoint: () throws -> Void = {}) throws -> [UUID: Witness] {
        try Task.checkCancellation(); try checkpoint()
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let profile = try SharedMediaNativeAppEligibility.profile(inventory), id = inventory.id
        let revision = inventory.revision
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
                let witness = try validate(row, context: context, inventory: inventory, projectionMemo: projectionMemo, checkpoint: checkpoint)
                for identity in witness.identities {
                    guard identities.insert(identity).inserted else { throw SharedMediaStorageFailure.conflict }
                }
                result[row.id] = witness
            }
        }
        try Task.checkCancellation(); try checkpoint()
        guard !context.hasChanges, inventory.revision == revision else { throw SharedMediaStorageFailure.stale }
        try requireAggregateRunway(inventoryRevision: revision, witnesses: Array(result.values),
            terminalConsumptionAdvances: SharedMediaNativeTerminalScan.read(container: context.container, inventoryID: inventory.id, checkpoint: checkpoint).consumptionAdvances)
        return result
    }

    /// Substitute only the own execution budget; preserve its presentation,
    /// every peer and terminal consumption exactly once. Callers retain their
    /// full-prestate audit and repeat this check immediately before saving.
    static func requireReplacementRunway(inventoryRevision: Int64, packageID: UUID,
                                         executionAdvances: Int64, saveAdvances: Int64,
                                         witnesses: [UUID: Witness], terminalConsumptionAdvances: Int64) throws {
        guard let own = witnesses[packageID], own.packageID == packageID else { throw SharedMediaStorageFailure.stale }
        let peers = witnesses.filter { $0.key != packageID }.values
        let remaining = try PhotoPreparationPolicy.add([saveAdvances, executionAdvances, own.presentationAdvances,
            terminalConsumptionAdvances] + peers.map { try $0.remainingAdvances })
        _ = try SharedMediaStoragePolicy.add(inventoryRevision, remaining)
    }

    /// Complete pending-root arithmetic only; raw orphan/terminal enumeration
    /// remains the scoped audit's obligation. This grants no write permission.
    static func requireAggregateRunway(inventoryRevision: Int64, witnesses: [Witness], terminalConsumptionAdvances: Int64 = 0) throws {
        let remaining = try PhotoPreparationPolicy.add([terminalConsumptionAdvances] + witnesses.map { try $0.remainingAdvances })
        _ = try SharedMediaStoragePolicy.add(inventoryRevision, remaining)
    }
}
