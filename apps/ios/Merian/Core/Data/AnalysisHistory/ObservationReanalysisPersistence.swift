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

    /// Caller has already durably copied verified input files to intent.photoPaths.
    /// Kept held until the dedicated execution owner is connected; ordinary workers cannot adopt it.
    @MainActor
    static func stage(_ intent: ObservationReanalysisIntent, container: ModelContainer,
                      isCurrent: () -> Bool, validateNew: (ModelContext) throws -> Void = { _ in },
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Stored {
        try ConfirmedSpeciesReviewPersistence.transaction {
            guard isCurrent() else { throw IntegrityError.accountChanged }
            let context = ModelContext(container); context.autosaveEnabled = false
            do {
                let scan = try ObservationHistorySyncService.enrolledScan(intent.request.observationID.uuidString, context: context)
                guard scan.analysisOwnerAccountID == intent.ownerID.uuidString.lowercased(),
                      !(try ObservationHistoryEnrollmentIntent.holds(scan.id, context: context)) else {
                    throw IntegrityError.unavailable
                }
                let sourceID = intent.request.sourceAnalysisID.uuidString.lowercased()
                var sourceQuery = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == sourceID })
                sourceQuery.fetchLimit = 1
                guard let source = try context.fetch(sourceQuery).first,
                      source.ownerAccountID == scan.analysisOwnerAccountID, source.observationID == scan.id else {
                    throw IntegrityError.unavailable
                }
                let lower = intent.request.analysisID.uuidString.lowercased(), upper = intent.request.analysisID.uuidString
                let rows = try context.fetch(FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == lower || $0.id == upper }))
                let job = try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: lower))
                let result: Stored
                if !rows.isEmpty || job != nil {
                    guard rows.count == 1, let row = rows.first, let job else { throw IntegrityError.conflict }
                    result = try restore(row: row, job: job)
                    guard result.intent == intent else { throw IntegrityError.conflict }
                    // Recovery never clears holds, resets attempts, or revives a terminal job.
                } else {
                    guard try context.fetch(FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })).isEmpty,
                          try context.fetch(FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })).isEmpty,
                          try context.fetch(FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == lower || $0.scanId == upper })).isEmpty,
                          !(try ObservationHistoryEnrollmentIntent.holds(lower, context: context)),
                          try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: upper)) == nil else {
                        throw IntegrityError.conflict
                    }
                    try validateNew(context)
                    let row = OfflineQueuedScan(id: lower, inferenceImagePaths: intent.photoPaths, queueNeedsAttention: true)
                    row.workKindRaw = "reanalysis"
                    row.parentObservationID = intent.request.observationID.uuidString.lowercased()
                    row.sourceAnalysisID = sourceID
                    row.reanalysisOwnerAccountID = intent.ownerID.uuidString.lowercased()
                    guard row.work == .reanalysis(intent.identity) else { throw IntegrityError.conflict }
                    guard let metadata = String(bytes: try intent.storedData(), encoding: .utf8) else {
                        throw IntegrityError.conflict
                    }
                    context.insert(row)
                    context.insert(OfflineJobRecord(id: OfflineQueueManager.scanIngestionJobId(scanId: lower), kind: .observationReanalysisSync,
                        subjectId: lower, status: .needsAttention, metadataJSON: metadata))
                    result = Stored(intent: intent, status: .needsAttention)
                }
                try Task.checkCancellation()
                guard isCurrent() else { throw IntegrityError.accountChanged }
                if context.hasChanges { try save(context) }
                return result
            } catch { context.rollback(); throw error }
        }
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
