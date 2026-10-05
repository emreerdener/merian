import Foundation
import SwiftData

/// Durable analysis-bound decisions. Delivery and paired-state reconciliation are separate owners.
enum ObservationAnalysisReviewPersistence {
    static let prefix = "observation-analysis-review:"
    enum IntegrityError: Error { case conflict, unavailable, accountChanged }
    static func observationPrefix(_ observationID: UUID) -> String { prefix + observationID.uuidString.lowercased() + ":" }
    static func jobID(_ operationID: UUID, observationID: UUID) -> String {
        observationPrefix(observationID) + operationID.uuidString.lowercased()
    }

    @MainActor
    static func stage(_ request: ObservationAnalysisReviewRequest, ownerID: UUID, container: ModelContainer,
                      isCurrent: () -> Bool, validateNew: (ModelContext) throws -> Void,
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws -> ObservationAnalysisReviewIntent {
        let candidate = try ObservationAnalysisReviewIntent(request: request, ownerID: ownerID)
        return try transaction(candidate, container: container, isCurrent: isCurrent, save: save) { context in
            // Native operation UUIDs never rebind, even across observations. The
            // server scopes receipts by observation; this is a stricter local fence.
            let suffix = ":" + request.operationID.uuidString.lowercased()
            let existingJobs = try context.fetch(FetchDescriptor<OfflineJobRecord>()).filter {
                $0.id.hasPrefix(prefix) && $0.id.hasSuffix(suffix)
            }
            guard existingJobs.count <= 1 else { throw IntegrityError.conflict }
            if let existing = existingJobs.first {
                let saved = try restore(existing)
                guard saved.ownerID == ownerID, saved.request == request,
                      saved.requestSHA256 == candidate.requestSHA256 else { throw IntegrityError.conflict }
                return saved
            }
            // Exact replay remains recoverable after authority advances. Only
            // newly accepted decision must still match the foreground preview.
            // Serialize decisions through paired reconciliation; otherwise two receipt
            // recoveries could each wait for the other's unfinished projection.
            let scope = observationPrefix(request.observationID)
            for job in try context.fetch(FetchDescriptor<OfflineJobRecord>()) where job.id.hasPrefix(scope) {
                guard try restore(job).isComplete else { throw IntegrityError.conflict }
            }
            try requireNewRevision(candidate, context: context)
            if case let .undo(rejectionID) = request.decision {
                guard let rejectJob = try context.fetchOfflineJob(id: jobID(rejectionID, observationID: request.observationID)) else {
                    throw IntegrityError.unavailable
                }
                let rejection = try restore(rejectJob)
                guard rejection.ownerID == ownerID, rejection.request.analysisID == request.analysisID,
                      rejection.request.decision == .reject, let receipt = rejection.receipt,
                      case let .applied(observationRevision, reviewRevision) = receipt.outcome,
                      request.expectedObservationRevision >= observationRevision,
                      request.expectedReviewRevision == reviewRevision else { throw IntegrityError.conflict }
            }
            try validateNew(context)
            guard let text = String(bytes: try candidate.storedData(), encoding: .utf8) else { throw IntegrityError.conflict }
            context.insert(OfflineJobRecord(id: jobID(request.operationID, observationID: request.observationID), kind: .observationAnalysisReviewSync,
                subjectId: request.observationID.uuidString.lowercased(), priority: 65,
                metadataJSON: text))
            return candidate
        }
    }

    /// A receipt is durable before paired-state reconciliation. No authority or selection writes occur here.
    @MainActor
    static func acknowledge(_ receipt: ObservationAnalysisReviewReceipt, claim: Claim,
                            at date: Date, container: ModelContainer, isCurrent: () -> Bool,
                            save: (ModelContext) throws -> Void = { try $0.save() }) throws -> ObservationAnalysisReviewIntent {
        try transaction(claim.intent, container: container, isCurrent: isCurrent, save: save) { context in
            guard let job = try context.fetchOfflineJob(id: jobID(claim.intent.request.operationID, observationID: claim.intent.request.observationID)) else {
                throw IntegrityError.unavailable
            }
            try validate(claim, job: job)
            let saved = try restore(job)
            let next = try saved.accepting(receipt, at: date)
            guard let text = String(bytes: try next.storedData(), encoding: .utf8) else { throw IntegrityError.conflict }
            job.metadataJSON = text
            job.status = .waiting; job.nextRunAt = nil
            job.lastErrorCode = nil; job.lastErrorMessage = nil; job.lastHTTPStatus = nil
            job.updatedAt = date
            return next
        }
    }

    static func restore(_ job: OfflineJobRecord) throws -> ObservationAnalysisReviewIntent {
        guard job.kindRaw == OfflineJobKind.observationAnalysisReviewSync.rawValue,
              let text = job.metadataJSON else { throw IntegrityError.conflict }
        let saved = try ObservationAnalysisReviewIntent.decode(Data(text.utf8))
        guard job.id == jobID(saved.request.operationID, observationID: saved.request.observationID),
              job.subjectId == saved.request.observationID.uuidString.lowercased() else { throw IntegrityError.conflict }
        if saved.isComplete {
            guard job.statusRaw == OfflineJobStatus.complete.rawValue, job.nextRunAt == nil else { throw IntegrityError.conflict }
        } else {
            guard [OfflineJobStatus.pending.rawValue, OfflineJobStatus.running.rawValue, OfflineJobStatus.waiting.rawValue, OfflineJobStatus.needsAttention.rawValue]
                .contains(job.statusRaw) else { throw IntegrityError.conflict }
        }
        return saved
    }

    /// Caller owns the deletion transaction/save. Erases even malformed local decisions.
    /// Cloud-confirmation fallback requires exact owner; ambiguous ownership keeps deletion retryable.
    static func removeForDeletion(_ scanID: String, context: ModelContext, ownerID: UUID? = nil) throws {
        guard let observationID = UUID(uuidString: scanID) else { return }
        let scope = observationPrefix(observationID)
        // The primary key is the independent erasure index. Never trust damaged
        // subject metadata to select another observation's namespace.
        for job in try context.fetch(FetchDescriptor<OfflineJobRecord>()) where job.id.hasPrefix(scope) {
            if let ownerID {
                guard let text = job.metadataJSON else { throw IntegrityError.conflict }
                let intent = try ObservationAnalysisReviewIntent.decode(Data(text.utf8))
                guard job.id == jobID(intent.request.operationID, observationID: intent.request.observationID) else {
                    throw IntegrityError.conflict
                }
                guard intent.ownerID == ownerID else { continue }
            }
            context.delete(job)
        }
    }

    @MainActor
    private static func requireNewRevision(_ intent: ObservationAnalysisReviewIntent, context: ModelContext) throws {
        let request = intent.request
        let scan = try ObservationHistorySyncService.enrolledScan(request.observationID.uuidString, context: context)
        let id = request.analysisID.uuidString.lowercased()
        var query = FetchDescriptor<LocalAnalysisStateRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 2
        let states = try context.fetch(query)
        var results = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == id })
        results.fetchLimit = 1
        let analysis = try context.fetch(results).first
        guard states.count == 1, let state = states.first, analysis?.state?.persistentModelID == state.persistentModelID,
              state.ownerAccountID == intent.ownerID.uuidString.lowercased(), state.observationID == scan.id,
              scan.observationStateRevision == request.expectedObservationRevision,
              state.observationStateRevision == request.expectedObservationRevision,
              state.reviewRevision == request.expectedReviewRevision else { throw IntegrityError.conflict }
    }

    @MainActor
    static func transaction<T>(
        _ intent: ObservationAnalysisReviewIntent, container: ModelContainer,
        isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() },
        body: (ModelContext) throws -> T
    ) throws -> T {
        try ConfirmedSpeciesReviewPersistence.transaction {
            guard isCurrent() else { throw IntegrityError.accountChanged }
            let context = ModelContext(container); context.autosaveEnabled = false
            do {
                let scan = try ObservationHistorySyncService.enrolledScan(intent.request.observationID.uuidString, context: context)
                guard scan.analysisOwnerAccountID == intent.ownerID.uuidString.lowercased(),
                      !(try ObservationHistoryEnrollmentIntent.holds(scan.id, context: context)) else { throw IntegrityError.unavailable }
                let id = intent.request.analysisID.uuidString.lowercased()
                var query = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == id })
                query.fetchLimit = 1
                guard let analysis = try context.fetch(query).first,
                      analysis.ownerAccountID == scan.analysisOwnerAccountID,
                      analysis.observationID == scan.id else { throw IntegrityError.unavailable }
                let result = try body(context)
                try Task.checkCancellation()
                guard isCurrent() else { throw IntegrityError.accountChanged }
                if context.hasChanges { try save(context) }
                return result
            } catch { context.rollback(); throw error }
        }
    }
}
