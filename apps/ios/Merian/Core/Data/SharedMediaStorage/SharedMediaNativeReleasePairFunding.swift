import Foundation

/// Pure prospective sizing from the audited predecessor and frozen attempt.
/// Uses existing reserves; does not change a limit or release any allocation.
@MainActor
enum SharedMediaNativeReleasePairFunding {
    typealias Projection = SharedMediaNativeReleaseSurvivorProjection
    static func check(_ attempt: SharedMediaNativeReleasePairAttempt,
                      snapshot: SharedMediaNativeReleaseMetadataSnapshot.Snapshot, funded: Projection.Projection) throws {
        let before = attempt.state, next = attempt.successor, old = before.plan
        let plan = SharedMediaNativePairPlan(intent: old.intent, writerEpoch: old.writerEpoch,
            inventoryID: old.inventoryID, inventoryGeneration: old.inventoryGeneration,
            inventoryRevision: try SharedMediaStoragePolicy.add(old.inventoryRevision, 1), packageID: old.packageID,
            draftGeneration: old.draftGeneration, packageRevision: next.package.revision, envelope: next.package.envelope,
            membershipRevision: next.member.revision, membership: next.member.bytes)
        let intent = try before.intent(), closure = attempt.closure
        let pair = SharedMediaNativePairFileState(plan: plan, phase: "retiring", publishedRevision: nil,
            allocatedBytes: before.allocatedBytes, work: try closure.entries.map { entry in
                let work = entry.work
                return .init(id: work.id, writerEpoch: work.writerEpoch, phase: "retiring", writerState: "closed",
                    device: work.device, inode: work.inode, finalIdentity: work.finalIdentity, retirementID: closure.retirementID,
                    retirementPartial: entry.identity.partial, retirementFinal: entry.identity.final,
                    retirementParent: entry.identity.parent, retirementNamespace: entry.identity.namespace,
                    closure: work.id == intent.ai.id ? try closure.encoded() : try closure.siblingMarker())
            })
        // Every retained pair's descriptive plan contains the package-wide
        // header and membership, even when its own physical rows stay unchanged.
        let pairs = try snapshot.pairs.map { existing -> SharedMediaNativePairFileState in
            if existing == before { return pair }
            let p = existing.plan
            let updated = SharedMediaNativePairPlan(intent: p.intent, writerEpoch: p.writerEpoch,
                inventoryID: p.inventoryID, inventoryGeneration: p.inventoryGeneration,
                inventoryRevision: try SharedMediaStoragePolicy.add(p.inventoryRevision, 1), packageID: p.packageID,
                draftGeneration: p.draftGeneration, packageRevision: next.package.revision, envelope: p.envelope,
                membershipRevision: next.member.revision, membership: next.member.bytes)
            return .init(plan: updated, phase: existing.phase, publishedRevision: existing.publishedRevision,
                allocatedBytes: existing.allocatedBytes, work: existing.work)
        }
        let current = Projection.components(snapshot)
        let after = Projection.Components(progress: attempt.after, prepared: current.prepared, received: current.received,
            package: next.package, member: next.member, envelopeBytes: current.envelopeBytes,
            membershipBytes: Int64(next.member.bytes.count), consumerBytes: current.consumerBytes,
            executionBytes: current.executionBytes, slotBytes: Int64(try attempt.after.encoded().count),
            pairs: pairs, ownedOriginals: current.ownedOriginals,
            targetOrigins: current.targetOrigins)
        let projection = try Projection.maximum(after)
        try projection.requireMetadataCapacity()
        guard projection.maximumIdentityExcludedBytes <= funded.maximumIdentityExcludedBytes,
              next.package.allocated == snapshot.release.state.package.allocated,
              next.package.phase == snapshot.release.state.package.phase,
              next.package.envelope == snapshot.release.state.package.envelope else { throw SharedMediaStorageFailure.capacity }
    }
}
