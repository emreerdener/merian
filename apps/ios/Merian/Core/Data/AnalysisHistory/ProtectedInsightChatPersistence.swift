import Foundation
import SwiftData

/// Prepared, inert outbox. No claims or delivery exist yet; generic scheduling excludes this kind.
enum ProtectedInsightChatPersistence {
    static let prefix = "observation-insight-chat:"
    enum IntegrityError: Error { case conflict, unavailable, accountChanged }
    static func observationPrefix(_ id: UUID) -> String { prefix + id.uuidString.lowercased() + ":" }
    static func jobID(_ request: ProtectedInsightChatRequest) -> String {
        observationPrefix(request.observationID) + request.clientMessageID.uuidString.lowercased()
    }

    @MainActor
    static func stage(_ request: ProtectedInsightChatRequest, ticket: ProtectedInsightChatTicket,
                      container: ModelContainer, isCurrent: () -> Bool,
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws -> ProtectedInsightChatIntent {
        guard request.observationID == ticket.observationID, request.selection == ticket.selection else { throw IntegrityError.conflict }
        let candidate = try ProtectedInsightChatIntent(request: request, ownerID: ticket.ownerID)
        return try ConfirmedSpeciesReviewPersistence.transaction {
            guard isCurrent() else { throw IntegrityError.accountChanged }
            let context = ModelContext(container); context.autosaveEnabled = false
            do {
                let scan = try ObservationHistorySyncService.enrolledScan(request.observationID.uuidString, context: context)
                guard scan.analysisOwnerAccountID == ticket.ownerID.uuidString.lowercased(),
                      !(try ObservationHistoryEnrollmentIntent.holds(scan.id, context: context)) else { throw IntegrityError.unavailable }
                let id = request.selection.analysisID.uuidString.lowercased()
                let children = try context.fetch(FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == id }))
                guard children.count == 1, let child = children.first, child.ownerAccountID == scan.analysisOwnerAccountID,
                      child.observationID == scan.id else { throw IntegrityError.unavailable }
                let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>())
                let chatJobs = jobs.filter { $0.id.hasPrefix(prefix) || $0.kindRaw == OfflineJobKind.protectedInsightChatSync.rawValue }
                let matches = try chatJobs.filter { try restore($0).request.clientMessageID == request.clientMessageID }
                guard matches.count <= 1 else { throw IntegrityError.conflict }
                let result: ProtectedInsightChatIntent
                if let job = matches.first {
                    let saved = try restore(job)
                    guard saved.ownerID == ticket.ownerID, saved.request == request,
                          saved.requestSHA256 == candidate.requestSHA256 else { throw IntegrityError.conflict }
                    result = saved // Exact recovery precedes current selection/review eligibility.
                } else {
                    try requireNew(candidate, ticket: ticket, scan: scan, jobs: jobs, context: context)
                    guard let metadata = String(bytes: try candidate.storedData(), encoding: .utf8) else { throw IntegrityError.conflict }
                    context.insert(OfflineJobRecord(id: jobID(request), kind: .protectedInsightChatSync,
                        subjectId: request.observationID.uuidString.lowercased(), priority: 65,
                        metadataJSON: metadata))
                    result = candidate
                }
                try Task.checkCancellation()
                guard isCurrent() else { throw IntegrityError.accountChanged }
                if context.hasChanges { try save(context) }
                return result
            } catch { context.rollback(); throw error }
        }
    }

    @MainActor
    private static func requireNew(_ candidate: ProtectedInsightChatIntent, ticket: ProtectedInsightChatTicket,
                                   scan: LocalScanRecord, jobs: [OfflineJobRecord], context: ModelContext) throws {
        let scope = observationPrefix(ticket.observationID), subject = ticket.observationID.uuidString.lowercased()
        for job in jobs where job.id.hasPrefix(scope)
            || (job.kindRaw == OfflineJobKind.protectedInsightChatSync.rawValue && job.subjectId?.lowercased() == subject) {
            let saved = try restore(job)
            guard saved.ownerID == ticket.ownerID, saved.request.observationID == ticket.observationID, saved.isComplete else {
                throw IntegrityError.conflict
            }
        }
        let reviewScope = ObservationAnalysisReviewPersistence.observationPrefix(ticket.observationID)
        for job in jobs where job.id.hasPrefix(reviewScope)
            || (job.kindRaw == OfflineJobKind.observationAnalysisReviewSync.rawValue && job.subjectId?.lowercased() == subject) {
            let saved = try ObservationAnalysisReviewPersistence.restore(job)
            guard saved.ownerID == ticket.ownerID, saved.request.observationID == ticket.observationID, saved.isComplete else {
                throw IntegrityError.conflict
            }
        }
        try ObservationHistorySelectionIntent.requireIdle(scan.id, context: context)
        try ObservationHistoryStateSyncService.requireSettledReview(scan, context: context)
        let entry = try ObservationHistoryListingService.entry(candidate.request.selection.analysisID, scan: scan, context: context)
        let baseline = ObservationHistoryListingService.Context(owner: ticket.ownerID,
            selected: try ObservationHistoryPage.uuid(scan.selectedAnalysisID), revision: try ObservationHistoryPage.integer(scan.observationStateRevision),
            pendingOperation: nil, undoOperation: nil)
        guard try ProtectedInsightChatTicket(entry: entry, context: baseline, observationID: ticket.observationID) == ticket else {
            throw IntegrityError.conflict
        }
    }

    static func restore(_ job: OfflineJobRecord) throws -> ProtectedInsightChatIntent {
        guard job.kindRaw == OfflineJobKind.protectedInsightChatSync.rawValue, let metadata = job.metadataJSON else { throw IntegrityError.conflict }
        let intent = try ProtectedInsightChatIntent.decode(Data(metadata.utf8))
        guard job.id == jobID(intent.request), job.subjectId == intent.request.observationID.uuidString.lowercased(),
              job.statusRaw == (intent.isComplete ? OfflineJobStatus.complete.rawValue : OfflineJobStatus.pending.rawValue),
              job.attemptCount == 0, job.lastAttemptAt == nil, job.nextRunAt == nil,
              job.lastErrorCode == nil, job.lastErrorMessage == nil, job.lastHTTPStatus == nil,
              job.serverStatus == nil, job.serverStage == nil, job.serverRetryAfter == nil, job.priority == 65,
              job.approximateBytes == 0, !job.requiresUnconstrainedNetwork, job.allowsCellular else { throw IntegrityError.conflict }
        return intent
    }

    private static func hasCanonicalNamespace(_ id: String) -> Bool {
        guard id.hasPrefix(prefix) else { return false }
        let parts = id.dropFirst(prefix.count).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return parts.allSatisfy { part in
            UUID(uuidString: String(part)).map { $0.uuidString.lowercased() == part } ?? false
        }
    }

    /// Called inside the caller's deletion transaction. Damaged metadata cannot prevent local erasure.
    static func removeForDeletion(_ scanID: String, context: ModelContext, ownerID: UUID? = nil) throws {
        guard let id = UUID(uuidString: scanID) else { return }
        let subject = id.uuidString.lowercased()
        for job in try context.fetch(FetchDescriptor<OfflineJobRecord>()) where job.id.hasPrefix(observationPrefix(id))
            || (!hasCanonicalNamespace(job.id) && job.kindRaw == OfflineJobKind.protectedInsightChatSync.rawValue
                && job.subjectId?.lowercased() == subject) {
            if let ownerID {
                guard let metadata = job.metadataJSON else { throw IntegrityError.conflict }
                let saved = try ProtectedInsightChatIntent.decode(Data(metadata.utf8))
                guard job.id == jobID(saved.request) else { throw IntegrityError.conflict }
                guard saved.ownerID == ownerID else { continue }
            }
            context.delete(job)
        }
    }
}
