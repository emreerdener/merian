import Foundation
import SwiftData

/// Accepted queue membership, checked only inside the registered owner's full
/// capture file/ledger audit. This value check alone grants no file or network
/// access. Reserved drafts and standalone artifact fixtures cannot qualify.
@MainActor
enum SharedMediaCaptureDispatchQualification {
    static func verify(container: ModelContainer, profile: SharedMediaNativeAppProfile,
                       rootBindingSHA256: String, checkpoint: () throws -> Void) throws {
        let pending = try pendingGenerations(container: container, profile: profile,
            rootBindingSHA256: rootBindingSHA256, checkpoint: checkpoint)
        guard pending.isEmpty else { throw SharedMediaStorageFailure.closed }
    }

    /// Reserved parents may recover their exact immutable submission, but they
    /// do not publish queue, upload, ordinary-file, or release authority.
    static func pendingGenerations(container: ModelContainer, profile: SharedMediaNativeAppProfile,
                                   rootBindingSHA256: String, checkpoint: () throws -> Void) throws -> Set<UUID> {
        let context = ModelContext(container); context.autosaveEnabled = false
        var query = FetchDescriptor<SharedMediaOrdinarySubmissionRecord>(sortBy: [SortDescriptor(\.cursorKey)])
        query.fetchLimit = SharedMediaStoragePolicy.pageSize
        var offset = 0, parents: Int64 = 0, children: Int64 = 0, accepted: Int64 = 0
        var pending: Set<UUID> = []
        while true {
            try checkpoint(); query.fetchOffset = offset
            let rows = try context.fetch(query)
            for row in rows where row.formatRaw == SharedMediaCaptureSubmission.Format.v1.rawValue {
                try checkpoint()
                let saved = try SharedMediaCaptureSubmissionReceipt.auditRead(row, in: context)
                guard saved.submission.profile == profile,
                      saved.submission.rootBindingSHA256 == rootBindingSHA256 else { throw SharedMediaStorageFailure.closed }
                switch saved.state {
                case .accepted:
                    try SharedMediaCaptureQueueIdentity.require(saved.submission, in: context)
                    accepted = try SharedMediaStoragePolicy.add(accepted, 1)
                case .reserved:
                    try SharedMediaCaptureQueueIdentity.requireAbsent(saved.submission, in: context)
                    guard pending.insert(saved.submission.generation).inserted else { throw SharedMediaStorageFailure.conflict }
                }
                parents = try SharedMediaStoragePolicy.add(parents, 1)
                children = try SharedMediaStoragePolicy.add(children, Int64(saved.artifacts.count))
            }
            if rows.count < SharedMediaStoragePolicy.pageSize { break }
            let (next, overflow) = offset.addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
        }
        let sources = try SharedMediaCaptureDraftSourceRecovery.unboundInventory(context: context,
            profile: profile, rootBindingSHA256: rootBindingSHA256, checkpoint: checkpoint)
        pending.formUnion(sources.generations)
        let journals = try SharedMediaCaptureDraftJournalReceipt.inventory(context: context, profile: profile,
            rootBindingSHA256: rootBindingSHA256, checkpoint: checkpoint)
        pending.formUnion(journals.pending)
        let raw = SharedMediaCaptureAcceptance.mediaAuthority
        guard parents > 0 || sources.artifactCount > 0 || journals.entryCount > 0,
              try SharedMediaStoragePolicy.add(children, sources.artifactCount) == Int64(context.fetchCount(FetchDescriptor<SharedMediaOrdinaryArtifactRecord>())),
              accepted == Int64(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.mediaAuthorityRaw == raw }))) else {
            throw SharedMediaStorageFailure.closed
        }
        try checkpoint()
        return pending
    }
}

