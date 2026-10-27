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

    static func receivedCandidates(_ container: ModelContainer, profile: SharedMediaNativeAppProfile) throws -> [SharedMediaNativeReceivedCandidate] {
        let context = ModelContext(container); context.autosaveEnabled = false
        let id = profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        guard try SharedMediaNativeAppEligibility.profile(inventory) == profile else { throw SharedMediaStorageFailure.stale }
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
        return try witnesses.values.compactMap { witness -> SharedMediaNativeReceivedCandidate? in
            guard case .generic(let value) = witness,
                  case .received = value.slot else { return nil }
            let row = value.row
            guard let resultHash = row.resultSHA256 else { throw SharedMediaStorageFailure.conflict }
            return SharedMediaNativeReceivedCandidate(profile: profile, packageID: row.id,
                draftGeneration: row.draftGeneration, operationID: row.operationID,
                revision: row.revision, preparedSHA256: row.preparedSHA256, receivedSHA256: resultHash)
        }.sorted { $0.packageID.uuidString < $1.packageID.uuidString }
    }

}
