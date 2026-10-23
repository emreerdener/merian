import Foundation
import SwiftData

enum SharedMediaNativeRepositoryOpenKind { case qualificationEmpty, qualificationOriginal, scopedInspection, appInitialization, appDispatch }

/// Fresh persisted facts only. File fences and capability construction remain
/// private to the repository; no helper here accepts or returns an authority.
@MainActor
enum SharedMediaNativeRepositoryFacts {
    static func empty(_ container: ModelContainer, inventoryID: UUID, storeIdentity: String,
                      rootBinding: String, generation: UUID) throws -> SharedMediaStorageSnapshot {
        let context = ModelContext(container); context.autosaveEnabled = false
        guard let row = try SharedMediaNativeEligibility.emptyState(context, inventoryID: inventoryID,
            storeIdentity: storeIdentity, rootBinding: rootBinding), row.generation == generation else {
            throw SharedMediaStorageFailure.conflict
        }
        return .init(generation: row.generation, revision: row.revision, phase: row.phaseRaw, cursor: row.cursor)
    }
    static func scoped(_ container: ModelContainer, scope: SharedMediaNativeScopeIdentity) throws -> SharedMediaStorageSnapshot {
        let context = ModelContext(container); context.autosaveEnabled = false
        let row = try SharedMediaNativeScopedEligibility.header(context: context, scope: scope)
        return .init(generation: row.generation, revision: row.revision, phase: row.phaseRaw, cursor: row.cursor)
    }
    static func app(_ container: ModelContainer, scope: SharedMediaNativeScopeIdentity?) throws -> SharedMediaNativeAppEligibility.Header {
        guard let scope else { throw SharedMediaStorageFailure.closed }
        let context = ModelContext(container); context.autosaveEnabled = false
        return try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope)
    }
    static func receivingSlot(_ container: ModelContainer, inventoryID: UUID,
                              packageID: UUID) throws -> SharedMediaNativeReceivingIntentGraph.Row? {
        let context = ModelContext(container); context.autosaveEnabled = false
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        return try SharedMediaNativeReceivingPhaseGraph.pending(context, inventory: inventory)[packageID]?.row
    }

}
