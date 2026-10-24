import Foundation
import SwiftData

/// First selected original only, after its pair is gone. No filesystem or
/// provider dependency is accepted. Every new attempt starts from durable state.
@MainActor
struct SharedMediaNativeAppOriginalDispositionOperations {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    let container: ModelContainer
    let authority: SharedMediaNativeAppOperationAuthority
    let expected: SharedMediaNativeAppEligibility.Header
    let settlement: SharedMediaNativeReleaseStageSettlement
    let recoveryHeader: () throws -> SharedMediaNativeAppEligibility.Header
    let boundary: (SharedMediaNativeMetadataBoundary) throws -> Void

    func apply(_ before: Values.Progress) async throws -> Values.Progress {
        try validate()
        guard settlement.request == nil, settlement.pendingPairDisposal == nil else { throw SharedMediaStorageFailure.closed }
        if let pending = settlement.pendingOriginalDisposition {
            guard pending.before == before else { throw SharedMediaStorageFailure.closed }
            return try recover(pending) // Exact read only; never reissue its save.
        }
        let saved = try SharedMediaNativeOriginalDispositionRecovery.snapshot(before, context: fresh(), header: expected)
        if try SharedMediaNativeOriginalDispositionRecovery.isSuccessor(saved.release.progress, of: before) {
            try validate(); return saved.release.progress
        }
        // A fresh registered owner holds the root/store and coordinator locks.
        // Saved predecessor is explicit restart admission, not a lost attempt.
        let id = UUID()
        try await SharedMediaNativeReleaseStageIdentity.audit(id, container: container, check: validate)
        try validate()
        let c = fresh()
        let attempt = try SharedMediaNativeOriginalDispositionAttempt.audited(before, retirementID: id, header: expected, context: c)
        let container = container, recoveryHeader = recoveryHeader
        try settlement.beginOriginalDisposition(attempt) {
            try SharedMediaNativeOriginalDispositionRecovery.read(attempt, container: container, header: recoveryHeader)
        }
        do {
            try mutate(attempt, context: c)
            try attempt.seal.validate(c); try boundary(.beforeSave); try validate()
            try attempt.requirePredecessor(fresh(), header: expected)
            try attempt.seal.validate(c); try validate()
            do { try c.save(); try boundary(.afterSave) }
            catch { c.rollback(); return try recover(attempt) }
            return try recover(attempt)
        } catch { c.rollback(); throw error }
    }
    private func mutate(_ a: SharedMediaNativeOriginalDispositionAttempt, context c: ModelContext) throws {
        let source = a.before.plan.targets[0].original
        let rows = try SharedMediaNativeAppOriginalRows(c, profile: a.before.plan.profile, source: source)
        let (ref, edge) = try SharedMediaNativeAppOriginalRows.reference(c, source: source, live: true)
        if let retirement = a.retirement {
            ref.isLive = false; ref.revision = try SharedMediaStoragePolicy.add(ref.revision, 1)
            edge.stateRaw = "retired"; edge.revision = ref.revision
            rows.asset.cleanupStateRaw = "retiring"
            rows.allocation.stateRaw = SharedMediaNativeRetirementIdentity.allocationState
            rows.allocation.physicalIdentity = try retirement.encoded()
        } else { c.delete(ref); c.delete(edge) }
        rows.count.liveCount = a.original.liveCount - 1
        rows.count.revision = try SharedMediaStoragePolicy.add(a.original.countRevision, 1)
        rows.count.retirementID = a.retirement?.retirementID
        rows.package.revision = a.successor.package.revision; rows.package.allocatedByteCount = a.successor.package.allocated
        rows.member.revision = a.successor.member.revision; rows.member.membersData = a.successor.member.bytes
        guard let slot = try SharedMediaNativeReceivingPhaseGraph.row(source.packageID, in: c) else { throw SharedMediaStorageFailure.stale }
        slot.revision = a.successor.slotRevision; slot.resultData = try a.after.encoded()
        slot.resultSHA256 = SharedMediaAcquisitionEncoding.digest(slot.resultData!)
        rows.inventory.revision = try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)
    }
    private func recover(_ a: SharedMediaNativeOriginalDispositionAttempt) throws -> Values.Progress {
        try boundary(.beforeReadback)
        let value = try SharedMediaNativeOriginalDispositionRecovery.read(a, container: container,
            header: { try authority.header(container) })
        guard value == a.after else { throw SharedMediaStorageFailure.closed }
        try settlement.resolvedOriginalDisposition(a)
        return value
    }
    private func validate() throws {
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
    }
    private func fresh() -> ModelContext { let c = ModelContext(container); c.autosaveEnabled = false; return c }
}
