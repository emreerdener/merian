import Foundation
import SwiftData

extension OfflineQueueManager {
    // MARK: - Cloud Deletions

    /// Drains the `PendingCloudDeletionTask` queue, calling the delete Edge function for each record.
    ///
    /// A task is removed only after an explicitly validated success response.
    /// Authentication, malformed-response, transport, and server errors all
    /// retain the task for the next connectivity cycle.
    func syncPendingDeletions() async {
        guard isOnline, let context = modelContext else { return }
        guard !isCloudDeletionSyncing else { return }
        isCloudDeletionSyncing = true
        defer { isCloudDeletionSyncing = false }

        let pendingTasks: [PendingCloudDeletionTask]
        do {
            var descriptor = FetchDescriptor<PendingCloudDeletionTask>(sortBy: [SortDescriptor(\.timestamp)])
            descriptor.fetchLimit = 200
            pendingTasks = try context.fetch(descriptor)
        } catch {
            MerianLog.data.debug("syncPendingDeletions: fetch failed: \(error, privacy: .private)")
            return
        }

        guard !pendingTasks.isEmpty else { return }

        let now = Date()
        var didPrepareJob = false
        var runnableTasks: [(
            task: PendingCloudDeletionTask,
            job: OfflineJobRecord
        )] = []
        do {
            for task in pendingTasks {
                let job = try ensureCloudDeletionJob(
                    scanId: task.scanId,
                    context: context
                )
                if job.created {
                    didPrepareJob = true
                }
                let record = job.record
                if Self.cloudDeletionStatusRequiresRecovery(record.status) {
                    // PendingCloudDeletionTask is the durable source of truth.
                    // Older builds could pause an erasure permanently after the
                    // generic retry budget, while complete/cancelled here would
                    // contradict the still-present task. Heal every such state
                    // before applying its retry eligibility date.
                    record.status = .pending
                    record.updatedAt = now
                    record.nextRunAt = nil
                    didPrepareJob = true
                }
                guard isRunnableCloudDeletionStatus(record.statusRaw) else {
                    continue
                }
                if let nextRunAt = record.nextRunAt, nextRunAt > now {
                    continue
                }
                runnableTasks.append((task, record))
            }
        } catch {
            context.rollback()
            MerianLog.data.error(
                "syncPendingDeletions: deletion-job fetch failed: \(error, privacy: .private)"
            )
            return
        }

        if didPrepareJob {
            do {
                try context.save()
            } catch {
                context.rollback()
                MerianLog.data.error("syncPendingDeletions: failed to prepare deletion jobs: \(error, privacy: .private)")
                return
            }
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
            OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        } catch {
            context.rollback()
            MerianLog.data.error("syncPendingDeletions: failed to claim deletion jobs: \(error, privacy: .private)")
            return
        }

        // Fetch O(n) results using the batch dispatcher
        let scanIds = runnableTasks.map(\.task.scanId)
        let allResults = await dispatchDeleteBatches(scanIds: scanIds)

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
                OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
            } catch {
                context.rollback()
                MerianLog.data.error("syncPendingDeletions: save failed: \(error, privacy: .private)")
            }
        }
    }

    /// No local error category proves remote erasure. In particular,
    /// `invalidResponse` can represent an auth/session failure or a malformed
    /// HTTP success body. Only a nil dispatch error means `deleteScan` decoded
    /// the Edge route's explicit `success: true` confirmation.
    static func cloudDeletionWasConfirmed(error: Error?) -> Bool {
        error == nil
    }

    /// A pending erasure cannot be cancelled or declared complete locally.
    /// These statuses came from an older exhausted retry budget or contradict
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
    private func dispatchDeleteBatches(scanIds: [String]) async -> [(String, Error?)] {
        let batchSize = ProcessInfo.processInfo.isLowPowerModeEnabled ? 3 : 10
        var allResults: [(String, Error?)] = []
        allResults.reserveCapacity(scanIds.count)

        for batchStart in stride(from: 0, to: scanIds.count, by: batchSize) {
            let batch = Array(scanIds[batchStart..<min(batchStart + batchSize, scanIds.count)])
            let batchResults: [(String, Error?)] = await withTaskGroup(of: (String, Error?).self) { group in
                for scanId in batch {
                    group.addTask {
                        do {
                            try await MerianNetworkClient.shared.deleteScan(scanId: scanId)
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
