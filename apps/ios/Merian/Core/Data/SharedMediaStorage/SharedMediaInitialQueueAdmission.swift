import Foundation
import SwiftData

/// Shared initial queue row contract. Each media owner must separately prove
/// its complete cohort and atomically save it alongside these rows.
struct SharedMediaInitialQueueAdmission: Sendable {
    let identity: OrdinaryInitialSubmissionIdentity
    let eventIdentity: UUID
    let jobID: String
    let mediaAuthority: String
    let metadata: OrdinaryInitialJobMetadata
    let timestamp: Date
    let telemetry: CaptureTelemetry
    let blurScore: Double?
    let preferredGoal: FieldTripPreferredGoal?
    let fieldNotes: String?
    let approximateBytes: Int64

    @MainActor
    struct Rows {
        let scan: OfflineQueuedScan
        let job: OfflineJobRecord
        let event: OfflineQueueEvent
        let goal: ActiveOfflineQueuedScanGoalHint?
        var identities: Set<PersistentIdentifier> {
            var ids: Set<PersistentIdentifier> = [scan.persistentModelID, job.persistentModelID, event.persistentModelID]
            if let goal { ids.insert(goal.persistentModelID) }
            return ids
        }
    }

    private var scanID: String { identity.scanID.uuidString.lowercased() }
    private var eventID: String { eventIdentity.uuidString.lowercased() }
    private var message: String { "Queued observation with retained originals." }

    @MainActor
    func makeRows() -> Rows {
        let scan = OfflineQueuedScan(id: scanID, timestamp: timestamp,
            gpsLatitude: telemetry.gpsLatitude, gpsLongitude: telemetry.gpsLongitude, gpsElevation: telemetry.gpsElevation,
            weatherCondition: telemetry.weatherCondition, weatherTemperatureF: telemetry.weatherTemperatureF,
            blurScore: blurScore, subjectDistanceInMeters: telemetry.subjectDistanceInMeters,
            locationName: telemetry.locationName, zoomFactor: telemetry.zoomFactor.map(Double.init),
            fieldNotes: fieldNotes, queueUpdatedAt: timestamp)
        scan.mediaAuthorityRaw = mediaAuthority
        let job = OfflineJobRecord(id: jobID, kind: .scanIngestion, subjectId: scanID,
            priority: 100, createdAt: timestamp, updatedAt: timestamp, approximateBytes: approximateBytes, metadataJSON: metadata.json)
        let event = OfflineQueueEvent(id: eventID, jobId: jobID, scanId: scanID,
            kind: .queued, createdAt: timestamp, message: message)
        let goal = preferredGoal.map { ActiveOfflineQueuedScanGoalHint(scanId: scanID,
            userFieldTripId: $0.userFieldTripId, itemId: $0.itemId) }
        return .init(scan: scan, job: job, event: event, goal: goal)
    }

