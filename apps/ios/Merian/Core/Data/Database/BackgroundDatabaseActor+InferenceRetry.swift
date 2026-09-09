import Foundation
import SwiftData

extension BackgroundDatabaseActor {
    // MARK: - Inference Retry Persistence

    /// Atomically records retry accounting and retreats only the inference
    /// generation that still owns the durable job. Returning `nil` means a
    /// replacement attempt won and the caller must discard its late callback.
    func scheduleInferenceRetry(
        id scanId: String,
        expectedGeneration: UUID?,
        code: String,
        message: String?,
        delay: TimeInterval,
        resetMediaUploads: Bool = false
    ) async -> Int? {
        await ScanInferencePersistenceCoordinator.shared.acquire(scanId: scanId)
        guard !Task.isCancelled else {
            await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
            return nil
        }
        let attempt = scheduleInferenceRetryLocked(
            id: scanId,
            expectedGeneration: expectedGeneration,
            code: code,
            message: message,
            delay: delay,
            resetMediaUploads: resetMediaUploads
        )
        await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
        return attempt
    }

    private func scheduleInferenceRetryLocked(
        id scanId: String,
        expectedGeneration: UUID?,
        code: String,
        message: String?,
        delay: TimeInterval,
        resetMediaUploads: Bool
    ) -> Int? {
        guard let records = inferenceRetryRecords(
            scanId: scanId,
            expectedGeneration: expectedGeneration,
            operation: "scheduleInferenceRetry"
        ) else {
            return nil
        }
        let scan = records.scan
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let job = records.job

        let mirroredAttempt =
            reconcileMirroredInferenceState(scan: scan, job: job)
        guard !OfflineQueueManager.isCompletedServerResultRecoveryCode(
            scan.queueLastErrorCode
        ), !OfflineQueueManager.isCompletedServerResultRecoveryCode(
            job.lastErrorCode
        ) else {
            do {
                // Persist the repair even though cloud completion vetoes this
                // retry transition. The surviving job-row authority remains
                // sufficient if this save fails, so the caller still must not
                // dispatch another provider request.
                try modelContext.save()
            } catch {
                modelContext.rollback()
                MerianLog.data.error(
                    "scheduleInferenceRetry: cloud-complete mirror repair failed for \(scanId, privacy: .private): \(error, privacy: .private)"
                )
            }
            MerianLog.data.debug(
                "scheduleInferenceRetry: completed cloud result owns scanId=\(scanId, privacy: .public)"
            )
            return nil
        }
        let attempt = mirroredAttempt + 1
        let now = Date()
        let nextRetryAt = now.addingTimeInterval(max(1, delay))
        scan.queueAttemptCount = attempt
        scan.queueLastAttemptAt = now
        scan.queueNextRetryAt = nextRetryAt
        scan.queueLastErrorCode = code
        scan.queueLastErrorMessage = message
        scan.queueLastHTTPStatus = nil
        scan.queueLastServerStatus = nil
        scan.queueLastServerStage = nil
        scan.queueLastServerRetryAfter = nil
        scan.queueNeedsAttention = false
        scan.scanStateRaw = resetMediaUploads
            ? ScanQueueState.pending.rawValue
            : ScanQueueState.staged.rawValue
        if resetMediaUploads {
            // Promotion consumes staging objects before the scan insert. The
            // local media remains authoritative, so force a fresh signed upload
            // instead of retrying object keys that may no longer exist.
            scan.stagedR2Keys = nil
        }
        scan.queueUpdatedAt = now

        job.status = .waiting
        job.updatedAt = now
        job.lastAttemptAt = now
        job.nextRunAt = nextRetryAt
        job.attemptCount = attempt
        job.lastErrorCode = code
        job.lastErrorMessage = message
        job.lastHTTPStatus = nil
        job.serverStatus = nil
        job.serverStage = nil
        job.serverRetryAfter = nil
        modelContext.insert(OfflineQueueEvent(
            jobId: jobId,
            scanId: scanId,
            kind: .retryScheduled,
            message: message,
            errorCode: code
        ))

        do {
            try modelContext.save()
            return attempt
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "scheduleInferenceRetry: save failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return nil
        }
    }

