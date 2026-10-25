import Foundation
import SwiftData

/// Read-only classification of the same persisted cleanup operation. An intact
/// retiring predecessor is a restart obligation, never an absence assertion.
@MainActor
enum SharedMediaNativeReleasePairRemovalRecovery {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Snapshot = SharedMediaNativeReleaseMetadataSnapshot.Snapshot
    static func successor(_ before: Values.Progress) throws -> Values.Progress {
        try before.validate()
        let target = before.targets[try before.selectedIndex(.retiringPair)]
        return try before.advancing(.init(pairID: target.pairID, stage: .pairGoneOriginalLive, pair: target.pair, original: nil))
    }
    static func read(_ before: Values.Progress, container: ModelContainer,
                     header: () throws -> SharedMediaNativeAppEligibility.Header) throws -> Snapshot {
        let after = try successor(before), current = try header(), plan = before.plan
        guard current.inventory.generation == plan.profile.generation,
              current.bootstrapID == plan.preHeader.bootstrapID,
              current.bootstrapGeneration == plan.preHeader.bootstrapGeneration,
              current.bootstrapContract == plan.preHeader.bootstrapContract,
              current.bootstrapRevision == plan.preHeader.bootstrapRevision else { throw SharedMediaStorageFailure.stale }
        let c = ModelContext(container); c.autosaveEnabled = false
        let id = plan.profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        guard try SharedMediaNativeAppEligibility.profile(inventory) == plan.profile,
              case .releasing(let result) = try SharedMediaNativeReceivingCleanGraph.pending(c, inventory: inventory)[plan.package.id],
              result.release.progress == before || result.release.progress == after,
              result.inventoryRevision == current.inventory.revision,
              try header() == current, !c.hasChanges else { throw SharedMediaStorageFailure.closed }
        // The complete clean audit checks both work/lease closure forms before
        // removal and the full absentPair negative row shape after removal.
        return result
    }
    static func settle(_ capability: SharedMediaNativeReleasePairRemovalCapability,
                       container: ModelContainer, io: SharedMediaNativeOriginalIO,
                       verify: (SharedMediaNativeRetiringPairInspection) throws -> Void,
                       header: () throws -> SharedMediaNativeAppEligibility.Header) async throws {
        let snapshot = try read(capability.before, container: container, header: header)
        let c = ModelContext(container); c.autosaveEnabled = false
        if snapshot.release.progress == capability.after {
            try capability.seal.requireSavedSuccessor(c)
            return
        }
        try capability.seal.requirePredecessor(c)
        guard snapshot.pairs.contains(capability.state) else { throw SharedMediaStorageFailure.stale }
        let pinned = try header()
        var inspections: [SharedMediaNativeRetiringPairInspection] = []
        for work in capability.state.work {
            let proof = try await io.inspectRetiringPair(capability.state, workID: work.id)
            guard try header() == pinned else { throw SharedMediaStorageFailure.stale }
            try capability.requireInspection(proof); inspections.append(proof)
        }
        let current = ModelContext(container); current.autosaveEnabled = false
        try capability.seal.requirePredecessor(current)
        guard try read(capability.before, container: container, header: header).release.progress == capability.before,
              try header() == pinned else { throw SharedMediaStorageFailure.stale }
        for proof in inspections { try verify(proof) }
        // No surviving invocation/capability or released charge is claimed.
        // Caller has joined the old task before this sealed-drain classification.
    }
}
