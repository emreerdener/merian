import Foundation
import SwiftData

@MainActor
enum SharedMediaCaptureReleasePersistence {
    static func member(_ prior: SharedMediaCaptureArtifactLedger.Snapshot, release: SharedMediaCaptureMemberRelease,
                       parent: SharedMediaCaptureSubmissionReceipt.Snapshot, container: ModelContainer,
                       authority: SharedMediaNativeAppOperationAuthority, files: SharedMediaCaptureArtifactFiles,
                       boundary: SharedMediaCaptureAcceptedReleaseWriter.Boundary) throws {
        let before = try authority.header(container), context = ModelContext(container); context.autosaveEnabled = false
        guard let intent = parent.release, intent.releasedRevision == nil,
              try SharedMediaCaptureAcceptedReleaseWriter.current(scanID: parent.submission.scanID,
                generation: parent.submission.generation, container: container, authority: authority, files: files) == parent,
              parent.artifacts.contains(prior), release.parentIntentSHA256 == (try intent.intentSHA256),
              intent.members.contains(release.member), release.inventoryRevision > intent.inventoryRevision,
              let stage = prior.stage, let remote = prior.remoteStage else { throw SharedMediaStorageFailure.stale }
        let released = release.releasedRevision != nil, revision = release.releasedRevision ?? release.inventoryRevision
        guard released == (prior.acceptedRelease != nil), revision == (try SharedMediaStoragePolicy.add(before.inventory.revision, 1)) else {
            throw SharedMediaStorageFailure.conflict
        }
        if let old = prior.acceptedRelease {
            var expected = old; expected.releasedRevision = release.releasedRevision
            guard old.releasedRevision == nil, expected == release else { throw SharedMediaStorageFailure.conflict }
        }
        var physical = prior; physical.acceptedRelease = release
        _ = try files.inspect(physical)
        let request = prior.request, id = request.id, inventoryID = request.profile.inventoryID
        let row = try one(context, FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.id == id }))
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let allocationID = request.allocationID, leaseID = request.leaseID, referenceID = request.referenceID
        let allocation = try one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == allocationID }))
        let lease = try one(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == leaseID }))
        let reference = try one(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID }))
        row.retirementData = try release.encoded(request: request, stage: stage, remote: remote)
        row.retirementSHA256 = row.retirementData.map(SharedMediaAcquisitionEncoding.digest)
        row.phaseRaw = released ? "acceptedReleased" : "acceptedRetiring"
        row.revision = try SharedMediaStoragePolicy.add(row.revision, 1)
        allocation.stateRaw = released ? "released" : "retiring"
        if released { allocation.materializedBytes = 0; allocation.reservedBytes = 0; allocation.physicalIdentity = nil }
        lease.stateRaw = "closed"; reference.stateRaw = released ? "released" : "held"; reference.revision = released ? 1 : 0
        inventory.revision = revision
        try boundary(released ? .beforeMemberReleaseSave : .beforeMemberIntentSave)
        try files.check()
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        try context.save()
        try boundary(released ? .afterMemberReleaseSave : .afterMemberIntentSave)
        _ = try authority.header(container); try files.check()
    }

    static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        return row
    }
}
