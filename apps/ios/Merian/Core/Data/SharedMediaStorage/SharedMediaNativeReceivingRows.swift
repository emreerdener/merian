import Foundation
import SwiftData

/// Exact ordinary-photo receiving set. No scheduler, legacy queue helper, or
/// relationship repair is called here. The owning transaction supplies all IDs.
@MainActor
enum SharedMediaNativeReceivingRows {
    struct Set {
        let consumer: SharedMediaConsumerRecord
        let queue: OfflineQueuedScan
        let job: OfflineJobRecord
        let event: OfflineQueueEvent
        var identities: Swift.Set<PersistentIdentifier> {
            [consumer.persistentModelID, queue.persistentModelID, job.persistentModelID, event.persistentModelID]
        }
    }
    static func insert(_ r: SharedMediaNativeAppReceivingRequest, in c: ModelContext) throws -> Set {
        let value = r.cohort, commit = r.freeze.commit
        let consumer = SharedMediaConsumerRecord(id: value.bindingID, kindRaw: "queue", consumerID: value.originQueueID,
            originQueueID: value.originQueueID, observationID: value.observationID, inventoryID: commit.inventoryID,
            inventoryGeneration: commit.inventoryGeneration, ownerID: r.profile.ownerID, packageID: r.package.id,
            draftGeneration: r.package.generation, frozenPackageRevision: try commit.packageRevision,
            contractVersion: SharedMediaNativeConsumerGraph.contract, digestVersion: 1, cohortSHA256: try value.digest(),
            executionKindRaw: value.executionKind, inferenceGeneration: value.inferenceGeneration)
        consumer.cohortData = try value.encoded()
        let queue = OfflineQueuedScan(id: value.originQueueID, timestamp: r.timestamp,
            scanState: .pending, queueUpdatedAt: r.timestamp, queueNeedsAttention: true)
        queue.mediaAuthorityRaw = "sharedDirectNativeReceivingV1"; queue.sharedMediaConsumerID = value.bindingID
        let job = OfflineJobRecord(id: r.jobID, kind: .scanIngestion, subjectId: value.originQueueID,
            priority: 0, status: .needsAttention, createdAt: r.timestamp, updatedAt: r.timestamp,
            requiresUnconstrainedNetwork: false, allowsCellular: false, approximateBytes: r.package.allocated,
            metadataJSON: r.metadata)
        let event = OfflineQueueEvent(id: r.eventID, jobId: r.jobID, scanId: value.originQueueID,
            kind: .needsAttention, createdAt: r.timestamp, metadataJSON: r.metadata)
        c.insert(consumer); c.insert(queue); c.insert(job); c.insert(event)
        return Set(consumer: consumer, queue: queue, job: job, event: event)
    }