    /// Detect uniqueness collisions before insertion. Uppercase legacy scan IDs
    /// are the same logical identity and cannot authorize a second queue row.
    @MainActor
    func requireAbsent(in context: ModelContext) throws {
        let rows = try matching(context)
        guard rows.scans.isEmpty, rows.jobs.isEmpty, rows.events.isEmpty, rows.goals.isEmpty else {
            throw SharedMediaStorageFailure.conflict
        }
        let lower = scanID, upper = identity.scanID.uuidString
        var local = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })
        var history = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.observationID == lower || $0.observationID == upper })
        var deletions = FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == lower || $0.scanId == upper })
        local.fetchLimit = 1; history.fetchLimit = 1; deletions.fetchLimit = 1
        guard try context.fetch(local).isEmpty, try context.fetch(history).isEmpty, try context.fetch(deletions).isEmpty else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    @MainActor
    func requireSaved(in context: ModelContext) throws {
        let found = try matching(context)
        guard found.scans.count == 1, found.jobs.count == 1, found.events.count == 1,
              found.goals.count == (preferredGoal == nil ? 0 : 1),
              let scan = found.scans.first, let job = found.jobs.first, let event = found.events.first else {
            throw SharedMediaStorageFailure.conflict
        }
        try requireRows(.init(scan: scan, job: job, event: event, goal: found.goals.first))
    }

    @MainActor
    func requireRows(_ rows: Rows) throws {
        let s = rows.scan, j = rows.job, e = rows.event
        guard s.id == scanID, s.mediaAuthorityRaw == mediaAuthority, s.sharedMediaConsumerID == nil,
              s.workKindRaw == "ordinary", s.parentObservationID == nil, s.sourceAnalysisID == nil,
              s.reanalysisOwnerAccountID == nil, s.timestamp == timestamp, s.recoveryPresentationData == nil,
              s.capturedMediaJSON == nil, s.capturedMediaEntries?.isEmpty == true,
              s.gpsLatitude == telemetry.gpsLatitude, s.gpsLongitude == telemetry.gpsLongitude,
              s.gpsElevation == telemetry.gpsElevation, s.weatherCondition == telemetry.weatherCondition,
              s.weatherTemperatureF == telemetry.weatherTemperatureF, s.blurScore == blurScore,
              s.subjectDistanceInMeters == telemetry.subjectDistanceInMeters, s.locationName == telemetry.locationName,
              s.isFlashFired == nil, s.cameraPitchDegrees == nil, s.compassHeading == nil,
              s.relativeHumidity == nil, s.uvIndex == nil, s.zoomFactor == telemetry.zoomFactor.map(Double.init),
              s.scanStateRaw == ScanQueueState.pending.rawValue, s.stagedR2Keys == nil,
              s.inferenceImagePaths == nil, s.visualMediaItemsJSON == nil, s.fieldNotes == fieldNotes,
              s.queueAttemptCount == 0, s.queueLastAttemptAt == nil, s.queueNextRetryAt == nil,
              s.queueLastErrorCode == nil, s.queueLastErrorMessage == nil, s.queueLastHTTPStatus == nil,
              s.queueLastServerStatus == nil, s.queueLastServerStage == nil, s.queueLastServerRetryAfter == nil,
              s.queueUpdatedAt == timestamp, !s.queueNeedsAttention, s.queueSchemaRepairGeneration == 1,
              s.coverImagePath == nil else { throw SharedMediaStorageFailure.conflict }
        guard j.id == jobID, j.kindRaw == OfflineJobKind.scanIngestion.rawValue,
              j.subjectId == scanID, j.priority == 100, j.statusRaw == OfflineJobStatus.pending.rawValue,
              j.createdAt == timestamp, j.updatedAt == timestamp, j.lastAttemptAt == nil, j.nextRunAt == nil,
              j.attemptCount == 0, j.lastErrorCode == nil, j.lastErrorMessage == nil, j.lastHTTPStatus == nil,
              j.serverStatus == nil, j.serverStage == nil, j.serverRetryAfter == nil,
              !j.requiresUnconstrainedNetwork, j.allowsCellular, j.approximateBytes == approximateBytes else {
            throw SharedMediaStorageFailure.conflict
        }
        try metadata.requireInitialReadback(j.metadataJSON)
        guard e.id == eventID, e.jobId == jobID, e.scanId == scanID,
              e.kindRaw == OfflineQueueEventKind.queued.rawValue, e.createdAt == timestamp,
              e.message == message, e.errorCode == nil, e.httpStatus == nil, e.metadataJSON == nil else {
            throw SharedMediaStorageFailure.conflict
        }
        if let goal = preferredGoal {
            guard let actual = rows.goal, actual.scanId == scanID, actual.userFieldTripId == goal.userFieldTripId,
                  actual.itemId == goal.itemId else { throw SharedMediaStorageFailure.conflict }
        } else if rows.goal != nil { throw SharedMediaStorageFailure.conflict }
    }

    @MainActor
    private struct Matches {
        let scans: [OfflineQueuedScan]
        let jobs: [OfflineJobRecord]
        let events: [OfflineQueueEvent]
        let goals: [ActiveOfflineQueuedScanGoalHint]
    }

    @MainActor
    private func matching(_ context: ModelContext) throws -> Matches {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let lower = scanID, upper = identity.scanID.uuidString, jobID = self.jobID
        let upperJob = OfflineQueueManager.scanIngestionJobId(scanId: upper)
        let event = eventID, upperEvent = eventIdentity.uuidString
        var scans = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == lower || $0.id == upper })
        var jobs = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate {
            $0.id == jobID || $0.id == upperJob || $0.subjectId == lower || $0.subjectId == upper
        })
        var events = FetchDescriptor<OfflineQueueEvent>(predicate: #Predicate {
            $0.id == event || $0.id == upperEvent || $0.scanId == lower || $0.scanId == upper || $0.jobId == jobID || $0.jobId == upperJob
        })
        var goals = FetchDescriptor<ActiveOfflineQueuedScanGoalHint>(predicate: #Predicate { $0.scanId == lower || $0.scanId == upper })
        scans.fetchLimit = 2; jobs.fetchLimit = 2; events.fetchLimit = 2; goals.fetchLimit = 2
        return .init(scans: try context.fetch(scans), jobs: try context.fetch(jobs),
            events: try context.fetch(events), goals: try context.fetch(goals))
    }
}
