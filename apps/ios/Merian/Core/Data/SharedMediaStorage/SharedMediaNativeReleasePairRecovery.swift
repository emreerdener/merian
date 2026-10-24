import Foundation
import SwiftData

/// Exact first pair-retirement outcome only. Readback does not inspect files,
/// mint a write right, release capacity, or advance to another target.
@MainActor
enum SharedMediaNativeReleasePairRecovery {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    static func read(_ expected: Values.Progress, container: ModelContainer,
                     closure: SharedMediaNativePairClosure? = nil, exactRevision: Int64? = nil,
                     header: () throws -> SharedMediaNativeAppEligibility.Header) throws -> Values.Progress {
        try expected.validate()
        guard expected.targets.first?.stage == .retiringPair,
              expected.targets.dropFirst().allSatisfy({ $0.stage == .readyPair }) else { throw SharedMediaStorageFailure.closed }
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
              let pair = snapshot.pairs.first(where: { (try? $0.intent().pairID) == expected.targets.first?.pairID }),
              let raw = pair.work.first?.closure,
              try (closure == nil || raw == closure?.encoded()),
              SharedMediaNativePairClosure.digest(Data(raw.utf8)) == expected.targets.first?.pair?.closureSHA256,
              try header() == before, !context.hasChanges else { throw SharedMediaStorageFailure.closed }
        return expected
    }
}
