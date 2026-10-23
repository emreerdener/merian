import Foundation
import SwiftData

/// Exact original start outcome only. A staged predecessor is not a retry right.
@MainActor
enum SharedMediaNativeReleaseStartRecovery {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    static func read(_ expected: Values.Progress, container: ModelContainer,
                     exactSuccessor: Bool = false,
                     header: () throws -> SharedMediaNativeAppEligibility.Header) throws -> Values.Progress {
        try expected.validate()
        guard expected == (try Values.Progress(plan: expected.plan)) else { throw SharedMediaStorageFailure.closed }
        let before = try header(), plan = expected.plan
        guard before.inventory.generation == plan.profile.generation,
              before.bootstrapID == plan.preHeader.bootstrapID,
              before.bootstrapGeneration == plan.preHeader.bootstrapGeneration,
              before.bootstrapContract == plan.preHeader.bootstrapContract,
              before.bootstrapRevision == plan.preHeader.bootstrapRevision else { throw SharedMediaStorageFailure.stale }
        let successor = try SharedMediaStoragePolicy.add(plan.preHeader.inventory.revision, 1)
        guard before.inventory.revision >= successor,
              !exactSuccessor || before.inventory.revision == successor else { throw SharedMediaStorageFailure.stale }
        let c = ModelContext(container); c.autosaveEnabled = false
        let id = plan.profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(c,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        guard try SharedMediaNativeAppEligibility.profile(inventory) == plan.profile,
              case .releasing(let snapshot) = try SharedMediaNativeReceivingCleanGraph.pending(c, inventory: inventory)[plan.package.id],
              snapshot.release.progress == expected, snapshot.inventoryRevision == before.inventory.revision,
              try header() == before, !c.hasChanges else { throw SharedMediaStorageFailure.closed }
        return snapshot.release.progress
    }
}
