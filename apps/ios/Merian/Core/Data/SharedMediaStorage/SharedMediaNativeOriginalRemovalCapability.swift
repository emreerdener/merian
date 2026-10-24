import Foundation
import os
import SwiftData

/// Revocation joins the entire synchronous descriptor operation. The body must
/// never re-enter MainActor or this lock, including DEBUG fault callbacks.
final class SharedMediaNativeOriginalUnlinkPermit: Sendable {
    private struct State: Sendable {
        var revoked = false, activated = false, consumed = false, absent = false
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let expected: SharedMediaNativeRetirementState
    private let binding: Data
    private let epoch: UUID
    fileprivate init(state: SharedMediaNativeRetirementState, binding: SharedMediaNativeBinding) {
        expected = state; self.binding = binding.bytes; epoch = binding.epoch
    }
    fileprivate func observe(_ proof: SharedMediaNativeHeldOriginalInspection) throws {
        try lock.withLock {
            guard proof.state == expected, proof.binding == binding, proof.epoch == epoch,
                  !$0.absent || !proof.present else { throw SharedMediaStorageFailure.conflict }
            // Evidence may arrive after revocation. It never reactivates authority.
            $0.absent = $0.absent || !proof.present
        }
    }
    fileprivate func activate(_ proof: SharedMediaNativeHeldOriginalInspection) throws {
        try lock.withLock {
            guard !$0.revoked, !$0.activated, !$0.absent || !proof.present, proof.state == expected,
                  proof.binding == binding, proof.epoch == epoch else { throw SharedMediaStorageFailure.closed }
            $0.activated = true; $0.absent = $0.absent || !proof.present
        }
    }
    func requireActive() throws {
        try lock.withLock { guard !$0.revoked, $0.activated, !$0.consumed else { throw SharedMediaStorageFailure.closed } }
    }
    var hasObservedAbsence: Bool { lock.withLock { $0.absent } }
    func revoke() { lock.withLock { $0.revoked = true } }
    func withCurrent<T>(_ retirement: SharedMediaNativeRetirement,
                        body: (Bool, () -> Void) throws -> T) throws -> T {
        try lock.withLock { state in
            guard !state.revoked, state.activated, !state.consumed, retirement.state == expected,
                  retirement.binding == binding, retirement.epoch == epoch else { throw SharedMediaStorageFailure.closed }
            state.consumed = true
            let absent = state.absent
            var observed = false
            defer { state.absent = state.absent || observed }
            return try body(absent, { observed = true })
        }
    }
}

/// Only the complete saved first-original retirement can mint this held-only
/// capability. Ordinary original lifecycle guards remain unchanged.
@MainActor
final class SharedMediaNativeOriginalRemovalCapability {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Snapshot = SharedMediaNativeReleaseMetadataSnapshot.Snapshot
    let before: Values.Progress, after: Values.Progress
    let snapshot: Snapshot
    let original: SharedMediaNativeOriginalAccounting.Snapshot
    let state: SharedMediaNativeRetirementState
    let successor: SharedMediaNativeReceivingReleaseState.Expected
    let seal: SharedMediaNativeOriginalRemovalPoststate
    let header: SharedMediaNativeAppEligibility.Header
    let binding: SharedMediaNativeBinding
    let liability: SharedMediaNativeOriginalLiability.Snapshot
    let terminal: SharedMediaAcquisitionReceipt.TerminalIdentity
    let permit: SharedMediaNativeOriginalUnlinkPermit

