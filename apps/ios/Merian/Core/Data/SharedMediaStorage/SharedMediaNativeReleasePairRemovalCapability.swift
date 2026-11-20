import Foundation
import os
import SwiftData

/// A single serial I/O invocation, not a persistence or new-admission authority.
/// The mutex covers the *whole* descriptor operation. No callback under this
/// lock may enter MainActor, settlement, or this permit (including DEBUG faults).
final class SharedMediaNativePairUnlinkPermit: Sendable {
    private struct State: Sendable {
        var revoked = false
        var activated = false
        var remaining: Set<UUID>
    }
    private let lock: OSAllocatedUnfairLock<State>
    private let progress: SharedMediaNativeReceivingReleaseValues.Progress
    private let closure: SharedMediaNativePairClosure
    private let pair: SharedMediaNativePairFileState
    private let binding: Data
    private let epoch: UUID
    fileprivate init(progress: SharedMediaNativeReceivingReleaseValues.Progress, closure: SharedMediaNativePairClosure,
                     state: SharedMediaNativePairFileState, binding: SharedMediaNativeBinding) {
        self.progress = progress; self.closure = closure; pair = state
        self.binding = binding.bytes; epoch = binding.epoch
        lock = OSAllocatedUnfairLock(initialState: State(remaining: Set(state.work.map(\.id))))
    }
    fileprivate func activate() throws {
        try lock.withLock {
            guard !$0.revoked, !$0.activated else { throw SharedMediaStorageFailure.closed }
            $0.activated = true
        }
    }
    fileprivate func requireActive() throws {
        try lock.withLock { guard !$0.revoked, $0.activated else { throw SharedMediaStorageFailure.closed } }
    }
    func revoke() { lock.withLock { $0.revoked = true } }
    func withCurrent<T>(_ disposal: SharedMediaNativePairDisposal, workID: UUID, body: () throws -> T) throws -> T {
        try lock.withLock { state in
            let target = progress.targets[try progress.selectedIndex(.retiringPair)]
            guard !state.revoked, state.activated, disposal.state == pair, disposal.binding == binding, disposal.epoch == epoch,
                  target.pair?.retirementID == closure.retirementID,
                  target.pair?.closureSHA256 == SharedMediaNativePairClosure.digest(Data(try closure.encoded().utf8)),
                  pair.work.allSatisfy({ $0.retirementID == closure.retirementID }),
                  state.remaining.remove(workID) != nil else { throw SharedMediaStorageFailure.closed }
            // Consume even on thrown unlink/fsync/fault. Repeating physical work
            // requires another complete audited invocation after termination.
            return try body()
        }
    }
}

/// The complete clean retiring graph, raw row identities and exact saved closure
/// authorize one selected pair only. No constructor accepts a bare Progress.
@MainActor
// The full domain name distinguishes this state or capability from adjacent storage boundaries.
// swiftlint:disable:next type_name
final class SharedMediaNativeReleasePairRemovalCapability {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Snapshot = SharedMediaNativeReleaseMetadataSnapshot.Snapshot
    let before: Values.Progress, after: Values.Progress
    let state: SharedMediaNativePairFileState
    let closure: SharedMediaNativePairClosure
    let successor: SharedMediaNativeReceivingReleaseState.Expected
    let seal: SharedMediaNativeReleasePairRemovalPoststate
    let snapshot: Snapshot
    let binding: SharedMediaNativeBinding
    let permit: SharedMediaNativePairUnlinkPermit
    private let container: ModelContainer
    private let authority: SharedMediaNativeAppOperationAuthority
    private let header: SharedMediaNativeAppEligibility.Header

