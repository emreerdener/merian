import Foundation

/// Frozen physical observations for one owner-local save attempt. Repeating a
/// pre-save rejection may revalidate these proofs, but never replace them.
@MainActor
final class SharedMediaNativeReleasePairAttempt {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    let before: Values.Progress, after: Values.Progress
    let row: SharedMediaNativeReceivingIntentGraph.Row
    let state: SharedMediaNativePairFileState
    let closure: SharedMediaNativePairClosure
    let proofs: [SharedMediaNativePairInspection]
    let successor: SharedMediaNativeReceivingReleaseState.Expected

    init(snapshot: SharedMediaNativeReleaseMetadataSnapshot.Snapshot,
         proofs: [SharedMediaNativePairInspection], binding: SharedMediaNativeBinding) throws {
        let progress = snapshot.release.progress
        guard progress == (try Values.Progress(plan: progress.plan)), let target = progress.targets.first,
              let state = snapshot.pairs.first(where: { (try? $0.intent().pairID) == target.pairID }),
              state.phase == "ready", proofs.count == 2,
              Set(proofs.map(\.workID)) == Set(state.work.map(\.id)) else { throw SharedMediaStorageFailure.closed }
        let cohort = try SharedMediaNativeFrozenCohort.decode(snapshot.release.origin.prepared.cohort.bytes)
        guard let entry = cohort.entries.first(where: { $0.intent == state.plan.intent }) else { throw SharedMediaStorageFailure.conflict }
        let entries = try zip(state.work, [entry.aiDescriptor, entry.displayDescriptor]).map { work, descriptor in
            guard let proof = proofs.first(where: { $0.workID == work.id }), proof.state == state,
                  proof.binding == binding.bytes, proof.epoch == binding.epoch,
                  proof.identity.partial == "absent",
                  proof.identity.final == "absent" || proof.identity.final == descriptor.file,
                  proof.identity.parent == descriptor.parent, proof.identity.namespace == descriptor.namespace,
                  work.finalIdentity == descriptor.file, work.phase == "completed", work.writerState == "closed" else {
                throw SharedMediaStorageFailure.conflict
            }
            return SharedMediaNativePairClosure.Entry(work: work, mode: .bound, identity: proof.identity)
        }
        let membership = try SharedMediaNativePairClosure.retirementMembership(state)
        let closure = SharedMediaNativePairClosure(version: 1, retirementID: UUID(), pairID: target.pairID,
            inventoryID: progress.plan.profile.inventoryID, inventoryGeneration: progress.plan.profile.generation,
            packageID: progress.plan.package.id, draftGeneration: progress.plan.package.generation,
            writerEpoch: state.plan.writerEpoch,
            beforeHash: SharedMediaNativePairClosure.digest(try SharedMediaNativeDraftEnvelope.bytes(state)),
            intentHash: SharedMediaNativePairClosure.digest(state.plan.intent.bytes),
            envelopeHash: SharedMediaNativePairClosure.digest(state.plan.envelope),
            afterMembershipHash: SharedMediaNativePairClosure.digest(membership),
            afterMembershipRevision: try SharedMediaStoragePolicy.add(state.plan.membershipRevision, 1),
            previous: .init(inventoryRevision: state.plan.inventoryRevision, packageRevision: state.plan.packageRevision,
                membershipRevision: state.plan.membershipRevision, membership: state.plan.membership, phase: state.phase,
                publishedRevision: state.publishedRevision, allocatedBytes: state.allocatedBytes), entries: entries)
        let after = try progress.advancing(.init(pairID: target.pairID, stage: .retiringPair,
            pair: .init(retirementID: closure.retirementID,
                closureSHA256: SharedMediaNativePairClosure.digest(Data(try closure.encoded().utf8))), original: nil))
        let successor = try SharedMediaNativeReceivingReleaseState.expected(after,
            prepared: snapshot.release.origin.prepared, received: snapshot.release.origin.received)
        guard successor.member.bytes == membership,
              try SharedMediaNativeReleasePairHistory.validate(closure, progress: after,
                prepared: snapshot.release.origin.prepared, received: snapshot.release.origin.received,
                inventoryRevision: SharedMediaStoragePolicy.add(snapshot.inventoryRevision, 1)) == state else {
            throw SharedMediaStorageFailure.conflict
        }
        before = progress; self.after = after; row = snapshot.release.slot; self.state = state
        self.closure = closure; self.proofs = proofs; self.successor = successor
    }
}