/// Stable queue ownership survives attempt counters and retry scheduling. The
/// immutable plan/context remain on the submission receipt, never reconstructed
/// from mutable queue metadata or from a prepared thumbnail.
@MainActor
enum SharedMediaCaptureQueueIdentity {
    static func require(_ submission: SharedMediaCaptureSubmission, in context: ModelContext) throws {
        guard !context.hasChanges, !context.container.mainContext.hasChanges else { throw SharedMediaStorageFailure.closed }
        let lower = submission.scanID.uuidString.lowercased(), upper = submission.scanID.uuidString
        let plan = try submission.plan()
        let expectedBytes = try plan.uploads.reduce(Int64(0)) { try SharedMediaStoragePolicy.add($0, Int64($1.artifact.byteCount)) }
        let jobID = submission.jobID, upperJobID = OfflineQueueManager.scanIngestionJobId(scanId: upper)
        let queue = try one(context, FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == lower || $0.id == upper }))
        // Enrollment and later analysis jobs may share the observation subject.
        // Only the original ingestion job owns the immutable capture proof.
        let ingestionKind = OfflineJobKind.scanIngestion.rawValue
        let job = try one(context, FetchDescriptor<OfflineJobRecord>(predicate: #Predicate {
            $0.id == jobID || $0.id == upperJobID || (($0.subjectId == lower || $0.subjectId == upper) && $0.kindRaw == ingestionKind)
        }))
        guard queue.id == lower, queue.mediaAuthorityRaw == SharedMediaCaptureAcceptance.mediaAuthority,
              queue.sharedMediaConsumerID == nil, queue.workKindRaw == "ordinary",
              queue.parentObservationID == nil, queue.sourceAnalysisID == nil, queue.reanalysisOwnerAccountID == nil,
              queue.capturedMediaJSON == nil, queue.inferenceImagePaths == nil,
              queue.visualMediaItemsJSON == nil, queue.stagedR2Keys == nil, queue.coverImagePath == nil,
              job.id == jobID, job.kind == .scanIngestion, job.subjectId == lower, job.approximateBytes == expectedBytes,
              job.status != .cancelled, let raw = job.metadataJSON,
              raw.utf8.count <= OrdinaryInferenceCompletion.maximumBytes else { throw SharedMediaStorageFailure.conflict }
        let object = try JSONSerialization.jsonObject(with: Data(raw.utf8))
        guard let fields = object as? [String: Any],
              try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) == Data(raw.utf8),
              try OrdinaryInitialSubmissionIdentity.read(fields[OrdinaryInitialEvidenceProof.expectationKey])
                == OrdinaryInitialSubmissionIdentity(ownerID: submission.profile.ownerID, scanID: submission.scanID, generation: submission.generation),
              try SharedMediaCaptureFundingResolution.funding(raw, submission: submission).accountId
                == submission.profile.ownerID else { throw SharedMediaStorageFailure.conflict }
        try SharedMediaCaptureFundingResolution.requireOperationalCustody(raw, submission: submission)
        var deletions = FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == lower || $0.scanId == upper })
        deletions.fetchLimit = 1
        guard try context.fetch(deletions).isEmpty else { throw SharedMediaStorageFailure.closed }
    }

    static func requireAbsent(_ submission: SharedMediaCaptureSubmission, in context: ModelContext) throws {
        guard !context.hasChanges, !context.container.mainContext.hasChanges else { throw SharedMediaStorageFailure.closed }
        let lower = submission.scanID.uuidString.lowercased(), upper = submission.scanID.uuidString
        let job = submission.jobID, upperJob = OfflineQueueManager.scanIngestionJobId(scanId: upper)
        try absent(context, FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == lower || $0.id == upper }))
        try absent(context, FetchDescriptor<OfflineJobRecord>(predicate: #Predicate {
            $0.id == job || $0.id == upperJob || $0.subjectId == lower || $0.subjectId == upper
        }))
        try absent(context, FetchDescriptor<OfflineQueueEvent>(predicate: #Predicate {
            $0.scanId == lower || $0.scanId == upper || $0.jobId == job || $0.jobId == upperJob
        }))
        try absent(context, FetchDescriptor<ActiveOfflineQueuedScanGoalHint>(predicate: #Predicate { $0.scanId == lower || $0.scanId == upper }))
        try absent(context, FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper }))
        try absent(context, FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.observationID == lower || $0.observationID == upper }))
        try absent(context, FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == lower || $0.scanId == upper }))
    }

    private static func absent<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws {
        var query = descriptor; query.fetchLimit = 1
        guard try context.fetch(query).isEmpty else { throw SharedMediaStorageFailure.conflict }
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        return row
    }
}
