import Foundation

@MainActor
// The full domain name distinguishes this state or capability from adjacent storage boundaries.
// swiftlint:disable:next type_name
enum SharedMediaNativeReleasePairRemovalFunding {
    typealias Projection = SharedMediaNativeReleaseSurvivorProjection
    static func check(_ value: SharedMediaNativeReleasePairRemovalCapability) throws {
        let snapshot = value.snapshot, next = value.successor, current = Projection.components(snapshot)
        let funded = try Projection.maximum(snapshot)
        try funded.requireMetadataCapacity()
        let pairs = try snapshot.pairs.filter { $0 != value.state }.map { existing in
            let p = existing.plan
            let plan = SharedMediaNativePairPlan(intent: p.intent, writerEpoch: p.writerEpoch,
                inventoryID: p.inventoryID, inventoryGeneration: p.inventoryGeneration,
                inventoryRevision: try SharedMediaStoragePolicy.add(p.inventoryRevision, 1), packageID: p.packageID,
                draftGeneration: p.draftGeneration, packageRevision: next.package.revision, envelope: p.envelope,
                membershipRevision: next.member.revision, membership: next.member.bytes)
            return SharedMediaNativePairFileState(plan: plan, phase: existing.phase, publishedRevision: existing.publishedRevision,
                allocatedBytes: next.package.allocated, work: existing.work)
        }
        let after = Projection.Components(progress: value.after, prepared: current.prepared, received: current.received,
            package: next.package, member: next.member, envelopeBytes: current.envelopeBytes,
            membershipBytes: Int64(next.member.bytes.count), consumerBytes: current.consumerBytes,
            executionBytes: current.executionBytes, slotBytes: Int64(try value.after.encoded().count),
            pairs: pairs, ownedOriginals: current.ownedOriginals, targetOrigins: current.targetOrigins)
        let projection = try Projection.maximum(after)
        try projection.requireMetadataCapacity()
        let intent = try value.state.intent()
        let removed = try PhotoPreparationPolicy.add([intent.ai.byteCount, intent.display.byteCount])
        guard projection.maximumIdentityExcludedBytes <= funded.maximumIdentityExcludedBytes,
              snapshot.release.state.package.allocated >= removed,
              next.package.allocated == snapshot.release.state.package.allocated - removed,
              next.package.phase == snapshot.release.state.package.phase,
              next.package.envelope == snapshot.release.state.package.envelope else { throw SharedMediaStorageFailure.capacity }
    }
}