    /// Collision checks include the canonical aliases and reverse identity joins.
    /// Exact recovery happens first; no partial set can enter fresh insertion.
    static func read(_ r: SharedMediaNativeAppReceivingRequest, in c: ModelContext, absent: Bool) throws -> Set? {
        let identities = Array(Swift.Set([r.cohort.originQueueID, r.cohort.observationID].flatMap { [$0, $0.uppercased()] }))
        let bindingID = r.cohort.bindingID, packageID = r.package.id
        let jobIDs = identities.map { "scan-ingestion:" + $0 }, eventIDs = [r.eventID, r.eventID.uppercased()]
        let consumers = try fetch(c, FetchDescriptor<SharedMediaConsumerRecord>(predicate: #Predicate {
            $0.id == bindingID || $0.packageID == packageID || identities.contains($0.consumerID) ||
                identities.contains($0.originQueueID) || identities.contains($0.observationID)
        }))
        let queues = try fetch(c, FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate {
            identities.contains($0.id) || $0.sharedMediaConsumerID == bindingID
        }))
        let jobs = try fetch(c, FetchDescriptor<OfflineJobRecord>(predicate: #Predicate {
            jobIDs.contains($0.id) || ($0.subjectId != nil && identities.contains($0.subjectId!))
        }))
        let events = try fetch(c, FetchDescriptor<OfflineQueueEvent>(predicate: #Predicate {
            eventIDs.contains($0.id) || ($0.scanId != nil && identities.contains($0.scanId!)) ||
                ($0.jobId != nil && jobIDs.contains($0.jobId!))
        }))
        guard try fetch(c, FetchDescriptor<LocalScanRecord>(predicate: #Predicate {
            identities.contains($0.id) || $0.sharedMediaConsumerID == bindingID
        })).isEmpty,
              try fetch(c, FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate {
            identities.contains($0.id) || identities.contains($0.observationID) || $0.sharedMediaConsumerID == bindingID
        })).isEmpty else { throw SharedMediaStorageFailure.conflict }
        if absent {
            guard consumers.isEmpty, queues.isEmpty, jobs.isEmpty, events.isEmpty else { throw SharedMediaStorageFailure.conflict }
            return nil
        }
        guard consumers.count == 1, queues.count == 1, jobs.count == 1, events.count == 1,
              let consumer = consumers.first, let queue = queues.first, let job = jobs.first, let event = events.first else {
            throw SharedMediaStorageFailure.conflict
        }
        let rows = Set(consumer: consumer, queue: queue, job: job, event: event)
        try validate(rows, request: r)
        return rows
    }

    static func validate(_ rows: Set, request r: SharedMediaNativeAppReceivingRequest) throws {
        let consumer = rows.consumer, queue = rows.queue, job = rows.job, event = rows.event, value = r.cohort
        guard consumer.id == value.bindingID, consumer.cursorKey == value.bindingID.uuidString.lowercased(),
              consumer.kindRaw == "queue", consumer.consumerID == value.originQueueID,
              consumer.originQueueID == value.originQueueID, consumer.observationID == value.observationID,
              consumer.inventoryID == r.profile.inventoryID, consumer.inventoryGeneration == r.profile.generation,
              consumer.ownerID == r.profile.ownerID, consumer.packageID == r.package.id,
              consumer.draftGeneration == r.package.generation, consumer.frozenPackageRevision == (try r.freeze.commit.packageRevision),
              consumer.contractVersion == SharedMediaNativeConsumerGraph.contract, consumer.digestVersion == 1,
              consumer.cohortData == (try value.encoded()), consumer.cohortSHA256 == (try value.digest()),
              consumer.executionKindRaw == "ordinaryV1", consumer.inferenceGeneration == value.inferenceGeneration,
              consumer.retirementID == nil, consumer.lifecycleRaw == "active", consumer.revision == 0 else { throw SharedMediaStorageFailure.conflict }
        guard queue.id == value.originQueueID, queue.timestamp == r.timestamp, queue.queueUpdatedAt == r.timestamp,
              queue.mediaAuthorityRaw == "sharedDirectNativeReceivingV1", queue.sharedMediaConsumerID == value.bindingID,
              queue.workKindRaw == "ordinary", queue.parentObservationID == nil, queue.sourceAnalysisID == nil,
              queue.reanalysisOwnerAccountID == nil, queue.scanStateRaw == ScanQueueState.pending.rawValue,
              queue.queueNeedsAttention, queue.queueAttemptCount == 0, queue.queueSchemaRepairGeneration == 1,
              queue.capturedMediaJSON == nil, queue.capturedMediaEntries?.isEmpty != false,
              queue.coverImagePath == nil, queue.inferenceImagePaths == nil, queue.visualMediaItemsJSON == nil,
              queue.fieldNotes == nil, queue.stagedR2Keys == nil, queue.queueLastAttemptAt == nil,
              queue.queueNextRetryAt == nil, queue.queueLastErrorCode == nil, queue.queueLastErrorMessage == nil,
              queue.queueLastHTTPStatus == nil, queue.queueLastServerStatus == nil, queue.queueLastServerStage == nil,
              queue.queueLastServerRetryAfter == nil, queue.gpsLatitude == nil, queue.gpsLongitude == nil,
              queue.gpsElevation == nil, queue.weatherCondition == nil, queue.weatherTemperatureF == nil,
              queue.blurScore == nil, queue.subjectDistanceInMeters == nil, queue.locationName == nil,
              queue.isFlashFired == nil, queue.cameraPitchDegrees == nil, queue.compassHeading == nil,
              queue.relativeHumidity == nil, queue.uvIndex == nil, queue.zoomFactor == nil else { throw SharedMediaStorageFailure.conflict }
        guard job.id == r.jobID, job.kindRaw == OfflineJobKind.scanIngestion.rawValue, job.subjectId == value.originQueueID,
              job.priority == 0, job.statusRaw == OfflineJobStatus.needsAttention.rawValue,
              job.createdAt == r.timestamp, job.updatedAt == r.timestamp, job.lastAttemptAt == nil,
              job.nextRunAt == nil, job.attemptCount == 0, job.lastErrorCode == nil, job.lastErrorMessage == nil,
              job.lastHTTPStatus == nil, job.serverStatus == nil, job.serverStage == nil, job.serverRetryAfter == nil,
              !job.requiresUnconstrainedNetwork, !job.allowsCellular, job.approximateBytes == r.package.allocated,
              job.metadataJSON == r.metadata else { throw SharedMediaStorageFailure.conflict }
        guard event.id == r.eventID, event.jobId == r.jobID, event.scanId == value.originQueueID,
              event.kindRaw == OfflineQueueEventKind.needsAttention.rawValue, event.createdAt == r.timestamp,
              event.message == nil, event.errorCode == nil, event.httpStatus == nil, event.metadataJSON == r.metadata else {
            throw SharedMediaStorageFailure.conflict
        }
    }
    private static func fetch<T: PersistentModel>(_ c: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> [T] {
        var query = descriptor; query.fetchLimit = 2; query.includePendingChanges = true
        return try c.fetch(query)
    }
}
