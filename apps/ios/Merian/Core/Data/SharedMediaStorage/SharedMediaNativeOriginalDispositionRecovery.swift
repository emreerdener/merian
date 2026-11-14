import Foundation
import SwiftData

@MainActor
// The full domain name distinguishes this state or capability from adjacent storage boundaries.
// swiftlint:disable:next type_name
enum SharedMediaNativeOriginalDispositionRecovery {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Snapshot = SharedMediaNativeReleaseMetadataSnapshot.Snapshot
    static func isSuccessor(_ after: Values.Progress, of before: Values.Progress) throws -> Bool {
        try before.validate(); try after.validate()
        let index = try before.selectedIndex(.pairGoneOriginalLive)
        guard after.targets.indices.contains(index) else { return false }
        let first = before.targets[index], next = after.targets[index]
        guard next.pair == first.pair,
              next.stage == .originalRetiring || (next.stage == .removed && next.original?.disposition == .shared) else { return false }
        return after == (try before.advancing(next))
    }
    static func snapshot(_ before: Values.Progress, context: ModelContext,
                         header: SharedMediaNativeAppEligibility.Header) throws -> Snapshot {
        _ = try before.selectedIndex(.pairGoneOriginalLive)
        guard !context.hasChanges else { throw SharedMediaStorageFailure.closed }
        let plan = before.plan, id = plan.profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        guard try SharedMediaNativeAppEligibility.profile(inventory) == plan.profile,
              inventory.revision == header.inventory.revision, header.inventory.generation == plan.profile.generation,
              header.bootstrapID == plan.preHeader.bootstrapID, header.bootstrapGeneration == plan.preHeader.bootstrapGeneration,
              header.bootstrapContract == plan.preHeader.bootstrapContract, header.bootstrapRevision == plan.preHeader.bootstrapRevision,
              case .releasing(let value) = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)[plan.package.id],
              value.inventoryRevision == header.inventory.revision,
              try (value.release.progress == before || isSuccessor(value.release.progress, of: before)), !context.hasChanges else {
            throw SharedMediaStorageFailure.closed
        }
        return value
    }
    /// Frozen attempt comparison is in-process only. Cold successors use the
    /// complete persisted audit above, not reconstruction of deleted row bodies.
    static func read(_ attempt: SharedMediaNativeOriginalDispositionAttempt, container: ModelContainer,
                     header: () throws -> SharedMediaNativeAppEligibility.Header) throws -> Values.Progress {
        let pinned = try header(), c = ModelContext(container); c.autosaveEnabled = false
        let saved = try snapshot(attempt.before, context: c, header: pinned)
        if saved.release.progress == attempt.before {
            try attempt.requirePredecessor(c, header: pinned)
        } else {
            guard saved.release.progress == attempt.after,
                  pinned == (try SharedMediaNativeAppMetadataFacts.successor(attempt.header)) else { throw SharedMediaStorageFailure.stale }
            try attempt.seal.requireSavedSuccessor(c)
            let original = try SharedMediaNativeOriginalAccounting.audit(assetID: attempt.original.assetID,
                inventoryID: attempt.original.inventoryID, context: c)
            guard original.liveCount == attempt.original.liveCount - 1,
                  original.countRevision == (try SharedMediaStoragePolicy.add(attempt.original.countRevision, 1)),
                  original.retirement == attempt.retirement else { throw SharedMediaStorageFailure.conflict }
            if attempt.retirement == nil {
                guard try SharedMediaNativeOriginalDispositionAttestation.referenceDigest(assetID: original.assetID, context: c) == attempt.survivingReferenceDigest else {
                    throw SharedMediaStorageFailure.stale
                }
            }
            guard let liability = attempt.expectedLiability,
                  try SharedMediaNativeOriginalLiability.read(context: c, inventoryID: original.inventoryID) == liability,
                  try SharedMediaNativeReleaseSurvivorProjection.maximum(saved) == SharedMediaNativeOriginalDispositionFunding.projection(attempt) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        guard try header() == pinned, !c.hasChanges else { throw SharedMediaStorageFailure.stale }
        return saved.release.progress
    }
}
