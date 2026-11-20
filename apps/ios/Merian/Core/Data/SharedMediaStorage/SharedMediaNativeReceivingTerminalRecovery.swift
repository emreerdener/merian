import Foundation
import SwiftData

@MainActor
// The full domain name distinguishes this state or capability from adjacent storage boundaries.
// swiftlint:disable:next type_name
enum SharedMediaNativeReceivingTerminalRecovery {
    enum Saved: Equatable { case before, after(SharedMediaNativeReceivingReleaseValues.Released) }
    // Owner-held uncertainty and joined shutdown remain exact-header only.
    // An unrelated advance is not evidence of this attempt's exact funding
    // successor and deliberately keeps this settlement closed.
    static func read(_ attempt: SharedMediaNativeReceivingTerminalAttempt, container: ModelContainer,
                     header: () throws -> SharedMediaNativeAppEligibility.Header) throws -> Saved {
        let pinned = try header(), c = ModelContext(container); c.autosaveEnabled = false
        let value: Saved
        if pinned == attempt.header {
            try attempt.requirePredecessor(c, header: pinned); value = .before
        } else {
            guard pinned == (try SharedMediaNativeAppMetadataFacts.successor(attempt.header)) else { throw SharedMediaStorageFailure.stale }
            try attempt.seal.requireSavedSuccessor(c)
            let terminal = try historical(attempt.before, context: c)
            guard terminal == attempt.after else { throw SharedMediaStorageFailure.stale }
            let id = attempt.before.plan.profile.inventoryID
            let inventory = try SharedMediaNativePairPlanGraph.one(c,
                FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
            try SharedMediaNativeReceivingTerminalAttempt.requireFunding(attempt.funding,
                SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory,
                    ownerID: attempt.before.plan.profile.ownerID, format: .appV2))
            value = .after(terminal)
        }
        guard try header() == pinned, !c.hasChanges else { throw SharedMediaStorageFailure.stale }
        return value
    }
    static func historical(_ before: SharedMediaNativeReceivingReleaseValues.Progress, context: ModelContext) throws
        -> SharedMediaNativeReceivingReleaseValues.Released {
        // Cold, read-only recovery permits later stable-header revisions. It
        // cannot settle an owner-held attempt or grant another save.
        try before.validate()
        guard before.targets.allSatisfy({ $0.stage == .removed }),
              let row = try SharedMediaNativeReceivingPhaseGraph.row(before.plan.package.id, in: context) else { throw SharedMediaStorageFailure.closed }
        let id = before.plan.profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        let terminal = try SharedMediaNativeReceivingTerminal.read(row, context: context, inventory: inventory)
        guard terminal.value == (try .init(progress: before, inventoryRevision: terminal.value.inventoryRevision)) else { throw SharedMediaStorageFailure.stale }
        return terminal.value
    }
}
