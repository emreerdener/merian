import Foundation
import SwiftData

extension OfflineQueueManager {
    // MARK: - Cloud Deletions

    /// Drains the `PendingCloudDeletionTask` queue, calling the delete Edge function for each record.
    ///
    /// A task is removed only after an explicitly validated success response.
    /// Ordinary failures retain the task for retry. A server-refused legacy
    /// history deletion is held durably until explicit reconciliation exists.
    func syncPendingDeletions(
        accountWork: CloudDeletionAccountWork? = nil,
        scheduler: OfflineJobScheduler? = nil,
        deleteScan: @escaping @Sendable (String, UUID) async throws -> Void = {
            try await MerianNetworkClient.shared.deleteScan(scanId: $0, expectedOwnerID: $1)
        }
    ) async {
        let accountWork = accountWork ?? .live
        let scheduler = scheduler ?? .shared
        guard isOnline, let context = modelContext else { return }
        guard !isCloudDeletionSyncing else { return }
        guard let lease = try? accountWork.begin() else { return }
        defer { accountWork.finish(lease) }
        guard accountWork.isCurrent(lease) else { return }
        isCloudDeletionSyncing = true
        defer {
            isCloudDeletionSyncing = false
            scheduler.scheduleNextPersistedWake(using: self)
        }

        let now = Date()
        var didPrepareJob = false
        let runnableTasks: [(task: PendingCloudDeletionTask, job: OfflineJobRecord)]
        do {
            runnableTasks = try prepareCloudDeletionBatch(
                context: context, now: now, accountID: lease.session.userID,
                didPrepareJob: &didPrepareJob
            )
            if didPrepareJob {
                try context.save()
                scheduler.scheduleNextPersistedWake(using: self)
            }
        } catch {
            context.rollback()
            MerianLog.data.error("syncPendingDeletions: failed to prepare deletion jobs: \(error, privacy: .private)")
            return
        }

        guard !runnableTasks.isEmpty else { return }

        for candidate in runnableTasks {
            let task = candidate.task
            let job = candidate.job
            job.status = .running
            job.updatedAt = now
            job.lastAttemptAt = now
            job.nextRunAt = nil
            context.insert(OfflineQueueEvent(
                jobId: job.id,
                scanId: task.scanId,
                kind: .claimed,
                message: "Cloud deletion started."
            ))
        }

        do {
            try context.save()
            scheduler.scheduleNextPersistedWake(using: self)
        } catch {
            context.rollback()
            MerianLog.data.error("syncPendingDeletions: failed to claim deletion jobs: \(error, privacy: .private)")
            return
        }

        // Fetch O(n) results using the batch dispatcher
        let scanIds = runnableTasks.map(\.task.scanId)
        let allResults = await dispatchDeleteBatches(scanIds: scanIds, accountID: lease.session.userID, deleteScan: deleteScan)
        guard accountWork.isCurrent(lease), modelContext === context else { return }

        // Build an O(1) lookup so the per-result loop below doesn't scan the full
        // pendingTasks array for each result (was O(n²) when the batch was large).
        let taskById = Dictionary(
            uniqueKeysWithValues: runnableTasks.map {
                ($0.task.scanId, $0.task)
            }
        )
        var didMutate = false
        for (scanId, error) in allResults {
            guard let task = taskById[scanId] else { continue }
            do {
                if Self.cloudDeletionWasConfirmed(error: error) {
                    MerianLog.data.debug("✅ Deleted \(scanId, privacy: .private) from Edge")
                    try markCloudDeletionJob(
                        scanId: scanId,
                        success: true,
                        error: nil,
                        context: context
                    )
                    let detailJobs = try context.fetch(FetchDescriptor<OfflineJobRecord>()).filter {
                        $0.id.hasPrefix("library-details:") && $0.subjectId == scanId
                    }
                    for job in detailJobs {
                        guard let json = job.metadataJSON,
                              let payload = try? JSONDecoder().decode(LibraryDetailsSyncService.Mutation.self, from: Data(json.utf8)),
                              payload.ownerID == lease.session.userID else { continue }
                        job.status = .cancelled
                    }
                    FieldNotesStore.setFieldNotes(nil, for: scanId)
                    context.delete(task)
                    didMutate = true
                } else if let error {
                    MerianLog.data.error("syncPendingDeletions: failed for \(scanId, privacy: .private): \(error, privacy: .private)")
                    try markCloudDeletionJob(
                        scanId: scanId,
                        success: false,
                        error: error,
                        context: context
                    )
                    didMutate = true
                }
            } catch {
                context.rollback()
                MerianLog.data.error(
                    "syncPendingDeletions: result job fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
                )
                return
            }
        }

        if didMutate {
            do {
                try context.save()
                scheduler.scheduleNextPersistedWake(using: self)
            } catch {
                context.rollback()
                MerianLog.data.error("syncPendingDeletions: save failed: \(error, privacy: .private)")
            }
        }
    }

