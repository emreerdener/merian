import Foundation
import SwiftData

extension OfflineQueueManager {
    // MARK: - Collections

    /// Marks collections as needing sync and attempts to push them immediately if online.
    /// The "Favorites" collection is excluded — it is managed locally only.
    func enqueueCollectionSync() {
        markCollectionSyncPending()
        syncCollectionsIfPending()
    }

    var hasPendingCollectionSyncJob: Bool {
        guard let context = modelContext else {
            return UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        }
        do {
            guard let job = try fetchCollectionSyncJob(context: context) else {
                return false
            }
            return isActiveCollectionSyncStatus(job.statusRaw)
        } catch {
            MerianLog.data.error(
                "hasPendingCollectionSyncJob: fetch failed: \(error, privacy: .private)"
            )
            return true
        }
    }

    private var isCollectionSyncJobRunnable: Bool {
        guard let context = modelContext else {
            return UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        }
        let job: OfflineJobRecord?
        do {
            job = try fetchCollectionSyncJob(context: context)
        } catch {
            MerianLog.data.error(
                "isCollectionSyncJobRunnable: fetch failed: \(error, privacy: .private)"
            )
            return false
        }
        guard let job, isActiveCollectionSyncStatus(job.statusRaw) else {
            return false
        }
        if let nextRunAt = job.nextRunAt, nextRunAt > Date() { return false }
        return true
    }

    private func fetchCollectionSyncJob(
        context: ModelContext
    ) throws -> OfflineJobRecord? {
        try context.fetchOfflineJob(id: Self.collectionSyncJobId)
    }

    private func isActiveCollectionSyncStatus(_ statusRaw: String) -> Bool {
        statusRaw == OfflineJobStatus.pending.rawValue ||
            statusRaw == OfflineJobStatus.waiting.rawValue ||
            statusRaw == OfflineJobStatus.running.rawValue
    }

    /// Pushes local `ScanCollection` records to the `sync-collections` Edge function if changes are pending.
    /// No-ops when offline or unauthenticated.
    func syncCollectionsIfPending() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.drainCollectionSyncIfPossible()
        }
    }

    /// Shared collection-sync drain used by both fire-and-forget UI edits and the
    /// launch-time historical sync. This guarantees all collection pushes pass through
    /// the same single-flight latch, so a stale upsert can never race a newer tombstone.
    @discardableResult
    func drainCollectionSyncIfPossible() async -> Bool {
        while hasPendingCollectionSyncJob {
            guard isOnline,
                  SupabaseManager.shared.allowsUnownedAccountBoundWork else {
                return false
            }
            guard isCollectionSyncJobRunnable else { return false }

            if let existingTask = collectionSyncTask {
                let didSucceed = await existingTask.value
                guard didSucceed else { return false }
                continue
            }

            guard let container = modelContext?.container else { return false }

            let capturedRevision = collectionSyncRevision
            isCollectionSyncing = true
            guard markCollectionSyncStarted() else {
                isCollectionSyncing = false
                return false
            }

            let task = BackgroundTaskWrapper.execute(name: "CollectionSync") { [weak self] _ in
                guard let self else { return false }
                let success = await CollectionSyncService(
                    dependencies: .live
                ).sync(modelContainer: container)

                await MainActor.run {
                    self.finishCollectionSyncAttempt(success: success, capturedRevision: capturedRevision)
                }

                return success
            }

            collectionSyncTask = task
            let didSucceed = await task.value
            guard didSucceed else { return false }
        }

        return true
    }

    /// Auth transitions close the dispatch gate before awaiting the one
    /// collection mutation that may already be in flight. This preserves the
    /// source session until that operation reaches a terminal local outcome;
    /// no new collection job can start while the transition owns Auth.
    func awaitCollectionSyncQuiescenceForAuthTransition() async {
        while let task = collectionSyncTask {
            _ = await task.value
        }
    }

    func markCollectionSyncPending() {
        collectionSyncRevision &+= 1
        guard let context = modelContext else {
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.needsCollectionSync)
            return
        }
        do {
            let job = try context.ensureOfflineJobRecord(
                id: Self.collectionSyncJobId,
                kind: .collectionSync,
                priority: 80
            )
            job.status = .pending
            job.attemptCount = 0
            job.updatedAt = Date()
            job.nextRunAt = nil
            job.lastErrorCode = nil
            job.lastErrorMessage = nil
            context.insert(OfflineQueueEvent(
                jobId: job.id,
                kind: .queued,
                message: "Queued collection sync."
            ))
            try context.save()
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.needsCollectionSync)
        } catch {
            context.rollback()
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.needsCollectionSync)
            MerianLog.data.error("markCollectionSyncPending: save failed: \(error, privacy: .private)")
        }
    }

    func finishCollectionSyncAttempt(success: Bool, capturedRevision: UInt64) {
        isCollectionSyncing = false
        collectionSyncTask = nil

        guard let context = modelContext else {
            if success, collectionSyncRevision == capturedRevision {
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.needsCollectionSync)
            }
            return
        }

        let job: OfflineJobRecord?
        do {
            job = try fetchCollectionSyncJob(context: context)
        } catch {
            MerianLog.data.error(
                "finishCollectionSyncAttempt: fetch failed: \(error, privacy: .private)"
            )
            return
        }
        guard let job else { return }
        job.updatedAt = Date()
        if success, collectionSyncRevision == capturedRevision {
            job.status = .complete
            job.nextRunAt = nil
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.needsCollectionSync)
            context.insert(OfflineQueueEvent(jobId: job.id, kind: .completed, message: "Collection sync completed."))
        } else if !success {
            job.lastAttemptAt = Date()
            if OfflineQueueRetryPolicy.canScheduleAutomaticRetry(currentAttempt: job.attemptCount) {
                job.attemptCount += 1
                job.status = .waiting
                job.nextRunAt = Date().addingTimeInterval(
                    OfflineQueueRetryPolicy.jitteredDelay(
                        forAttempt: job.attemptCount,
                        scope: .maintenance
                    )
                )
                job.lastErrorCode = "collection_sync_failed"
                context.insert(OfflineQueueEvent(
                    jobId: job.id,
                    kind: .retryScheduled,
                    message: "Collection sync will retry.",
                    errorCode: "collection_sync_failed"
                ))
            } else {
                job.status = .needsAttention
                job.nextRunAt = nil
                job.lastErrorCode = "collection_sync_retry_limit_reached"
                context.insert(OfflineQueueEvent(
                    jobId: job.id,
                    kind: .needsAttention,
                    message: "Collection sync paused after repeated failures.",
                    errorCode: "collection_sync_retry_limit_reached"
                ))
            }
        }
        do {
            try context.save()
            OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        } catch {
            context.rollback()
            MerianLog.data.error("finishCollectionSyncAttempt: save failed: \(error, privacy: .private)")
        }
    }

    private func markCollectionSyncStarted() -> Bool {
        guard let context = modelContext else { return false }
        let job: OfflineJobRecord?
        do {
            job = try fetchCollectionSyncJob(context: context)
        } catch {
            MerianLog.data.error(
                "markCollectionSyncStarted: fetch failed: \(error, privacy: .private)"
            )
            return false
        }
        guard let job else { return false }
        job.status = .running
        job.updatedAt = Date()
        job.lastAttemptAt = Date()
        job.nextRunAt = nil
        context.insert(OfflineQueueEvent(jobId: job.id, kind: .claimed, message: "Collection sync started."))
        do {
            try context.save()
            OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
            return true
        } catch {
            context.rollback()
            MerianLog.data.error("markCollectionSyncStarted: save failed: \(error, privacy: .private)")
            return false
        }
    }
}
