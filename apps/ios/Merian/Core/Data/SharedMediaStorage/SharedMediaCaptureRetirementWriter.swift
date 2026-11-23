import Foundation
import SwiftData

/// Shared physical bookkeeping; each version keeps its separate authority check.
@MainActor
enum SharedMediaCaptureRetirementWriter {
    typealias Boundary = SharedMediaCaptureSourceDiscard.Boundary

    static func persist(_ prior: SharedMediaCaptureArtifactLedger.Snapshot,
                        retirement: SharedMediaCaptureArtifactRetirement, container: ModelContainer,
                        authority: SharedMediaNativeAppOperationAuthority, boundary: Boundary) throws {
        let before = try authority.header(container)
        try requireParentless(prior.request, container: container)
        let context = ModelContext(container); context.autosaveEnabled = false
        if retirement.version == 2 {
            try SharedMediaCapturePreparedAttempt.requireAbortMember(prior.request,
                digest: retirement.preparationSHA256, context: context)
        } else {
            let input = try SharedMediaCaptureDraftSourceInput(retained: prior.request)
            try SharedMediaCaptureDraftJournalReceipt.requireSource(input, states: [.discarding, .released],
                phases: [.editing, .discarding, .released], context: context)
        }
        let request = prior.request, id = request.id, inventoryID = request.profile.inventoryID
        guard try SharedMediaCaptureArtifactLedger.auditRead(id: id, profile: authority.profile,
            rootBindingSHA256: request.rootBindingSHA256, context: context) == prior else { throw SharedMediaStorageFailure.stale }
        let row = try one(context, FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.id == id }))
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let allocationID = request.allocationID, leaseID = request.leaseID, referenceID = request.referenceID
        let allocation = try one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == allocationID }))
        let lease = try one(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == leaseID }))
        let reference = try one(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID }))
        let released = retirement.releasedRevision != nil
        guard released == (prior.retirement != nil),
              (retirement.releasedRevision ?? retirement.inventoryRevision) == (try SharedMediaStoragePolicy.add(inventory.revision, 1)) else {
            throw SharedMediaStorageFailure.conflict
        }
        row.retirementData = try retirement.encoded(request: request, stage: prior.stage)
        row.retirementSHA256 = SharedMediaAcquisitionEncoding.digest(try retirement.encoded(request: request, stage: prior.stage))
        row.phaseRaw = released ? "released" : "retiring"
        row.revision = try SharedMediaStoragePolicy.add(row.revision, 1)
        allocation.stateRaw = row.phaseRaw
        if released { allocation.materializedBytes = 0; allocation.reservedBytes = 0; allocation.physicalIdentity = nil }
        lease.stateRaw = "closed"
        reference.stateRaw = released ? "released" : "held"
        reference.revision = released ? 1 : 0
        inventory.revision = retirement.releasedRevision ?? retirement.inventoryRevision
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        try boundary(released ? .beforeReleaseSave : .beforeIntentSave)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        // If save throws, no unlink is attempted. Retry must read the exact
        // durable intent rather than infer that an ambiguous save was absent.
        try context.save()
        try boundary(released ? .afterReleaseSave : .afterIntentSave)
        _ = try authority.header(container)
    }

    private static func requireParentless(_ request: SharedMediaCaptureArtifactRequest, container: ModelContainer) throws {
        let context = ModelContext(container); context.autosaveEnabled = false
        guard try SharedMediaCaptureSubmissionReceipt.matching(scanID: request.scanID,
            generation: request.submissionGeneration, in: context) == nil else { throw SharedMediaStorageFailure.closed }
        try SharedMediaCaptureDraftSourceBinding.requireUnclaimed(scan: request.scanID, context: context)
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        return row
    }
}
