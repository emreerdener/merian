import Foundation
import SwiftData

/// Role-aware start proof. Logical identities are unique, while a physical
/// original and its acquisition/lease may be shared through distinct references.
@MainActor
enum SharedMediaNativeReleaseStartIdentity {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Snapshot = SharedMediaNativeReceivedReleaseSnapshot.StagedSnapshot
    static func ids(_ p: Values.Plan) -> Set<UUID> {
        Set([p.releaseID, p.operationID, p.queueID, p.observationID, p.bindingID, p.generation, p.eventID] + p.targets.flatMap(\.identities))
    }
    static func physical(_ p: Values.Plan) -> Set<UUID> {
        Set(p.targets.flatMap { [$0.original.assetID, $0.acquisitionID] })
    }
    static func audit(_ snapshot: Snapshot, container: ModelContainer, check: () throws -> Void) async throws {
        let plan = snapshot.components.progress.plan, identities = ids(plan)
        let allowedReceipts = Set(plan.targets.map(\.acquisitionID))
        var offset = 0
        while true {
            try Task.checkCancellation(); try check()
            let count: Int = try {
                let c = ModelContext(container); c.autosaveEnabled = false
                var q = FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(sortBy: [SortDescriptor(\.id)])
                q.fetchOffset = offset; q.fetchLimit = SharedMediaStoragePolicy.pageSize
                let rows = try c.fetch(q)
                for row in rows {
                    let receipt = try SharedMediaAcquisitionReceipt.read(row)
                    if allowedReceipts.contains(row.id) {
                        guard case .completed(let request, _) = receipt,
                              let target = plan.targets.first(where: { $0.acquisitionID == request.operationID }),
                              request.assetID == target.original.assetID,
                              request.assetGeneration == target.original.assetGeneration,
                              request.ownerID == target.original.ownerID,
                              request.referenceID == target.original.referenceID || !identities.contains(request.referenceID) else {
                            throw SharedMediaStorageFailure.conflict
                        }
                    } else {
                        for id in identities { try SharedMediaNativeReleaseStageIdentity.requireAbsent(id, receipt: receipt) }
                    }
                }
                return rows.count
            }()
            try check()
            if count < SharedMediaStoragePolicy.pageSize { break }
            let (next, overflow) = offset.addingReportingOverflow(count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }
            offset = next; await Task.yield()
        }
    }
    static func direct(_ snapshot: Snapshot, witnesses: [UUID: SharedMediaNativeReceivingCleanGraph.Witness], context: ModelContext) throws {
        let plan = snapshot.components.progress.plan
        let other = witnesses.filter { $0.key != plan.package.id }.map(\.value)
        for id in ids(plan).subtracting(physical(plan)) {
            try SharedMediaNativeReleaseStageIdentity.requireAbsent(id, witnesses: other)
        }
        for witness in other { try sharedRoles(plan, other: witness, context: context) }
        _ = try SharedMediaNativeTerminalScan.read(container: context.container, inventoryID: plan.profile.inventoryID) {
            try SharedMediaNativeTerminalIdentity.requireCompatible($0.value, plan: plan)
        }
        try SharedMediaNativeReleaseStartDirectIdentity.check(snapshot, context: context)
    }
    static func requirePhysical(_ plan: Values.Plan, assetID: UUID, acquisitionID: UUID,
                                generation: UUID, ownerID: UUID, digest: String) throws {
        let shared = physical(plan)
        guard shared.contains(assetID) || shared.contains(acquisitionID) else { return }
        guard plan.targets.contains(where: {
            $0.original.assetID == assetID && $0.acquisitionID == acquisitionID &&
            $0.original.assetGeneration == generation && $0.original.ownerID == ownerID && $0.originalIdentitySHA256 == digest
        }) else { throw SharedMediaStorageFailure.conflict }
    }
    static func sharedRoles(_ plan: Values.Plan, other: SharedMediaNativeReceivingCleanGraph.Witness, context: ModelContext) throws {
        let shared = physical(plan)
        guard shared.isDisjoint(with: other.identities) else { throw SharedMediaStorageFailure.conflict }
        switch other {
        case .allocating(let value): try sharedPrepared(plan, prepared: value.prepared, context: context)
        case .generic(let witness):
            switch witness.slot {
            case .prepared(let p), .received(let p, _, _):
                try sharedPrepared(plan, prepared: p, context: context)
            case .abandoned: break
            }
        case .staged(let snapshot): try sharedPlan(plan, other: snapshot.components.progress)
        case .releasing(let snapshot): try sharedPlan(plan, other: snapshot.release.progress)
        }
    }
    private static func sharedPrepared(_ plan: Values.Plan, prepared p: SharedMediaNativeReceivingIntent.Prepared, context: ModelContext) throws {
        let shared = physical(plan)
                for entry in try SharedMediaNativeFrozenCohort.decode(p.cohort.bytes).entries {
                    let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes), original = intent.preparation.original
                    let unique = [intent.pairID, original.reference.referenceID] + [intent.ai, intent.display].flatMap { [$0.id, $0.assetID, $0.referenceID, $0.leaseID] }
                    guard shared.isDisjoint(with: unique) else { throw SharedMediaStorageFailure.conflict }
                    let assetID = original.reference.assetID
                    let receipt = try SharedMediaNativePairPlanGraph.one(context,
                        FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
                    guard case .completed(let request, _) = try SharedMediaAcquisitionReceipt.read(receipt) else { throw SharedMediaStorageFailure.closed }
                    guard ids(plan).subtracting(shared).contains(request.operationID) == false else { throw SharedMediaStorageFailure.conflict }
                    try requirePhysical(plan, assetID: assetID, acquisitionID: request.operationID,
                        generation: original.reference.assetGeneration, ownerID: original.reference.ownerID,
                        digest: SharedMediaAcquisitionEncoding.digest(Data(try original.descriptor.encoded().utf8)))
                }
    }
    private static func sharedPlan(_ plan: Values.Plan, other: Values.Progress) throws {
        let shared = physical(plan)
        let retirements = other.targets.flatMap { [$0.pair?.retirementID, $0.original?.retirementID].compactMap { $0 } }
        guard ids(plan).isDisjoint(with: retirements) else { throw SharedMediaStorageFailure.conflict }
        for target in other.plan.targets {
            let unique = [target.pairID, target.original.referenceID] + [target.ai, target.display].flatMap(\.identities)
            guard shared.isDisjoint(with: unique) else { throw SharedMediaStorageFailure.conflict }
            try requirePhysical(plan, assetID: target.original.assetID, acquisitionID: target.acquisitionID,
                generation: target.original.assetGeneration, ownerID: target.original.ownerID, digest: target.originalIdentitySHA256)
        }
    }
}
