import Foundation
import SwiftData

/// Atomic qualified queue staging. No network, funding, file mutation or selection effects.
enum ObservationReanalysisPersistence {
    enum IntegrityError: Error { case conflict, unavailable, accountChanged }
    struct Stored: Sendable {
        let intent: ObservationReanalysisIntent
        let status: OfflineJobStatus
        var isTerminal: Bool { status == .complete || status == .cancelled }
    }

    enum DraftState: Sendable {
        case draft(ObservationReanalysisDraft)
        case bound(Stored)
    }

    /// Caller has durably copied verified input files. All work stays held until execution is connected.
    @MainActor
    static func stage(_ intent: ObservationReanalysisIntent, container: ModelContainer,
                      isCurrent: () -> Bool, validateNew: (ModelContext) throws -> Void = { _ in },
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Stored {
        try transaction(intent.identity, container: container, isCurrent: isCurrent, save: save) { context in
            if let (row, job) = try pair(intent.identity, context: context) {
                let stored = try restore(row: row, job: job)
                guard stored.intent == intent else { throw IntegrityError.conflict }
                return stored
            }
            try validateNew(context)
            try insert(intent.identity, paths: intent.photoPaths, metadata: intent.storedData(), context: context)
            return Stored(intent: intent, status: .needsAttention)
        }
    }

    /// No recipient, funding or network operation is needed to persist the original offline identity.
    @MainActor
    static func stageDraft(_ draft: ObservationReanalysisDraft, container: ModelContainer,
                           isCurrent: () -> Bool, validateSource: (ModelContext) throws -> Void = { _ in },
                           save: (ModelContext) throws -> Void = { try $0.save() }) throws -> DraftState {
        try transaction(draft.identity, container: container, isCurrent: isCurrent, save: save) { context in
            try validateSource(context)
            if let (row, job) = try pair(draft.identity, context: context) {
                return try restoreDraft(draft, row: row, job: job)
            }
            try insert(draft.identity, paths: draft.photoPaths, metadata: draft.storedData(), context: context)
            return .draft(draft)
        }
    }

    /// Compare-and-save exactly once. A stale draft cannot overwrite a bound request or revive work.
    @MainActor
    static func bindDraft(_ expected: ObservationReanalysisDraft, processor: IdentificationRecipientExpectation,
                          container: ModelContainer, isCurrent: () -> Bool,
                          save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Stored {
        // recoveryOnly cannot reconstruct the immutable request or authorize provider work.
        let candidate = try expected.binding(processor: processor)
        return try transaction(expected.identity, container: container, isCurrent: isCurrent, save: save) { context in
            guard let (row, job) = try pair(expected.identity, context: context) else { throw IntegrityError.unavailable }
            switch try restoreDraft(expected, row: row, job: job) {
            case let .bound(stored):
                guard stored.intent == candidate else { throw IntegrityError.conflict }
                return stored
            case .draft:
                guard let metadata = String(bytes: try candidate.storedData(), encoding: .utf8) else { throw IntegrityError.conflict }
                job.metadataJSON = metadata
                return Stored(intent: candidate, status: .needsAttention)
            }
        }
    }

    static func restoreDraft(_ expected: ObservationReanalysisDraft, row: OfflineQueuedScan, job: OfflineJobRecord) throws -> DraftState {
        guard let text = job.metadataJSON else { throw IntegrityError.conflict }
        // Version 1 has a full request; its strict decoder rejects all draft and unknown envelopes.
        if let bound = try? ObservationReanalysisIntent.decode(Data(text.utf8)) {
            let stored = try restore(row: row, job: job)
            guard bound.identity == expected.identity, bound.request.evidence == expected.evidence else { throw IntegrityError.conflict }
            return .bound(stored)
        }
        let draft = try ObservationReanalysisDraft.decode(Data(text.utf8))
        let childID = draft.identity.analysisID.uuidString.lowercased()
        guard draft == expected, row.work == .reanalysis(draft.identity), row.id == childID,
              row.inferenceImagePaths == draft.photoPaths, row.queueNeedsAttention,
              ScanQueueState(rawValue: row.scanStateRaw) != nil, row.queueAttemptCount == 0, row.queueNextRetryAt == nil,
              job.id == OfflineQueueManager.scanIngestionJobId(scanId: childID), job.subjectId == childID,
              job.kindRaw == OfflineJobKind.observationReanalysisSync.rawValue,
              job.statusRaw == OfflineJobStatus.needsAttention.rawValue,
              job.attemptCount == 0, job.lastAttemptAt == nil, job.nextRunAt == nil else { throw IntegrityError.conflict }
        return .draft(draft)
    }

    @MainActor
    static func transaction<T>(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer, isCurrent: () -> Bool,
                               save: (ModelContext) throws -> Void, body: (ModelContext) throws -> T) throws -> T {
        try ConfirmedSpeciesReviewPersistence.transaction {
            guard isCurrent() else { throw IntegrityError.accountChanged }
            let context = ModelContext(container); context.autosaveEnabled = false
            do {
                let lower = identity.analysisID.uuidString.lowercased(), upper = identity.analysisID.uuidString
                guard try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(identity.analysisID)) == nil,
                      try (lower == upper || context.fetchOfflineJob(id: "reanalysis-erasure:" + upper) == nil) else {
                    throw IntegrityError.unavailable
                }
                let scan = try ObservationHistorySyncService.enrolledScan(identity.observationID.uuidString, context: context)
                guard scan.analysisOwnerAccountID == identity.ownerID.uuidString.lowercased(),
                      !(try ObservationHistoryEnrollmentIntent.holds(scan.id, context: context)) else { throw IntegrityError.unavailable }
                let sourceID = identity.sourceAnalysisID.uuidString.lowercased()
                var query = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == sourceID })
                query.fetchLimit = 1
                guard let source = try context.fetch(query).first,
                      source.ownerAccountID == scan.analysisOwnerAccountID, source.observationID == scan.id else { throw IntegrityError.unavailable }
                let result = try body(context)
                try Task.checkCancellation()
                guard isCurrent() else { throw IntegrityError.accountChanged }
                if context.hasChanges { try save(context) }
                return result
            } catch { context.rollback(); throw error }
        }
    }

    @MainActor
    static func pair(_ identity: OfflineQueueWork.Reanalysis, context: ModelContext) throws -> (OfflineQueuedScan, OfflineJobRecord)? {
        let lower = identity.analysisID.uuidString.lowercased(), upper = identity.analysisID.uuidString
        let rows = try context.fetch(FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == lower || $0.id == upper }))
        let job = try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: lower))
        if rows.isEmpty && job == nil { return nil }
        guard rows.count == 1, let row = rows.first, let job else { throw IntegrityError.conflict }
        return (row, job)
    }

    @MainActor
    static func insert(_ identity: OfflineQueueWork.Reanalysis, paths: [String], metadata: Data, context: ModelContext) throws {
        let lower = identity.analysisID.uuidString.lowercased(), upper = identity.analysisID.uuidString
        guard try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(identity.analysisID)) == nil,
              try context.fetch(FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })).isEmpty,
              try context.fetch(FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })).isEmpty,
              try context.fetch(FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == lower || $0.scanId == upper })).isEmpty,
              !(try ObservationHistoryEnrollmentIntent.holds(lower, context: context)),
              try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: upper)) == nil,
              let text = String(bytes: metadata, encoding: .utf8) else { throw IntegrityError.conflict }
        let row = OfflineQueuedScan(id: lower, inferenceImagePaths: paths, queueNeedsAttention: true)
        row.workKindRaw = "reanalysis"
        row.parentObservationID = identity.observationID.uuidString.lowercased()
        row.sourceAnalysisID = identity.sourceAnalysisID.uuidString.lowercased()
        row.reanalysisOwnerAccountID = identity.ownerID.uuidString.lowercased()
        guard row.work == .reanalysis(identity) else { throw IntegrityError.conflict }
        context.insert(row)
        context.insert(OfflineJobRecord(id: OfflineQueueManager.scanIngestionJobId(scanId: lower), kind: .observationReanalysisSync,
            subjectId: lower, status: .needsAttention, metadataJSON: text))
    }

    static func restore(row: OfflineQueuedScan, job: OfflineJobRecord) throws -> Stored {
        guard let metadata = job.metadataJSON,
              job.kindRaw == OfflineJobKind.observationReanalysisSync.rawValue,
              let status = OfflineJobStatus(rawValue: job.statusRaw) else { throw IntegrityError.conflict }
        let intent = try ObservationReanalysisIntent.decode(Data(metadata.utf8))
        let childID = intent.request.analysisID.uuidString.lowercased()
        guard row.work == .reanalysis(intent.identity), row.id == childID,
              row.inferenceImagePaths == intent.photoPaths,
              job.id == OfflineQueueManager.scanIngestionJobId(scanId: childID), job.subjectId == childID,
              ScanQueueState(rawValue: row.scanStateRaw) != nil,
              job.attemptCount >= 0, row.queueAttemptCount >= 0 else { throw IntegrityError.conflict }
        if [.complete, .cancelled, .needsAttention].contains(status) {
            guard job.nextRunAt == nil else { throw IntegrityError.conflict }
        }
        return Stored(intent: intent, status: status)
    }
}
