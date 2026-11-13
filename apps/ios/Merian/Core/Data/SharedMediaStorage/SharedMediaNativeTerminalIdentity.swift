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
            checkpoint: checkpoint, visitApplied: { applied in
                let other = try namespace(applied.prepared, context: context)
                for terminal in selected { try checkpoint(); try requireCompatible(namespace(terminal.value), other) }
            }) { other in
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

    /// Bounded role-aware projection for retained originals. Draft generations,
    /// writer epochs and arbitrary payload UUIDs are not exclusive operation IDs.
    struct Physical: Equatable {
        let assetID: UUID, acquisitionID: UUID, generation: UUID, ownerID: UUID
        let identityDigest: String
    }
    struct Namespace {
        let all: Set<UUID>
        let physical: [Physical]
        var shared: Set<UUID> { Set(physical.flatMap { [$0.assetID, $0.acquisitionID] }) }
        var exclusive: Set<UUID> { all.subtracting(shared) }
    }

    static func namespace(_ p: SharedMediaNativeReceivingIntent.Prepared, context: ModelContext) throws -> Namespace {
        var unique = Set([p.package.id, p.operationID, p.queueID, p.observationID, p.bindingID, p.generation, p.eventID])
        var physical: [Physical] = []
        for entry in try SharedMediaNativeFrozenCohort.decode(p.cohort.bytes).entries {
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes), original = intent.preparation.original
            unique.formUnion([intent.pairID, original.reference.referenceID])
            unique.formUnion([intent.ai, intent.display].flatMap { [$0.id, $0.assetID, $0.referenceID, $0.leaseID] })
            let assetID = original.reference.assetID
            let receipt = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
            guard case .completed(let request, _) = try SharedMediaAcquisitionReceipt.read(receipt),
                  request.assetID == assetID, request.assetGeneration == original.reference.assetGeneration,
                  request.ownerID == original.reference.ownerID else { throw SharedMediaStorageFailure.conflict }
            physical.append(.init(assetID: assetID, acquisitionID: request.operationID,
                generation: original.reference.assetGeneration, ownerID: original.reference.ownerID,
                identityDigest: SharedMediaAcquisitionEncoding.digest(Data(try original.descriptor.encoded().utf8))))
        }
        let shared = Set(physical.flatMap { [$0.assetID, $0.acquisitionID] })
        guard unique.isDisjoint(with: shared) else { throw SharedMediaStorageFailure.conflict }
        return .init(all: unique.union(shared), physical: physical)
    }

    static func namespace(_ plan: Values.Plan, additional: [UUID] = []) -> Namespace {
        .init(all: SharedMediaNativeReleaseStartIdentity.ids(plan).union([plan.package.id]).union(additional),
            physical: plan.targets.map { .init(assetID: $0.original.assetID, acquisitionID: $0.acquisitionID,
                generation: $0.original.assetGeneration, ownerID: $0.original.ownerID, identityDigest: $0.originalIdentitySHA256) })
    }

    static func requireCompatible(_ left: Namespace, _ right: Namespace) throws {
        guard left.exclusive.isDisjoint(with: right.all), right.exclusive.isDisjoint(with: left.all) else {
            throw SharedMediaStorageFailure.conflict
        }
        for first in left.physical {
            for second in right.physical where first.assetID == second.assetID || first.acquisitionID == second.acquisitionID {
                guard first == second else { throw SharedMediaStorageFailure.conflict }
            }
        }
    }

    private static func namespace(_ value: Values.Released) -> Namespace {
        namespace(value.plan, additional: value.outcomes.flatMap { [$0.pairRetirementID, $0.originalRetirementID].compactMap { $0 } })
    }

    private static func namespace(_ witness: SharedMediaNativeReceivingCleanGraph.Witness, context: ModelContext) throws -> Namespace {
        switch witness {
        case .allocating(let value), .initial(let value): return try namespace(value.prepared, context: context)
        case .generic(let value):
            switch value.slot {
            case .prepared(let p), .received(let p, _, _): return try namespace(p, context: context)
            case .abandoned: return .init(all: Set(witness.identities).union([witness.packageID]), physical: [])
            }
        case .releasing(let value):
            let progress = value.release.progress
            return namespace(progress.plan, additional: progress.targets.flatMap { [$0.pair?.retirementID, $0.original?.retirementID].compactMap { $0 } })
        case .staged(let value):
            let progress = value.components.progress
            return namespace(progress.plan, additional: progress.targets.flatMap { [$0.pair?.retirementID, $0.original?.retirementID].compactMap { $0 } })
        }
    }

    /// Compare one bounded retained page against pending roots and streamed
    /// retained/terminal history. No global decoded library or accounting sum.
    static func auditAppliedPage(_ selected: [SharedMediaNativePhotoAllocationSnapshot.Applied],
                                 live: [UUID: SharedMediaNativeReceivingCleanGraph.Witness], context: ModelContext,
                                 expectedHeader: SharedMediaNativeAppEligibility.Header?, checkpoint: () throws -> Void) throws {
        guard !context.hasChanges, selected.count <= SharedMediaStoragePolicy.pageSize,
              Set(selected.map { $0.row.id }).count == selected.count else { throw SharedMediaStorageFailure.conflict }
        guard let first = selected.first else { return }
        let facts = try selected.map { value -> Namespace in
            try checkpoint(); try value.requireCurrent(context: context)
            guard value.prepared.profile == first.prepared.profile else { throw SharedMediaStorageFailure.conflict }
            let facts = try namespace(value.prepared, context: context)
            for witness in live.values { try checkpoint(); try requireCompatible(facts, namespace(witness, context: context)) }
            return facts
        }
        var seen = Set<UUID>()
        _ = try SharedMediaNativeTerminalScan.read(container: context.container,
            inventoryID: first.prepared.profile.inventoryID, expectedHeader: expectedHeader, checkpoint: checkpoint,
            visitApplied: { other in
                let otherFacts = try namespace(other.prepared, context: context)
                for (index, value) in selected.enumerated() {
                    try checkpoint()
                    if value.row.id == other.row.id {
                        guard value.row == other.row, value.cohort == other.cohort, value.header == other.header,
                              seen.insert(value.row.id).inserted else { throw SharedMediaStorageFailure.stale }
                    } else { try requireCompatible(facts[index], otherFacts) }
                }
            }) { terminal in
                for value in facts { try checkpoint(); try requireCompatible(value, namespace(terminal.value)) }
            }
        guard seen.count == selected.count else { throw SharedMediaStorageFailure.stale }
        for value in selected { try checkpoint(); try value.requireCurrent(context: context) }
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
            case .allocating(let r), .initial(let r): try requireCompatible(value, prepared: r.prepared, context: context)
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
