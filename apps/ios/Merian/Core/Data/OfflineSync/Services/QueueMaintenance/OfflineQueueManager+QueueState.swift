import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

extension OfflineQueueManager {
    /// Deletes an `OfflineQueuedScan` from the **main context** and saves,
    /// reliably triggering `@Query queuedScans` (and `@Query rawRecords`) in
    /// any open sheet to re-evaluate.
    ///
    /// **Why main-actor deletion is the only reliable trigger**:
    /// `BackgroundDatabaseActor` saves propagate via
    /// `NSPersistentStoreRemoteChangeNotification`, but SwiftData's `@Query`
    /// in a presented `.sheet` does not reliably respond to those remote
    /// notifications. A main-context `save()` with actual pending changes
    /// (this deletion) is the only guaranteed trigger.
    ///
    /// Legacy cleanup path for callers that only need to remove the queue row.
    /// Video-aware finalization should use
    /// `deleteQueuedScan(scanId:explicitlyAdoptedMediaPaths:)` so
    /// inference-only frames can be purged without deleting adopted display
    /// media.
    ///
    /// Generation-guarded inference callers own their status-probe lifecycle.
    /// A server poll that performs recovery can additionally preserve its exact
    /// registry token through this method; both expectations are revalidated
    /// after URLSession enumeration.
    ///
    /// When `@Query` re-evaluates after this save it fetches fresh data from the
    /// persistent store, picking up both the deleted `OfflineQueuedScan` and the
    /// newly inserted `LocalScanRecord` (committed earlier by the background
    /// actor) in a single pass.
    @discardableResult
    func flushOfflineQueuedScan(scanId: String) -> Bool {
        guard let context = modelContext else { return false }
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        // The background actor intentionally leaves the OfflineQueuedScan alive
        // so this deletion is always a real pending change on the main context.
        // Guard defensively in case of an unexpected concurrent deletion (e.g.
        // deleteQueuedScan racing).
        let scan: OfflineQueuedScan?
        do {
            scan = try context.fetch(descriptor).first
        } catch {
            MerianLog.data.debug(
                "flushOfflineQueuedScan: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }

        guard let scan else {
            context.deletePreferredGoalHint(scanId: scanId)
            do {
                try context.save()
            } catch {
                context.rollback()
                MerianLog.data.error(
                    "flushOfflineQueuedScan: goal hint cleanup failed for \(scanId, privacy: .private): \(error, privacy: .private)"
                )
                return false
            }
            updateUnsyncedItemCount()
            return true
        }

        context.deletePreferredGoalHint(scanId: scanId)
        context.delete(scan)
        do {
            try context.save()
            updateUnsyncedItemCount()
            AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
            MerianLog.data.debug(
                "flushOfflineQueuedScan: deleted queue scanId=\(scanId, privacy: .public)"
            )
            return true
        } catch {
            context.rollback()
            MerianLog.data.error(
                "flushOfflineQueuedScan: save failed for \(scanId, privacy: .private); rolled back queue deletion: \(error, privacy: .private)"
            )
            updateUnsyncedItemCount()
            return false
        }
    }

    /// Refreshes `unsyncedItemsCount` from the count of locally runnable queue
    /// records.
    ///
    /// Queue transitions are also committed by `BackgroundDatabaseActor`. Use
    /// a fresh read context so a cached main-context fault cannot retain an
    /// attention-only row or hide newly persisted automatic work.
    func updateUnsyncedItemCount() {
        guard let context = modelContext else { return }
        let readContext = ModelContext(context.container)
        let firstNonRunnableRaw = ScanQueueState.externalImport.rawValue
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate {
                $0.scanStateRaw < firstNonRunnableRaw
                    && !$0.queueNeedsAttention
            }
        )
        let count: Int
        do {
            count = try readContext.fetchCount(descriptor)
        } catch {
            MerianLog.data.debug(
                "updateUnsyncedItemCount: fetchCount failed: \(error, privacy: .private)"
            )
            return
        }
        self.unsyncedItemsCount = count
    }

    /// Tombstones a scan by transitioning it to `.failed`.
    ///
    /// Used for scans whose source files are missing or whose uploads were
    /// permanently rejected. The record is excluded from future sync attempts.
    /// Rows that still need user attention stay visible until the user retries
    /// or cancels; non-actionable failures can be purged later.
    @discardableResult
    func softDeleteQueuedScan(
        scanId: String,
        reason: String? = nil,
        errorCode: String? = nil,
        httpStatus: Int? = nil,
        needsAttention: Bool = true
    ) -> Bool {
        guard let context = modelContext else { return false }
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate<OfflineQueuedScan> { $0.id == scanId }
        )
        let match: OfflineQueuedScan?
        do {
            match = try context.fetch(descriptor).first
        } catch {
            MerianLog.data.debug(
                "softDeleteQueuedScan: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
        guard let match else { return false }
        match.scanStateRaw = ScanQueueState.failed.rawValue
        match.queueLastAttemptAt = Date()
        match.queueNextRetryAt = nil
        match.queueLastErrorCode = errorCode
        match.queueLastErrorMessage = reason
        match.queueLastHTTPStatus = httpStatus
        match.queueNeedsAttention = needsAttention
        match.queueUpdatedAt = Date()
        if let job = try? context.fetchOfflineJob(
            id: Self.scanIngestionJobId(scanId: scanId)
        ) {
            job.status = needsAttention ? .needsAttention : .cancelled
            job.updatedAt = Date()
            job.nextRunAt = nil
            job.lastErrorCode = errorCode
            job.lastErrorMessage = reason
            job.lastHTTPStatus = httpStatus
        }
        context.insert(OfflineQueueEvent(
            jobId: Self.scanIngestionJobId(scanId: scanId),
            scanId: scanId,
            kind: needsAttention ? .needsAttention : .failed,
            message: reason,
            errorCode: errorCode,
            httpStatus: httpStatus
        ))
        do {
            try context.save()
        } catch {
            context.rollback()
            MerianLog.data.error(
                "softDeleteQueuedScan: save failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            updateUnsyncedItemCount()
            return false
        }
        updateUnsyncedItemCount()
        OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)

        if AppSettings.shared.isPushNotificationsEnabled {
            #if canImport(UIKit)
            if UIApplication.shared.applicationState != .active {
                PushNotificationManager.shared.sendUploadFailedNotification()
            }
            #endif
        }
        return true
    }
}
