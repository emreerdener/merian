import Foundation

@MainActor
enum SharedMediaNativeOriginalRemovalFunding {
    typealias Projection = SharedMediaNativeReleaseSurvivorProjection
    typealias Liability = SharedMediaNativeOriginalLiability
    static func check(_ a: SharedMediaNativeOriginalRemovalCapability) throws {
        let before = try Projection.maximum(a.snapshot), after = try projection(a)
        try before.requireMetadataCapacity(); try after.requireMetadataCapacity()
        let predicted = try liability(a)
        guard after.maximumIdentityExcludedBytes <= before.maximumIdentityExcludedBytes,
              try PhotoPreparationPolicy.add([predicted.currentBytes, predicted.reservedBytes]) <=
                  PhotoPreparationPolicy.add([a.liability.currentBytes, a.liability.reservedBytes]),
              a.successor.package.envelope == a.snapshot.release.state.package.envelope,
              a.successor.package.phase == a.snapshot.release.state.package.phase else { throw SharedMediaStorageFailure.capacity }
    }
    static func projection(_ a: SharedMediaNativeOriginalRemovalCapability) throws -> Projection.Projection {
        let current = Projection.components(a.snapshot), next = a.successor
        let pairs = try current.pairs.map { existing in
            let p = existing.plan
            return SharedMediaNativePairFileState(plan: .init(intent: p.intent, writerEpoch: p.writerEpoch,
                inventoryID: p.inventoryID, inventoryGeneration: p.inventoryGeneration,
                inventoryRevision: try SharedMediaStoragePolicy.add(p.inventoryRevision, 1), packageID: p.packageID,
                draftGeneration: p.draftGeneration, packageRevision: next.package.revision, envelope: p.envelope,
                membershipRevision: next.member.revision, membership: next.member.bytes),
                phase: existing.phase, publishedRevision: existing.publishedRevision, allocatedBytes: next.package.allocated, work: existing.work)
        }
        return try Projection.maximum(.init(progress: a.after, prepared: current.prepared, received: current.received,
            package: next.package, member: next.member, envelopeBytes: current.envelopeBytes,
            membershipBytes: Int64(next.member.bytes.count), consumerBytes: current.consumerBytes,
            executionBytes: current.executionBytes, slotBytes: Int64(try a.after.encoded().count), pairs: pairs,
            ownedOriginals: current.ownedOriginals.filter { $0.assetID != a.original.assetID },
            targetOrigins: current.targetOrigins.map { old in
                old.assetID == a.original.assetID
                    ? .init(assetID: old.assetID, acquisitionID: old.acquisitionID, location: .released(a.terminal)) : old
            }))
    }
    static func liability(_ a: SharedMediaNativeOriginalRemovalCapability) throws -> Liability.Snapshot {
        var entries = a.liability.entries
        guard let old = entries.removeValue(forKey: a.original.assetID), old.retiring,
              !a.liability.retainedTargets.contains(a.original.assetID) else { throw SharedMediaStorageFailure.conflict }
        return .init(inventoryID: a.liability.inventoryID, generation: a.liability.generation,
            revision: try SharedMediaStoragePolicy.add(a.liability.revision, 1), entries: entries, retainedTargets: a.liability.retainedTargets)
    }
}
