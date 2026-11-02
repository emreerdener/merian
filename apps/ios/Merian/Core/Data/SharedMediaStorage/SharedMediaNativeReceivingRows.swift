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
            contractVersion: value.format.rawValue, digestVersion: 1, cohortSHA256: try value.digest(),
            executionKindRaw: value.executionKind, inferenceGeneration: value.inferenceGeneration)
        consumer.cohortData = try value.encoded()
        let queue = OfflineQueuedScan(id: value.originQueueID, timestamp: r.timestamp,
            scanState: .pending, queueUpdatedAt: r.timestamp, queueNeedsAttention: true)
        queue.mediaAuthorityRaw = value.queueAuthority; queue.sharedMediaConsumerID = value.bindingID
        let job = OfflineJobRecord(id: r.jobID, kind: .scanIngestion, subjectId: value.originQueueID,
            priority: 0, status: .needsAttention, createdAt: r.timestamp, updatedAt: r.timestamp,
            requiresUnconstrainedNetwork: false, allowsCellular: false, approximateBytes: r.package.allocated,
            metadataJSON: r.metadata)
        let event = OfflineQueueEvent(id: r.eventID, jobId: r.jobID, scanId: value.originQueueID,
            kind: .needsAttention, createdAt: r.timestamp, metadataJSON: r.metadata)
        c.insert(consumer); c.insert(queue); c.insert(job); c.insert(event)
        return Set(consumer: consumer, queue: queue, job: job, event: event)
    }

    /// Descriptive collision keys cannot construct an executable receiving request.
    struct CollisionKey {
        let packageID: UUID, bindingID: UUID
        let queueID: String, observationID: String, eventID: String
        init(_ prepared: SharedMediaNativeReceivingIntent.Prepared) {
            packageID = prepared.package.id; bindingID = prepared.bindingID
            queueID = prepared.queueID.uuidString.lowercased()
            observationID = prepared.observationID.uuidString.lowercased()
            eventID = prepared.eventID.uuidString.lowercased()
        }
        init(_ abandoned: SharedMediaNativeReceivingIntent.Abandoned) {
            packageID = abandoned.package.id; bindingID = abandoned.bindingID
            queueID = abandoned.queueID.uuidString.lowercased()
            observationID = abandoned.observationID.uuidString.lowercased()
            eventID = abandoned.eventID.uuidString.lowercased()
        }
        init(_ plan: SharedMediaNativeReceivingReleaseValues.Plan) {
            packageID = plan.package.id; bindingID = plan.bindingID
            queueID = plan.queueID.uuidString.lowercased()
            observationID = plan.observationID.uuidString.lowercased()
            eventID = plan.eventID.uuidString.lowercased()
        }
        fileprivate init(_ request: SharedMediaNativeReceivingIntent.Transaction) {
            packageID = request.package.id; bindingID = request.cohort.bindingID
            queueID = request.cohort.originQueueID; observationID = request.cohort.observationID
            eventID = request.eventID
        }
    }
    private struct Matches {
        let consumers: [SharedMediaConsumerRecord], queues: [OfflineQueuedScan]
        let jobs: [OfflineJobRecord], events: [OfflineQueueEvent]
        var isEmpty: Bool { consumers.isEmpty && queues.isEmpty && jobs.isEmpty && events.isEmpty }
    }
    static func requireAbsent(_ key: CollisionKey, in context: ModelContext) throws {
        guard try matches(key, in: context).isEmpty else { throw SharedMediaStorageFailure.conflict }
    }
    /// Collision checks include canonical aliases and every reverse identity join.
    private static func matches(_ key: CollisionKey, in c: ModelContext) throws -> Matches {
        let identities = Array(Swift.Set([key.queueID, key.observationID].flatMap { [$0, $0.uppercased()] }))
        let bindingID = key.bindingID, packageID = key.packageID
        let jobIDs = identities.map { "scan-ingestion:" + $0 }, eventIDs = [key.eventID, key.eventID.uppercased()]
        let consumers = try fetch(c, FetchDescriptor<SharedMediaConsumerRecord>(predicate: #Predicate {
            $0.id == bindingID || $0.packageID == packageID || identities.contains($0.consumerID) ||
                identities.contains($0.originQueueID) || identities.contains($0.observationID)
        }))
        let queues = try queueMatches(key, in: c)
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
        return .init(consumers: consumers, queues: queues, jobs: jobs, events: events)
    }
    /// Freshness only, after the caller's full graph validation. Reuse the exact
    /// collision predicate, including pending aliases and reverse bindings.
    static func requireRecoveryPresentation(_ expected: Data?, request: SharedMediaNativeReceivingIntent.Transaction,
                                            in context: ModelContext) throws {
        guard try recoveryPresentationBytes(request: request, in: context) == expected else { throw SharedMediaStorageFailure.stale }
    }

    /// A present queue with nil bytes is distinct from a missing queue. This
    /// bounded descriptive read never replaces full receiving validation.
    static func recoveryPresentationBytes(request: SharedMediaNativeReceivingIntent.Transaction,
                                          in context: ModelContext) throws -> Data? {
        let found = try queueMatches(.init(request), in: context)
        guard found.count == 1, let queue = found.first,
              queue.id == request.cohort.originQueueID,
              queue.sharedMediaConsumerID == request.cohort.bindingID else { throw SharedMediaStorageFailure.stale }
        return queue.recoveryPresentationData
    }

    private static func queueMatches(_ key: CollisionKey, in context: ModelContext) throws -> [OfflineQueuedScan] {
        let identities = Array(Swift.Set([key.queueID, key.observationID].flatMap { [$0, $0.uppercased()] }))
        let bindingID = key.bindingID
        return try fetch(context, FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate {
            identities.contains($0.id) || $0.sharedMediaConsumerID == bindingID
        }))
    }

    static func read(_ r: SharedMediaNativeAppReceivingRequest, in c: ModelContext, absent: Bool) throws -> Set? {
        try read(.init(r), in: c, absent: absent)
    }
    static func read(_ r: SharedMediaNativeReceivingIntent.Transaction, in c: ModelContext, absent: Bool) throws -> Set? {
        let found = try matches(.init(r), in: c)
        if absent {
            guard found.isEmpty else { throw SharedMediaStorageFailure.conflict }
            return nil
        }
        guard found.consumers.count == 1, found.queues.count == 1, found.jobs.count == 1, found.events.count == 1,
              let consumer = found.consumers.first, let queue = found.queues.first,
              let job = found.jobs.first, let event = found.events.first else { throw SharedMediaStorageFailure.conflict }
        let rows = Set(consumer: consumer, queue: queue, job: job, event: event)
        try validate(rows, request: r)
        return rows
    }

    static func validate(_ rows: Set, request r: SharedMediaNativeAppReceivingRequest) throws {
        try validate(rows, request: SharedMediaNativeReceivingIntent.Transaction(r))
    }
    static func validate(_ rows: Set, request r: SharedMediaNativeReceivingIntent.Transaction) throws {
        let consumer = rows.consumer, queue = rows.queue, job = rows.job, event = rows.event, value = r.cohort
        guard consumer.id == value.bindingID, consumer.cursorKey == value.bindingID.uuidString.lowercased(),
              consumer.kindRaw == "queue", consumer.consumerID == value.originQueueID,
              consumer.originQueueID == value.originQueueID, consumer.observationID == value.observationID,
              consumer.inventoryID == r.profile.inventoryID, consumer.inventoryGeneration == r.profile.generation,
              consumer.ownerID == r.profile.ownerID, consumer.packageID == r.package.id,
              consumer.draftGeneration == r.package.generation, consumer.frozenPackageRevision == (try r.freeze.commit.packageRevision),
              consumer.contractVersion == value.format.rawValue, consumer.digestVersion == 1,
              consumer.cohortData == (try value.encoded()), consumer.cohortSHA256 == (try value.digest()),
              consumer.executionKindRaw == "ordinaryV1", consumer.inferenceGeneration == value.inferenceGeneration,
              consumer.retirementID == nil, consumer.lifecycleRaw == "active", consumer.revision == 0 else { throw SharedMediaStorageFailure.conflict }
        guard queue.id == value.originQueueID, queue.timestamp == r.timestamp, queue.queueUpdatedAt == r.timestamp,
              queue.mediaAuthorityRaw == value.queueAuthority, queue.sharedMediaConsumerID == value.bindingID,
              queue.workKindRaw == "ordinary", queue.parentObservationID == nil, queue.sourceAnalysisID == nil,
              queue.reanalysisOwnerAccountID == nil, queue.scanStateRaw == ScanQueueState.pending.rawValue,
              queue.queueNeedsAttention, queue.queueAttemptCount == 0, queue.queueSchemaRepairGeneration == 1,
              queue.recoveryPresentationData == nil, queue.capturedMediaJSON == nil, queue.capturedMediaEntries?.isEmpty != false,
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
    /// Descriptive companion only. Callers still validate the complete receiving
    /// set; this never relaxes the nil-only admission guard above.
    nonisolated static func recoveryPresentation(_ data: Data?, prepared: SharedMediaNativeReceivingIntent.Prepared) throws
        -> AnalysisRecoveryPresentation.StorageLiability {
        try AnalysisRecoveryPresentation.storageLiability(data, identity: .init(
            ownerID: prepared.profile.ownerID, observationID: prepared.observationID,
            operationID: prepared.operationID))
    }

    private static func fetch<T: PersistentModel>(_ c: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> [T] {
        var query = descriptor; query.fetchLimit = 2; query.includePendingChanges = true
        return try c.fetch(query)
    }
}
