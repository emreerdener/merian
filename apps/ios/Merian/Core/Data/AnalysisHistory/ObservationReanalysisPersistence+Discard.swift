import Foundation
import SwiftData

extension ObservationReanalysisPersistence {
    /// Explicit discard of one local, unbound preparation. No sibling, provider or filesystem mutation.
    /// The receipt fences even a plan cancelled before its first files_pending write.
    @MainActor
    static func discardPreparation(source: ObservationReanalysisSource, analysisID: UUID, container: ModelContainer,
                                   isCurrent: () -> Bool,
                                   save: (ModelContext) throws -> Void = { try $0.save() }) throws -> ObservationReanalysisErasureReceipt {
        let identity = OfflineQueueWork.Reanalysis(observationID: source.observationID, sourceAnalysisID: source.analysisID,
            analysisID: analysisID, ownerID: source.ownerID)
        guard Set([identity.observationID, identity.sourceAnalysisID, identity.analysisID]).count == 3 else { throw IntegrityError.conflict }
        return try ConfirmedSpeciesReviewPersistence.transaction {
            try Task.checkCancellation()
            guard isCurrent() else { throw IntegrityError.accountChanged }
            let context = ModelContext(container); context.autosaveEnabled = false
            let receipt = ObservationReanalysisErasureReceipt(parentID: source.observationID, childID: analysisID)
            do {
                try requireNoResultCollision(identity, context: context)
                let existingPair = try pair(identity, context: context)
                if let existing = try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(analysisID)) {
                    guard try ObservationReanalysisErasureReceipt.restore(existing) == receipt, existingPair == nil else { throw IntegrityError.conflict }
                    guard isCurrent() else { throw IntegrityError.accountChanged }
                    return receipt // Parent deletion and completed cleanup remain authoritative.
                }
                try source.validate(context: context)
                if let (row, job) = existingPair {
                    guard row.scanStateRaw == ScanQueueState.pending.rawValue, row.queueLastAttemptAt == nil,
                          row.stagedR2Keys == nil, row.queueLastHTTPStatus == nil, row.queueLastServerStatus == nil,
                          row.queueLastServerStage == nil, row.queueLastServerRetryAfter == nil,
                          row.queueLastErrorCode == nil, row.queueLastErrorMessage == nil,
                          job.lastErrorCode == nil, job.lastErrorMessage == nil, job.lastHTTPStatus == nil,
                          job.serverStatus == nil, job.serverStage == nil, job.serverRetryAfter == nil,
                          let text = job.metadataJSON, text.utf8.count <= 1_048_576 else { throw IntegrityError.conflict }
                    let bytes = Data(text.utf8)
                    try ObservationVideoPreparation.requireNonVideo(bytes)
                    if let pending = try? ObservationReanalysisPreparationIntent.decode(bytes) {
                        guard pending.draft.identity == identity else { throw IntegrityError.conflict }
                        try validatePending(pending, row: row, job: job, context: context)
                    } else if let submitted = try? ObservationReanalysisSubmissionIntent.decode(bytes) {
                        guard submitted.draft.identity == identity,
                              case .submitted = try restoreDraft(submitted.draft, row: row, job: job) else { throw IntegrityError.conflict }
                    } else if let work = try? ObservationReanalysisAdmissionWork.decode(bytes) {
                        guard work.preparation.draft.identity == identity else { throw IntegrityError.conflict }
                        try ObservationReanalysisAdmissionStore.validateDiscard(identity, context: context)
                    } else {
                        // Bound requests, unknown phases and terminal/attempted jobs cannot authorize local discard.
                        let draft = try ObservationReanalysisDraft.decode(bytes)
                        guard draft.identity == identity, case .draft = try restoreDraft(draft, row: row, job: job) else {
                            throw IntegrityError.conflict
                        }
                    }
                    try context.deletePreferredGoalHint(scanId: row.id)
                    context.delete(job)
                    context.delete(row)
                }
                try receipt.record(in: context)
                try Task.checkCancellation()
                guard isCurrent() else { throw IntegrityError.accountChanged }
                try save(context)
                return receipt
            } catch { context.rollback(); throw error }
        }
    }

    /// Completed results or another use of this UUID win over a local preparation's discard intent.
    @MainActor
    static func requireNoResultCollision(_ identity: OfflineQueueWork.Reanalysis, context: ModelContext) throws {
        let lower = identity.analysisID.uuidString.lowercased(), upper = identity.analysisID.uuidString
        let alternateReceiptID = "reanalysis-erasure:" + upper
        guard try (upper == lower || context.fetchOfflineJob(id: alternateReceiptID) == nil), try context.fetch(FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })).isEmpty,
              try context.fetch(FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })).isEmpty,
              try context.fetch(FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == lower || $0.scanId == upper })).isEmpty,
              !(try ObservationHistoryEnrollmentIntent.holds(lower, context: context)),
              try (upper == lower || context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: upper)) == nil) else { throw IntegrityError.conflict }
    }
}
