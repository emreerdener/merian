import Foundation
import SwiftData

@MainActor
enum SharedMediaNativeOriginalDispositionFunding {
    typealias Projection = SharedMediaNativeReleaseSurvivorProjection
    typealias Liability = SharedMediaNativeOriginalLiability
    static func check(_ a: SharedMediaNativeOriginalDispositionAttempt, context: ModelContext) throws {
        let before = try Projection.maximum(a.snapshot), after = try projection(a)
        try before.requireMetadataCapacity(); try after.requireMetadataCapacity()
        let predicted = try liability(a, context: context)
        guard after.maximumIdentityExcludedBytes <= before.maximumIdentityExcludedBytes,
              try PhotoPreparationPolicy.add([predicted.currentBytes, predicted.reservedBytes]) <=
                  PhotoPreparationPolicy.add([a.liability.currentBytes, a.liability.reservedBytes]),
              a.successor.package.envelope == a.snapshot.release.state.package.envelope,
              a.successor.package.phase == a.snapshot.release.state.package.phase else { throw SharedMediaStorageFailure.capacity }
    }
    static func projection(_ a: SharedMediaNativeOriginalDispositionAttempt) throws -> Projection.Projection {
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
        let originals = try current.ownedOriginals.map { old in
            guard old.assetID == a.original.assetID, let retirement = a.retirement else { return old }
            return SharedMediaNativeReleaseMetadataSnapshot.Original(assetID: old.assetID, physicalOriginID: old.physicalOriginID,
                receiptBytes: old.receiptBytes, identityBytes: Int64(try retirement.encoded().utf8.count), retiring: true)
        }
        return try Projection.maximum(.init(progress: a.after, prepared: current.prepared, received: current.received,
            package: next.package, member: next.member, envelopeBytes: current.envelopeBytes,
            membershipBytes: Int64(next.member.bytes.count), consumerBytes: current.consumerBytes,
            executionBytes: current.executionBytes, slotBytes: Int64(try a.after.encoded().count), pairs: pairs,
            ownedOriginals: originals, targetOrigins: current.targetOrigins))
    }
    static func liability(_ a: SharedMediaNativeOriginalDispositionAttempt, context: ModelContext) throws -> Liability.Snapshot {
        var entries = a.liability.entries, retained = a.liability.retainedTargets
        let id = a.original.assetID
        guard let old = entries[id] else { throw SharedMediaStorageFailure.conflict }
        if let retirement = a.retirement {
            let bytes = Int64(try retirement.encoded().utf8.count)
            entries[id] = .init(assetID: id, acquisitionID: old.acquisitionID, physicalOriginID: old.physicalOriginID,
                currentBytes: bytes, reservedBytes: 512 - bytes, retiring: true)
        } else if old.physicalOriginID != a.before.plan.package.id {
            // Existing foreign-origin restriction: all surviving references must
            // already be fully retained nonqueue consumers, not merely counters.
            let excluded = a.before.plan.targets[0].original.referenceID
            try Liability.requireRetainedSurvivors(assetID: id, excludingID: excluded,
                expectedCount: a.original.liveCount - 1, context: context)
            entries.removeValue(forKey: id); retained.insert(id)
        }
        return .init(inventoryID: a.liability.inventoryID, generation: a.liability.generation,
            revision: try SharedMediaStoragePolicy.add(a.liability.revision, 1), entries: entries, retainedTargets: retained)
    }
}
