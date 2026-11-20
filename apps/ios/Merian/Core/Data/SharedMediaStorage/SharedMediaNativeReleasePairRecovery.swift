import Foundation
import SwiftData

/// Exact selected pair-retirement outcome only. Readback does not inspect files,
/// mint a write right, release capacity, or advance to another target.
@MainActor
enum SharedMediaNativeReleasePairRecovery {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    static func read(_ expected: Values.Progress, container: ModelContainer,
                     closure: SharedMediaNativePairClosure? = nil, exactRevision: Int64? = nil,
                     header: () throws -> SharedMediaNativeAppEligibility.Header) throws -> Values.Progress {
        try expected.validate()
        let target = expected.targets[try expected.selectedIndex(.retiringPair)]
        let before = try header(), plan = expected.plan
        guard before.inventory.generation == plan.profile.generation,
              before.bootstrapID == plan.preHeader.bootstrapID, before.bootstrapGeneration == plan.preHeader.bootstrapGeneration,
              before.bootstrapContract == plan.preHeader.bootstrapContract, before.bootstrapRevision == plan.preHeader.bootstrapRevision,
              exactRevision == nil || before.inventory.revision == exactRevision else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        let id = plan.profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        guard try SharedMediaNativeAppEligibility.profile(inventory) == plan.profile,
              case .releasing(let snapshot) = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)[plan.package.id],
              snapshot.release.progress == expected, snapshot.inventoryRevision == before.inventory.revision,
              let pair = snapshot.pairs.first(where: { (try? $0.intent().pairID) == target.pairID }),
              let raw = pair.work.first?.closure,
              try (closure == nil || raw == closure?.encoded()),
              SharedMediaNativePairClosure.digest(Data(raw.utf8)) == target.pair?.closureSHA256,
              try header() == before, !context.hasChanges else { throw SharedMediaStorageFailure.closed }
        return expected
    }
    /// Only a joined owner's continuation may hand back its exact ready
    /// predecessor. This read grants nothing and retains the spent local right.
    static func readContinuation(_ attempt: SharedMediaNativeReleasePairAttempt,
                                 seal: SharedMediaNativeReleasePairPoststate, container: ModelContainer,
                                 header: () throws -> SharedMediaNativeAppEligibility.Header) throws -> Values.Progress {
        let pinned = try header()
        if pinned.inventory.revision != attempt.state.plan.inventoryRevision {
            return try read(attempt.after, container: container, closure: attempt.closure, header: header)
        }
        let context = ModelContext(container); context.autosaveEnabled = false
        let snapshot = try SharedMediaNativeReleaseContinuationAudit.read(attempt.before, header: pinned, context: context)
        guard snapshot.release.slot == attempt.row, snapshot.pairs.contains(attempt.state) else { throw SharedMediaStorageFailure.stale }
        try seal.requirePredecessor(context)
        guard try header() == pinned, !context.hasChanges else { throw SharedMediaStorageFailure.stale }
        return attempt.before
    }

}
