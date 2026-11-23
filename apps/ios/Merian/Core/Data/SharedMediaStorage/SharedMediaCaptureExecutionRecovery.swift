import Foundation
import SwiftData

/// Accepted Capture work only. Discovery grants no file or network authority;
/// the retained owner requalifies the exact observation before each operation.
/// The inference identity is fixed at acceptance and survives every retry.
@MainActor
enum SharedMediaCaptureExecutionRecovery {
    struct Candidate: Equatable, Sendable {
        let scanID: UUID
        let generation: UUID
        let status: OfflineJobStatus
        let attemptCount: Int
        let due: Date?
        var dispatch: SharedMediaCaptureExecutionIntent.Dispatch?
    }

    struct Page: Equatable, Sendable {
        let candidates: [Candidate]
        let nextCursor: String?
    }

    static let pageSize = 32

    static func page(after cursor: String?, container: ModelContainer,
                     authority: SharedMediaNativeAppOperationAuthority,
                     files: SharedMediaCaptureArtifactFiles) async throws -> Page {
        if let cursor { _ = try uuid(cursor) }
        let before = try authority.header(container)
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        try files.check()
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        let capture = SharedMediaCaptureAcceptance.mediaAuthority
        var query: FetchDescriptor<OfflineQueuedScan>
        if let cursor {
            query = FetchDescriptor(predicate: #Predicate { $0.mediaAuthorityRaw == capture && $0.id > cursor }, sortBy: [SortDescriptor(\.id)])
        } else {
            query = FetchDescriptor(predicate: #Predicate { $0.mediaAuthorityRaw == capture }, sortBy: [SortDescriptor(\.id)])
        }
        query.fetchLimit = pageSize + 1
        let rows = try context.fetch(query)
        var candidates: [Candidate] = []
        for row in rows.prefix(pageSize) {
            try Task.checkCancellation()
            let scanID = try uuid(row.id)
            let jobID = OfflineQueueManager.scanIngestionJobId(scanId: row.id)
            if let completed = try context.fetchOfflineJob(id: jobID), completed.status == .complete {
                guard let raw = completed.metadataJSON else { throw SharedMediaStorageFailure.conflict }
                let initial = try OrdinaryInferenceCompletion.retainedInitialIdentity(metadata: raw, scanID: scanID, owner: authority.profile.ownerID)
                let terminal = try SharedMediaCaptureCompletedCustody.read(scanID: scanID, generation: initial.generation,
                    ownerID: authority.profile.ownerID, context: context)
                guard terminal.submission.profile == authority.profile,
                      terminal.submission.rootBindingSHA256 == files.rootBindingSHA256 else { throw SharedMediaStorageFailure.conflict }
                continue
            }
            let saved = try retained(scanID: scanID, context: context, authority: authority, files: files)
            let job = try SharedMediaCaptureCompletionReadback.job(saved.submission, context: context)
            guard let status = OfflineJobStatus(rawValue: job.statusRaw) else { throw SharedMediaStorageFailure.conflict }
            switch status {
            case .complete, .needsAttention: continue
            case .cancelled: throw SharedMediaStorageFailure.conflict
            case .pending, .running, .waiting:
                try requireQueueState(row, job: job)
                candidates.append(try candidate(saved, job: job))
            }
        }
        try files.check()
        guard try authority.header(container) == before, !context.hasChanges else { throw SharedMediaStorageFailure.stale }
        return .init(candidates: candidates, nextCursor: rows.count > pageSize ? rows[pageSize - 1].id : nil)
    }

    /// Requalify the exact claimed job and all upload acknowledgements under
    /// the retained root. Discovery or an old in-memory plan is insufficient.
    static func ready(_ expected: Candidate, container: ModelContainer,
                      authority: SharedMediaNativeAppOperationAuthority,
                      files: SharedMediaCaptureArtifactFiles) async throws -> SharedMediaCaptureSubmissionReceipt.Snapshot {
        let saved = try await admitted(expected, container: container, authority: authority, files: files)
        guard expected.status == .running else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        guard let raw = try SharedMediaCaptureCompletionReadback.job(saved.submission, context: context).metadataJSON,
              try SharedMediaCaptureFundingResolution.funding(raw, submission: saved.submission).allowsDispatch else {
            throw SharedMediaStorageFailure.closed
        }
        _ = try SharedMediaCaptureUploadReadiness.require(saved)
        return saved
    }

    /// Funding qualification precedes upload. It proves the accepted target
    /// and exact queue attempt without requiring uploaded artifacts to exist.
    static func preparationFunding(_ expected: Candidate, container: ModelContainer,
                                   authority: SharedMediaNativeAppOperationAuthority,
                                   files: SharedMediaCaptureArtifactFiles) async throws -> ScanFundingReservation {
        let saved = try await admitted(expected, container: container, authority: authority, files: files)
        let context = ModelContext(container); context.autosaveEnabled = false
        guard let raw = try SharedMediaCaptureCompletionReadback.job(saved.submission, context: context).metadataJSON else {
            throw SharedMediaStorageFailure.conflict
        }
        return try SharedMediaCaptureFundingResolution.funding(raw, submission: saved.submission)
    }

    static func resolveFunding(_ expected: Candidate, decision: CaptureDeferredFundingDecision,
                               requireEvidence: () throws -> Void, container: ModelContainer,
                               authority: SharedMediaNativeAppOperationAuthority, files: SharedMediaCaptureArtifactFiles,
                               boundary: (SharedMediaCaptureReservationBoundary) throws -> Void = { _ in }) async throws -> Candidate {
        func qualifyEvidence() throws {
            try requireEvidence()
            let ids = Set(decision.original.blockerScanIds + [decision.original.scanId])
            let entries = try SharedMediaCaptureFundingQualification.entries(ids, normalizing: decision.original.scanId,
                container: container, authority: authority, files: files)
            guard entries.mapValues(\.proof) == decision.evidence.ownershipProofs else { throw SharedMediaStorageFailure.stale }
        }
        try qualifyEvidence()
        return try await update(expected, container: container, authority: authority, files: files, boundary: { point in
            try qualifyEvidence(); try boundary(point)
        }) { job in
            try qualifyEvidence()
            guard expected.dispatch == nil, let raw = job.metadataJSON else { throw SharedMediaStorageFailure.closed }
            let context = ModelContext(container); context.autosaveEnabled = false
            let saved = try retained(scanID: expected.scanID, context: context, authority: authority, files: files)
            guard try saved.submission.context.metadata(plan: saved.submission.plan()).funding == decision.original else {
                throw SharedMediaStorageFailure.conflict
            }
            let resolution = try SharedMediaCaptureFundingResolution(submission: saved.submission,
                effective: decision.effective, evidenceSHA256: decision.evidenceSHA256)
            job.metadataJSON = try resolution.retaining(in: raw, submission: saved.submission)
        }
    }

    private static func admitted(_ expected: Candidate, container: ModelContainer,
                                 authority: SharedMediaNativeAppOperationAuthority,
                                 files: SharedMediaCaptureArtifactFiles) async throws -> SharedMediaCaptureSubmissionReceipt.Snapshot {
        let before = try authority.header(container)
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        try files.check()
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        let saved = try retained(scanID: expected.scanID, context: context, authority: authority, files: files)
        let job = try SharedMediaCaptureCompletionReadback.job(saved.submission, context: context)
        try requireQueueState(try queue(saved.submission, context: context), job: job)
        guard try candidate(saved, job: job) == expected else {
            throw SharedMediaStorageFailure.stale
        }
        return saved
    }

    /// Persist the attempt before external work. A restart may retry a running
    /// job only through the one account-lifetime execution worker. No new
    /// inference generation, funding reservation or observation is created.
    static func begin(_ expected: Candidate, now: Date, container: ModelContainer,
                      authority: SharedMediaNativeAppOperationAuthority,
                      files: SharedMediaCaptureArtifactFiles,
                      boundary: (SharedMediaCaptureReservationBoundary) throws -> Void = { _ in }) async throws -> Candidate {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              expected.due.map({ $0 <= now }) ?? true else { throw SharedMediaStorageFailure.closed }
        return try await update(expected, container: container, authority: authority, files: files, boundary: boundary) { job in
            guard [.pending, .running, .waiting].contains(expected.status),
                  OfflineQueueRetryPolicy.canScheduleAutomaticRetry(currentAttempt: expected.attemptCount) else {
                throw SharedMediaStorageFailure.closed
            }
            job.status = .running
            job.attemptCount += 1
            job.lastAttemptAt = now; job.updatedAt = now; job.nextRunAt = nil
            job.lastErrorCode = nil; job.lastErrorMessage = nil
        }
    }

    /// An uncertain network outcome retains the exact accepted body and
    /// inference identity. A stale attempt cannot reschedule a newer one.
    static func postpone(_ claimed: Candidate, until due: Date, container: ModelContainer,
                         authority: SharedMediaNativeAppOperationAuthority,
                         files: SharedMediaCaptureArtifactFiles,
                         boundary: (SharedMediaCaptureReservationBoundary) throws -> Void = { _ in }) async throws -> Candidate {
        guard [.pending, .running, .waiting].contains(claimed.status), due.timeIntervalSinceReferenceDate.isFinite else {
            throw SharedMediaStorageFailure.conflict
        }
        return try await update(claimed, container: container, authority: authority, files: files, boundary: boundary) { job in
            let retriesRemain = OfflineQueueRetryPolicy.canScheduleAutomaticRetry(currentAttempt: claimed.attemptCount)
            job.status = retriesRemain ? .waiting : .needsAttention
            job.nextRunAt = retriesRemain ? due : nil
            job.lastErrorCode = retriesRemain ? "capture_execution_retry" : "automatic_retry_limit_reached"
            job.lastErrorMessage = nil // Never persist a response body or private transport diagnostic.
        }
    }

    /// Only a fresh positively acknowledged save may precede one primary HTTP
    /// call. After a throw or process restart, the saved marker is recovery-only.
    static func reserveDispatch(_ claimed: Candidate, container: ModelContainer,
                                authority: SharedMediaNativeAppOperationAuthority,
                                files: SharedMediaCaptureArtifactFiles,
                                boundary: (SharedMediaCaptureReservationBoundary) throws -> Void = { _ in }) async throws -> Candidate {
        guard claimed.status == .running, claimed.dispatch == nil else { throw SharedMediaStorageFailure.closed }
        return try await update(claimed, container: container, authority: authority, files: files, boundary: boundary) { job in
            let context = ModelContext(container); context.autosaveEnabled = false
            let saved = try retained(scanID: claimed.scanID, context: context, authority: authority, files: files)
            guard let raw = job.metadataJSON,
                  try SharedMediaCaptureFundingResolution.funding(raw, submission: saved.submission).allowsDispatch else {
                throw SharedMediaStorageFailure.closed
            }
            job.metadataJSON = try SharedMediaCaptureExecutionIntent.reserving(submission: saved.submission,
                attemptCount: claimed.attemptCount, metadata: job.metadataJSON)
        }
    }

    private static func update(_ expected: Candidate, container: ModelContainer,
                               authority: SharedMediaNativeAppOperationAuthority,
                               files: SharedMediaCaptureArtifactFiles,
                               boundary: (SharedMediaCaptureReservationBoundary) throws -> Void,
                               mutate: (OfflineJobRecord) throws -> Void) async throws -> Candidate {
        let before = try authority.header(container)
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        try files.check()
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        let saved = try retained(scanID: expected.scanID, context: context, authority: authority, files: files)
        let job = try SharedMediaCaptureCompletionReadback.job(saved.submission, context: context)
        let queueRow = try queue(saved.submission, context: context)
        try requireQueueState(queueRow, job: job)
        guard try candidate(saved, job: job) == expected else { throw SharedMediaStorageFailure.stale }
        try mutate(job)
        queueRow.queueAttemptCount = job.attemptCount; queueRow.queueLastAttemptAt = job.lastAttemptAt
        queueRow.queueNextRetryAt = job.nextRunAt; queueRow.queueNeedsAttention = job.status == .needsAttention
        queueRow.queueLastErrorCode = job.lastErrorCode; queueRow.queueLastErrorMessage = job.lastErrorMessage
        queueRow.queueUpdatedAt = job.updatedAt
        let written = try candidate(saved, job: job)
        let writtenMetadata = job.metadataJSON
        try boundary(.beforeSave); try Task.checkCancellation(); try files.check()
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        try context.save()
        try boundary(.afterSave); try files.check()
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        let read = ModelContext(container); read.autosaveEnabled = false
        let current = try retained(scanID: expected.scanID, context: read, authority: authority, files: files)
        let currentJob = try SharedMediaCaptureCompletionReadback.job(current.submission, context: read)
        try requireQueueState(try queue(current.submission, context: read), job: currentJob)
        guard current == saved, currentJob.metadataJSON == writtenMetadata,
              try candidate(current, job: currentJob) == written else { throw SharedMediaStorageFailure.stale }
        return written
    }

    private static func candidate(_ saved: SharedMediaCaptureSubmissionReceipt.Snapshot,
                                  job: OfflineJobRecord) throws -> Candidate {
        guard let status = OfflineJobStatus(rawValue: job.statusRaw), [.pending, .running, .waiting, .needsAttention].contains(status),
              job.attemptCount >= 0, job.nextRunAt?.timeIntervalSinceReferenceDate.isFinite ?? true,
              job.lastAttemptAt?.timeIntervalSinceReferenceDate.isFinite ?? true,
              InferenceGenerationMetadataContract.matches(saved.submission.generation, in: job.metadataJSON) else {
            throw SharedMediaStorageFailure.conflict
        }
        let dispatch = try SharedMediaCaptureExecutionIntent.read(job.metadataJSON, submission: saved.submission)
        guard dispatch.map({ $0.attemptCount <= job.attemptCount }) ?? true else { throw SharedMediaStorageFailure.conflict }
        return .init(scanID: saved.submission.scanID, generation: saved.submission.generation,
            status: status, attemptCount: job.attemptCount, due: job.nextRunAt,
            dispatch: dispatch)
    }

    private static func retained(scanID: UUID, context: ModelContext,
                                 authority: SharedMediaNativeAppOperationAuthority,
                                 files: SharedMediaCaptureArtifactFiles) throws -> SharedMediaCaptureSubmissionReceipt.Snapshot {
        try files.check(); _ = try authority.header(context.container)
        let key = scanID.uuidString.lowercased()
        guard let job = try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: key)),
              let raw = job.metadataJSON, raw.utf8.count <= OrdinaryInferenceCompletion.maximumBytes else {
            throw SharedMediaStorageFailure.conflict
        }
        let identity = try OrdinaryInitialSubmissionIdentity.read(
            OfflineScanJobMetadataContract.object(from: raw)[OrdinaryInitialEvidenceProof.expectationKey])
        guard let identity, identity.ownerID == authority.profile.ownerID, identity.scanID == scanID,
              let saved = try SharedMediaCaptureSubmissionReceipt.matching(scanID: scanID, generation: identity.generation, in: context),
              case .accepted = saved.state, saved.submission.profile == authority.profile,
              saved.submission.rootBindingSHA256 == files.rootBindingSHA256 else { throw SharedMediaStorageFailure.conflict }
        try SharedMediaCaptureQueueIdentity.require(saved.submission, in: context)
        if job.status != .complete {
            // A library result and unfinished ingestion job cannot be a valid
            // atomic completion. Keep that inconsistency away from dispatch.
            let upper = scanID.uuidString
            var records = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == key || $0.id == upper })
            records.fetchLimit = 1
            guard try context.fetch(records).isEmpty else { throw SharedMediaStorageFailure.conflict }
        }
        return saved
    }

    private static func uuid(_ value: String) throws -> UUID {
        guard let id = UUID(uuidString: value), id.uuidString.lowercased() == value else { throw SharedMediaStorageFailure.conflict }
        return id
    }

    private static func queue(_ submission: SharedMediaCaptureSubmission, context: ModelContext) throws -> OfflineQueuedScan {
        let key = submission.scanID.uuidString.lowercased()
        var query = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == key })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        return row
    }

    private static func requireQueueState(_ queue: OfflineQueuedScan, job: OfflineJobRecord) throws {
        // Private Capture never enters the legacy URLSession/R2 state machine.
        // The job owns execution; the queue mirrors bounded retry presentation.
        guard queue.scanStateRaw == ScanQueueState.pending.rawValue,
              queue.queueAttemptCount == job.attemptCount, queue.queueLastAttemptAt == job.lastAttemptAt,
              queue.queueNextRetryAt == job.nextRunAt, queue.queueNeedsAttention == (job.status == .needsAttention),
              queue.queueLastErrorCode == job.lastErrorCode, queue.queueLastErrorMessage == job.lastErrorMessage,
              queue.queueUpdatedAt == job.updatedAt else { throw SharedMediaStorageFailure.conflict }
    }
}