    /// Records a bounded retry when the cloud scan is already complete but its
    /// owner result could not yet be hydrated locally.
    ///
    /// Unlike an inference retry, this keeps the queue row `.inferencing` and
    /// retains the latest server status. Moving it back to `.staged` would make
    /// replay eligible to dispatch a second provider request for a scan whose
    /// durable result already exists.
    func scheduleServerResultRecoveryRetry(
        id scanId: String,
        expectedGeneration: UUID?,
        code: String,
        message: String?,
        delay: TimeInterval
    ) async -> Int? {
        await ScanInferencePersistenceCoordinator.shared.acquire(scanId: scanId)
        guard !Task.isCancelled else {
            await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
            return nil
        }
        let attempt = scheduleServerResultRecoveryRetryLocked(
            id: scanId,
            expectedGeneration: expectedGeneration,
            code: code,
            message: message,
            delay: delay
        )
        await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
        return attempt
    }

    private func scheduleServerResultRecoveryRetryLocked(
        id scanId: String,
        expectedGeneration: UUID?,
        code: String,
        message: String?,
        delay: TimeInterval
    ) -> Int? {
        guard let records = inferenceRetryRecords(
            scanId: scanId,
            expectedGeneration: expectedGeneration,
            operation: "scheduleServerResultRecoveryRetry"
        ) else {
            return nil
        }
        let scan = records.scan
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let job = records.job

        let attempt = reconcileMirroredInferenceState(
            scan: scan,
            job: job
        ) + 1
        let now = Date()
        let nextRetryAt = now.addingTimeInterval(max(1, delay))
        scan.queueAttemptCount = attempt
        scan.queueLastAttemptAt = now
        scan.queueNextRetryAt = nextRetryAt
        scan.queueLastErrorCode = code
        scan.queueLastErrorMessage = message
        scan.queueNeedsAttention = false
        scan.queueUpdatedAt = now

        job.status = .waiting
        job.updatedAt = now
        job.lastAttemptAt = now
        job.nextRunAt = nextRetryAt
        job.attemptCount = attempt
        job.lastErrorCode = code
        job.lastErrorMessage = message
        modelContext.insert(OfflineQueueEvent(
            jobId: jobId,
            scanId: scanId,
            kind: .retryScheduled,
            message: message,
            errorCode: code
        ))

        do {
            try modelContext.save()
            return attempt
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "scheduleServerResultRecoveryRetry: save failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return nil
        }
    }

    private func inferenceRetryRecords(
        scanId: String,
        expectedGeneration: UUID?,
        operation: String
    ) -> (scan: OfflineQueuedScan, job: OfflineJobRecord)? {
        let inferencingRaw = ScanQueueState.inferencing.rawValue
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate {
                $0.id == scanId && $0.scanStateRaw == inferencingRaw
            }
        )
        scanDescriptor.fetchLimit = 1

        let scan: OfflineQueuedScan
        do {
            guard let persistedScan = try modelContext.fetch(
                scanDescriptor
            ).first else {
                return nil
            }
            scan = persistedScan
        } catch {
            MerianLog.data.error(
                "Inference retry scan lookup failed operation=\(operation, privacy: .public) scanId=\(scanId, privacy: .private) error=\(error, privacy: .private)"
            )
            return nil
        }

        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let existingJob: OfflineJobRecord?
        do {
            existingJob = try modelContext.fetchOfflineJob(id: jobId)
        } catch {
            MerianLog.data.error(
                "Inference retry job lookup failed operation=\(operation, privacy: .public) scanId=\(scanId, privacy: .private) error=\(error, privacy: .private)"
            )
            return nil
        }

        if let expectedGeneration {
            guard let existingJob,
                  InferenceGenerationMetadataContract.matches(
                      expectedGeneration,
                      in: existingJob.metadataJSON
                  ) else {
                MerianLog.data.debug(
                    "Inference retry generation mismatch operation=\(operation, privacy: .public) scanId=\(scanId, privacy: .public)"
                )
                return nil
            }
            return (scan, existingJob)
        }
        if let existingJob {
            // Relaunch recovery has no in-memory generation; task and server
            // poll snapshots still fence it, while the persisted queue state
            // prevents a second claim inside this critical section.
            return (scan, existingJob)
        }

        let createdJob = OfflineJobRecord(
            id: jobId,
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running
        )
        modelContext.insert(createdJob)
        return (scan, createdJob)
    }
}
