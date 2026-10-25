import Foundation
import SwiftData

/// Exact identity of one explicitly requested later-target admission. Persisted
/// progress supplies evidence only; the registered owner's settlement owns it.
@MainActor
struct SharedMediaNativeReleaseContinuation: Equatable {
    let progress: SharedMediaNativeReceivingReleaseValues.Progress
    let bytes: Data
    let index: Int
    let row: SharedMediaNativeReceivingIntentGraph.Row
    let persistentID: PersistentIdentifier
    let header: SharedMediaNativeAppEligibility.Header
    let binding: Data
    let epoch: UUID

    var key: String { SharedMediaAcquisitionEncoding.digest(bytes) }
}

@MainActor
enum SharedMediaNativeReleaseContinuationAudit {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Snapshot = SharedMediaNativeReleaseMetadataSnapshot.Snapshot

    static func read(_ progress: Values.Progress, header: SharedMediaNativeAppEligibility.Header,
                     context: ModelContext) throws -> Snapshot {
        guard try progress.selectedIndex(.readyPair) > 0, !context.hasChanges else { throw SharedMediaStorageFailure.closed }
        let plan = progress.plan, id = plan.profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        guard try SharedMediaNativeAppEligibility.profile(inventory) == plan.profile,
              inventory.revision == header.inventory.revision, header.inventory.generation == plan.profile.generation,
              header.bootstrapID == plan.preHeader.bootstrapID, header.bootstrapGeneration == plan.preHeader.bootstrapGeneration,
              header.bootstrapContract == plan.preHeader.bootstrapContract, header.bootstrapRevision == plan.preHeader.bootstrapRevision else {
            throw SharedMediaStorageFailure.stale
        }
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
        guard case .releasing(let snapshot) = witnesses[plan.package.id], snapshot.release.progress == progress,
              snapshot.inventoryRevision == header.inventory.revision else { throw SharedMediaStorageFailure.stale }
        try SharedMediaNativeReleaseSurvivorProjection.maximum(snapshot).requireMetadataCapacity()
        _ = try SharedMediaStoragePolicy.add(inventory.revision, PhotoPreparationPolicy.add([SharedMediaNativeTerminalScan.read(container: context.container, inventoryID: inventory.id).consumptionAdvances] + witnesses.values.map { try $0.remainingAdvances }))
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        return snapshot
    }
}

@MainActor
struct SharedMediaNativeAppReleaseContinuationOperations {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    let container: ModelContainer
    let authority: SharedMediaNativeAppOperationAuthority
    let expected: SharedMediaNativeAppEligibility.Header
    let settlement: SharedMediaNativeReleaseStageSettlement
    let io: SharedMediaNativeOriginalIO
    let binding: SharedMediaNativeBinding
    let verify: (SharedMediaNativeReleasePrefix) throws -> Void

    func apply(_ progress: Values.Progress) async throws {
        do {
            try validate()
            let (identity, snapshot) = try read(progress)
            let prefix = try SharedMediaNativeReleasePrefix(snapshot)
            try await io.verifyReleasePrefix(prefix)
            try validate()
            let (current, repeated) = try read(progress)
            guard current == identity, try SharedMediaNativeReleasePrefix(repeated) == prefix,
                  try SharedMediaNativeReleaseSurvivorProjection.maximum(snapshot) == SharedMediaNativeReleaseSurvivorProjection.maximum(repeated) else {
                throw SharedMediaStorageFailure.stale
            }
            // Repeat descriptor checks after the awaited inspection and complete
            // live audit. No await between physical/row fences and admission.
            try verify(prefix); try validate()
            let (final, _) = try read(progress)
            guard final == identity else { throw SharedMediaStorageFailure.stale }
            try settlement.issueContinuation(identity)
        } catch {
            settlement.abandonContinuation(progress)
            throw error
        }
    }

    private func read(_ progress: Values.Progress) throws -> (SharedMediaNativeReleaseContinuation, SharedMediaNativeReleaseMetadataSnapshot.Snapshot) {
        try validate()
        let context = ModelContext(container); context.autosaveEnabled = false
        let snapshot = try SharedMediaNativeReleaseContinuationAudit.read(progress, header: expected, context: context)
        guard let row = try SharedMediaNativeReceivingPhaseGraph.row(progress.plan.package.id, in: context),
              SharedMediaNativeReceivingIntentGraph.Row(row) == snapshot.release.slot else { throw SharedMediaStorageFailure.stale }
        return (.init(progress: progress, bytes: try progress.encoded(), index: try progress.selectedIndex(.readyPair),
            row: snapshot.release.slot, persistentID: row.persistentModelID, header: expected,
            binding: binding.bytes, epoch: binding.epoch), snapshot)
    }
    private func validate() throws {
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
    }
}