    private init(snapshot: Snapshot, context: ModelContext, container: ModelContainer,
                 authority: SharedMediaNativeAppOperationAuthority, binding: SharedMediaNativeBinding,
                 header: SharedMediaNativeAppEligibility.Header) throws {
        let before = snapshot.release.progress
        let target = before.targets[try before.selectedIndex(.retiringPair)]
        guard let state = snapshot.pairs.first(where: { (try? $0.intent().pairID) == target.pairID }),
              state.phase == "retiring", let raw = state.work.first?.closure else { throw SharedMediaStorageFailure.closed }
        let closure = try SharedMediaNativePairClosure.decode(raw)
        _ = try SharedMediaNativeReleasePairHistory.validate(closure, progress: before,
            prepared: snapshot.release.origin.prepared, received: snapshot.release.origin.received,
            inventoryRevision: snapshot.inventoryRevision)
        let after = try before.advancing(.init(pairID: target.pairID, stage: .pairGoneOriginalLive, pair: target.pair, original: nil))
        let next = try SharedMediaNativeReceivingReleaseState.expected(after,
            prepared: snapshot.release.origin.prepared, received: snapshot.release.origin.received)
        self.before = before; self.after = after; self.state = state; self.closure = closure; successor = next
        self.snapshot = snapshot; self.binding = binding; self.container = container; self.authority = authority; self.header = header
        seal = try .init(state: state, before: before, after: after, successor: next, context: context)
        permit = .init(progress: before, closure: closure, state: state, binding: binding)
    }
    static func audited(_ progress: Values.Progress, context: ModelContext, container: ModelContainer,
                        authority: SharedMediaNativeAppOperationAuthority, binding: SharedMediaNativeBinding,
                        header: SharedMediaNativeAppEligibility.Header) throws -> Self {
        guard try authority.header(container) == header, progress.plan.profile == authority.profile else { throw SharedMediaStorageFailure.stale }
        let id = authority.profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        guard case .releasing(let snapshot) = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)[progress.plan.package.id],
              snapshot.release.progress == progress, snapshot.inventoryRevision == header.inventory.revision else { throw SharedMediaStorageFailure.stale }
        let capability = try Self(snapshot: snapshot, context: context, container: container, authority: authority, binding: binding, header: header)
        try capability.validate()
        return capability
    }
    func validate() throws {
        guard try authority.header(container) == header else { throw SharedMediaStorageFailure.stale }
    }
    func requireSame(_ other: SharedMediaNativeReleasePairRemovalCapability) throws {
        guard before == other.before, after == other.after, state == other.state,
              closure == other.closure, binding.bytes == other.binding.bytes, binding.epoch == other.binding.epoch,
              snapshot.release.slot == other.snapshot.release.slot,
              snapshot.pairs == other.snapshot.pairs, snapshot.ownedOriginals == other.snapshot.ownedOriginals,
              snapshot.targetOrigins == other.snapshot.targetOrigins else { throw SharedMediaStorageFailure.stale }
    }
    func activate(_ proofs: [SharedMediaNativeRetiringPairInspection], verify: (SharedMediaNativeRetiringPairInspection) throws -> Void) throws {
        try validate()
        guard proofs.count == 2, Set(proofs.map(\.workID)) == Set(state.work.map(\.id)) else { throw SharedMediaStorageFailure.conflict }
        for proof in proofs { try requireInspection(proof); try verify(proof) }
        try permit.activate()
    }
    /// Called by the existing fileprivate disposal constructor adapter.
    func requireDisposal() throws { try validate(); try permit.requireActive() }
    func requireInspection(_ proof: SharedMediaNativeRetiringPairInspection) throws {
        guard proof.state == state, proof.binding == binding.bytes, proof.epoch == binding.epoch,
              let entry = closure.entries.first(where: { $0.work.id == proof.workID }),
              proof.identity.parent == entry.identity.parent, proof.identity.namespace == entry.identity.namespace,
              proof.identity.partial == "absent" || proof.identity.partial == entry.identity.partial,
              proof.identity.final == "absent" || proof.identity.final == entry.identity.final else {
            throw SharedMediaStorageFailure.conflict
        }
    }
}
