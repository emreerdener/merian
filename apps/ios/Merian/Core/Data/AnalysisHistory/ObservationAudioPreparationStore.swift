import Foundation
import SwiftData

/// Uses the V58 qualified child and erasure namespace; saved photo envelopes stay unchanged.
@MainActor
enum ObservationAudioPreparationStore {
    private typealias Persistence = ObservationReanalysisPersistence
    typealias Phase = ObservationAudioPreparation.Phase

    static func begin(_ proof: ObservationAudioPreparation.Verified, container: ModelContainer, isCurrent: () -> Bool,
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Phase {
        let preparation = proof.preparation
        return try Persistence.transaction(preparation.identity, container: container, isCurrent: isCurrent, save: save) { context in
            try proof.validate(context: context)
            if let (row, job) = try Persistence.pair(preparation.identity, context: context) {
                return try restore(preparation, row: row, job: job)
            }
            try Persistence.insert(preparation.identity, paths: [], metadata: preparation.storedData(phase: .pending), context: context)
            guard let (row, _) = try Persistence.pair(preparation.identity, context: context) else { throw Persistence.IntegrityError.conflict }
            row.inferenceImagePaths = nil
            row.replaceCapturedMedia(with: preparation.media)
            return .pending
        }
    }

    /// Called only from the file owner's locked boundaries; never recreates deleted work.
    static func validate(_ proof: ObservationAudioPreparation.Verified, container: ModelContainer, isCurrent: () -> Bool,
                         expectedPhase: Phase = .pending, makeReady: Bool = false, save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let preparation = proof.preparation
        try Persistence.transaction(preparation.identity, container: container, isCurrent: isCurrent, save: save) { context in
            try proof.validate(context: context)
            guard let (row, job) = try Persistence.pair(preparation.identity, context: context),
                  try restore(preparation, row: row, job: job) == expectedPhase,
                  !makeReady || expectedPhase == .pending else { throw Persistence.IntegrityError.conflict }
            if makeReady {
                guard let text = String(bytes: try preparation.storedData(phase: preparation.preparedPhase), encoding: .utf8) else { throw Persistence.IntegrityError.conflict }
                job.metadataJSON = text
            }
        }
    }

    static func restore(_ expected: ObservationAudioPreparation, row: OfflineQueuedScan, job: OfflineJobRecord) throws -> Phase {
        guard let metadata = job.metadataJSON else { throw Persistence.IntegrityError.conflict }
        let saved = try ObservationAudioPreparation.decode(Data(metadata.utf8))
        guard saved.preparation == expected else { throw Persistence.IntegrityError.conflict }
        try validateRow(expected, row: row, job: job)
        return saved.phase
    }

    /// Shared by audio preparation and its separate bound envelope; no metadata interpretation here.
    static func validateRow(_ expected: ObservationAudioPreparation, row: OfflineQueuedScan, job: OfflineJobRecord) throws {
        let child = expected.identity.analysisID.uuidString.lowercased()
        guard row.id == child, row.work == .reanalysis(expected.identity),
              row.inferenceImagePaths == nil, row.visualMediaItemsJSON == nil, row.coverImagePath == nil,
              let json = row.capturedMediaJSON, MediaJSONParser.serializedItems(jsonString: json) == expected.media,
              CapturedMediaEntry.serializedItems(from: row.capturedMediaEntries ?? []) == expected.media,
              row.queueNeedsAttention, row.scanStateRaw == ScanQueueState.pending.rawValue,
              row.queueAttemptCount == 0, row.queueLastAttemptAt == nil, row.queueNextRetryAt == nil,
              row.stagedR2Keys == nil, row.fieldNotes == nil,
              row.queueLastErrorCode == nil, row.queueLastErrorMessage == nil, row.queueLastHTTPStatus == nil,
              row.queueLastServerStatus == nil, row.queueLastServerStage == nil, row.queueLastServerRetryAfter == nil,
              job.id == OfflineQueueManager.scanIngestionJobId(scanId: child), job.subjectId == child,
              job.kindRaw == OfflineJobKind.observationReanalysisSync.rawValue,
              job.statusRaw == OfflineJobStatus.needsAttention.rawValue,
              job.attemptCount == 0, job.lastAttemptAt == nil, job.nextRunAt == nil,
              job.lastErrorCode == nil, job.lastErrorMessage == nil, job.lastHTTPStatus == nil,
              job.serverStatus == nil, job.serverStage == nil, job.serverRetryAfter == nil else { throw Persistence.IntegrityError.conflict }
    }
}
