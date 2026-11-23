import Foundation
import SwiftData

/// Discovery and retry metadata for already committed Capture results. These
/// values never authorize provider work, queue removal or original retirement.
/// The repository supplies its current account/root operation for every page.
@MainActor
enum SharedMediaCaptureFundingRecovery {
    struct Candidate: Equatable, Sendable {
        let scanID: UUID
        let generation: UUID
        let due: Date?
    }

    struct Page: Equatable, Sendable {
        let candidates: [Candidate]
        let nextCursor: String?
    }

    static let pageSize = 32

    static func page(after cursor: String?, container: ModelContainer,
                     authority: SharedMediaNativeAppOperationAuthority,
                     files: SharedMediaCaptureArtifactFiles) async throws -> Page {
        if let cursor { try requireCursor(cursor) }
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
        for queue in rows.prefix(pageSize) {
            try Task.checkCancellation()
            try requireCursor(queue.id)
            let scanID = try requireUUID(queue.id)
            let jobID = OfflineQueueManager.scanIngestionJobId(scanId: queue.id)
            guard let job = try context.fetchOfflineJob(id: jobID) else { throw SharedMediaStorageFailure.conflict }
            guard job.status == .complete else { continue }
            let saved = try committed(scanID: scanID, context: context, authority: authority, files: files)
            let raw = try metadata(job)
            let receipt = try SharedMediaCaptureFundingReceipt.read(raw)
            guard receipt.scanID == scanID else { throw SharedMediaStorageFailure.conflict }
            _ = try receipt.settlement(ownerID: authority.profile.ownerID)
            if !receipt.delivered {
                guard job.nextRunAt?.timeIntervalSinceReferenceDate.isFinite ?? true else { throw SharedMediaStorageFailure.conflict }
                candidates.append(.init(scanID: scanID, generation: saved.submission.generation, due: job.nextRunAt))
            }
        }
        try files.check()
        guard try authority.header(container) == before, !context.hasChanges else { throw SharedMediaStorageFailure.stale }
        return .init(candidates: candidates, nextCursor: rows.count > pageSize ? rows[pageSize - 1].id : nil)
    }

    /// Failure schedules only settlement redelivery. The ingestion status stays
    /// complete, so a local acknowledgement failure cannot buy another inference.
    static func postpone(_ candidate: Candidate, until due: Date, container: ModelContainer,
                         authority: SharedMediaNativeAppOperationAuthority,
                         files: SharedMediaCaptureArtifactFiles) async throws {
        guard due.timeIntervalSinceReferenceDate.isFinite else { throw SharedMediaStorageFailure.conflict }
        let before = try authority.header(container)
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        let saved = try committed(scanID: candidate.scanID, context: context, authority: authority, files: files)
        guard saved.submission.generation == candidate.generation else { throw SharedMediaStorageFailure.stale }
        let job = try SharedMediaCaptureCompletionReadback.job(saved.submission, context: context)
        let receipt = try SharedMediaCaptureFundingReceipt.read(metadata(job))
        guard receipt.scanID == candidate.scanID else { throw SharedMediaStorageFailure.conflict }
        _ = try receipt.settlement(ownerID: authority.profile.ownerID)
        guard !receipt.delivered else { return }
        guard job.nextRunAt == candidate.due else { throw SharedMediaStorageFailure.stale }
        job.nextRunAt = due
        try files.check()
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        try context.save()
        let readback = ModelContext(container); readback.autosaveEnabled = false
        let current = try committed(scanID: candidate.scanID, context: readback, authority: authority, files: files)
        let written = try SharedMediaCaptureCompletionReadback.job(current.submission, context: readback)
        guard current == saved, written.status == .complete, written.nextRunAt == due,
              try SharedMediaCaptureFundingReceipt.read(metadata(written)) == receipt else { throw SharedMediaStorageFailure.stale }
    }

    private static func committed(scanID: UUID, context: ModelContext,
                                  authority: SharedMediaNativeAppOperationAuthority,
                                  files: SharedMediaCaptureArtifactFiles) throws -> SharedMediaCaptureSubmissionReceipt.Snapshot {
        try files.check(); _ = try authority.header(context.container)
        let lower = scanID.uuidString.lowercased(), upper = scanID.uuidString
        var query = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let record = rows.first, record.id == lower,
              record.mediaAuthorityRaw == SharedMediaCaptureAcceptance.mediaAuthority,
              record.sharedMediaConsumerID == nil,
              let job = try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: lower)),
              job.status == .complete else { throw SharedMediaStorageFailure.conflict }
        let identity = try OrdinaryInferenceCompletion.retainedInitialIdentity(metadata: metadata(job),
            scanID: scanID, owner: authority.profile.ownerID)
        let saved = try SharedMediaCaptureCompletedCustody.read(scanID: scanID, generation: identity.generation,
            ownerID: authority.profile.ownerID, context: context)
        guard saved.submission.profile == authority.profile,
              saved.submission.rootBindingSHA256 == files.rootBindingSHA256 else { throw SharedMediaStorageFailure.conflict }
        return saved
    }

    private static func metadata(_ job: OfflineJobRecord) throws -> String {
        guard let raw = job.metadataJSON, raw.utf8.count <= OrdinaryInferenceCompletion.maximumBytes else {
            throw SharedMediaStorageFailure.conflict
        }
        return raw
    }

    private static func requireCursor(_ cursor: String) throws { _ = try requireUUID(cursor) }
    private static func requireUUID(_ value: String) throws -> UUID {
        guard let id = UUID(uuidString: value), id.uuidString.lowercased() == value else { throw SharedMediaStorageFailure.conflict }
        return id
    }
}