    static let cloudDeletionHistoryHoldCode = "legacy_observation_delete_requires_upgrade"

    static func cloudDeletionRequiresHistoryReview(error: Error) -> Bool {
        guard case MerianError.httpError(statusCode: 409, message: _) = error else {
            return false
        }
        return EdgeFunctionErrorPolicy.stableCode(from: error) == cloudDeletionHistoryHoldCode
    }

    /// Uses existing durable job fields; no SwiftData shape or historical
    /// schema changes. The code fences even a contradictory generic job status.
    static func cloudDeletionIsHeld(_ job: OfflineJobRecord) -> Bool {
        job.lastErrorCode == cloudDeletionHistoryHoldCode ||
            job.lastErrorCode == CloudDeletionIntent.legacyHoldCode
    }

    static let cloudDeletionDiscoveryJobID = "cloud-deletion-discovery"

    private struct CloudDeletionDiscoveryCursor: Codable {
        let version: Int
        let timestamp: Date
        let scanID: String
        let accountID: UUID
        var offeredWork: Bool?
    }

    /// Inspect at most two 200-row pages and dispatch at most 200 tasks.
    /// Persist the keyset cursor and scheduler wake even when every row is held.
    /// EOF resets the cursor so newly inserted earlier rows join the next sweep.
    private func prepareCloudDeletionBatch(
        context: ModelContext,
        now: Date,
        accountID: UUID,
        didPrepareJob: inout Bool
    ) throws -> [(task: PendingCloudDeletionTask, job: OfflineJobRecord)] {
        let batchLimit = 200
        let continuation = try context.fetchOfflineJob(id: Self.cloudDeletionDiscoveryJobID)
        var cursor = continuation?.metadataJSON.flatMap {
            try? JSONDecoder().decode(CloudDeletionDiscoveryCursor.self, from: Data($0.utf8))
        }
        // Another account's sweep may have skipped this account's earlier tasks.
        // Old unbound cursors also restart; neither cursor format is authority.
        if cursor?.version != 2 || cursor?.accountID != accountID { cursor = nil }
        let needsRewind = cursor?.offeredWork == true
        var offeredWork = needsRewind
        var exhausted = false
        var runnable: [(task: PendingCloudDeletionTask, job: OfflineJobRecord)] = []
        for _ in 0..<2 {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<PendingCloudDeletionTask>(sortBy: [
                SortDescriptor(\.timestamp),
                // Match the predicate's lexical > comparison; the default
                // localized numeric ordering can skip/revisit UUID ties.
                SortDescriptor(\.scanId, comparator: .lexical)
            ])
            descriptor.fetchLimit = batchLimit
            if let cursor {
                let afterDate = cursor.timestamp
                let afterID = cursor.scanID
                descriptor.predicate = #Predicate {
                    $0.timestamp > afterDate || ($0.timestamp == afterDate && $0.scanId > afterID)
                }
            }
            let page = try context.fetch(descriptor)
            guard !page.isEmpty else { exhausted = true; break }
            var examined = 0
            for task in page {
                examined += 1
                cursor = CloudDeletionDiscoveryCursor(version: 2, timestamp: task.timestamp, scanID: task.scanId, accountID: accountID)
                let job = try ensureCloudDeletionJob(scanId: task.scanId, context: context)
                didPrepareJob = didPrepareJob || job.created
                let record = job.record
                guard !Self.cloudDeletionIsHeld(record) else { continue }
                guard let intent = CloudDeletionIntent.restoring(record.metadataJSON, scanID: task.scanId) else {
                    record.status = .needsAttention
                    record.nextRunAt = nil
                    record.updatedAt = now
                    record.lastErrorCode = CloudDeletionIntent.legacyHoldCode
                    record.lastErrorMessage = "This saved deletion needs account and intent review."
                    context.insert(OfflineQueueEvent(jobId: record.id, scanId: task.scanId,
                        kind: .needsAttention, message: record.lastErrorMessage,
                        errorCode: CloudDeletionIntent.legacyHoldCode))
                    didPrepareJob = true
                    continue
                }
                guard intent.requestingAccountID == accountID else { continue }
                if Self.cloudDeletionStatusRequiresRecovery(record.status) {
                    // Exhausted legacy retries and contradictory terminal states
                    // still recover, except the explicit history hold above.
                    record.status = .pending
                    record.updatedAt = now
                    record.nextRunAt = nil
                    didPrepareJob = true
                }
                guard isRunnableCloudDeletionStatus(record.statusRaw),
                      record.nextRunAt.map({ $0 <= now }) ?? true else { continue }
                offeredWork = true
                runnable.append((task, record))
                if runnable.count == batchLimit { break }
            }
            if examined == page.count && page.count < batchLimit {
                exhausted = true
                break
            }
            if runnable.count == batchLimit { break }
        }
        if exhausted {
            if let continuation {
                // A prior cursor may have committed before its offered batch
                // was dispatched/acknowledged. Rewind once so restartable jobs
                // behind it are not stranded without a retry deadline.
                continuation.status = needsRewind ? .waiting : .complete
                continuation.nextRunAt = needsRewind ? now.addingTimeInterval(1) : nil
                continuation.metadataJSON = nil
                continuation.updatedAt = now
                didPrepareJob = true
            }
        } else if var cursor {
            cursor.offeredWork = offeredWork
            let continuation = continuation ?? OfflineJobRecord(
                id: Self.cloudDeletionDiscoveryJobID, kind: .cloudDeletion, priority: 60
            )
            context.insert(continuation)
            continuation.status = .waiting
            continuation.nextRunAt = now.addingTimeInterval(1)
            continuation.metadataJSON = String(data: try JSONEncoder().encode(cursor), encoding: .utf8)
            continuation.updatedAt = now
            didPrepareJob = true
        }
        return runnable
    }

    /// No local error category proves remote erasure. In particular,
    /// `invalidResponse` can represent an auth/session failure or a malformed
    /// HTTP success body. Only a nil dispatch error means `deleteScan` decoded
    /// the Edge route's explicit `success: true` confirmation.
    static func cloudDeletionWasConfirmed(error: Error?) -> Bool {
        error == nil
    }

    /// A pending erasure cannot be cancelled or declared complete locally.
    /// Called only after excluding a durable history hold. These statuses
    /// came from an older exhausted retry budget or contradict
    /// the still-present durable task, so the next drain repairs them.
    static func cloudDeletionStatusRequiresRecovery(
        _ status: OfflineJobStatus
    ) -> Bool {
        switch status {
        case .needsAttention, .complete, .cancelled:
            true
        case .pending, .running, .waiting:
            false
        }
    }

    /// Cloud erasure retries never exhaust. The diagnostic attempt number is
    /// capped only so exponential delay remains bounded and corrupt persisted
    /// values cannot overflow.
    static func nextCloudDeletionRetryAttempt(after currentAttempt: Int) -> Int {
        let maximumAttempt = OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
        let boundedAttempt = min(max(0, currentAttempt), maximumAttempt)
        return min(boundedAttempt + 1, maximumAttempt)
    }

    /// Fans out deletions in batches to prevent unbounded concurrent network requests.
    /// Without a cap, a user returning from a week offline could saturate the pool and trigger rate limits.
    ///
    /// Batch size is hardware-aware: 10 concurrent sockets is the normal-operation ceiling,
    /// but in Low Power Mode the baseband chip is already constrained by the OS. Dropping to 3
    /// limits peak antenna transmit power, avoiding the thermal spike that cascades to CPU
    /// throttling and visible UI lag during large backlog drains.
    private func dispatchDeleteBatches(
        scanIds: [String],
        accountID: UUID,
        deleteScan: @escaping @Sendable (String, UUID) async throws -> Void
    ) async -> [(String, Error?)] {
        let batchSize = ProcessInfo.processInfo.isLowPowerModeEnabled ? 3 : 10
        var allResults: [(String, Error?)] = []
        allResults.reserveCapacity(scanIds.count)

        for batchStart in stride(from: 0, to: scanIds.count, by: batchSize) {
            let batch = Array(scanIds[batchStart..<min(batchStart + batchSize, scanIds.count)])
            let batchResults: [(String, Error?)] = await withTaskGroup(of: (String, Error?).self) { group in
                for scanId in batch {
                    group.addTask {
                        do {
                            try Task.checkCancellation()
                            try await deleteScan(scanId, accountID)
                            return (scanId, nil)
                        } catch {
                            return (scanId, error)
                        }
                    }
                }
                var collected: [(String, Error?)] = []
                for await result in group { collected.append(result) }
                return collected
            }
            allResults.append(contentsOf: batchResults)
        }
        return allResults
    }

    private func markCloudDeletionJob(
        scanId: String,
        success: Bool,
        error: Error?,
        context: ModelContext
    ) throws {
        let jobId = "cloud-deletion:\(scanId)"
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        descriptor.fetchLimit = 1
        guard let job = try context.fetch(descriptor).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        job.updatedAt = Date()
        if success {
            job.status = .complete
            job.nextRunAt = nil
            job.lastErrorCode = nil
            job.lastErrorMessage = nil
            job.lastHTTPStatus = nil
            context.insert(OfflineQueueEvent(
                jobId: job.id,
                scanId: scanId,
                kind: .completed,
                message: "Cloud deletion completed."
            ))
        } else if let error, Self.cloudDeletionRequiresHistoryReview(error: error) {
            // This is a refusal of legacy authority, not a failed erasure.
            // Keep the task and never turn it into an explicit history delete.
            job.status = .needsAttention
            job.nextRunAt = nil
            job.lastErrorCode = Self.cloudDeletionHistoryHoldCode
            job.lastHTTPStatus = 409
            job.lastErrorMessage = "Saved identification history needs review before this deletion can continue."
            context.insert(OfflineQueueEvent(
                jobId: job.id,
                scanId: scanId,
                kind: .needsAttention,
                message: job.lastErrorMessage,
                errorCode: Self.cloudDeletionHistoryHoldCode,
                httpStatus: 409
            ))
        } else {
            job.lastAttemptAt = Date()
            job.lastErrorMessage = error?.localizedDescription
            job.status = .waiting
            job.attemptCount = Self.nextCloudDeletionRetryAttempt(
                after: job.attemptCount
            )
            job.nextRunAt = Date().addingTimeInterval(
                OfflineQueueRetryPolicy.jitteredDelay(
                    forAttempt: job.attemptCount,
                    scope: .maintenance
                )
            )
            job.lastErrorCode = "cloud_deletion_failed"
            context.insert(OfflineQueueEvent(
                jobId: job.id,
                scanId: scanId,
                kind: .retryScheduled,
                message: error?.localizedDescription,
                errorCode: "cloud_deletion_failed"
            ))
        }
    }

    private func isRunnableCloudDeletionStatus(_ statusRaw: String) -> Bool {
        statusRaw == OfflineJobStatus.pending.rawValue ||
            statusRaw == OfflineJobStatus.waiting.rawValue ||
            statusRaw == OfflineJobStatus.running.rawValue
    }

    private func ensureCloudDeletionJob(
        scanId: String,
        context: ModelContext
    ) throws -> (record: OfflineJobRecord, created: Bool) {
        let jobId = "cloud-deletion:\(scanId)"
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return (existing, false)
        }

        let record = OfflineJobRecord(
            id: jobId,
            kind: .cloudDeletion,
            subjectId: scanId,
            priority: 60
        )
        context.insert(record)
        context.insert(OfflineQueueEvent(
            jobId: jobId,
            scanId: scanId,
            kind: .queued,
            message: "Queued cloud deletion."
        ))
        return (record, true)
    }
}
