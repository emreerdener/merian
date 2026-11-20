import Foundation
import SwiftData

/// One frozen metadata attempt. Never reconstructed by a historical terminal
/// reader; uncertainty permits only exact saved-before/saved-after comparison.
@MainActor
// The full domain name distinguishes this state or capability from adjacent storage boundaries.
// swiftlint:disable:next type_name
final class SharedMediaNativeReceivingTerminalAttempt {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    let before: Values.Progress
    let after: Values.Released
    let header: SharedMediaNativeAppEligibility.Header
    let prefix: SharedMediaNativeReleasePrefix
    let seal: SharedMediaNativeReceivingTerminalPoststate
    let funding: SharedMediaNativeAcquisitionBudget.Snapshot
    let binding: SharedMediaNativeBinding

    private init(snapshot: SharedMediaNativeReleaseMetadataSnapshot.Snapshot,
                 header: SharedMediaNativeAppEligibility.Header, binding: SharedMediaNativeBinding,
                 context: ModelContext) throws {
        before = snapshot.release.progress; self.header = header; self.binding = binding
        after = try .init(progress: before, inventoryRevision: SharedMediaStoragePolicy.add(header.inventory.revision, 1))
        prefix = try .init(terminal: snapshot)
        let projection = try SharedMediaNativeReleaseSurvivorProjection.maximum(snapshot)
        try projection.requireMetadataCapacity()
        guard Int64(try after.encoded().count) <= projection.maximumTerminalSlotBytes else { throw SharedMediaStorageFailure.capacity }
        let id = before.plan.profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        // Full prestate Budget and asset-owned proof precede successor projection.
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory,
            ownerID: before.plan.profile.ownerID, format: .appV2)
        funding = try SharedMediaNativeAcquisitionBudget.terminalProjection(context: context, inventory: inventory,
            before: snapshot, after: after)
        seal = try .init(before: snapshot, after: after, context: context)
    }
    static func audited(_ before: Values.Progress, header: SharedMediaNativeAppEligibility.Header,
                        binding: SharedMediaNativeBinding, context: ModelContext) throws -> SharedMediaNativeReceivingTerminalAttempt {
        let snapshot = try predecessor(before, header: header, context: context)
        return try .init(snapshot: snapshot, header: header, binding: binding, context: context)
    }
    static func predecessor(_ before: Values.Progress, header: SharedMediaNativeAppEligibility.Header,
                            context: ModelContext) throws -> SharedMediaNativeReleaseMetadataSnapshot.Snapshot {
        try before.validate()
        guard before.targets.allSatisfy({ $0.stage == .removed }), !context.hasChanges else { throw SharedMediaStorageFailure.closed }
        let plan = before.plan, id = plan.profile.inventoryID
        let scope = SharedMediaNativeScopeIdentity(inventoryID: id, generation: plan.profile.generation,
            ownerID: plan.profile.ownerID, storeIdentity: plan.profile.storeIdentity, rootBinding: try plan.profile.rootIdentity)
        guard try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope) == header else { throw SharedMediaStorageFailure.stale }
        let inventory = try SharedMediaNativeAppEligibility.header(context: context, scope: scope)
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
        guard case .releasing(let snapshot) = witnesses[plan.package.id], snapshot.release.progress == before,
              snapshot.inventoryRevision == header.inventory.revision else { throw SharedMediaStorageFailure.stale }
        return snapshot
    }
    func requirePredecessor(_ context: ModelContext, header: SharedMediaNativeAppEligibility.Header) throws {
        guard self.header == header else { throw SharedMediaStorageFailure.stale }
        let snapshot = try Self.predecessor(before, header: header, context: context)
        guard try SharedMediaNativeReleasePrefix(terminal: snapshot) == prefix else { throw SharedMediaStorageFailure.stale }
        try seal.requirePredecessor(context)
        let id = before.plan.profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        try Self.requireFunding(funding, SharedMediaNativeAcquisitionBudget.terminalProjection(context: context,
            inventory: inventory, before: snapshot, after: after))
    }
    static func requireFunding(_ a: SharedMediaNativeAcquisitionBudget.Snapshot, _ b: SharedMediaNativeAcquisitionBudget.Snapshot) throws {
        guard a.totals == b.totals, a.originalIdentity == b.originalIdentity,
              a.metadataByPackage == b.metadataByPackage, a.baseMetadataByPackage == b.baseMetadataByPackage,
              a.receivedLiabilityByPackage == b.receivedLiabilityByPackage else { throw SharedMediaStorageFailure.conflict }
    }
}
