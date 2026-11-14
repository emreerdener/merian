import Foundation
import SwiftData

/// Scalar-only traversal of historical receiving slots. Each page owns a fresh
/// context; no context, model, or unbounded decoded collection escapes a page.
@MainActor
enum SharedMediaNativeTerminalScan {
    typealias Terminal = SharedMediaNativeReceivingTerminal
    struct Summary: Equatable {
        var bytes: Int64 = 0
        var consumptionAdvances: Int64 = 0
        var appliedHandoffAdvances: Int64 = 0
        var remainingAdvances: Int64 { get throws { try PhotoPreparationPolicy.add([consumptionAdvances, appliedHandoffAdvances]) } }
        mutating func include(_ bytes: Int64) throws {
            guard bytes > 0, bytes <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
            self.bytes = try PhotoPreparationPolicy.add([self.bytes, bytes])
            consumptionAdvances = try SharedMediaStoragePolicy.add(consumptionAdvances, 1)
        }
    }

    /// Also used by strict dirty poststate owners: reads the unchanged saved
    /// terminals independently of their dirty context. Their write seals forbid
    /// changing terminal rows. The terminal writer has its own projected delta.
    static func read(container: ModelContainer, inventoryID: UUID,
                     expectedHeader: SharedMediaNativeAppEligibility.Header? = nil,
                     checkpoint: () throws -> Void = {},
                     visitApplied: (SharedMediaNativePhotoAllocationSnapshot.Applied) throws -> Void = { _ in },
                     visit: (Terminal.Snapshot) throws -> Void = { _ in }) throws -> Summary {
        let (scope, expected) = try fence(container, inventoryID: inventoryID)
        if let expectedHeader {
            guard expected == expectedHeader else { throw SharedMediaStorageFailure.stale }
        }
        var offset = 0, result = Summary()
        while true {
            try Task.checkCancellation(); try checkpoint()
            let count: Int = try {
                let c = fresh(container)
                let inventory = try SharedMediaNativeAppEligibility.header(context: c, scope: scope)
                guard try SharedMediaNativeAppEligibility.snapshot(context: c, scope: scope) == expected else { throw SharedMediaStorageFailure.stale }
                var q = FetchDescriptor<SharedMediaReceivingIntentRecord>(sortBy: [SortDescriptor(\.cursorKey)])
                q.fetchOffset = offset; q.fetchLimit = SharedMediaStoragePolicy.pageSize
                let rows = try c.fetch(q)
                for row in rows {
                    try Task.checkCancellation(); try checkpoint()
                    guard row.inventoryID == scope.inventoryID, row.inventoryGeneration == scope.generation,
                          row.ownerID == scope.ownerID, row.cursorKey == row.id.uuidString.lowercased() else { throw SharedMediaStorageFailure.conflict }
                    if row.phaseRaw == "released" {
                        let terminal = try Terminal.read(row, context: c, inventory: inventory, checkpoint: checkpoint)
                        try result.include(terminal.bytes); try visit(terminal)
                    } else if let consumer = try SharedMediaConsumerLookup.one(c, packageID: row.id),
                              SharedMediaNativeConsumerCohort.AppliedInitialFormat(rawValue: consumer.contractVersion) != nil {
                        // Retained occupancy is not a terminal byte charge or a
                        // terminal-consumption advance. Do not recurse into roots.
                        let applied = try SharedMediaNativePhotoAllocationSnapshot.Applied.read(row,
                            inventory: inventory, context: c, checkpoint: checkpoint)
                        result.appliedHandoffAdvances = try SharedMediaStoragePolicy.add(result.appliedHandoffAdvances,
                            applied.cohort.historyHandoffRemainingAdvances)
                        try visitApplied(applied)
                    } else {
                        // Live roots are classified by CleanGraph. This scan must
                        // not recurse into that graph or filter away raw orphans.
                        let id = row.id
                        let member = try SharedMediaNativePairPlanGraph.one(c,
                            FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
                        guard member.inventoryID == scope.inventoryID, member.inventoryGeneration == scope.generation,
                              member.ownerID == scope.ownerID, member.draftGeneration == row.draftGeneration else { throw SharedMediaStorageFailure.conflict }
                    }
                }
                guard !c.hasChanges, try SharedMediaNativeAppEligibility.snapshot(context: c, scope: scope) == expected else { throw SharedMediaStorageFailure.stale }
                return rows.count
            }()
            try checkpoint()
            guard try SharedMediaNativeAppEligibility.snapshot(context: fresh(container), scope: scope) == expected else { throw SharedMediaStorageFailure.stale }
            if count < SharedMediaStoragePolicy.pageSize { break }
            let (next, overflow) = offset.addingReportingOverflow(count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
        }
        return result
    }

    static func requireAbsent(_ ids: [UUID], container: ModelContainer, inventoryID: UUID,
                              checkpoint: () throws -> Void = {}) throws {
        let selected = Set(ids)
        _ = try read(container: container, inventoryID: inventoryID, checkpoint: checkpoint, visitApplied: { applied in
            let context = fresh(container)
            try applied.requireCurrent(context: context)
            guard try selected.isDisjoint(with: SharedMediaNativeTerminalIdentity.namespace(applied.prepared, context: context).all) else {
                throw SharedMediaStorageFailure.conflict
            }
        }) { terminal in
            guard selected.isDisjoint(with: SharedMediaNativeTerminalIdentity.all(terminal.value)) else { throw SharedMediaStorageFailure.conflict }
        }
    }

    private static func fence(_ container: ModelContainer, inventoryID: UUID) throws
        -> (SharedMediaNativeScopeIdentity, SharedMediaNativeAppEligibility.Header) {
        guard !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let c = fresh(container)
        let inventory = try SharedMediaNativePairPlanGraph.one(c,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let p = try SharedMediaNativeAppEligibility.profile(inventory)
        let scope = SharedMediaNativeScopeIdentity(inventoryID: p.inventoryID, generation: p.generation,
            ownerID: p.ownerID, storeIdentity: p.storeIdentity, rootBinding: try p.rootIdentity)
        return (scope, try SharedMediaNativeAppEligibility.snapshot(context: c, scope: scope))
    }
    private static func fresh(_ container: ModelContainer) -> ModelContext {
        let c = ModelContext(container); c.autosaveEnabled = false; return c
    }
}
