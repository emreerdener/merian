import Foundation
import SwiftData

/// The selected saved originalRetiring target only, behind existing owner locks.
@MainActor
struct SharedMediaNativeAppOriginalRemovalOperations {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Rows = SharedMediaNativeAppOriginalRows
    let container: ModelContainer
    let authority: SharedMediaNativeAppOperationAuthority
    let expected: SharedMediaNativeAppEligibility.Header
    let settlement: SharedMediaNativeReleaseStageSettlement
    let io: SharedMediaNativeOriginalIO
    let binding: SharedMediaNativeBinding
    let verify: (SharedMediaNativeHeldOriginalInspection) throws -> SharedMediaNativeHeldOriginalInspection
    let requireAbsence: (SharedMediaNativeRetirementState) throws -> Void
    let recoveryHeader: () throws -> SharedMediaNativeAppEligibility.Header
    let boundary: (SharedMediaNativeMetadataBoundary) throws -> Void

    func apply(_ before: Values.Progress) async throws -> Values.Progress {
        try validate()
        guard settlement.request == nil, settlement.pendingPairDisposal == nil, settlement.pendingOriginalDisposition == nil else {
            throw SharedMediaStorageFailure.closed
        }
        if let prior = settlement.pendingOriginalDisposal {
            guard prior.before == before else { throw SharedMediaStorageFailure.closed }
            // In-process uncertainty is read-only, even if the file is absent.
            let saved = try SharedMediaNativeOriginalRemovalRecovery.read(prior, container: container, header: { try authority.header(container) })
            guard saved == prior.after else { throw SharedMediaStorageFailure.closed }
            try settlement.resolvedOriginalDisposal(prior)
            return saved
        }
        let c = fresh(), saved = try SharedMediaNativeOriginalRemovalRecovery.snapshot(before, context: c, header: expected)
        let after = try SharedMediaNativeOriginalRemovalRecovery.successor(before)
        if saved.release.progress == after { return after }
        let a = try SharedMediaNativeOriginalRemovalCapability.audited(before, header: expected, binding: binding, context: c)
        let container = container, io = io, verify = verify, recoveryHeader = recoveryHeader
        try settlement.beginOriginalDisposal(a) {
            try await SharedMediaNativeOriginalRemovalRecovery.settle(a, container: container,
                io: io, verify: verify, header: recoveryHeader)
        }
        defer { a.permit.revoke() }
        let inspection = try await io.inspectHeldOriginal(a.state)
        try a.requireInspection(inspection); try validate(); try predecessor(a)
        try a.verifyInspection(inspection, using: verify); try a.activate(inspection)
        let proof = try await io.release(a.disposal())
        try validate(); try predecessor(a)
        guard proof.retirement.state == a.state, proof.retirement.binding == binding.bytes,
              proof.retirement.epoch == binding.epoch else { throw SharedMediaStorageFailure.conflict }
        try requireAbsence(a.state)
        do {
            let rows = try Rows(c, profile: before.plan.profile, source: before.plan.targets[try before.selectedIndex(.originalRetiring)].original)
            let (ref, edge) = try Rows.reference(c, source: before.plan.targets[try before.selectedIndex(.originalRetiring)].original, live: false)
            c.delete(ref); c.delete(edge); c.delete(rows.asset); c.delete(rows.allocation); c.delete(rows.count); c.delete(rows.lease)
            rows.receipt.phaseRaw = "terminal"; rows.receipt.revision = 2; rows.receipt.terminalOutcomeRaw = "released"
            rows.receipt.requestData = nil; rows.receipt.resultData = nil; rows.receipt.packageID = nil; rows.receipt.assetID = nil
            rows.package.allocatedByteCount = a.successor.package.allocated; rows.package.revision = a.successor.package.revision
            rows.member.membersData = a.successor.member.bytes; rows.member.revision = a.successor.member.revision
            rows.inventory.revision = try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)
            guard let slot = try SharedMediaNativeReceivingPhaseGraph.row(before.plan.package.id, in: c) else { throw SharedMediaStorageFailure.stale }
            slot.revision = a.successor.slotRevision; slot.resultData = try after.encoded()
            slot.resultSHA256 = SharedMediaAcquisitionEncoding.digest(slot.resultData!)
            try a.seal.validate(c); try boundary(.beforeSave); try validate(); try predecessor(a)
            try a.seal.validate(c); try requireAbsence(a.state); try validate()
            // No await between fresh complete graph/absence/raw checks and save.
            do { try c.save(); try boundary(.afterSave) }
            catch { c.rollback(); return try recover(a) }
            return try recover(a)
        } catch { c.rollback(); throw error }
    }
    private func predecessor(_ a: SharedMediaNativeOriginalRemovalCapability) throws {
        try validate(); try a.requirePredecessor(fresh(), header: expected)
    }
    private func recover(_ a: SharedMediaNativeOriginalRemovalCapability) throws -> Values.Progress {
        try boundary(.beforeReadback)
        let saved = try SharedMediaNativeOriginalRemovalRecovery.read(a, container: container, header: { try authority.header(container) })
        guard saved == a.after else { throw SharedMediaStorageFailure.closed }
        try settlement.resolvedOriginalDisposal(a)
        return saved
    }
    private func validate() throws {
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
    }
    private func fresh() -> ModelContext { let c = ModelContext(container); c.autosaveEnabled = false; return c }
}
