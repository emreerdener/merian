import Foundation
import SwiftData

/// Inactive ordered held-pair metadata transaction. The existing owner supplies
/// all locks and file access. There is deliberately no unlink or dispatch path.
@MainActor
struct SharedMediaNativeAppReleasePairOperations {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Snapshot = SharedMediaNativeReleaseMetadataSnapshot.Snapshot
    let container: ModelContainer
    let authority: SharedMediaNativeAppOperationAuthority
    let expected: SharedMediaNativeAppEligibility.Header
    let settlement: SharedMediaNativeReleaseStageSettlement
    let io: SharedMediaNativeOriginalIO
    let binding: SharedMediaNativeBinding
    let verify: (SharedMediaNativePairInspection) throws -> Void
    let verifyPrefix: (SharedMediaNativeReleasePrefix) throws -> Void
    let recoveryHeader: () throws -> SharedMediaNativeAppEligibility.Header
    let boundary: (SharedMediaNativeMetadataBoundary) throws -> Void

    func apply(_ progress: Values.Progress) async throws -> Values.Progress {
        do { return try await perform(progress) }
        catch { settlement.abandonContinuation(progress); throw error }
    }
    private func perform(_ progress: Values.Progress) async throws -> Values.Progress {
        try progress.validate(); try validate()
        let admission = try settlement.pairAdmission(progress)
        let attempt: SharedMediaNativeReleasePairAttempt
        if let frozen = try settlement.frozenPair(admission) { attempt = frozen }
        else {
            let context = fresh(), inventory = try inventory(context)
            let snapshot = try predecessor(admission, context: context, inventory: inventory)
            let target = progress.targets[try progress.selectedIndex(.readyPair)]
            guard let state = snapshot.pairs.first(where: { (try? $0.intent().pairID) == target.pairID }) else { throw SharedMediaStorageFailure.closed }
            var proofs: [SharedMediaNativePairInspection] = []
            for work in state.work { proofs.append(try await io.inspectPair(state, workID: work.id)); try validate() }
            attempt = try settlement.freezePair(.init(snapshot: snapshot, proofs: proofs, binding: binding), admission: admission)
        }
        try await SharedMediaNativeReleaseStageIdentity.audit(attempt.closure.retirementID, container: container, check: validate)
        try validate()
        let context = fresh(), inventory = try inventory(context)
        let snapshot = try predecessor(admission, context: context, inventory: inventory, attempt: attempt)
        let seal = try SharedMediaNativeReleasePairPoststate(attempt, context: context)
        let packageID = progress.plan.package.id, pairID = attempt.closure.pairID
        let package = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        let pair = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }))
        guard let row = try SharedMediaNativeReceivingPhaseGraph.row(packageID, in: context) else { throw SharedMediaStorageFailure.stale }
        if admission.continuation != nil {
            let container = container, header = recoveryHeader
            try settlement.beginPair(attempt) {
                .releasing(try SharedMediaNativeReleasePairRecovery.readContinuation(attempt,
                    seal: seal, container: container, header: header))
            }
        }
        do {
            try SharedMediaNativePairRetirementRows.apply(context: context, package: package, pair: pair,
                before: attempt.state, closure: attempt.closure)
            package.revision = attempt.successor.package.revision
            member.revision = attempt.successor.member.revision; member.membersData = attempt.successor.member.bytes
            row.revision = attempt.successor.slotRevision; row.resultData = try attempt.after.encoded()
            row.resultSHA256 = SharedMediaAcquisitionEncoding.digest(row.resultData!)
            inventory.revision = try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)
            try seal.validate(context); try boundary(.beforeSave); try validate()
            let current = fresh(), currentInventory = try self.inventory(current)
            let repeated = try predecessor(admission, context: current, inventory: currentInventory, attempt: attempt)
            try requireSame(snapshot, repeated); try seal.requirePredecessor(current)
            try seal.validate(context); try validate()
            for proof in attempt.proofs { try verify(proof) }
            let container = container, header = recoveryHeader
            if admission.continuation == nil {
                try settlement.beginPair(attempt) {
                    .releasing(try SharedMediaNativeReleasePairRecovery.read(attempt.after, container: container,
                        closure: attempt.closure, header: header))
                }
            }
            do { try context.save(); try boundary(.afterSave) }
            catch { context.rollback(); return try recover(attempt) }
            return try recover(attempt)
        } catch { context.rollback(); throw error }
    }
    private func predecessor(_ admission: SharedMediaNativeReleasePairAdmission, context: ModelContext,
                             inventory: SharedMediaInventoryRecord, attempt: SharedMediaNativeReleasePairAttempt? = nil) throws -> Snapshot {
        try validate()
        try settlement.validatePair(admission, attempt: attempt)
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory, checkpoint: validate)
        guard case .releasing(let snapshot) = witnesses[admission.progress.plan.package.id],
              snapshot.release.progress == admission.progress, snapshot.release.slot == admission.row else { throw SharedMediaStorageFailure.stale }
        if let continuation = admission.continuation {
            guard continuation.header == expected, continuation.binding == binding.bytes, continuation.epoch == binding.epoch,
                  continuation.bytes == (try admission.progress.encoded()),
                  let row = try SharedMediaNativeReceivingPhaseGraph.row(admission.progress.plan.package.id, in: context),
                  row.persistentModelID == continuation.persistentID else { throw SharedMediaStorageFailure.stale }
            try verifyPrefix(SharedMediaNativeReleasePrefix(snapshot))
        }
        let projection = try SharedMediaNativeReleaseSurvivorProjection.maximum(snapshot)
        try projection.requireMetadataCapacity()
        if let attempt {
            guard attempt.before == admission.progress, attempt.row == admission.row,
                  snapshot.pairs.contains(attempt.state), attempt.state.plan.inventoryRevision == expected.inventory.revision else {
                throw SharedMediaStorageFailure.stale
            }
            try SharedMediaNativeReleaseStageIdentity.requireAbsent(attempt.closure.retirementID, witnesses: Array(witnesses.values))
            try SharedMediaNativeTerminalScan.requireAbsent([attempt.closure.retirementID], container: container, inventoryID: inventory.id)
            try SharedMediaNativeReleaseStageIdentity.direct(attempt.closure.retirementID, context: context)
            try SharedMediaNativeReleasePairFunding.check(attempt, snapshot: snapshot, funded: projection)
            let other = try witnesses.filter { $0.key != admission.progress.plan.package.id }.values.map { try $0.remainingAdvances }
            _ = try SharedMediaStoragePolicy.add(inventory.revision, PhotoPreparationPolicy.add([SharedMediaNativeTerminalScan.read(container: container, inventoryID: inventory.id).consumptionAdvances, 1, attempt.after.remainingAdvances] + other))
        }
        return snapshot
    }
    private func requireSame(_ a: Snapshot, _ b: Snapshot) throws {
        guard a.release.slot == b.release.slot, a.inventoryRevision == b.inventoryRevision,
              a.release.state.package == b.release.state.package, a.release.state.member == b.release.state.member,
              a.pairs == b.pairs, a.ownedOriginals == b.ownedOriginals, a.targetOrigins == b.targetOrigins,
              try SharedMediaNativeReleaseSurvivorProjection.maximum(a) == SharedMediaNativeReleaseSurvivorProjection.maximum(b) else {
            throw SharedMediaStorageFailure.stale
        }
    }
    private func recover(_ attempt: SharedMediaNativeReleasePairAttempt) throws -> Values.Progress {
        try boundary(.beforeReadback)
        if try attempt.before.selectedIndex(.readyPair) == 0 {
            let value = try SharedMediaNativeReleasePairRecovery.read(attempt.after, container: container,
                closure: attempt.closure, exactRevision: SharedMediaStoragePolicy.add(expected.inventory.revision, 1),
                header: { try authority.header(container) })
            try settlement.resolvedPair(value); return value
        }
        let revision = try authority.header(container).inventory.revision
        let successorRevision = try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)
        guard revision == expected.inventory.revision || revision == successorRevision else {
            throw SharedMediaStorageFailure.stale
        }
        // Recovery closures are pinned to this attempt's raw predecessor seal
        // and retirement identity; they grant no subsequent admission.
        return try settlement.recoverPair(attempt.after)
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
