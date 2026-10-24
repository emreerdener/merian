import Foundation
import SwiftData

/// Inactive, dedicated start leaf under the existing audited stage workflow.
/// It changes no media, held execution rows, accounting or provider state.
@MainActor
struct SharedMediaNativeAppReleaseStartOperations {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Snapshot = SharedMediaNativeReceivedReleaseSnapshot.StagedSnapshot
    let container: ModelContainer
    let authority: SharedMediaNativeAppOperationAuthority
    let expected: SharedMediaNativeAppEligibility.Header
    let settlement: SharedMediaNativeReleaseStageSettlement
    let recoveryHeader: () throws -> SharedMediaNativeAppEligibility.Header
    let boundary: (SharedMediaNativeMetadataBoundary) throws -> Void

    func apply(_ request: SharedMediaNativeReleaseStartRequest) async throws -> Values.Progress {
        try request.validate(); try validate()
        guard request.profile == authority.profile else { throw SharedMediaStorageFailure.closed }
        let admission = try settlement.startAdmission(request)
        let context = fresh(), inventory = try inventory(context)
        let snapshot = try predecessor(admission, context: context, inventory: inventory)
        try await SharedMediaNativeReleaseStartIdentity.audit(snapshot, container: container, check: validate)
        try validate()
        guard let row = try SharedMediaNativeReceivingPhaseGraph.row(request.packageID, in: context) else {
            throw SharedMediaStorageFailure.stale
        }
        let seal = try SharedMediaNativeReleaseStartPoststate(snapshot: snapshot, context: context, row: row, inventory: inventory)
        let progress = snapshot.components.progress, bytes = try progress.encoded()
        do {
            row.phaseRaw = "releasing"; row.revision = try progress.plan.releasingRevision
            row.preparedData = nil; row.resultData = bytes; row.resultSHA256 = SharedMediaAcquisitionEncoding.digest(bytes)
            row.releaseStartData = nil; row.releaseStartSHA256 = nil
            inventory.revision = try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)
            try seal.validate(context, row: row, inventory: inventory)
            try boundary(.beforeSave); try validate()
            let current = fresh(), currentInventory = try self.inventory(current)
            let repeated = try predecessor(admission, context: current, inventory: currentInventory)
            guard let currentRow = try SharedMediaNativeReceivingPhaseGraph.row(request.packageID, in: current) else {
                throw SharedMediaStorageFailure.stale
            }
            try seal.requirePredecessor(row: currentRow, inventory: currentInventory)
            try requireSame(snapshot, repeated)
            try seal.validate(context, row: row, inventory: inventory); try validate()
            let container = container, header = recoveryHeader
            try settlement.beginStart(admission, progress: progress) {
                .releasing(try SharedMediaNativeReleaseStartRecovery.read(progress, container: container, header: header))
            }
            do { try context.save(); try boundary(.afterSave) }
            catch { context.rollback(); return try recover(progress) }
            return try acknowledge(progress)
        } catch { context.rollback(); throw error }
    }
    private func predecessor(_ admission: SharedMediaNativeReleaseStartAdmission,
                             context: ModelContext, inventory: SharedMediaInventoryRecord) throws -> Snapshot {
        try validate()
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory, checkpoint: validate)
        guard case .staged(let snapshot) = witnesses[admission.request.packageID],
              snapshot.origin.request == admission.request, snapshot.origin.header == expected else {
            throw SharedMediaStorageFailure.stale
        }
        try settlement.validateStart(admission, row: snapshot.origin.row)
        try SharedMediaNativeReleaseStartIdentity.direct(snapshot, witnesses: witnesses, context: context)
        let others = try witnesses.filter { $0.key != admission.request.packageID }.values.map { try $0.remainingAdvances }
        let needed = try PhotoPreparationPolicy.add([1, snapshot.components.progress.remainingAdvances] + others)
        _ = try SharedMediaStoragePolicy.add(inventory.revision, needed)
        try snapshot.funding.release.requireExistingFunding()
        return snapshot
    }
    private func requireSame(_ a: Snapshot, _ b: Snapshot) throws {
        let x = a.components, y = b.components
        guard a.origin.row == b.origin.row, a.origin.header == b.origin.header,
              x.progress == y.progress, x.package == y.package, x.member == y.member,
              x.targetOrigins == y.targetOrigins, x.ownedOriginals == y.ownedOriginals,
              try x.pairs.map({ try SharedMediaNativeDraftEnvelope.bytes($0) }) == y.pairs.map({ try SharedMediaNativeDraftEnvelope.bytes($0) }),
              a.historical.baseBytes == b.historical.baseBytes, a.historical.originIDs == b.historical.originIDs,
              a.historical.liability == b.historical.liability, a.funding.staged == b.funding.staged,
              a.funding.release.projection == b.funding.release.projection else { throw SharedMediaStorageFailure.stale }
    }
    private func acknowledge(_ progress: Values.Progress) throws -> Values.Progress {
        try boundary(.beforeReadback)
        let result = try SharedMediaNativeReleaseStartRecovery.read(progress, container: container,
            exactSuccessor: true, header: { try authority.header(container) })
        guard let row = try SharedMediaNativeReceivingPhaseGraph.row(progress.plan.package.id, in: fresh()) else {
            throw SharedMediaStorageFailure.closed
        }
        try Task.checkCancellation()
        guard try authority.header(container) == SharedMediaNativeAppMetadataFacts.successor(expected) else {
            throw SharedMediaStorageFailure.stale
        }
        try settlement.acknowledgedStart(result, row: .init(row)); return result
    }
    private func recover(_ progress: Values.Progress) throws -> Values.Progress {
        try boundary(.beforeReadback)
        let value = try SharedMediaNativeReleaseStartRecovery.read(progress, container: container,
            exactSuccessor: true, header: { try authority.header(container) })
        try settlement.resolvedStart(value); return value
    }
    private func validate() throws {
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
    }
    private func fresh() -> ModelContext { let c = ModelContext(container); c.autosaveEnabled = false; return c }
    private func inventory(_ c: ModelContext) throws -> SharedMediaInventoryRecord {
        let id = authority.profile.inventoryID
        return try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
    }
}
