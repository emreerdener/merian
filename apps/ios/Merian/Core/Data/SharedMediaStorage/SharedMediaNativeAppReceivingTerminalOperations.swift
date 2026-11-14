import Foundation
import SwiftData

/// Final atomic receiving closure under the existing registered release owner.
/// No unlink, new reservation, admission, AI dispatch or funding operation.
@MainActor
// The full name identifies the exact native operation and its ownership boundary.
// swiftlint:disable:next type_name
struct SharedMediaNativeAppReceivingTerminalOperations {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    let container: ModelContainer
    let authority: SharedMediaNativeAppOperationAuthority
    let expected: SharedMediaNativeAppEligibility.Header
    let settlement: SharedMediaNativeReleaseStageSettlement
    let io: SharedMediaNativeOriginalIO
    let binding: SharedMediaNativeBinding
    let verify: (SharedMediaNativeReleasePrefix) throws -> Void
    let recoveryHeader: () throws -> SharedMediaNativeAppEligibility.Header
    let boundary: (SharedMediaNativeMetadataBoundary) throws -> Void

    func apply(_ before: Values.Progress) async throws -> Values.Released {
        try validate()
        guard before.plan.profile == authority.profile else { throw SharedMediaStorageFailure.closed }
        if let pending = settlement.pendingTerminal {
            guard pending.before == before, pending.binding.bytes == binding.bytes, pending.binding.epoch == binding.epoch else { throw SharedMediaStorageFailure.closed }
            return try recover(pending)
        }
        guard !settlement.hasPending else { throw SharedMediaStorageFailure.closed }
        let c = fresh()
        if let row = try SharedMediaNativeReceivingPhaseGraph.row(before.plan.package.id, in: c), row.phaseRaw == "released" {
            // Cold historical replay is database-only and never remints an attempt.
            return try SharedMediaNativeReceivingTerminalRecovery.historical(before, context: c)
        }
        let attempt = try SharedMediaNativeReceivingTerminalAttempt.audited(before, header: expected, binding: binding, context: c)
        try await io.verifyReleasePrefix(attempt.prefix)
        try validate(); try attempt.requirePredecessor(fresh(), header: expected)
        try verify(attempt.prefix); try validate()
        let container = container, header = recoveryHeader
        try settlement.beginTerminal(attempt) {
            try SharedMediaNativeReceivingTerminalRecovery.read(attempt, container: container, header: header)
        }
        do {
            try mutate(attempt, context: c)
            try attempt.seal.validate(c); try boundary(.beforeSave); try validate()
            try attempt.requirePredecessor(fresh(), header: expected)
            try verify(attempt.prefix); try validate(); try attempt.seal.validate(c)
            // No suspension between authoritative physical/store fences and save.
            do { try c.save(); try boundary(.afterSave) } catch { c.rollback(); return try recover(attempt) }
            return try recover(attempt)
        } catch { c.rollback(); throw error }
    }
    private func mutate(_ a: SharedMediaNativeReceivingTerminalAttempt, context c: ModelContext) throws {
        let plan = a.before.plan, id = plan.profile.inventoryID, packageID = plan.package.id
        let origin = try SharedMediaNativeReleaseOrigin.read(plan, in: c)
        let package = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        let inventory = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        guard let row = try SharedMediaNativeReceivingPhaseGraph.row(packageID, in: c) else { throw SharedMediaStorageFailure.stale }
        row.phaseRaw = "released"; row.revision = try SharedMediaNativeReceivingTerminal.revision(a.after)
        row.preparedData = nil; row.releaseStartData = nil; row.releaseStartSHA256 = nil
        row.resultData = try a.after.encoded(); row.resultSHA256 = SharedMediaAcquisitionEncoding.digest(row.resultData!)
        inventory.revision = a.after.inventoryRevision
        c.delete(package); c.delete(member); c.delete(origin.rows.consumer)
        c.delete(origin.rows.queue); c.delete(origin.rows.job); c.delete(origin.rows.event)
    }
    private func recover(_ a: SharedMediaNativeReceivingTerminalAttempt) throws -> Values.Released {
        try boundary(.beforeReadback)
        guard case .after(let value) = try SharedMediaNativeReceivingTerminalRecovery.read(a, container: container,
            header: { try authority.header(container) }) else { throw SharedMediaStorageFailure.closed }
        try settlement.resolvedTerminal(a); return value
    }
    private func validate() throws {
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
    }
    private func fresh() -> ModelContext { let c = ModelContext(container); c.autosaveEnabled = false; return c }
}
