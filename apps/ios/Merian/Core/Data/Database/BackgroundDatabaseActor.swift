import CoreLocation
import Foundation
import os
import Supabase
import SwiftData

// MARK: - Background Database Actor

/// Serializes local persistence for a single scan id across independent SwiftData contexts.
///
/// Live inference and background URLSession inference can complete the same queued scan in
/// parallel. Both write `LocalScanRecord.id`, and letting those saves race can force Core
/// Data's unique-constraint merge policy to merge to-many relationships. Some SwiftData
/// relationships in this schema intentionally have no inverse, so avoiding the conflict is
/// safer than relying on merge-policy recovery.
actor ScanFinalizationCoordinator {
    static let shared = ScanFinalizationCoordinator()

    private var activeScanIds: Set<String> = []
    private var waitersByScanId: [String: [CheckedContinuation<Void, Never>]] = [:]

    private init() {}

    @discardableResult
    func acquire(scanId: String) async -> Bool {
        if !activeScanIds.contains(scanId) {
            activeScanIds.insert(scanId)
            return false
        }

        await withCheckedContinuation { continuation in
            waitersByScanId[scanId, default: []].append(continuation)
        }
        return true
    }

    func release(scanId: String) {
        guard var waiters = waitersByScanId[scanId], !waiters.isEmpty else {
            activeScanIds.remove(scanId)
            waitersByScanId[scanId] = nil
            return
        }

        let next = waiters.removeFirst()
        waitersByScanId[scanId] = waiters.isEmpty ? nil : waiters
        next.resume()
    }
}

/// Serializes inference claims and retry retreats across every SwiftData actor
/// instance. The durable generation remains the source of truth; this lock
/// closes the fetch-then-save window between independent ModelContexts.
actor ScanInferencePersistenceCoordinator {
    static let shared = ScanInferencePersistenceCoordinator()

    private var activeScanIds: Set<String> = []
    private var waitersByScanId: [String: [CheckedContinuation<Void, Never>]] = [:]

    private init() {}

    func acquire(scanId: String) async {
        if activeScanIds.insert(scanId).inserted {
            return
        }

        await withCheckedContinuation { continuation in
            waitersByScanId[scanId, default: []].append(continuation)
        }
    }

    func release(scanId: String) {
        guard var waiters = waitersByScanId[scanId], !waiters.isEmpty else {
            activeScanIds.remove(scanId)
            waitersByScanId[scanId] = nil
            return
        }

        let next = waiters.removeFirst()
        waitersByScanId[scanId] = waiters.isEmpty ? nil : waiters
        next.resume()
    }
}

/// Durable outcome of promoting a completed upload manifest into inference-ready state.
///
/// The URLSession callback must not infer success from an in-memory HTTP completion set:
/// inference is eligible only after the queue transition commits, or when another serialized
/// owner already advanced the same durable row.
enum ScanStagingTransitionOutcome: Sendable, Equatable {
    /// This call committed `.uploading → .staged` with the exact R2 keys.
    case staged
    /// A serialized owner saved the same staged manifest or already began inference.
    case alreadyAdvanced
    /// The row remains retryable, but this call could not commit the transition.
    case retryRequired
    /// The row is missing or non-runnable and must not be resurrected.
    case discarded
}

