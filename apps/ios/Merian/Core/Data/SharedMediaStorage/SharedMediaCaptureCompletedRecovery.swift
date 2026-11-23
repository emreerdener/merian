import Foundation
import SwiftData

/// Discovery for committed results only. A candidate grants no media read,
/// provider call, enrollment, or deletion authority. Each continuation rereads
/// the retained submission under its current account/root owner.
@MainActor
enum SharedMediaCaptureCompletedRecovery {
    struct Candidate: Equatable, Sendable {
        let scanID: UUID
        let generation: UUID
        let releaseStarted: Bool
    }
    struct Page: Equatable, Sendable {
        let candidates: [Candidate]
        let nextCursor: String?
    }
    static let pageSize = 32

    static func page(after cursor: String?, container: ModelContainer,
                     authority: SharedMediaNativeAppOperationAuthority,
                     files: SharedMediaCaptureArtifactFiles) async throws -> Page {
        if let cursor {
            guard let id = UUID(uuidString: cursor), id.uuidString.lowercased() == cursor else {
                throw SharedMediaStorageFailure.invalid
            }
        }
        let before = try authority.header(container)
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        let format = SharedMediaCaptureSubmission.Format.v1.rawValue
        var query: FetchDescriptor<SharedMediaOrdinarySubmissionRecord>
        if let cursor {
            query = .init(predicate: #Predicate { $0.formatRaw == format && $0.cursorKey > cursor }, sortBy: [SortDescriptor(\.cursorKey)])
        } else {
            query = .init(predicate: #Predicate { $0.formatRaw == format }, sortBy: [SortDescriptor(\.cursorKey)])
        }
        query.fetchLimit = pageSize + 1
        let rows = try context.fetch(query)
        var candidates: [Candidate] = []
        for row in rows.prefix(pageSize) {
            try Task.checkCancellation()
            let saved = try SharedMediaCaptureSubmissionReceipt.auditRead(row, in: context)
            guard saved.submission.profile == authority.profile, saved.submission.rootBindingSHA256 == files.rootBindingSHA256 else {
                throw SharedMediaStorageFailure.conflict
            }
            guard case .accepted = saved.state else { continue }
            let job = try SharedMediaCaptureCompletionReadback.job(saved.submission, context: context)
            if saved.release != nil {
                _ = try SharedMediaCaptureCompletedCustody.read(scanID: saved.submission.scanID,
                    generation: saved.submission.generation, ownerID: authority.profile.ownerID, context: context)
            }
            guard job.status == .complete else { continue }
            let candidate = Candidate(scanID: saved.submission.scanID, generation: saved.submission.generation,
                releaseStarted: saved.release != nil)
            let current = try read(candidate, context: context, authority: authority, files: files)
            guard let raw = job.metadataJSON else { throw SharedMediaStorageFailure.conflict }
            let funding = try SharedMediaCaptureFundingReceipt.read(raw)
            guard funding.scanID == candidate.scanID else { throw SharedMediaStorageFailure.conflict }
            _ = try funding.settlement(ownerID: authority.profile.ownerID)
            if funding.delivered && current.release?.releasedRevision == nil { candidates.append(candidate) }
        }
        try files.check()
        guard try authority.header(container) == before, !context.hasChanges else { throw SharedMediaStorageFailure.stale }
        return .init(candidates: candidates, nextCursor: rows.count > pageSize ? rows[pageSize - 1].cursorKey : nil)
    }

    static func read(_ candidate: Candidate, context: ModelContext,
                     authority: SharedMediaNativeAppOperationAuthority,
                     files: SharedMediaCaptureArtifactFiles) throws -> SharedMediaCaptureSubmissionReceipt.Snapshot {
        _ = try authority.header(context.container); try files.check()
        let saved = try SharedMediaCaptureCompletedCustody.read(scanID: candidate.scanID, generation: candidate.generation,
            ownerID: authority.profile.ownerID, context: context)
        guard saved.submission.profile == authority.profile, saved.submission.rootBindingSHA256 == files.rootBindingSHA256,
              (saved.release != nil) == candidate.releaseStarted, case .accepted = saved.state else { throw SharedMediaStorageFailure.stale }
        let job = try SharedMediaCaptureCompletionReadback.job(saved.submission, context: context)
        guard job.status == .complete, let raw = job.metadataJSON,
              try OrdinaryInferenceCompletion.retainedInitialIdentity(metadata: raw, scanID: candidate.scanID, owner: authority.profile.ownerID)
                == .init(ownerID: authority.profile.ownerID, scanID: candidate.scanID, generation: candidate.generation) else {
            throw SharedMediaStorageFailure.closed
        }
        return saved
    }

    /// Refresh only release progression for the same exact observation. A lost
    /// acknowledgement may have saved an intent or completed cleanup; neither
    /// permits replacing the caller's scan or generation.
    static func refresh(_ candidate: Candidate, context: ModelContext,
                        authority: SharedMediaNativeAppOperationAuthority,
                        files: SharedMediaCaptureArtifactFiles) throws -> Candidate {
        let saved = try SharedMediaCaptureCompletedCustody.read(scanID: candidate.scanID, generation: candidate.generation,
            ownerID: authority.profile.ownerID, context: context)
        let current = Candidate(scanID: candidate.scanID, generation: candidate.generation, releaseStarted: saved.release != nil)
        guard !candidate.releaseStarted || current.releaseStarted else { throw SharedMediaStorageFailure.stale }
        _ = try read(current, context: context, authority: authority, files: files)
        let lower = candidate.scanID.uuidString.lowercased(), upper = candidate.scanID.uuidString
        var query = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })
        query.fetchLimit = 2
        let records = try context.fetch(query)
        guard records.count == 1, let record = records.first, record.id == lower,
              record.mediaAuthorityRaw == SharedMediaCaptureAcceptance.mediaAuthority,
              record.sharedMediaConsumerID == nil else { throw SharedMediaStorageFailure.conflict }
        if saved.release == nil {
            if record.analysisOwnerAccountID == nil {
                _ = try SharedMediaCaptureCompletionReadback.retained(for: record, ownerID: authority.profile.ownerID, context: context)
            } else {
                guard let baseline = try ObservationHistoryEnrollmentService.acknowledgedInitialBaseline(
                    observation: candidate.scanID, owner: authority.profile.ownerID, context: context),
                      let raw = try SharedMediaCaptureCompletionReadback.job(saved.submission, context: context).metadataJSON,
                      try OrdinaryInferenceCompletion.matchesRetainedInitialResult(baseline.result, metadata: raw,
                        scanID: candidate.scanID, owner: authority.profile.ownerID) else { throw SharedMediaStorageFailure.conflict }
            }
        }
        return current
    }
}
