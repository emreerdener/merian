import Foundation
import SwiftData

/// Immutable chat outbox. Dedicated claims are prepared; generic scheduling excludes this kind.
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
                let scan = try requireScope(candidate, context: context)
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
              job.lastErrorMessage == nil, job.lastHTTPStatus == nil,
              job.serverStatus == nil, job.serverStage == nil, job.serverRetryAfter == nil, job.priority == 65,
              job.approximateBytes == 0, !job.requiresUnconstrainedNetwork, job.allowsCellular else { throw IntegrityError.conflict }
        try validateShape(job, intent: intent)
        return intent
    }

    @MainActor
    static func requireScope(_ intent: ProtectedInsightChatIntent, context: ModelContext) throws -> LocalScanRecord {
        let scan = try ObservationHistorySyncService.enrolledScan(intent.request.observationID.uuidString, context: context)
        guard scan.analysisOwnerAccountID == intent.ownerID.uuidString.lowercased(),
              !(try ObservationHistoryEnrollmentIntent.holds(scan.id, context: context)) else { throw IntegrityError.unavailable }
        let id = intent.request.selection.analysisID.uuidString.lowercased()
        let children = try context.fetch(FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == id }))
        guard children.count == 1, let child = children.first, child.ownerAccountID == scan.analysisOwnerAccountID,
              child.observationID == scan.id else { throw IntegrityError.unavailable }
        return scan
    }

    /// Closed local state only; neither a status nor a receipt grants dispatch permission.
    enum PendingState { case pending, running, held }
    struct PendingStatus {
        let intent: ProtectedInsightChatIntent
        let state: PendingState
    }
    struct StatusPage {
        let unfinished: PendingStatus?
        let completed: [ProtectedInsightChatIntent]
        let nextAfterMessageID: UUID?
    }

    /// Bounded local discovery, never an admission/absence proof. Completed pages are
    /// lexical message-ID pages; they are not a mutable conversation or a latest result.
    @MainActor
    static func status(ownerID: UUID, observationID: UUID, afterMessageID: UUID? = nil,
                       limit: Int = 20, container: ModelContainer, isCurrent: () -> Bool) throws -> StatusPage {
        guard (1...20).contains(limit) else { throw IntegrityError.conflict }
        return try ConfirmedSpeciesReviewPersistence.transaction {
            guard isCurrent() else { throw IntegrityError.accountChanged }
            let context = ModelContext(container); context.autosaveEnabled = false
            let scan = try ObservationHistorySyncService.enrolledScan(observationID.uuidString, context: context)
            guard scan.analysisOwnerAccountID == ownerID.uuidString.lowercased(),
                  !(try ObservationHistoryEnrollmentIntent.holds(scan.id, context: context)) else { throw IntegrityError.unavailable }
            let scope = observationPrefix(observationID), subject = observationID.uuidString.lowercased()
            let kind = OfflineJobKind.protectedInsightChatSync.rawValue
            var unfinished: PendingStatus?
            var completed: [ProtectedInsightChatIntent] = []
            var cursor: String?
            repeat {
                let after = cursor ?? "", started = cursor != nil
                var query = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate {
                    ($0.id.starts(with: scope) || $0.kindRaw == kind) && (!started || $0.id > after)
                }, sortBy: [SortDescriptor(\OfflineJobRecord.id)])
                query.fetchLimit = 64
                let batch = try context.fetch(query)
                for job in batch where job.id.hasPrefix(scope)
                    || (!hasCanonicalNamespace(job.id) && job.subjectId?.lowercased() == subject) {
                    let saved = try restore(job)
                    guard saved.ownerID == ownerID, saved.request.observationID == observationID else { throw IntegrityError.conflict }
                    _ = try requireScope(saved, context: context)
                    if saved.isComplete {
                        if afterMessageID.map({ saved.request.clientMessageID.uuidString.lowercased() > $0.uuidString.lowercased() }) ?? true {
                            completed.append(saved)
                            completed.sort { $0.request.clientMessageID.uuidString.lowercased() < $1.request.clientMessageID.uuidString.lowercased() }
                            if completed.count > limit + 1 { completed.removeLast() }
                        }
                    } else {
                        guard unfinished == nil else { throw IntegrityError.conflict }
                        let state: PendingState
                        switch job.status {
                        case .pending: state = .pending
                        case .running: state = .running
                        case .needsAttention: state = .held
                        default: throw IntegrityError.conflict
                        }
                        unfinished = .init(intent: saved, state: state)
                    }
                }
                guard isCurrent() else { throw IntegrityError.accountChanged }
                cursor = batch.count == 64 ? batch.last?.id : nil
            } while cursor != nil
            return StatusPage(unfinished: unfinished, completed: Array(completed.prefix(limit)),
                nextAfterMessageID: completed.count > limit ? completed[limit - 1].request.clientMessageID : nil)
        }
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