/// Swift 6-safe actor that performs all SwiftData reads and writes off the main thread.
///
/// Conforms to `@ModelActor`, which provides an isolated `modelContext` bound to this actor.
/// All methods are safe to call from `Task { }` or `BackgroundTaskWrapper.execute` contexts.
///
/// Shared data transfer objects (`ExtractedScanData`, `OfflineScanProcessingResult`,
/// `PendingScanPayload`, `ScanUploadItem`) live in `OfflineSyncTypes.swift`.
@ModelActor
actor BackgroundDatabaseActor {

    struct ScanErasurePayload: Sendable {
        let id: String
        let imagePaths: [String]
    }

    struct ExpiredNonBiologicalPurgeResult: Sendable, Equatable {
        let deletedRecordCount: Int
        let localMediaPaths: [String]
    }

    /// Reconciles the two durable copies of retry ownership before a queue
    /// transition mutates either model.
    ///
    /// Real migrated stores can temporarily expose a stale scalar snapshot in
    /// one SwiftData context after another context commits. The monotonic
    /// counter and high-authority cloud-recovery markers must therefore heal
    /// from either copy instead of trusting only the queue row.
    @discardableResult
    private func reconcileMirroredInferenceState(
        scan: OfflineQueuedScan,
        job: OfflineJobRecord
    ) -> Int {
        let attempt = max(
            0,
            max(scan.queueAttemptCount, job.attemptCount)
        )
        scan.queueAttemptCount = attempt
        job.attemptCount = attempt

        let hasCompletedCloudResult =
            OfflineQueueManager.isCompletedServerResultRecoveryCode(
                scan.queueLastErrorCode
            ) ||
            OfflineQueueManager.isCompletedServerResultRecoveryCode(
                job.lastErrorCode
            )
        if hasCompletedCloudResult {
            scan.queueLastErrorCode =
                OfflineQueueManager.completedServerResultRecoveryCode
            scan.queueLastErrorMessage =
                OfflineQueueManager.completedServerResultRecoveryMessage
            job.lastErrorCode =
                OfflineQueueManager.completedServerResultRecoveryCode
            job.lastErrorMessage =
                OfflineQueueManager.completedServerResultRecoveryMessage
        } else if OfflineQueueManager.isServerRetryableFailureCode(
            scan.queueLastErrorCode
        ) || OfflineQueueManager.isServerRetryableFailureCode(
            job.lastErrorCode
        ) {
            let retryMessage = OfflineQueueManager
                .isServerRetryableFailureCode(scan.queueLastErrorCode)
                ? (scan.queueLastErrorMessage ?? job.lastErrorMessage)
                : (job.lastErrorMessage ?? scan.queueLastErrorMessage)
            scan.queueLastErrorCode =
                OfflineQueueManager.serverRetryableFailureCode
            scan.queueLastErrorMessage = retryMessage
            job.lastErrorCode =
                OfflineQueueManager.serverRetryableFailureCode
            job.lastErrorMessage = retryMessage
        }
        return attempt
    }

    // MARK: - Pending Scan Fetching

    /// Returns up to `limit` `.pending` (state 0) `OfflineQueuedScan` records sorted oldest-first.
    ///
    /// Scans in `.uploading`, `.staged`, `.inferencing`, or `.failed` states are excluded —
    /// they are either already in flight or terminal, and handled by separate recovery paths.
    func fetchPendingScans(limit: Int) -> [PendingScanPayload] {
        let pendingRaw = ScanQueueState.pending.rawValue
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.scanStateRaw == pendingRaw }
        )
        descriptor.sortBy = [SortDescriptor(\.timestamp)]
        descriptor.fetchLimit = max(limit, limit * 3)

        let pending: [OfflineQueuedScan]
        do {
            pending = try modelContext.fetch(descriptor)
        } catch {
            MerianLog.data.error("fetchPendingScans: fetch failed: \(error, privacy: .private)")
            return []
        }
        let now = Date()
        let runnable = pending.filter { scan in
            !scan.queueNeedsAttention && (scan.queueNextRetryAt == nil || (scan.queueNextRetryAt ?? now) <= now)
        }
        MerianLog.data.debug("fetchPendingScans: fetched \(pending.count, privacy: .public) pending scans runnable=\(runnable.count, privacy: .public)")
        return runnable.prefix(limit).map { scan in
            let snapshot = scan.capturedMediaSnapshot
            return PendingScanPayload(
                id: scan.id,
                localImagePaths: scan.inferenceImagePaths?.isEmpty == false
                    ? scan.inferenceImagePaths ?? []
                    : snapshot.thumbnailImagePaths,
                localAudioPaths: snapshot.audioPaths,
                localVideoPaths: snapshot.videoPaths
            )
        }
    }

    // MARK: - Record Deletion

    /// Deletes non-biological scans and queues their cloud erasure atomically.
    ///
    /// Returns local-only file paths after the database commit succeeds so callers can
    /// purge disk artifacts without risking an inconsistent database state.
    func bulkDeleteNonBiologicalScans(payloads: [ScanErasurePayload]) throws -> [String] {
        var imagePathsToDelete: [String] = []

        do {
            for payload in payloads {
                let scanId = payload.id
                let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
                if let record = try modelContext.fetch(descriptor).first {
                    modelContext.delete(record)
                }

                imagePathsToDelete.append(contentsOf: payload.imagePaths.filter { !$0.starts(with: "http") })
                try modelContext.ensurePendingCloudDeletionTask(scanId: scanId)
            }

            try modelContext.save()
            return imagePathsToDelete
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Deletes non-biological records older than the supplied cutoff.
    ///
    /// The fetch is bounded so foreground cleanup cannot accidentally load a pathological
    /// library into memory. Callers may invoke this again on the next foreground if more
    /// expired records remain.
    func purgeExpiredNonBiologicalScans(cutoffDate: Date, limit: Int = MerianConfig.nonBiologicalPurgeBatchSize) throws -> ExpiredNonBiologicalPurgeResult {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate {
                $0.isBiological == false &&
                $0.timestamp < cutoffDate
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        descriptor.fetchLimit = limit

        let expiredRecords = try modelContext.fetch(descriptor)
        guard !expiredRecords.isEmpty else {
            return ExpiredNonBiologicalPurgeResult(deletedRecordCount: 0, localMediaPaths: [])
        }

        let payloads = expiredRecords.map { record in
            let mediaSnapshot = record.capturedMediaSnapshot
            return ScanErasurePayload(
                id: record.id,
                imagePaths: mediaSnapshot.thumbnailImagePaths + mediaSnapshot.audioPaths + mediaSnapshot.videoPaths
            )
        }

        let deletedPaths = try bulkDeleteNonBiologicalScans(payloads: payloads)
        return ExpiredNonBiologicalPurgeResult(
            deletedRecordCount: expiredRecords.count,
            localMediaPaths: deletedPaths
        )
    }

    // MARK: - State Transitions

    /// Atomically transitions a scan from `.staged` to `.inferencing`.
    ///
    /// Returns `true` if the claim succeeded (scan was in `.staged` state and is now `.inferencing`).
    /// Returns `false` if the scan was already `.inferencing` or not found — caller must skip.
    ///
    /// This is the distributed lock that prevents two concurrent inference pipelines
    /// from running for the same scan: only one actor can win the `.staged → .inferencing`
    /// transition because `BackgroundDatabaseActor` serializes writes through its executor.
    func tryClaimForInference(
        scanId: String,
        generation: UUID? = nil
    ) async -> Bool {
        await ScanInferencePersistenceCoordinator.shared.acquire(scanId: scanId)
        guard !Task.isCancelled else {
            await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
            return false
        }
        let didClaim = tryClaimForInferenceLocked(
            scanId: scanId,
            generation: generation
        )
        await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
        return didClaim
    }

    private func tryClaimForInferenceLocked(
        scanId: String,
        generation: UUID?
    ) -> Bool {
        let stagedRaw     = ScanQueueState.staged.rawValue
        let inferencingRaw = ScanQueueState.inferencing.rawValue
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        guard let scan = (try? modelContext.fetch(descriptor))?.first else {
            MerianLog.data.debug("tryClaimForInference: scan missing scanId=\(scanId, privacy: .public)")
            return false
        }
        guard scan.scanStateRaw == stagedRaw else {
            MerianLog.data.debug(
                "tryClaimForInference: state mismatch scanId=\(scanId, privacy: .public) state=\(scan.scanStateRaw, privacy: .public)"
            )
            return false
        }
        let now = Date()
        scan.scanStateRaw = inferencingRaw
        scan.queueLastAttemptAt = now
        scan.queueNextRetryAt = nil
        scan.queueUpdatedAt = now
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let job = fetchOfflineJob(id: jobId) ?? {
            let created = OfflineJobRecord(
                id: jobId,
                kind: .scanIngestion,
                subjectId: scanId,
                status: .running
            )
            modelContext.insert(created)
            return created
        }()
        reconcileMirroredInferenceState(scan: scan, job: job)
        if let generation {
            job.metadataJSON =
                InferenceGenerationMetadataContract.json(for: generation)
        }
        job.status = .running
        job.updatedAt = now
        job.lastAttemptAt = now
        job.nextRunAt = nil
        modelContext.insert(OfflineQueueEvent(
            jobId: jobId,
            scanId: scanId,
            kind: .inferenceStarted,
            message: "Queued scan claimed for inference."
        ))
        do {
            try modelContext.save()
            MerianLog.data.debug("tryClaimForInference: claimed scanId=\(scanId, privacy: .public)")
        } catch {
            modelContext.rollback()
            MerianLog.data.error("tryClaimForInference: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return false
        }
        return true
    }

    /// Transitions a scan back to `.staged` from `.inferencing` and persists.
    ///
    /// **Only valid for the transient-error retry path** (`handleInferenceRetry` transient catch).
    /// Guarded to `.inferencing` as source state so a concurrent `softDeleteQueuedScan` on
    /// the MainActor that already tombstoned the scan to `.failed` cannot be overwritten —
    /// the last-writer-wins nature of two separate `ModelContext`s would otherwise resurrect
    /// a tombstoned scan back into the inference replay queue.
    @discardableResult
    func transitionScanToStaged(
        id scanId: String,
        expectedGeneration: UUID? = nil
    ) async -> Bool {
        await ScanInferencePersistenceCoordinator.shared.acquire(scanId: scanId)
        guard !Task.isCancelled else {
            await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
            return false
        }
        let didTransition = transitionScanToStagedLocked(
            id: scanId,
            expectedGeneration: expectedGeneration
        )
        await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
        return didTransition
    }

    private func transitionScanToStagedLocked(
        id scanId: String,
        expectedGeneration: UUID?
    ) -> Bool {
        let inferencingRaw = ScanQueueState.inferencing.rawValue
        let stagedRaw      = ScanQueueState.staged.rawValue
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        guard let scan = (try? modelContext.fetch(descriptor))?.first else {
            return false
        }
        // Only retreat from .inferencing — do not overwrite a concurrent tombstone (.failed).
        guard scan.scanStateRaw == inferencingRaw else { return false }
        if let expectedGeneration {
            let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
            let expectedMetadata =
                InferenceGenerationMetadataContract.json(
                    for: expectedGeneration
                )
            var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
                predicate: #Predicate {
                    $0.id == jobId && $0.metadataJSON == expectedMetadata
                }
            )
            jobDescriptor.fetchLimit = 1
            guard (try? modelContext.fetch(jobDescriptor).first) != nil else {
                MerianLog.data.debug(
                    "transitionScanToStaged: generation mismatch scanId=\(scanId, privacy: .public)"
                )
                return false
            }
        }
        scan.scanStateRaw = stagedRaw
        scan.queueUpdatedAt = Date()
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error("transitionScanToStaged: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return false
        }
    }

    /// Must be called only while `ScanInferencePersistenceCoordinator` is held
    /// for `scanId`. This intentionally does not acquire the coordinator itself
    /// so the main-actor queue deletion path can validate durable ownership
    /// while keeping the lock across URLSession cancellation and SwiftData save.
    ///
    /// An absent queue row is accepted only when the exact generation's durable
    /// job is already complete. That narrow terminal proof makes committed
    /// queue deletion idempotent without allowing an active or stale generation
    /// to delete replacement work.
    func inferenceGenerationIsCurrentAssumingPersistenceLock(
        scanId: String,
        expectedGeneration: UUID
    ) -> Bool {
        let inferencingRaw = ScanQueueState.inferencing.rawValue
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        let queuedScan: OfflineQueuedScan?
        do {
            queuedScan = try modelContext.fetch(scanDescriptor).first
        } catch {
            MerianLog.data.error(
                "inferenceGenerationIsCurrent: queue lookup failed scanId=\(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }

        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let expectedMetadata =
            InferenceGenerationMetadataContract.json(
                for: expectedGeneration
            )
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate {
                $0.id == jobId && $0.metadataJSON == expectedMetadata
            }
        )
        jobDescriptor.fetchLimit = 1
        let job: OfflineJobRecord?
        do {
            job = try modelContext.fetch(jobDescriptor).first
        } catch {
            MerianLog.data.error(
                "inferenceGenerationIsCurrent: job lookup failed scanId=\(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
        guard let job else { return false }
        if let queuedScan {
            return queuedScan.scanStateRaw == inferencingRaw
        }
        return job.status == .complete
    }

    /// Validates a foreground owner while
    /// `ScanInferencePersistenceCoordinator` is already held for `scanId`.
    ///
    /// Unlike background inference, a live request may own a queued scan while
    /// recovery media is pending, uploading, or staged. The durable job
    /// generation is therefore the cross-actor source of truth.
    func liveInferenceGenerationIsCurrentAssumingPersistenceLock(
        scanId: String,
        expectedGeneration: UUID
    ) -> Bool {
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        guard let scan = try? modelContext.fetch(scanDescriptor).first,
              scan.queueState != .failed,
              scan.queueState != .externalImport else {
            return false
        }

        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let expectedMetadata =
            InferenceGenerationMetadataContract.json(
                for: expectedGeneration
            )
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate {
                $0.id == jobId && $0.metadataJSON == expectedMetadata
            }
        )
        jobDescriptor.fetchLimit = 1
        return (try? modelContext.fetch(jobDescriptor).first) != nil
    }

    private func livePersistenceFenceIsCurrentAssumingPersistenceLock(
        _ fence: LiveInferencePersistenceFence
    ) async -> Bool {
        guard !Task.isCancelled,
              liveInferenceGenerationIsCurrentAssumingPersistenceLock(
                  scanId: fence.scanId,
                  expectedGeneration: fence.generation
              ) else {
            return false
        }
        let isCurrentInMemory = await MainActor.run {
            OfflineQueueManager.shared
                .isForegroundInferenceAttemptCurrent(
                    scanId: fence.scanId,
                    generation: fence.generation
                )
        }
        return !Task.isCancelled &&
            isCurrentInMemory &&
            liveInferenceGenerationIsCurrentAssumingPersistenceLock(
                scanId: fence.scanId,
                expectedGeneration: fence.generation
            )
    }

    private func livePersistenceFenceMatchesResult(
        _ fence: LiveInferencePersistenceFence?,
        mappedScanId: String?
    ) -> Bool {
        guard let fence else { return true }
        guard let mappedScanId else { return false }
        return mappedScanId.caseInsensitiveCompare(fence.scanId)
            == .orderedSame
    }

    /// Future claims always persist their generation before dispatch. Adoption
    /// exists only for an inference task already in flight during this upgrade;
    /// once set, every stale result must match exactly.
    private func validateOrAdoptInferenceGenerationLocked(
        scanId: String,
        expectedGeneration: UUID
    ) -> Bool {
        let inferencingRaw = ScanQueueState.inferencing.rawValue
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate {
                $0.id == scanId && $0.scanStateRaw == inferencingRaw
            }
        )
        scanDescriptor.fetchLimit = 1
        guard (try? modelContext.fetch(scanDescriptor).first) != nil else {
            return false
        }

        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        guard let job = fetchOfflineJob(id: jobId) else { return false }
        let expectedMetadata =
            InferenceGenerationMetadataContract.json(
                for: expectedGeneration
            )
        if job.metadataJSON == expectedMetadata {
            return true
        }
        guard job.metadataJSON == nil else { return false }

        job.metadataJSON = expectedMetadata
        job.updatedAt = Date()
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "validateOrAdoptInferenceGenerationLocked: save failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
    }

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
        let inferencingRaw = ScanQueueState.inferencing.rawValue
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate {
                $0.id == scanId && $0.scanStateRaw == inferencingRaw
            }
        )
        scanDescriptor.fetchLimit = 1
        guard let scan = try? modelContext.fetch(scanDescriptor).first else {
            return nil
        }

        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let job: OfflineJobRecord
        if let expectedGeneration {
            let expectedMetadata =
                InferenceGenerationMetadataContract.json(
                    for: expectedGeneration
                )
            var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
                predicate: #Predicate {
                    $0.id == jobId && $0.metadataJSON == expectedMetadata
                }
            )
            jobDescriptor.fetchLimit = 1
            guard let ownedJob = try? modelContext.fetch(jobDescriptor).first else {
                MerianLog.data.debug(
                    "scheduleInferenceRetry: generation mismatch scanId=\(scanId, privacy: .public)"
                )
                return nil
            }
            job = ownedJob
        } else if let existingJob = fetchOfflineJob(id: jobId) {
            // Relaunch recovery has no in-memory generation; task and server
            // poll snapshots still fence it, while the persisted queue state
            // prevents a second claim inside this critical section.
            job = existingJob
        } else {
            let createdJob = OfflineJobRecord(
                id: jobId,
                kind: .scanIngestion,
                subjectId: scanId,
                status: .running
            )
            modelContext.insert(createdJob)
            job = createdJob
        }

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
        let inferencingRaw = ScanQueueState.inferencing.rawValue
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate {
                $0.id == scanId && $0.scanStateRaw == inferencingRaw
            }
        )
        scanDescriptor.fetchLimit = 1
        guard let scan = try? modelContext.fetch(scanDescriptor).first else {
            return nil
        }

        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let job: OfflineJobRecord
        if let expectedGeneration {
            let expectedMetadata =
                InferenceGenerationMetadataContract.json(
                    for: expectedGeneration
                )
            var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
                predicate: #Predicate {
                    $0.id == jobId && $0.metadataJSON == expectedMetadata
                }
            )
            jobDescriptor.fetchLimit = 1
            guard let ownedJob = try? modelContext.fetch(jobDescriptor).first else {
                MerianLog.data.debug(
                    "scheduleServerResultRecoveryRetry: generation mismatch scanId=\(scanId, privacy: .public)"
                )
                return nil
            }
            job = ownedJob
        } else if let existingJob = fetchOfflineJob(id: jobId) {
            job = existingJob
        } else {
            let createdJob = OfflineJobRecord(
                id: jobId,
                kind: .scanIngestion,
                subjectId: scanId,
                status: .running
            )
            modelContext.insert(createdJob)
            job = createdJob
        }

        let attempt =
            reconcileMirroredInferenceState(scan: scan, job: job) + 1
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

    /// Persists confirmed R2 keys, normally resets upload retry metadata, and transitions to `.staged`.
    ///
    /// Called once the last image upload for a scan is confirmed (HTTP 200).
    /// Storing keys here eliminates auth-dependent key reconstruction at inference time.
    /// An exact scheduled server-failure reclaim preserves its retry latch and
    /// accounting through a required fresh upload.
    ///
    /// Guards: only transitions from `.uploading`. If the scan was tombstoned (`.failed`) while
    /// a subset of its images were still in transit — e.g., one source file was missing —
    /// this prevents the completed uploads from resurrecting the scan into the inference pipeline
    /// with partial image data.
    @discardableResult
    func markScanAsStaged(
        scanId: String,
        r2Keys: [String]
    ) -> ScanStagingTransitionOutcome {
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let scan: OfflineQueuedScan?
        do {
            scan = try modelContext.fetch(descriptor).first
        } catch {
            MerianLog.data.error(
                "markScanAsStaged: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return .retryRequired
        }
        guard let scan else {
            MerianLog.data.debug("markScanAsStaged: scan missing scanId=\(scanId, privacy: .public)")
            return .discarded
        }
        // Only advance from .uploading — do not resurrect tombstoned (.failed) scans.
        guard scan.scanStateRaw == ScanQueueState.uploading.rawValue else {
            MerianLog.data.debug(
                "markScanAsStaged: state mismatch scanId=\(scanId, privacy: .public) state=\(scan.scanStateRaw, privacy: .public)"
            )
            switch scan.queueState {
            case .staged:
                guard scan.stagedR2Keys == r2Keys else {
                    MerianLog.data.error(
                        "markScanAsStaged: durable staged manifest mismatch scanId=\(scanId, privacy: .private)"
                    )
                    return .retryRequired
                }
                return .alreadyAdvanced
            case .inferencing:
                return .alreadyAdvanced
            case .pending:
                return .retryRequired
            case .externalImport, .failed:
                return .discarded
            case .uploading:
                // The raw-value guard above makes this branch unreachable.
                return .retryRequired
            }
        }
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        jobDescriptor.fetchLimit = 1
        let job: OfflineJobRecord?
        do {
            job = try modelContext.fetch(jobDescriptor).first
        } catch {
            MerianLog.data.error(
                "markScanAsStaged: job fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return .retryRequired
        }

        let now = Date()
        if let job {
            reconcileMirroredInferenceState(scan: scan, job: job)
        }
        let preservesInferenceRecovery =
            OfflineQueueManager.isServerRetryableFailureCode(
                scan.queueLastErrorCode
            ) ||
            OfflineQueueManager.isServerRetryableFailureCode(
                job?.lastErrorCode
            ) ||
            OfflineQueueManager.isCompletedServerResultRecoveryCode(
                scan.queueLastErrorCode
            ) ||
            OfflineQueueManager.isCompletedServerResultRecoveryCode(
                job?.lastErrorCode
            )
        scan.stagedR2Keys = r2Keys
        scan.scanStateRaw = ScanQueueState.staged.rawValue
        if !preservesInferenceRecovery {
            scan.queueAttemptCount = 0
            scan.queueLastAttemptAt = nil
            scan.queueLastErrorCode = nil
            scan.queueLastErrorMessage = nil
        }
        scan.queueNextRetryAt = nil
        scan.queueLastHTTPStatus = nil
        scan.queueLastServerStatus = nil
        scan.queueLastServerStage = nil
        scan.queueLastServerRetryAfter = nil
        scan.queueNeedsAttention = false
        scan.queueUpdatedAt = now
        if let job {
            job.status = .running
            job.updatedAt = now
            job.nextRunAt = nil
            if !preservesInferenceRecovery {
                job.lastAttemptAt = nil
                job.attemptCount = 0
                job.lastErrorCode = nil
                job.lastErrorMessage = nil
            }
            job.lastHTTPStatus = nil
            job.serverStatus = nil
            job.serverStage = nil
            job.serverRetryAfter = nil
        }
        modelContext.insert(OfflineQueueEvent(
            jobId: jobId,
            scanId: scanId,
            kind: .staged,
            message: "Queued scan media staged for inference."
        ))
        do {
            try modelContext.save()
            MerianLog.data.debug(
                "markScanAsStaged: staged scanId=\(scanId, privacy: .public) keys=\(r2Keys.count, privacy: .public)"
            )
            return .staged
        } catch {
            modelContext.rollback()
            MerianLog.data.error("markScanAsStaged: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return .retryRequired
        }
    }

    /// Marks scans in `.uploading` state that have no active URLSession task as `.pending`,
    /// so `syncPendingScans` re-dispatches them on the next sync cycle.
    ///
    /// `observedThrough` fences the URLSession snapshot: a scan claimed after
    /// that instant belongs to newer work and must not be reset by this pass.
    ///
    /// Returns `true` if at least one orphan was reset, `false` if nothing changed.
    /// Callers that need to react to an actual state change (e.g. triggering a new sync)
    /// can use the return value; all other call sites may discard it.
    ///
    /// Callers capture `observedThrough` before enumerating URLSession tasks. The
    /// cutoff makes both cold-start and later safety-net passes safe if new work
    /// is claimed while the actor call is waiting to run.
    @discardableResult
    func reconcileOrphanedUploadingScans(
        activeScanIds: Set<String>,
        observedThrough: Date = Date()
    ) -> Bool {
        let uploadingRaw = ScanQueueState.uploading.rawValue
        let pendingRaw   = ScanQueueState.pending.rawValue
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.scanStateRaw == uploadingRaw }
        )
        let scans: [OfflineQueuedScan]
        do {
            scans = try modelContext.fetch(descriptor)
        } catch {
            MerianLog.data.debug("reconcileOrphanedUploadingScans: fetch failed: \(error, privacy: .private)")
            return false
        }
        var changed = false
        var resetIds: [String] = []
        for scan in scans
        where scan.queueUpdatedAt <= observedThrough
            && !activeScanIds.contains(scan.id) {
            scan.scanStateRaw = pendingRaw
            scan.queueUpdatedAt = Date()
            changed = true
            resetIds.append(scan.id)
        }
        if changed {
            do {
                try modelContext.save()
                MerianLog.data.debug(
                    "reconcileOrphanedUploadingScans: reset ids=\(resetIds.joined(separator: ","), privacy: .public)"
                )
            } catch {
                modelContext.rollback()
                MerianLog.data.error("reconcileOrphanedUploadingScans: save failed: \(error, privacy: .private)")
                return false
            }
        }
        return changed
    }

    /// Resets `.inferencing` scans that have no active background URLSession inference task
    /// back to `.staged` so `replayInferenceForUploadedScans` can re-claim them.
    ///
    /// Replaces `resetOrphanedInferencingScans` with a cross-reference against the live
    /// URLSession task list so that background download tasks still owned by the OS are
    /// not blindly reset — which would cause a duplicate inference dispatch on relaunch.
    /// The snapshot cutoff also excludes generations claimed while reconciliation awaits
    /// this actor.
    func reconcileOrphanedInferencingScans(
        activeInferenceScanIds: Set<String>,
        observedThrough: Date = Date()
    ) {
        let inferencingRaw = ScanQueueState.inferencing.rawValue
        let stagedRaw      = ScanQueueState.staged.rawValue
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.scanStateRaw == inferencingRaw }
        )
        let scans: [OfflineQueuedScan]
        do {
            scans = try modelContext.fetch(descriptor)
        } catch {
            MerianLog.data.debug("reconcileOrphanedInferencingScans: fetch failed: \(error, privacy: .private)")
            return
        }
        var changed = false
        for scan in scans
        where scan.queueUpdatedAt <= observedThrough
            && !activeInferenceScanIds.contains(scan.id) {
            scan.scanStateRaw = stagedRaw
            scan.queueUpdatedAt = Date()
            changed = true
        }
        if changed {
            do {
                try modelContext.save()
                MerianLog.data.debug("reconcileOrphanedInferencingScans: reset orphaned .inferencing scans to .staged")
            } catch {
                modelContext.rollback()
                MerianLog.data.error("reconcileOrphanedInferencingScans: save failed: \(error, privacy: .private)")
            }
        }
    }

    /// Persists weather backfill data onto the queued scan record before the inference
    /// request is dispatched as a background download task.
    ///
    /// Called after WeatherKit resolves so the delegate can read hydrated telemetry from
    /// SwiftData on result delivery — even if the app was suspended between dispatch and receipt.
    func updateScanTelemetry(
        scanId: String,
        weatherCondition: String?,
        weatherTemperatureF: Double?,
        locationName: String?
    ) {
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        guard let scan = (try? modelContext.fetch(descriptor))?.first else { return }
        if let wc = weatherCondition { scan.weatherCondition = wc }
        if let wt = weatherTemperatureF { scan.weatherTemperatureF = wt }
        if scan.locationName == nil, let ln = locationName { scan.locationName = ln }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            MerianLog.data.error("updateScanTelemetry: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
        }
    }

    /// Transitions scans to `.uploading` state and persists, preventing `syncPendingScans`
    /// from re-dispatching upload tasks for these scans after an app restart.
    func markScansAsUploading(scanIds: [String]) -> Set<String> {
        guard !scanIds.isEmpty else { return [] }
        let pendingRaw   = ScanQueueState.pending.rawValue
        let uploadingRaw = ScanQueueState.uploading.rawValue
        var claimedScanIds = Set<String>()

        // Process in chunks to prevent unbounded memory loads and SQL IN-clause overflow.
        let chunkSize = 50
        for i in stride(from: 0, to: scanIds.count, by: chunkSize) {
            let chunkEnd = min(i + chunkSize, scanIds.count)
            let chunk = Array(scanIds[i..<chunkEnd])

            // SwiftData safely supports array.contains in #Predicate for bounded chunks
            let descriptor = FetchDescriptor<OfflineQueuedScan>(
                predicate: #Predicate { chunk.contains($0.id) && $0.scanStateRaw == pendingRaw }
            )

            do {
                let scans = try modelContext.fetch(descriptor)
                for scan in scans {
                    scan.scanStateRaw = uploadingRaw
                    scan.queueLastAttemptAt = Date()
                    scan.queueNextRetryAt = nil
                    scan.queueUpdatedAt = Date()
                    if let job = fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: scan.id)) {
                        reconcileMirroredInferenceState(scan: scan, job: job)
                        job.status = .running
                        job.updatedAt = Date()
                        job.lastAttemptAt = Date()
                        job.nextRunAt = nil
                        job.attemptCount = scan.queueAttemptCount
                    }
                    modelContext.insert(OfflineQueueEvent(
                        jobId: OfflineQueueManager.scanIngestionJobId(scanId: scan.id),
                        scanId: scan.id,
                        kind: .claimed,
                        message: "Queued scan claimed for media upload."
                    ))
                    claimedScanIds.insert(scan.id)
                }
            } catch {
                modelContext.rollback()
                MerianLog.data.error("markScansAsUploading: fetch failed: \(error, privacy: .private)")
                return []
            }
        }

        guard !claimedScanIds.isEmpty else {
            MerianLog.data.debug(
                "markScansAsUploading: no pending scans claimed from candidates=\(scanIds.joined(separator: ","), privacy: .public)"
            )
            return []
        }

        do {
            try modelContext.save()
            MerianLog.data.debug(
                "markScansAsUploading: claimed ids=\(claimedScanIds.sorted().joined(separator: ","), privacy: .public)"
            )
            return claimedScanIds
        } catch {
            modelContext.rollback()
            MerianLog.data.error("markScansAsUploading: save failed: \(error, privacy: .private)")
            return []
        }
    }

    private func fetchOfflineJob(id: String) -> OfflineJobRecord? {
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Offline Scan Processing

    private func acquireFinalizationLock(scanId: String, operation: String) async {
        let waited = await ScanFinalizationCoordinator.shared.acquire(scanId: scanId)
        if waited {
            MerianLog.data.debug(
                "Scan finalization waited for existing writer operation=\(operation, privacy: .public) scanId=\(scanId, privacy: .public)"
            )
        }
    }

    /// Decodes edge inference results and persists a `LocalScanRecord` (when confidence > 0).
    ///
    /// The `OfflineQueuedScan` is intentionally **not** deleted here — that is delegated to
    /// the main actor's queue-deletion path so the main `ModelContext` always has a real
    /// pending change on its save, which is the only reliable `@Query` re-evaluation trigger
    /// in a presented sheet (SwiftData platform limitation).
    func processAndCleanupOfflineScan(
        resultData: Data,
        originalImagePaths: [String],
        scanId: String,
        originalTimestamp: Date,
        telemetry: CaptureTelemetry? = nil,
        observationContextsJSON: [String]? = nil,
        audioFilePaths: [String]? = nil,
        videoFilePaths: [String]? = nil,
        capturedMediaJSON: String? = nil,
        expectedGeneration: UUID? = nil
    ) async -> OfflineScanProcessingResult {
        await ScanInferencePersistenceCoordinator.shared.acquire(scanId: scanId)
        guard !Task.isCancelled else {
            await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
            return OfflineScanProcessingResult(
                resolvedSpeciesName: nil,
                isNewDiscovery: false,
                finalScanId: nil,
                speciesData: nil,
                wasCleaned: false
            )
        }
        if let expectedGeneration,
           !validateOrAdoptInferenceGenerationLocked(
               scanId: scanId,
               expectedGeneration: expectedGeneration
           ) {
            await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
            MerianLog.data.debug(
                "processAndCleanupOfflineScan: durable generation mismatch scanId=\(scanId, privacy: .public)"
            )
            return OfflineScanProcessingResult(
                resolvedSpeciesName: nil,
                isNewDiscovery: false,
                finalScanId: nil,
                speciesData: nil,
                wasCleaned: false
            )
        }

        var resolvedSpeciesName: String?
        var finalIsNewDiscovery = false
        var resultingScanId: String?
        var resultSpeciesData: SpeciesData?
        var finalizationScanId: String?

        // --- Step 1: Decode Edge Response ---
        
        let parsedWrapper: EdgeResponseWrapper
        do {
            parsedWrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: resultData)
        } catch {
            MerianLog.data.debug("processAndCleanupOfflineScan: JSON decode failed: \(error, privacy: .private)")
            await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
            return OfflineScanProcessingResult(
                resolvedSpeciesName: nil,
                isNewDiscovery: false,
                finalScanId: nil,
                speciesData: nil,
                wasCleaned: false
            )
        }
        guard IdentifySuccessEnvelopeValidator.isUsable(parsedWrapper) else {
            MerianLog.data.debug(
                "processAndCleanupOfflineScan: decoded response failed the client success boundary scanId=\(scanId, privacy: .public)"
            )
            await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
            return OfflineScanProcessingResult(
                resolvedSpeciesName: nil,
                isNewDiscovery: false,
                finalScanId: nil,
                speciesData: nil,
                wasCleaned: false
            )
        }

        // --- Step 2: Map Data and Resolve Identifiers ---
        
        var mappedData = SpeciesData(
            fromEdgeResponse: parsedWrapper.data,
            locationName: telemetry?.locationName,
            weatherCondition: telemetry?.weatherCondition,
            weatherTemperatureF: telemetry?.weatherTemperatureF,
            gpsElevation: telemetry?.gpsElevation,
            gpsLatitude: telemetry?.gpsLatitude,
            gpsLongitude: telemetry?.gpsLongitude
        )
        mappedData.zoomFactor = telemetry?.zoomFactor.map { Double($0) }
        mappedData.audioFilePaths = audioFilePaths
        mappedData.videoFilePaths = videoFilePaths

        if expectedGeneration != nil,
           mappedData.scanId?.caseInsensitiveCompare(scanId)
                != .orderedSame {
            await ScanInferencePersistenceCoordinator.shared.release(
                scanId: scanId
            )
            MerianLog.data.debug(
                "processAndCleanupOfflineScan: response scan ID mismatch scanId=\(scanId, privacy: .public)"
            )
            return OfflineScanProcessingResult(
                resolvedSpeciesName: nil,
                isNewDiscovery: false,
                finalScanId: nil,
                speciesData: nil,
                wasCleaned: false
            )
        }

        if mappedData.confidenceScore > 0.0 {
            resolvedSpeciesName = mappedData.commonName

            let recordId = mappedData.scanId ?? scanId
            await acquireFinalizationLock(scanId: recordId, operation: "offline")
            finalizationScanId = recordId

            let shouldInsertRecord = fetchLocalScanRecord(id: recordId) == nil
            let (activeSpeciesId, isNew) = resolveSpeciesIdAndDiscoveryStatus(for: mappedData.scientificName)

            if shouldInsertRecord && isNew {
                mappedData.isNewDiscovery = true
                finalIsNewDiscovery = true
            }

            // Capture mappedData (with isNewDiscovery set) to hydrate the live InferenceEngine.
            resultSpeciesData = mappedData

            // --- Step 3: Atomic Record Insertion ---
            if shouldInsertRecord {
                await insertLocalScanRecordIfMissing(
                    mappedData: mappedData,
                    recordId: recordId,
                    activeSpeciesId: activeSpeciesId,
                    discoveryTimestamp: originalTimestamp,
                    captureDate: originalTimestamp,
                    originalImagePaths: originalImagePaths,
                    observationContextsJSON: observationContextsJSON,
                    audioFilePaths: audioFilePaths,
                    videoFilePaths: videoFilePaths,
                    capturedMediaJSON: capturedMediaJSON
                )
            }

            resultingScanId = recordId
        }

        // --- Step 4: Commit LocalScanRecord ---
        //
        // The `OfflineQueuedScan` is intentionally NOT deleted here. Delegation to the main
        // actor's queue-deletion path ensures the main `ModelContext` always has a real
        // pending deletion when it saves. SwiftData's `@Query` in a presented sheet only
        // re-evaluates reliably when the *main* context performs a save with actual pending
        // changes; background-context saves propagate via `NSPersistentStoreRemoteChangeNotification`
        // but do not reliably trigger `@Query` in open sheets (SwiftData platform limitation).
        let commitSuccess: Bool
        do {
            try modelContext.save()
            commitSuccess = true
        } catch {
            MerianLog.data.error("processAndCleanupOfflineScan: save failed — rolling back.")
            modelContext.rollback()
            resolvedSpeciesName = nil
            resultingScanId = nil
            resultSpeciesData = nil
            commitSuccess = false
        }
        if let finalizationScanId {
            await ScanFinalizationCoordinator.shared.release(scanId: finalizationScanId)
        }

        let result = OfflineScanProcessingResult(
            resolvedSpeciesName: resolvedSpeciesName,
            isNewDiscovery: finalIsNewDiscovery,
            finalScanId: resultingScanId,
            speciesData: resultSpeciesData,
            wasCleaned: commitSuccess
        )
        await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
        return result
    }

    // MARK: - Offline Queue Processing Helpers

    /// Determines the correct speciesId and whether this is a new discovery for the user.
    private func resolveSpeciesIdAndDiscoveryStatus(for targetName: String) -> (speciesId: String, isNewDiscovery: Bool) {
        var fetchDescriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate<LocalScanRecord> { $0.scientificName == targetName }
        )
        fetchDescriptor.fetchLimit = 1
        fetchDescriptor.propertiesToFetch = [\.speciesId]
        
        let existingRecords: [LocalScanRecord]
        do {
            existingRecords = try modelContext.fetch(fetchDescriptor)
        } catch {
            MerianLog.data.debug("resolveSpeciesIdAndDiscoveryStatus: lookup failed: \(error, privacy: .private)")
            existingRecords = []
        }

        let activeSpeciesId = existingRecords.first?.speciesId ?? UUID().uuidString
        let isNewDiscovery = existingRecords.isEmpty
        return (activeSpeciesId, isNewDiscovery)
    }

    /// Shared helper to map SpeciesData into a LocalScanRecord, preventing 120+ lines of duplication.
    private func buildScanRecord(
        from mappedData: SpeciesData,
        recordId: String,
        speciesId: String,
        timestamp: Date,
        captureDate: Date,
        capturedMediaJSON: String? = nil,
        coverImagePath: String? = nil,
        isLiveCapture: Bool,
        fieldNotes: String? = nil
    ) -> LocalScanRecord {
        let petIdentificationData = mappedData.petIdentification.flatMap {
            try? JSONEncoder().encode($0)
        }
        let semanticPetTags = [mappedData.petIdentification?.label].compactMap {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let record = LocalScanRecord(
            id: recordId,
            speciesId: speciesId,
            scientificName: mappedData.scientificName,
            commonName: mappedData.commonName,
            timestamp: timestamp,
            captureDate: captureDate,
            capturedMediaJSON: capturedMediaJSON,
            coverImagePath: coverImagePath,
            semanticTags: [mappedData.commonName, mappedData.scientificName] + semanticPetTags + (mappedData.colors ?? []) + (mappedData.groupTags ?? []),
            hazardType: mappedData.insightData.hazardType,
            isBiological: mappedData.isBiological,
            isLiveCapture: isLiveCapture,
            isInvasive: mappedData.isInvasive,
            invasiveStatusRegion: mappedData.invasiveStatusRegion,
            invasiveRationale: mappedData.invasiveRationale,
            invasiveConfidence: mappedData.invasiveConfidence,
            ecologyType: mappedData.ecologyType,
            wikipediaUrl: mappedData.wikipediaUrl,
            referenceImageUrl: mappedData.referenceImageUrl,
            confidenceScore: mappedData.confidenceScore,
            taxonomyKingdom: mappedData.taxonomy?.kingdom,
            taxonomyPhylum: mappedData.taxonomy?.phylum,
            taxonomyClass: mappedData.taxonomy?.className,
            taxonomyOrder: mappedData.taxonomy?.order,
            taxonomyFamily: mappedData.taxonomy?.family,
            taxonomyGenus: mappedData.taxonomy?.genus,
            locationName: mappedData.locationName,
            weatherCondition: mappedData.weatherCondition,
            weatherTemperatureF: mappedData.weatherTemperatureF,
            similarSpecies: mappedData.similarSpecies?.lookalikes,
            candidatesData: mappedData.candidates.flatMap { try? JSONEncoder().encode($0) },
            iucnRedListStatus: mappedData.iucnRedListStatus,
            gpsLatitude: mappedData.gpsLatitude,
            gpsLongitude: mappedData.gpsLongitude,
            gpsElevation: mappedData.gpsElevation,
            zoomFactor: mappedData.zoomFactor,
            aiReasoning: mappedData.aiReasoning,
            habitatDescription: mappedData.habitatDescription,
            gbifTaxonKey: mappedData.gbifTaxonKey,
            estimatedSizeCm: mappedData.estimatedSizeCm,
            lifeStage: mappedData.lifeStage,
            reproductiveCondition: mappedData.reproductiveCondition,
            sex: mappedData.sex,
            sexConfidence: mappedData.sexConfidence,
            sexEvidence: mappedData.sexEvidence,
            individualCount: mappedData.individualCount,
            ecologicalInteractions: mappedData.ecologicalInteractions,
            inferenceTier: mappedData.inferenceTier,
            imageQualityScore: mappedData.imageQualityScore,
            alternativeCommonNames: mappedData.alternativeCommonNames,
            petIdentificationData: petIdentificationData,
            fieldNotes: fieldNotes
        )

        if let capturedMediaJSON,
           let items = MediaJSONParser.serializedItems(jsonString: capturedMediaJSON) {
            record.replaceCapturedMedia(with: items)
        } else {
            record.coverImagePath = coverImagePath
        }

        return record
    }

    private func resolvedFieldNotesText(for scanId: String) -> String? {
        if let localNotes = fetchLocalScanRecord(id: scanId)?.fieldNotes?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !localNotes.isEmpty {
            return localNotes
        }

        var queuedDescriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        queuedDescriptor.fetchLimit = 1
        let queuedNotes = (try? modelContext.fetch(queuedDescriptor))?.first?.fieldNotes?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (queuedNotes?.isEmpty == false) ? queuedNotes : nil
    }

    private func fetchLocalScanRecord(id recordId: String) -> LocalScanRecord? {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == recordId }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    @discardableResult
    private func deleteLocalScanRecordIfPresent(id recordId: String) -> Bool {
        guard let existing = fetchLocalScanRecord(id: recordId) else { return false }
        modelContext.delete(existing)
        return true
    }

    /// Idempotently inserts a new LocalScanRecord.
    private func insertLocalScanRecordIfMissing(
        mappedData: SpeciesData,
        recordId: String,
        activeSpeciesId: String,
        discoveryTimestamp: Date,
        captureDate: Date,
        originalImagePaths: [String],
        observationContextsJSON: [String]? = nil,
        audioFilePaths: [String]? = nil,
        videoFilePaths: [String]? = nil,
        capturedMediaJSON: String? = nil
    ) async {
        if fetchLocalScanRecord(id: recordId) == nil {
            let resolvedFieldNotes = resolvedFieldNotesText(for: recordId)
            let resolvedCapturedMediaJSON: String?
            if let capturedMediaJSON {
                resolvedCapturedMediaJSON = capturedMediaJSON
            } else {
                resolvedCapturedMediaJSON = await buildCapturedMediaJSON(
                    localImagePaths: originalImagePaths,
                    observationContextsJSON: observationContextsJSON,
                    audioFilePaths: audioFilePaths ?? mappedData.audioFilePaths,
                    videoFilePaths: videoFilePaths ?? mappedData.videoFilePaths
                )
            }
            
            let record = buildScanRecord(
                from: mappedData,
                recordId: recordId,
                speciesId: activeSpeciesId,
                timestamp: discoveryTimestamp,
                captureDate: captureDate,
                capturedMediaJSON: resolvedCapturedMediaJSON,
                coverImagePath: originalImagePaths.first,
                isLiveCapture: mappedData.isLiveCapture,
                fieldNotes: resolvedFieldNotes
            )

            modelContext.insert(record)
        }
    }

    private func insertReplacingLocalScanRecord(
        mappedData: SpeciesData,
        recordId: String,
        speciesId: String,
        timestamp: Date,
        captureDate: Date,
        capturedMediaJSON: String?,
        coverImagePath: String?,
        isLiveCapture: Bool,
        fieldNotes: String?
    ) {
        deleteLocalScanRecordIfPresent(id: recordId)

        let record = buildScanRecord(
            from: mappedData,
            recordId: recordId,
            speciesId: speciesId,
            timestamp: timestamp,
            captureDate: captureDate,
            capturedMediaJSON: capturedMediaJSON,
            coverImagePath: coverImagePath,
            isLiveCapture: isLiveCapture,
            fieldNotes: fieldNotes
        )
        modelContext.insert(record)
    }

    private func decodedObservationContexts(from observationContextsJSON: [String]?) -> [ObservationContext] {
        guard let observationContextsJSON else { return [] }
        return observationContextsJSON.compactMap { contextJSON in
            guard let data = contextJSON.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(ObservationContext.self, from: data)
        }
    }

    private func buildCapturedMediaJSON(
        localImagePaths: [String]? = nil,
        observationContextsJSON: [String]? = nil,
        audioFilePaths: [String]? = nil,
        videoFilePaths: [String]? = nil,
        mediaTimeline: [CaptureSubmissionMediaItem]? = nil
    ) async -> String? {
        let resolvedLocalImagePaths = localImagePaths ?? []
        let resolvedObservationContexts = decodedObservationContexts(from: observationContextsJSON)
        let resolvedAudioFilePaths = audioFilePaths ?? []
        let resolvedVideoFilePaths = videoFilePaths ?? []
        let resolvedMediaTimeline = mediaTimeline ?? CaptureSubmissionMediaItem.defaultTimeline(
            imageCount: resolvedLocalImagePaths.count,
            observationContexts: resolvedObservationContexts,
            audioFilePaths: resolvedAudioFilePaths,
            videoFilePaths: resolvedVideoFilePaths
        )

        var mediaItems: [SerializedMediaItem] = []

        for item in resolvedMediaTimeline {
            switch item {
            case .image(let index):
                guard resolvedLocalImagePaths.indices.contains(index) else { continue }
                mediaItems.append(.image(StoredMediaReference(legacyPath: resolvedLocalImagePaths[index])))
            case .description(let context):
                guard !context.isEmpty else { continue }
                mediaItems.append(.description(context))
            case .audio(let sourcePath):
                if let persistedPath = await FileIOActor.shared.persistAudioFile(tempPath: sourcePath) {
                    mediaItems.append(.audio(.documents(persistedPath)))
                }
            case .video(let sourcePath, let posterImageIndex, let audioFilePath):
                if let persistedPath = await FileIOActor.shared.persistVideoFile(tempPath: sourcePath) {
                    let thumbnail = posterImageIndex.flatMap { index -> StoredMediaReference? in
                        guard resolvedLocalImagePaths.indices.contains(index) else { return nil }
                        return StoredMediaReference(legacyPath: resolvedLocalImagePaths[index])
                    }
                    let audio: StoredMediaReference?
                    if let audioFilePath,
                       let persistedAudioPath = await FileIOActor.shared.persistAudioFile(tempPath: audioFilePath) {
                        audio = .documents(persistedAudioPath)
                    } else {
                        audio = nil
                    }
                    mediaItems.append(.video(StoredVideoMediaReference(
                        video: .documents(persistedPath),
                        thumbnail: thumbnail,
                        audio: audio
                    )))
                }
            }
        }

        guard !mediaItems.isEmpty else { return nil }
        return (try? JSONEncoder().encode(mediaItems)).flatMap { String(data: $0, encoding: .utf8) }
    }

    // MARK: - Live Scan Recording

    /// Persists a real-time scan result to SwiftData on the actor thread.
    func saveLiveScanRecord(
        mappedData: SpeciesData,
        localImagePaths: [String],
        observationContextsJSON: [String]? = nil,
        audioFilePaths: [String]? = nil,
        videoFilePaths: [String]? = nil,
        mediaTimeline: [CaptureSubmissionMediaItem]? = nil,
        persistenceFence: LiveInferencePersistenceFence? = nil
    ) async -> LiveInferencePersistenceResult {
        guard mappedData.confidenceScore > 0.0, !localImagePaths.isEmpty else {
            return .notSaved
        }
        guard livePersistenceFenceMatchesResult(
            persistenceFence,
            mappedScanId: mappedData.scanId
        ) else {
            return .notSaved
        }

        let recordId = mappedData.scanId ?? UUID().uuidString
        let persistenceScanId = persistenceFence?.scanId ?? recordId
        if let persistenceFence {
            await ScanInferencePersistenceCoordinator.shared.acquire(
                scanId: persistenceScanId
            )
            guard await livePersistenceFenceIsCurrentAssumingPersistenceLock(
                persistenceFence
            ) else {
                await ScanInferencePersistenceCoordinator.shared.release(
                    scanId: persistenceScanId
                )
                return .notSaved
            }
        }

        await acquireFinalizationLock(scanId: recordId, operation: "live_visual")
        if let persistenceFence {
            let isCurrent =
                await livePersistenceFenceIsCurrentAssumingPersistenceLock(
                    persistenceFence
                )
            if !isCurrent {
                await ScanFinalizationCoordinator.shared.release(
                    scanId: recordId
                )
                await ScanInferencePersistenceCoordinator.shared.release(
                    scanId: persistenceScanId
                )
                return .notSaved
            }
        }
        let (activeSpeciesId, isNewDiscovery) = resolveSpeciesIdAndDiscoveryStatus(for: mappedData.scientificName)

        let capturedMediaJSON = await buildCapturedMediaJSON(
            localImagePaths: localImagePaths,
            observationContextsJSON: observationContextsJSON,
            audioFilePaths: audioFilePaths,
            videoFilePaths: videoFilePaths,
            mediaTimeline: mediaTimeline
        )
        if let persistenceFence {
            let isCurrent =
                await livePersistenceFenceIsCurrentAssumingPersistenceLock(
                    persistenceFence
                )
            if !isCurrent {
                await ScanFinalizationCoordinator.shared.release(
                    scanId: recordId
                )
                await ScanInferencePersistenceCoordinator.shared.release(
                    scanId: persistenceScanId
                )
                return .notSaved
            }
        }

        let preservedFieldNotes = resolvedFieldNotesText(for: recordId)

        // Prevent duplicate insertion collisions or silent drops from offline queue background races.
        // If the offline queue already inserted a skeleton/partial record, purge it so the
        // comprehensive live inference result (which correctly includes audio paths) takes over.
        insertReplacingLocalScanRecord(
            mappedData: mappedData,
            recordId: recordId,
            speciesId: activeSpeciesId,
            timestamp: Date(),
            captureDate: Date(), // Live captures always match current time
            capturedMediaJSON: capturedMediaJSON,
            coverImagePath: localImagePaths.first,
            isLiveCapture: mappedData.isLiveCapture,
            fieldNotes: preservedFieldNotes
        )
        if persistenceFence != nil, Task.isCancelled {
            modelContext.rollback()
            await ScanFinalizationCoordinator.shared.release(scanId: recordId)
            await ScanInferencePersistenceCoordinator.shared.release(
                scanId: persistenceScanId
            )
            return .notSaved
        }
        do {
            try modelContext.save()
            await ScanFinalizationCoordinator.shared.release(scanId: recordId)
        } catch {
            modelContext.rollback()
            MerianLog.data.error("saveLiveScanRecord: save failed: \(error, privacy: .private)")
            await ScanFinalizationCoordinator.shared.release(scanId: recordId)
            if persistenceFence != nil {
                await ScanInferencePersistenceCoordinator.shared.release(
                    scanId: persistenceScanId
                )
            }
            return .notSaved
        }
        if persistenceFence != nil {
            await ScanInferencePersistenceCoordinator.shared.release(
                scanId: persistenceScanId
            )
        }
        return LiveInferencePersistenceResult(
            wasSaved: true,
            isNewDiscovery: isNewDiscovery
        )
    }

    // MARK: - Non-Visual Recording

    /// Persists a non-visual scan result with no captured image.
    ///
    /// Handles description-only, audio-only, audio+description, and other future no-image
    /// combinations. Records are saved with `is_live_capture = false` and no cover image path,
    /// allowing the library to fall back to reference imagery when available.
    func saveNonVisualRecord(
        mappedData: SpeciesData,
        observationContextsJSON: [String]? = nil,
        audioFilePaths: [String]? = nil,
        videoFilePaths: [String]? = nil,
        mediaTimeline: [CaptureSubmissionMediaItem]? = nil,
        persistenceFence: LiveInferencePersistenceFence? = nil
    ) async -> LiveInferencePersistenceResult {
        guard mappedData.confidenceScore > 0.0 else { return .notSaved }
        guard livePersistenceFenceMatchesResult(
            persistenceFence,
            mappedScanId: mappedData.scanId
        ) else {
            return .notSaved
        }

        let recordId = mappedData.scanId ?? UUID().uuidString
        let persistenceScanId = persistenceFence?.scanId ?? recordId
        if let persistenceFence {
            await ScanInferencePersistenceCoordinator.shared.acquire(
                scanId: persistenceScanId
            )
            guard await livePersistenceFenceIsCurrentAssumingPersistenceLock(
                persistenceFence
            ) else {
                await ScanInferencePersistenceCoordinator.shared.release(
                    scanId: persistenceScanId
                )
                return .notSaved
            }
        }

        await acquireFinalizationLock(scanId: recordId, operation: "live_nonvisual")
        if let persistenceFence {
            let isCurrent =
                await livePersistenceFenceIsCurrentAssumingPersistenceLock(
                    persistenceFence
                )
            if !isCurrent {
                await ScanFinalizationCoordinator.shared.release(
                    scanId: recordId
                )
                await ScanInferencePersistenceCoordinator.shared.release(
                    scanId: persistenceScanId
                )
                return .notSaved
            }
        }
        let (activeSpeciesId, isNewDiscovery) = resolveSpeciesIdAndDiscoveryStatus(for: mappedData.scientificName)

        let capturedMediaJSON = await buildCapturedMediaJSON(
            observationContextsJSON: observationContextsJSON,
            audioFilePaths: audioFilePaths,
            videoFilePaths: videoFilePaths,
            mediaTimeline: mediaTimeline
        )
        if let persistenceFence {
            let isCurrent =
                await livePersistenceFenceIsCurrentAssumingPersistenceLock(
                    persistenceFence
                )
            if !isCurrent {
                await ScanFinalizationCoordinator.shared.release(
                    scanId: recordId
                )
                await ScanInferencePersistenceCoordinator.shared.release(
                    scanId: persistenceScanId
                )
                return .notSaved
            }
        }

        let preservedFieldNotes = resolvedFieldNotesText(for: recordId)
        insertReplacingLocalScanRecord(
            mappedData: mappedData,
            recordId: recordId,
            speciesId: activeSpeciesId,
            timestamp: Date(),
            captureDate: Date(),
            capturedMediaJSON: capturedMediaJSON,
            coverImagePath: nil,
            isLiveCapture: false,
            fieldNotes: preservedFieldNotes
        )
        if persistenceFence != nil, Task.isCancelled {
            modelContext.rollback()
            await ScanFinalizationCoordinator.shared.release(scanId: recordId)
            await ScanInferencePersistenceCoordinator.shared.release(
                scanId: persistenceScanId
            )
            return .notSaved
        }
        do {
            try modelContext.save()
            await ScanFinalizationCoordinator.shared.release(scanId: recordId)
        } catch {
            modelContext.rollback()
            MerianLog.data.error("saveNonVisualRecord: save failed: \(error, privacy: .private)")
            await ScanFinalizationCoordinator.shared.release(scanId: recordId)
            if persistenceFence != nil {
                await ScanInferencePersistenceCoordinator.shared.release(
                    scanId: persistenceScanId
                )
            }
            return .notSaved
        }
        if persistenceFence != nil {
            await ScanInferencePersistenceCoordinator.shared.release(
                scanId: persistenceScanId
            )
        }
        return LiveInferencePersistenceResult(
            wasSaved: true,
            isNewDiscovery: isNewDiscovery
        )
    }

    // MARK: - Wikipedia Enrichment

    /// Retroactively hydrates a scan record with Wikipedia data post-inference.
    func updateScanWithWikipedia(scanId: String, extract: String?, url: String?, imageUrl: String?) {
        var descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let record: LocalScanRecord?
        do {
            record = try modelContext.fetch(descriptor).first
        } catch {
            MerianLog.data.debug("updateScanWithWikipedia: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return
        }
        guard let record else { return }

        if let extract { record.wikipediaOverview = extract }
        if let url { record.wikipediaUrl = url }
        if let imageUrl, !imageUrl.isEmpty {
            record.referenceImageUrl = ExternalReferenceImagePolicy.sanitizedURLList(
                imageUrl
            )
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            MerianLog.data.error("updateScanWithWikipedia: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
        }
    }

    // MARK: - Record Mutation

    /// Fetches a single `LocalScanRecord` by ID, applies `mutation`, and saves.
    /// All point-update methods below delegate here to keep fetch-mutate-save DRY.
    private func mutateScan(id: String, mutation: (LocalScanRecord) -> Void) {
        var descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        mutation(record)
        do { try modelContext.save() } catch {
            modelContext.rollback()
            MerianLog.data.error("mutateScan: save failed for \(id, privacy: .private): \(error, privacy: .private)")
        }
    }

    // MARK: - Species Enrichment

    /// Patches a scan record with post-inference enrichment data from the `enrich-scan` Edge function.
    /// Each parameter is optional — callers pass only the fields their scope resolved, nil fields are skipped.
    func updateScanWithEnrichment(
        scanId: String,
        habitatDescription: String?,
        gbifTaxonKey: Int?,
        similarSpeciesJsonData: Data?,
        taxonomy: EdgeResponse.Taxonomy?,
        alternativeCommonNames: [String]? = nil
    ) {
        mutateScan(id: scanId) { record in
            if let habitat = habitatDescription { record.habitatDescription = habitat }
            if let key = gbifTaxonKey { record.gbifTaxonKey = key }
            if let jsonData = similarSpeciesJsonData { record.lookalikesData = jsonData }
            if let tax = taxonomy {
                record.taxonomyKingdom = tax.kingdom
                record.taxonomyPhylum = tax.phylum
                record.taxonomyClass = tax.`class`
                record.taxonomyOrder = tax.order
                record.taxonomyFamily = tax.family
                record.taxonomyGenus = tax.genus
            }
            if let names = alternativeCommonNames { record.alternativeCommonNames = names }
        }
    }

    /// One-time recovery path for stale similar-species caches written before the backend
    /// began enforcing validated taxonomy. Clearing both the rich blob and legacy flat
    /// array forces future scan opens to rehydrate from the server under the new rules.
    func clearAllLocalLookalikesCache() {
        let batchSize = 200

        while true {
            var descriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate {
                    $0.isBiological == true &&
                    ($0.lookalikesData != nil || $0.similarSpecies != nil)
                },
                sortBy: [SortDescriptor(\.timestamp)]
            )
            descriptor.fetchLimit = batchSize

            let records: [LocalScanRecord]
            do {
                records = try modelContext.fetch(descriptor)
            } catch {
                MerianLog.data.error("clearAllLocalLookalikesCache: fetch failed: \(error, privacy: .private)")
                return
            }

            guard !records.isEmpty else { return }

            for record in records {
                record.lookalikesData = nil
                record.similarSpecies = nil
            }

            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                MerianLog.data.error("clearAllLocalLookalikesCache: save failed: \(error, privacy: .private)")
                return
            }
        }
    }

    // MARK: - Identification Override Persistence

    /// Persists the user's identification review action to the local SwiftData store.
    /// - Parameters:
    ///   - scanId: The scan record to update.
    ///   - override: The scientific name the user selected, or nil to clear.
    ///   - newConfirmedSpeciesId: The definitive species UUID (either the AI original or an override candidate).
    func updateScanWithOverride(
        scanId: String,
        override: String?,
        confirmed: Bool,
        newConfirmedSpeciesId: String?,
        userReviewState: UserReviewState
    ) {
        mutateScan(id: scanId) { record in
            record.userIdentificationOverride = override
            record.userConfirmedIdentification = confirmed
            record.confirmedSpeciesId = newConfirmedSpeciesId
            record.userReviewState = userReviewState
        }
    }

    /// Persists the species-dictionary data fetched for an identification override or reset,
    /// so the corrected species fields survive sheet dismissal and reopen.
    ///
    /// `scientificName` is deliberately excluded — that column is preserved as the authoritative
    /// original-AI identifier and is reused as `aiScientificName` on `load(from:)`. This allows
    /// `resetIdentificationReview` to recover the original name without a separate schema field.
    func updateScanWithOverrideSpeciesData(
        scanId: String,
        commonName: String,
        hazardType: String,
        wikipediaOverview: String?,
        wikipediaUrl: String?,
        referenceImageUrl: String?,
        iucnRedListStatus: String?,
        habitatDescription: String?,
        gbifTaxonKey: Int?,
        taxonomy: TaxonomyData?
    ) {
        mutateScan(id: scanId) { record in
            record.commonName = commonName
            record.hazardType = hazardType
            record.wikipediaOverview = wikipediaOverview
            record.wikipediaUrl = wikipediaUrl
            record.referenceImageUrl = ExternalReferenceImagePolicy.sanitizedURLList(
                referenceImageUrl
            )
            record.iucnRedListStatus = iucnRedListStatus
            record.habitatDescription = habitatDescription
            record.gbifTaxonKey = gbifTaxonKey
            if let tax = taxonomy {
                record.taxonomyKingdom = tax.kingdom
                record.taxonomyPhylum = tax.phylum
                record.taxonomyClass = tax.className
                record.taxonomyOrder = tax.order
                record.taxonomyFamily = tax.family
                record.taxonomyGenus = tax.genus
            }
        }
    }

    /// Persists the user's manual review flag to the local SwiftData store.
    func updateScanAsFlagged(scanId: String) {
        mutateScan(id: scanId) { $0.isFlagged = true }
    }

    /// Removes the user's manual review flag from the local SwiftData store.
    func updateScanAsUnflagged(scanId: String) {
        mutateScan(id: scanId) { $0.isFlagged = false }
    }

    // MARK: - Collections Edge Sync

    struct SyncCollectionPayload: Encodable, Equatable, Sendable {
        let id: String
        let name: String
        let created_at: String
        let is_deleted: Bool
        let scan_ids: [String]
    }

    struct SyncRequestPayload: Encodable, Sendable {
        let collections: [SyncCollectionPayload]
    }

    /// Projects only syncable collection rows and their direct inverse memberships.
    ///
    /// This deliberately avoids paging through every `LocalScanRecord`: unrelated scans do
    /// not participate in a collection mutation, and OFFSET pages become progressively more
    /// expensive as a library grows. Sorting IDs also makes retries byte-for-byte stable.
    func collectionSyncPayloads() -> [SyncCollectionPayload]? {
        var descriptor = FetchDescriptor<ScanCollection>(
            predicate: #Predicate { $0.name != "Favorites" },
            sortBy: [
                SortDescriptor(\.createdAt),
                SortDescriptor(\.id)
            ]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.scans]

        let collections: [ScanCollection]
        do {
            collections = try modelContext.fetch(descriptor)
        } catch {
            MerianLog.data.debug(
                "collectionSyncPayloads: collection fetch failed: \(error, privacy: .private)"
            )
            return nil
        }

        return collections.map { collection in
            SyncCollectionPayload(
                id: collection.id,
                name: collection.name,
                created_at: DateUtilities.iso8601Formatter.string(from: collection.createdAt),
                is_deleted: collection.isDeleted,
                scan_ids: Array(Set((collection.scans ?? []).map(\.id))).sorted()
            )
        }
    }

    func pushCollectionsToEdge() async -> Bool {
        guard let payloadList = collectionSyncPayloads() else { return false }

        do {
            try await SupabaseManager.shared.client.functions.invoke(
                "sync-collections",
                options: .init(body: SyncRequestPayload(collections: payloadList))
            )
            
            // Cloud sync confirmed — purge soft-deleted tombstones so they cannot resurface on reinstall.
            let tombstoneIDs = payloadList.filter { $0.is_deleted }.map(\.id)
            let tombstones: [ScanCollection]
            if tombstoneIDs.isEmpty {
                tombstones = []
            } else {
                let descriptor = FetchDescriptor<ScanCollection>(
                    predicate: #Predicate { tombstoneIDs.contains($0.id) }
                )
                do {
                    tombstones = try modelContext.fetch(descriptor)
                } catch {
                    MerianLog.data.error(
                        "pushCollectionsToEdge: failed to refetch synced collection tombstones: \(error, privacy: .private)"
                    )
                    return false
                }
            }
            for tombstone in tombstones {
                modelContext.delete(tombstone)
            }
            if !tombstones.isEmpty {
                do {
                    try modelContext.save()
                } catch {
                    modelContext.rollback()
                    MerianLog.data.error("pushCollectionsToEdge: failed to purge synced collection tombstones: \(error, privacy: .private)")
                    return false
                }
            }
            
            MerianLog.data.debug("✅ Pushed \(payloadList.count, privacy: .public) collections to Edge (\(tombstones.count, privacy: .public) tombstones purged)")
            return true
        } catch {
            MerianLog.data.debug("pushCollectionsToEdge: sync failed: \(error, privacy: .private)")
            return false
        }
    }
}
