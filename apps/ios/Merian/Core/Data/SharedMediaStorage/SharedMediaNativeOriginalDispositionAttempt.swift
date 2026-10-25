import Foundation
import SwiftData

/// Minted only from a complete saved boundary under the registered owner's
/// locks. Historical acquisition identity grants no physical I/O authority.
@MainActor
final class SharedMediaNativeOriginalDispositionAttempt {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Snapshot = SharedMediaNativeReleaseMetadataSnapshot.Snapshot
    let before: Values.Progress, after: Values.Progress
    let snapshot: Snapshot
    let original: SharedMediaNativeOriginalAccounting.Snapshot
    let retirement: SharedMediaNativeRetirementIdentity?
    let successor: SharedMediaNativeReceivingReleaseState.Expected
    let seal: SharedMediaNativeOriginalDispositionPoststate
    let referenceDigest: String
    let survivingReferenceDigest: String
    private(set) var expectedLiability: SharedMediaNativeOriginalLiability.Snapshot?
    let liability: SharedMediaNativeOriginalLiability.Snapshot
    let header: SharedMediaNativeAppEligibility.Header

    private init(snapshot: Snapshot, original: SharedMediaNativeOriginalAccounting.Snapshot,
                 retirement: SharedMediaNativeRetirementIdentity?, header: SharedMediaNativeAppEligibility.Header,
                 context: ModelContext) throws {
        let before = snapshot.release.progress
        let index = try before.selectedIndex(.pairGoneOriginalLive), first = before.targets[index]
        guard original.retirement == nil, original.liveCount > 0,
              (retirement != nil) == (original.liveCount == 1) else { throw SharedMediaStorageFailure.closed }
        func progress(_ digest: String) throws -> Values.Progress {
            try before.advancing(.init(pairID: first.pairID, stage: retirement == nil ? .removed : .originalRetiring,
                pair: first.pair, original: .init(disposition: retirement == nil ? .shared : .removed,
                    retirementID: retirement?.retirementID, closureSHA256: digest)))
        }
        // Expected membership/revisions do not depend on the attestation itself.
        let sizing = try progress(String(repeating: "0", count: 64))
        let next = try SharedMediaNativeReceivingReleaseState.expected(sizing,
            prepared: snapshot.release.origin.prepared, received: snapshot.release.origin.received)
        let digest: String
        if let retirement { digest = try SharedMediaAcquisitionEncoding.digest(Data(retirement.encoded().utf8)) }
        else { digest = try SharedMediaNativeOriginalDispositionAttestation.digest(before: before, next: next, header: header, context: context) }
        let after = try progress(digest)
        self.before = before; self.after = after; self.snapshot = snapshot; self.original = original
        self.retirement = retirement; self.header = header; successor = next
        referenceDigest = try SharedMediaNativeOriginalDispositionAttestation.referenceDigest(assetID: original.assetID, context: context)
        survivingReferenceDigest = try SharedMediaNativeOriginalDispositionAttestation.referenceDigest(assetID: original.assetID,
            excludingID: before.plan.targets[index].original.referenceID, context: context)
        liability = try SharedMediaNativeOriginalLiability.read(context: context, inventoryID: before.plan.profile.inventoryID)
        seal = try .init(before: before, after: after, successor: next, original: original, retirement: retirement, context: context)
        expectedLiability = try SharedMediaNativeOriginalDispositionFunding.liability(self, context: context)
        try SharedMediaNativeOriginalDispositionFunding.check(self, context: context)
    }
    static func audited(_ before: Values.Progress, retirementID: UUID, header: SharedMediaNativeAppEligibility.Header,
                        context: ModelContext) throws -> SharedMediaNativeOriginalDispositionAttempt {
        let snapshot = try SharedMediaNativeOriginalDispositionRecovery.snapshot(before, context: context, header: header)
        let target = before.plan.targets[try before.selectedIndex(.pairGoneOriginalLive)]
        guard snapshot.release.progress == before else { throw SharedMediaStorageFailure.closed }
        let original = try SharedMediaNativeOriginalAccounting.audit(assetID: target.original.assetID,
            inventoryID: before.plan.profile.inventoryID, context: context)
        let rows = try SharedMediaNativeAppOriginalRows(context, profile: before.plan.profile, source: target.original)
        _ = try SharedMediaNativeAppOriginalRows.reference(context, source: target.original, live: true)
        try SharedMediaNativeAppOriginalRows.noPair(context, source: target.original)
        let assetID = target.original.assetID, packageID = before.plan.package.id
        guard try context.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate {
            $0.assetID == assetID && $0.packageID == packageID
        })) == 1, original.liveCount > 0, original.retirement == nil,
              original.inventoryRevision == header.inventory.revision else { throw SharedMediaStorageFailure.conflict }
        let retirement: SharedMediaNativeRetirementIdentity?
        if original.liveCount == 1 {
            try SharedMediaNativeReleaseStageIdentity.requireFresh([retirementID], inventoryID: before.plan.profile.inventoryID, context: context)
            retirement = try .init(retirementID: retirementID, assetID: assetID, assetGeneration: original.assetGeneration,
                inventoryID: original.inventoryID, inventoryGeneration: original.inventoryGeneration,
                ownerID: original.ownerID, proof: rows.completed().1.descriptor)
        } else { retirement = nil }
        return try .init(snapshot: snapshot, original: original, retirement: retirement, header: header, context: context)
    }
    func requirePredecessor(_ context: ModelContext, header: SharedMediaNativeAppEligibility.Header) throws {
        guard header == self.header,
              try SharedMediaNativeOriginalDispositionRecovery.snapshot(before, context: context, header: header).release.progress == before,
              try SharedMediaNativeOriginalAccounting.audit(assetID: original.assetID, inventoryID: original.inventoryID, context: context) == original,
              try SharedMediaNativeOriginalDispositionAttestation.referenceDigest(assetID: original.assetID, context: context) == referenceDigest,
              try SharedMediaNativeOriginalLiability.read(context: context, inventoryID: original.inventoryID) == liability else {
            throw SharedMediaStorageFailure.stale
        }
        try seal.requirePredecessor(context)
        if let retirement { try SharedMediaNativeReleaseStageIdentity.requireFresh([retirement.retirementID], inventoryID: original.inventoryID, context: context) }
        try SharedMediaNativeOriginalDispositionFunding.check(self, context: context)
    }
}
