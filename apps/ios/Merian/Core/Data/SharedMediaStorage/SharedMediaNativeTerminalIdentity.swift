import Foundation
import SwiftData

/// Role-aware historical namespace. A bounded terminal vector is compared with
/// bounded live roots and streamed terminal pages, never an all-history set.
@MainActor
enum SharedMediaNativeTerminalIdentity {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    static func all(_ value: Values.Released) -> Set<UUID> {
        // Draft generations are row fences, not globally exclusive operation
        // identities. Exact row/value joins validate them in the terminal leaf.
        Set([value.plan.package.id])
            .union(SharedMediaNativeReleaseStartIdentity.ids(value.plan))
            .union(value.outcomes.flatMap { [$0.pairRetirementID, $0.originalRetirementID].compactMap { $0 } })
    }
    static func exclusive(_ value: Values.Released) -> Set<UUID> {
        all(value).subtracting(SharedMediaNativeReleaseStartIdentity.physical(value.plan))
    }
    static func requireCompatible(_ value: Values.Released, other: Values.Released) throws {
        guard exclusive(value).isDisjoint(with: all(other)), exclusive(other).isDisjoint(with: all(value)) else {
            throw SharedMediaStorageFailure.conflict
        }
        for target in other.plan.targets {
            try SharedMediaNativeReleaseStartIdentity.requirePhysical(value.plan,
                assetID: target.original.assetID, acquisitionID: target.acquisitionID,
                generation: target.original.assetGeneration, ownerID: target.original.ownerID,
                digest: target.originalIdentitySHA256)
        }
    }
    static func requireCompatible(_ value: Values.Released, plan: Values.Plan) throws {
        let allPlan = SharedMediaNativeReleaseStartIdentity.ids(plan).union([plan.package.id])
        guard exclusive(value).isDisjoint(with: allPlan),
              allPlan.subtracting(SharedMediaNativeReleaseStartIdentity.physical(plan)).isDisjoint(with: all(value)) else {
            throw SharedMediaStorageFailure.conflict
        }
        for target in plan.targets {
            try SharedMediaNativeReleaseStartIdentity.requirePhysical(value.plan,
                assetID: target.original.assetID, acquisitionID: target.acquisitionID,
                generation: target.original.assetGeneration, ownerID: target.original.ownerID,
                digest: target.originalIdentitySHA256)
        }
    }
    static func audit(_ terminal: SharedMediaNativeReceivingTerminal.Snapshot,
                      live: [UUID: SharedMediaNativeReceivingCleanGraph.Witness], context: ModelContext) throws {
        try auditPage([terminal], live: live, context: context)
    }

    /// One deep history traversal per bounded page; comparisons never contribute
    /// to accounting totals. No snapshot or model survives a page suspension.
    static func auditPage(_ selected: [SharedMediaNativeReceivingTerminal.Snapshot],
                          live: [UUID: SharedMediaNativeReceivingCleanGraph.Witness], context: ModelContext,
                          expectedHeader: SharedMediaNativeAppEligibility.Header? = nil,
                          checkpoint: () throws -> Void = {}) throws {
        try Task.checkCancellation(); try checkpoint()
        guard !context.hasChanges, selected.count <= SharedMediaStoragePolicy.pageSize,
              Set(selected.map { $0.row.id }).count == selected.count,
              Set(selected.map { $0.persistentID }).count == selected.count else {
            throw SharedMediaStorageFailure.conflict
        }
        guard let first = selected.first else { return }
        for terminal in selected {
            try Task.checkCancellation(); try checkpoint()
            guard terminal.value.plan.profile == first.value.plan.profile else { throw SharedMediaStorageFailure.conflict }
            try auditLive(terminal.value, live: live, context: context, checkpoint: checkpoint)
        }
        var seen = Set<UUID>()
        _ = try SharedMediaNativeTerminalScan.read(container: context.container,
            inventoryID: first.value.plan.profile.inventoryID, expectedHeader: expectedHeader,
            checkpoint: checkpoint) { other in
            if let id = try comparePage(selected, other: other, checkpoint: checkpoint) {
                guard seen.insert(id).inserted else { throw SharedMediaStorageFailure.stale }
            }
        }
        try Task.checkCancellation(); try checkpoint()
        guard !context.hasChanges, seen.count == selected.count else { throw SharedMediaStorageFailure.stale }
    }

    /// Bracket bounded, synchronous value comparisons with full authority checks.
    /// No database/file access, await or authority issuance occurs inside the
    /// batch. The closing check must succeed before its match can be accepted.
    static func comparePage(_ selected: [SharedMediaNativeReceivingTerminal.Snapshot],
                            other: SharedMediaNativeReceivingTerminal.Snapshot,
                            checkpoint: () throws -> Void) throws -> UUID? {
        try Task.checkCancellation(); try checkpoint()
        guard selected.count <= SharedMediaStoragePolicy.pageSize else { throw SharedMediaStorageFailure.conflict }
        var match: UUID?
        for terminal in selected {
            try Task.checkCancellation()
            if other.row.id == terminal.row.id {
                guard other == terminal, match == nil else { throw SharedMediaStorageFailure.stale }
                match = terminal.row.id
            } else { try requireCompatible(terminal.value, other: other.value) }
        }
        try Task.checkCancellation(); try checkpoint()
        return match
    }

    private static func auditLive(_ value: Values.Released,
                                  live: [UUID: SharedMediaNativeReceivingCleanGraph.Witness], context: ModelContext,
                                  checkpoint: () throws -> Void) throws {
        guard !live.keys.contains(value.plan.package.id) else { throw SharedMediaStorageFailure.conflict }
        for id in exclusive(value) {
            try Task.checkCancellation(); try checkpoint()
            guard !live.keys.contains(id) else { throw SharedMediaStorageFailure.conflict }
            try SharedMediaNativeReleaseStageIdentity.requireAbsent(id, witnesses: Array(live.values))
        }
        for witness in live.values {
            try Task.checkCancellation(); try checkpoint()
            try SharedMediaNativeReleaseStartIdentity.sharedRoles(value.plan, other: witness, context: context)
            switch witness {
            case .releasing(let r): try requireCompatible(value, plan: r.release.progress.plan)
            case .staged(let r): try requireCompatible(value, plan: r.components.progress.plan)
            case .allocating(let r): try requireCompatible(value, prepared: r.prepared, context: context)
            case .generic(let generic):
                switch generic.slot {
                case .prepared(let p), .received(let p, _, _):
                    try requireCompatible(value, prepared: p, context: context)
                case .abandoned(let a):
                    guard !all(value).contains(a.package.id) else { throw SharedMediaStorageFailure.conflict }
                }
            }
        }
    }
    private static func requireCompatible(_ value: Values.Released, prepared p: SharedMediaNativeReceivingIntent.Prepared, context: ModelContext) throws {
                    guard !all(value).contains(p.package.id) else { throw SharedMediaStorageFailure.conflict }
                    for entry in try SharedMediaNativeFrozenCohort.decode(p.cohort.bytes).entries {
                        let assetID = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes).preparation.original.reference.assetID
                        let receipt = try SharedMediaNativePairPlanGraph.one(context,
                            FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
                        guard !exclusive(value).contains(receipt.id) else { throw SharedMediaStorageFailure.conflict }
                    }
    }

}
