import Foundation
import SwiftData

@MainActor
enum SharedMediaNativeOriginalRemovalRecovery {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Snapshot = SharedMediaNativeReleaseMetadataSnapshot.Snapshot
    static func successor(_ before: Values.Progress) throws -> Values.Progress {
        try before.validate()
        let first = before.targets[try before.selectedIndex(.originalRetiring)]
        guard first.original?.disposition == .removed, first.original?.retirementID != nil else { throw SharedMediaStorageFailure.closed }
        return try before.advancing(.init(pairID: first.pairID, stage: .removed, pair: first.pair, original: first.original))
    }
    static func snapshot(_ before: Values.Progress, context: ModelContext,
                         header: SharedMediaNativeAppEligibility.Header) throws -> Snapshot {
        let after = try successor(before), plan = before.plan, id = plan.profile.inventoryID
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        guard try SharedMediaNativeAppEligibility.profile(inventory) == plan.profile,
              inventory.revision == header.inventory.revision, header.inventory.generation == plan.profile.generation,
              header.bootstrapID == plan.preHeader.bootstrapID, header.bootstrapGeneration == plan.preHeader.bootstrapGeneration,
              header.bootstrapContract == plan.preHeader.bootstrapContract, header.bootstrapRevision == plan.preHeader.bootstrapRevision,
              case .releasing(let value) = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)[plan.package.id],
              value.inventoryRevision == header.inventory.revision,
              value.release.progress == before || value.release.progress == after, !context.hasChanges else {
            throw SharedMediaStorageFailure.closed
        }
        // LiveAudit validates complete original absence, including reverse aliases,
        // terminal receipt and absent PhotoPreparationLease for a saved successor.
        return value
    }
    static func read(_ a: SharedMediaNativeOriginalRemovalCapability, container: ModelContainer,
                     header: () throws -> SharedMediaNativeAppEligibility.Header) throws -> Values.Progress {
        let pinned = try header(), c = ModelContext(container); c.autosaveEnabled = false
        let saved = try snapshot(a.before, context: c, header: pinned)
        if saved.release.progress == a.before { try a.requirePredecessor(c, header: pinned) }
        else {
            guard saved.release.progress == a.after,
                  pinned == (try SharedMediaNativeAppMetadataFacts.successor(a.header)) else { throw SharedMediaStorageFailure.stale }
            try a.seal.requireSavedSuccessor(c)
            guard try SharedMediaNativeOriginalLiability.read(context: c, inventoryID: a.original.inventoryID) == SharedMediaNativeOriginalRemovalFunding.liability(a),
                  try SharedMediaNativeReleaseSurvivorProjection.maximum(saved) == SharedMediaNativeOriginalRemovalFunding.projection(a) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        guard try header() == pinned, !c.hasChanges else { throw SharedMediaStorageFailure.stale }
        return saved.release.progress
    }
    static func settle(_ a: SharedMediaNativeOriginalRemovalCapability, container: ModelContainer,
                       io: SharedMediaNativeOriginalIO,
                       verify: (SharedMediaNativeHeldOriginalInspection) throws -> SharedMediaNativeHeldOriginalInspection,
                       header: () throws -> SharedMediaNativeAppEligibility.Header) async throws {
        if try read(a, container: container, header: header) == a.after { return }
        let pinned = try header()
        let inspection = try await io.inspectHeldOriginal(a.state)
        try a.requireInspection(inspection)
        guard try header() == pinned, try read(a, container: container, header: header) == a.before else {
            throw SharedMediaStorageFailure.stale
        }
        try a.verifyInspection(inspection, using: verify)
        // Old owner has joined. This only hands back the same durable cleanup
        // obligation; no new capability, metadata save or unlink occurs here.
    }
}
