import Foundation
import SwiftData

extension ObservationReanalysisPersistence {
    enum PreparationState: Sendable {
        case pending(ObservationReanalysisPreparationIntent)
        case ready(DraftState)
    }

    /// Targeted local recovery read. Decoding a pending envelope never authorizes file or provider work.
    @MainActor
    static func preparation(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
                            isCurrent: () -> Bool,
                            submissionProof: ObservationReanalysisPreparationIntent.Verified? = nil) throws -> PreparationState {
        try transaction(identity, container: container, isCurrent: isCurrent, save: { try $0.save() }) { context in
            if let submissionProof {
                guard submissionProof.pending.draft.identity == identity, submissionProof.pending.action == .submit else { throw IntegrityError.conflict }
                try submissionProof.validate(context: context)
            }
            guard let (row, job) = try pair(identity, context: context), let text = job.metadataJSON else { throw IntegrityError.unavailable }
            let data = Data(text.utf8)
            if let pending = try? ObservationReanalysisPreparationIntent.decode(data) {
                guard pending.draft.identity == identity else { throw IntegrityError.conflict }
                try validatePending(pending, row: row, job: job, context: context)
                return .pending(pending)
            }
            if let draft = try? ObservationReanalysisDraft.decode(data) {
                guard draft.identity == identity else { throw IntegrityError.conflict }
                return .ready(try restoreDraft(draft, row: row, job: job))
            }
            if let submitted = try? ObservationReanalysisSubmissionIntent.decode(data) {
                guard submitted.draft.identity == identity else { throw IntegrityError.conflict }
                return .ready(try restoreDraft(submitted.draft, row: row, job: job))
            }
            let bound = try restore(row: row, job: job)
            guard bound.intent.identity == identity else { throw IntegrityError.conflict }
            return .ready(.bound(bound))
        }
    }

    /// Persist the deletion/recovery index before any private file is created.
    /// A ready or bound replay is returned without rewriting its phase or touching files.
    @MainActor
    static func beginPreparation(_ proof: ObservationReanalysisPreparationIntent.Verified, container: ModelContainer,
                                 isCurrent: () -> Bool,
                                 save: (ModelContext) throws -> Void = { try $0.save() }) throws -> DraftState? {
        let pending = proof.pending
        return try transaction(pending.draft.identity, container: container, isCurrent: isCurrent, save: save) { context in
            try proof.validate(context: context)
            if let (row, job) = try pair(pending.draft.identity, context: context) {
                if let text = job.metadataJSON, let existing = try? ObservationReanalysisPreparationIntent.decode(Data(text.utf8)) {
                    guard existing == pending else { throw IntegrityError.conflict }
                    try validatePending(pending, row: row, job: job, context: context)
                    return nil
                }
                let ready = try restoreDraft(pending.draft, row: row, job: job)
                switch ready {
                case .draft: guard pending.action == .hold else { throw IntegrityError.conflict }
                case let .submitted(saved): guard saved.preparation == pending else { throw IntegrityError.conflict }
                case .bound: break
                }
                return ready
            }
            try insert(pending.draft.identity, paths: pending.draft.photoPaths, metadata: pending.storedData(), context: context)
            return nil
        }
    }

    /// Both calls run while the filesystem lock is held. No absent pair may be reinserted.
    @MainActor
    static func validatePreparation(_ proof: ObservationReanalysisPreparationIntent.Verified, container: ModelContainer,
                                    isCurrent: () -> Bool,
                                    makeReady: Bool = false,
                                    save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let pending = proof.pending
        return try transaction(pending.draft.identity, container: container, isCurrent: isCurrent, save: save) { context in
            try proof.validate(context: context)
            guard let (row, job) = try pair(pending.draft.identity, context: context) else { throw IntegrityError.unavailable }
            try validatePending(pending, row: row, job: job, context: context)
            if makeReady {
                guard let text = String(bytes: try pending.readyData(), encoding: .utf8) else { throw IntegrityError.conflict }
                job.metadataJSON = text
            }
        }
    }

    @MainActor
    static func validatePending(_ pending: ObservationReanalysisPreparationIntent, row: OfflineQueuedScan,
                                job: OfflineJobRecord, context: ModelContext) throws {
        let draft = pending.draft, child = draft.identity.analysisID.uuidString.lowercased()
        guard try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(draft.identity.analysisID)) == nil,
              let text = job.metadataJSON, try ObservationReanalysisPreparationIntent.decode(Data(text.utf8)) == pending,
              row.work == .reanalysis(draft.identity), row.id == child, row.inferenceImagePaths == draft.photoPaths,
              row.queueNeedsAttention, ScanQueueState(rawValue: row.scanStateRaw) != nil,
              row.queueAttemptCount == 0, row.queueNextRetryAt == nil,
              job.id == OfflineQueueManager.scanIngestionJobId(scanId: child), job.subjectId == child,
              job.kindRaw == OfflineJobKind.observationReanalysisSync.rawValue,
              job.statusRaw == OfflineJobStatus.needsAttention.rawValue, job.attemptCount == 0,
              job.lastAttemptAt == nil, job.nextRunAt == nil else { throw IntegrityError.conflict }
    }
}