    private init(before: Values.Progress, snapshot: Snapshot, original: SharedMediaNativeOriginalAccounting.Snapshot,
                 state: SharedMediaNativeRetirementState, header: SharedMediaNativeAppEligibility.Header,
                 binding: SharedMediaNativeBinding, context: ModelContext) throws {
        let after = try SharedMediaNativeOriginalRemovalRecovery.successor(before)
        self.before = before; self.after = after; self.snapshot = snapshot; self.original = original
        self.state = state; self.header = header; self.binding = binding
        successor = try SharedMediaNativeReceivingReleaseState.expected(after,
            prepared: snapshot.release.origin.prepared, received: snapshot.release.origin.received)
        let receiptID = original.leaseID
        let receipt = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == receiptID }))
        terminal = .init(operationID: receipt.id, inventoryID: receipt.inventoryID, inventoryGeneration: receipt.inventoryGeneration,
            ownerID: receipt.ownerID, requestFingerprint: receipt.requestFingerprint)
        liability = try SharedMediaNativeOriginalLiability.read(context: context, inventoryID: original.inventoryID)
        seal = try .init(before: before, after: after, successor: successor, original: original, context: context)
        permit = .init(state: state, binding: binding)
        try SharedMediaNativeOriginalRemovalFunding.check(self)
    }
    static func audited(_ before: Values.Progress, header: SharedMediaNativeAppEligibility.Header,
                        binding: SharedMediaNativeBinding, context: ModelContext) throws -> SharedMediaNativeOriginalRemovalCapability {
        let snapshot = try SharedMediaNativeOriginalRemovalRecovery.snapshot(before, context: context, header: header)
        guard snapshot.release.progress == before, let target = before.plan.targets.first else { throw SharedMediaStorageFailure.closed }
        let original = try SharedMediaNativeOriginalAccounting.audit(assetID: target.original.assetID,
            inventoryID: before.plan.profile.inventoryID, context: context)
        guard original.liveCount == 0, let identity = original.retirement,
              before.targets.first?.original?.retirementID == identity.retirementID,
              before.targets.first?.original?.closureSHA256 == SharedMediaAcquisitionEncoding.digest(Data(try identity.encoded().utf8)),
              original.inventoryRevision == header.inventory.revision else { throw SharedMediaStorageFailure.conflict }
        let rows = try SharedMediaNativeAppOriginalRows(context, profile: before.plan.profile, source: target.original)
        _ = try SharedMediaNativeAppOriginalRows.reference(context, source: target.original, live: false)
        try SharedMediaNativeAppOriginalRows.noPair(context, source: target.original)
        let (request, result) = try rows.completed()
        guard request.operationID == target.acquisitionID, result.descriptor == identity.proof else { throw SharedMediaStorageFailure.conflict }
        let state = SharedMediaNativeRetirementState(request: request, file: original.file, identity: identity,
            reference: target.original, inventoryRevision: header.inventory.revision, packageRevision: rows.package.revision,
            membershipRevision: rows.member.revision, countRevision: original.countRevision,
            membershipBytes: rows.member.membersData, envelope: rows.package.supportingContextData)
        return try .init(before: before, snapshot: snapshot, original: original, state: state,
            header: header, binding: binding, context: context)
    }
    func requirePredecessor(_ context: ModelContext, header: SharedMediaNativeAppEligibility.Header) throws {
        guard header == self.header,
              try SharedMediaNativeOriginalRemovalRecovery.snapshot(before, context: context, header: header).release.progress == before,
              try SharedMediaNativeOriginalAccounting.audit(assetID: original.assetID, inventoryID: original.inventoryID, context: context) == original,
              try SharedMediaNativeOriginalLiability.read(context: context, inventoryID: original.inventoryID) == liability else {
            throw SharedMediaStorageFailure.stale
        }
        try seal.requirePredecessor(context)
        try SharedMediaNativeOriginalRemovalFunding.check(self)
    }
    func activate(_ proof: SharedMediaNativeHeldOriginalInspection) throws {
        try requireInspection(proof)
        try permit.activate(proof)
    }
    func requireInspection(_ proof: SharedMediaNativeHeldOriginalInspection) throws {
        guard proof.state == state, proof.binding == binding.bytes, proof.epoch == binding.epoch else { throw SharedMediaStorageFailure.conflict }
        try permit.observe(proof)
    }
    func verifyInspection(_ proof: SharedMediaNativeHeldOriginalInspection,
                          using verify: (SharedMediaNativeHeldOriginalInspection) throws -> SharedMediaNativeHeldOriginalInspection) throws {
        try requireInspection(proof)
        let current = try verify(proof)
        try requireInspection(current) // Record before a changed-presence failure.
        guard current.present == proof.present else { throw SharedMediaStorageFailure.conflict }
    }
    func requireDisposal() throws { try permit.requireActive() }
    func disposal() throws -> SharedMediaNativeRetirement { try .held(self) }
}
