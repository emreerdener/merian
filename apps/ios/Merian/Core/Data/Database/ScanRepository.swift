import Foundation
import os
import SwiftData

// MARK: - Scan Repository

/// Facade over `OfflineQueueManager` and SwiftData for scan persistence and sync.
///
/// Keeps UI components and view models decoupled from `ModelContext` and queue internals.
/// Inject the `ModelContext` once at startup via `configure(with:)`.
@MainActor
final class ScanRepository {

    // MARK: - Singleton

    static let shared = ScanRepository()

    // MARK: - Dependencies

    private let offlineQueue = OfflineQueueManager.shared
    private let historicalCloudClient = HistoricalSyncCloudClient.live
    private let mediaRecoveryRegistrationService =
        ScanMediaRecoveryRegistrationService()
    private var mediaRecoveryRegistrationTask: Task<Void, Never>?

    // MARK: - Lifecycle

    private init() {}

    /// Injects the SwiftData context and seeds the default "Favorites" collection if absent.
    ///
    /// The Favorites check is deferred to a `Task` so the synchronous launch path is never
    /// blocked by a SQLite fetch. On large libraries the original synchronous fetch caused a
    /// visible hitch before the first frame rendered.
    func configure(with modelContext: ModelContext) {
        offlineQueue.modelContext = modelContext
        offlineQueue.bootstrapOfflineJobBridgeIfNeeded()
        offlineQueue.restoreFundingReservationsForCurrentAccount()
        Task { @MainActor in
            self.seedFavoritesIfNeeded(modelContext: modelContext)
        }
        scheduleLocalMediaRecoveryRegistration(for: modelContext)
    }

    private func scheduleLocalMediaRecoveryRegistration(
        for modelContext: ModelContext
    ) {
        let previousRegistrationTask = mediaRecoveryRegistrationTask
        previousRegistrationTask?.cancel()
        mediaRecoveryRegistrationTask = nil

        guard !TestExecutionCoordinator.isRunningTests else { return }

        let expectedContainer = modelContext.container
        let service = mediaRecoveryRegistrationService
        mediaRecoveryRegistrationTask = Task(priority: .utility) {
            do {
                await previousRegistrationTask?.value
                try Task.checkCancellation()
                guard let currentContainer = self.offlineQueue
                    .modelContext?.container,
                    currentContainer === expectedContainer else {
                    return
                }
                LocalScanMediaRecoveryResolver
                    .resetRegisteredRecoveryMappings()
                let recoveryCount = try await service.registerMappings(
                    in: expectedContainer
                )
                try Task.checkCancellation()
                guard let currentContainer = self.offlineQueue
                    .modelContext?.container,
                    currentContainer === expectedContainer,
                    let recoveryCount else {
                    return
                }
                MerianLog.data.info(
                    "Post-startup media recovery registered \(recoveryCount, privacy: .public) legacy scan image mapping(s)."
                )
            } catch is CancellationError {
                return
            } catch {
                MerianLog.data.error(
                    "Post-startup media recovery could not read the local scan library: \(error, privacy: .private)"
                )
            }
        }
    }

    private func seedFavoritesIfNeeded(modelContext: ModelContext) {
        var descriptor = FetchDescriptor<ScanCollection>(
            predicate: #Predicate { $0.name == "Favorites" }
        )
        descriptor.fetchLimit = 1
        let count: Int
        do {
            count = try modelContext.fetchCount(descriptor)
        } catch {
            MerianLog.data.error(
                "configure: Favorites lookup failed: \(error, privacy: .private)"
            )
            return
        }
        guard count == 0 else { return }

        let favorites = ScanCollection(name: "Favorites")
        modelContext.insert(favorites)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            MerianLog.data.error("configure: Favorites seed save failed: \(error, privacy: .private)")
        }
    }

    // MARK: - Local Fetching

    // MARK: - Replaced Manual Fetchers
    // `fetchLocalCollections` and `fetchLocalScans` have been deleted.
    // The MainActor UI relies natively on iOS 17 declarative @Query macros over the globally elevated LocalScanRecord structure.

    // MARK: - Capture Persistence

    /// Enqueues a capture for upload, writing image data to disk and buffering offline if connectivity is absent.
    func saveScan(
        imageData: Data,
        telemetry: CaptureTelemetry,
        blurScore: Double? = nil
    ) {
        offlineQueue.enqueueCapture(
            imageDatas: [imageData],
            telemetry: telemetry,
            blurScore: blurScore
        )
    }

    // MARK: - Remote Sync

    /// Pulls the authenticated user's scan and collection history from Supabase and reconciles it with the local SwiftData store.
    ///
    /// Fetches are paginated (`HistoricalSyncPolicy.scanPageSize` /
    /// `HistoricalSyncPolicy.collectionPageSize`) to
    /// prevent OOM on accounts with large histories. All reconciliation work runs on a single
    /// `HistoricalDatabaseActor` invocation to minimise actor-boundary crossings.
    func syncHistoricalScansDown(modelContext: ModelContext) async {
        guard let accountWorkLease = try? historicalCloudClient
            .beginAccountWork() else { return }
        defer {
            historicalCloudClient.finishAccountWork(accountWorkLease)
        }
        let userId = accountWorkLease.session.userID.uuidString
        var didChangeExploreShareState = false

        do {
            let container = modelContext.container
            let dbActor = HistoricalDatabaseActor(modelContainer: container)

            // --- Push local collections before pulling ---
            // Local collections created while offline (or before auth completed) are never
            // uploaded until OfflineQueueManager drains pending collection sync work. If we reconcile against
            // the cloud first, those unsynced collections will be deleted during the sync pass.
            // Route this through OfflineQueueManager's shared drain so launch-time historical
            // sync cannot race a stale background upsert against a newer tombstone delete.
            if offlineQueue.hasPendingCollectionSyncJob {
                let didDrainCollections = await offlineQueue.drainCollectionSyncIfPossible()
                guard didDrainCollections else {
                    MerianLog.data.debug("syncHistoricalScansDown: skipped cloud reconciliation because pending collection mutations could not be drained safely.")
                    return
                }
                guard historicalCloudClient
                    .isAccountWorkCurrent(accountWorkLease) else {
                    return
                }
            }

            // --- Paginated scans — streamed page-by-page through the actor ---
            // Never accumulate the full history into memory. For power users with 10k+ scans
            // the full allScans[] array can exceed 100 MB before any processing begins,
            // causing OOM kills on 3GB devices under memory pressure.
            var scanOffset = 0
            let scanPageSize = HistoricalSyncPolicy.scanPageSize
            var totalNewRecords = 0

            while true {
                let exploreShareStateSnapshot = ExploreShareStateStore
                    .makeReconciliationSnapshot()
                let rawPage = try await historicalCloudClient.fetchScanPage(
                    HistoricalScanPageRequest(
                        userID: userId,
                        offset: scanOffset,
                        pageSize: scanPageSize
                    )
                )
                let decodedPage = try HistoricalScanPageDecoder.decode(rawPage)
                let page = decodedPage.responses
                guard historicalCloudClient
                    .isAccountWorkCurrent(accountWorkLease) else {
                    return
                }
                if decodedPage.rejectedRowCount > 0 {
                    MerianLog.data.error(
                        "syncHistoricalScansDown: quarantined malformed cloud rows count=\(decodedPage.rejectedRowCount, privacy: .public) firstPath=\((decodedPage.firstRejectedCodingPath ?? "unknown"), privacy: .public)"
                    )
                }
                if !page.isEmpty {
                    if scanOffset == 0 {
                        MerianLog.data.debug("🔄 Merian Sync: Streaming remote scan pages (page size: \(scanPageSize, privacy: .public))…")
                    }
                    totalNewRecords += try await dbActor.reconcileScanPage(
                        responses: page
                    )
                    guard historicalCloudClient
                        .isAccountWorkCurrent(accountWorkLease) else {
                        return
                    }
                    if reconcileExploreShareState(
                        from: page,
                        ifUnchangedSince: exploreShareStateSnapshot
                    ) {
                        didChangeExploreShareState = true
                    }
                }
                if decodedPage.remoteRowCount < scanPageSize { break }
                scanOffset += scanPageSize
            }

            if didChangeExploreShareState {
                AppDIContainer.shared.appEventPublisher.send(
                    .exploreShareStateReconciled
                )
                didChangeExploreShareState = false
            }

            // --- Paginated collections fetch ---
            // Collections must be fully accumulated before calling syncCollectionsDown because
            // syncCollections deletes local collections absent from the remote set — streaming
            // per page would incorrectly delete collections that exist on future pages.
            // Memory exposure is bounded: sync-collections enforces MAX_COLLECTIONS = 200 on
            // write, so the remote DB cannot hold more than 200 rows for this user.
            var allCollections: [CloudCollectionResponse] = []
            allCollections.reserveCapacity(HistoricalSyncPolicy.collectionPageSize)
            var colOffset = 0
            let colPageSize = HistoricalSyncPolicy.collectionPageSize
            while true {
                let page = try await historicalCloudClient
                    .fetchCollectionPage(
                        HistoricalCollectionPageRequest(
                            userID: userId,
                            offset: colOffset,
                            pageSize: colPageSize
                        )
                    )
                guard historicalCloudClient
                    .isAccountWorkCurrent(accountWorkLease) else {
                    return
                }
                allCollections.append(contentsOf: page)
                if page.count < colPageSize { break }
                colOffset += colPageSize
            }

            // Reconcile collections after all scan pages have been ingested so that
            // collection → scan relationships can resolve against the full local set.
            guard historicalCloudClient
                .isAccountWorkCurrent(accountWorkLease) else {
                return
            }
            try await dbActor.syncCollectionsDown(
                remoteCollections: allCollections
            )

            if totalNewRecords > 0 {
                MerianLog.data.debug("✅ Merian Sync: Restored \(totalNewRecords, privacy: .public) new historical records.")
            }
            Task { @MainActor in
                AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
            }

        } catch is CancellationError {
            if didChangeExploreShareState,
               historicalCloudClient.isAccountWorkCurrent(
                   accountWorkLease
               ) {
                AppDIContainer.shared.appEventPublisher.send(
                    .exploreShareStateReconciled
                )
            }
        } catch {
            if didChangeExploreShareState,
               historicalCloudClient.isAccountWorkCurrent(
                   accountWorkLease
               ) {
                AppDIContainer.shared.appEventPublisher.send(
                    .exploreShareStateReconciled
                )
            }
            MerianLog.data.error("🚨 Failed reconciling historical scans from Supabase: \(error, privacy: .private)")
        }
    }

    /// Pulls a single completed scan by ID after the outbox status endpoint confirms
    /// the server has persisted it. This avoids waiting for a full historical sync when
    /// the photo's EXIF timestamp places it deep in the user's remote history.
    func syncHistoricalScanDown(
        scanId: String,
        modelContext: ModelContext
    ) async -> HistoricalScanDownOutcome {
        guard let accountWorkLease = try? historicalCloudClient
            .beginAccountWork() else { return .transientFailure }
        defer {
            historicalCloudClient.finishAccountWork(accountWorkLease)
        }
        let userId = accountWorkLease.session.userID.uuidString
        let exploreShareStateSnapshot = ExploreShareStateStore
            .makeReconciliationSnapshot()

        let rawResponse: Data
        do {
            rawResponse = try await historicalCloudClient.fetchScan(
                HistoricalScanRecordRequest(
                    userID: userId,
                    scanID: scanId
                )
            )
        } catch is CancellationError {
            return .transientFailure
        } catch {
            MerianLog.data.error(
                "syncHistoricalScanDown: targeted fetch failed scanId=\(scanId, privacy: .public)"
            )
            return .transientFailure
        }

        let decodedPage: HistoricalScanPageDecodeResult
        do {
            decodedPage = try HistoricalScanPageDecoder.decode(rawResponse)
        } catch {
            MerianLog.data.error(
                "syncHistoricalScanDown: invalid response envelope scanId=\(scanId, privacy: .public)"
            )
            return .contractMismatch
        }

        guard historicalCloudClient
            .isAccountWorkCurrent(accountWorkLease) else {
            return .transientFailure
        }

        guard decodedPage.rejectedRowCount == 0 else {
            MerianLog.data.error(
                "syncHistoricalScanDown: cloud row contract mismatch scanId=\(scanId, privacy: .public) path=\((decodedPage.firstRejectedCodingPath ?? "unknown"), privacy: .public)"
            )
            return .contractMismatch
        }

        guard !decodedPage.responses.isEmpty else {
            MerianLog.data.debug(
                "syncHistoricalScanDown: server had status=found but targeted fetch returned no row scanId=\(scanId, privacy: .public)"
            )
            return .notFound
        }

        let dbActor = HistoricalDatabaseActor(
            modelContainer: modelContext.container
        )
        let newRecords: Int
        do {
            newRecords = try await dbActor.reconcileScanPage(
                responses: decodedPage.responses
            )
        } catch is CancellationError {
            return .transientFailure
        } catch {
            MerianLog.data.error(
                "syncHistoricalScanDown: local reconciliation failed scanId=\(scanId, privacy: .public) error=\(error, privacy: .private)"
            )
            return .transientFailure
        }
        guard historicalCloudClient
            .isAccountWorkCurrent(accountWorkLease) else {
            return .transientFailure
        }
        if reconcileExploreShareState(
            from: decodedPage.responses,
            ifUnchangedSince: exploreShareStateSnapshot
        ) {
            AppDIContainer.shared.appEventPublisher.send(
                .exploreShareStateReconciled
            )
        }
        MerianLog.data.debug(
            "syncHistoricalScanDown: reconciled scanId=\(scanId, privacy: .public) newRecords=\(newRecords, privacy: .public)"
        )
        AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
        return .reconciled
    }

    private func reconcileExploreShareState(
        from responses: [HistoricalScanResponse],
        ifUnchangedSince snapshot: ExploreShareStateStore
            .ReconciliationSnapshot
    ) -> Bool {
        var postIdsByScanId: [String: String] = [:]
        for response in responses {
            if let postId = response.activeExplorePostId {
                postIdsByScanId[response.id] = postId
            }
        }
        return !ExploreShareStateStore.reconcileSharedPostIds(
            postIdsByScanId,
            forScanIds: responses.map(\.id),
            ifUnchangedSince: snapshot
        ).isEmpty
    }

    // MARK: - Queue Control

    /// Triggers an immediate upload flush. Normally managed automatically on connectivity change.
    func syncPendingScans() {
        offlineQueue.syncPendingScans()
    }

    /// Permanently removes all soft-deleted queue records and their associated image files from disk.
    func purgeSoftDeletedRecords() {
        offlineQueue.purgeSoftDeletedRecords()
    }

    func purgeExpiredNonBiologicalScans(
        modelContainer: ModelContainer,
        referenceDate: Date = Date()
    ) async {
        guard let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -NonBiologicalRetentionPolicy.retentionDays,
            to: referenceDate
        ) else { return }

        let actor = BackgroundDatabaseActor(modelContainer: modelContainer)

        do {
            let result = try await actor.purgeExpiredNonBiologicalScans(cutoffDate: cutoffDate)
            // Missing rows can still commit file/tombstone work.
            guard result.committedErasureCount > 0 else { return }

            await FileIOActor.shared.deleteFiles(at: result.localMediaPaths)
            // Refresh projections only when this transaction removed a row.
            if result.deletedRecordCount > 0 {
                AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
            }
            await offlineQueue.syncPendingDeletions()
            MerianLog.data.debug(
                "purgeExpiredNonBiologicalScans: purged \(result.deletedRecordCount, privacy: .public) records and \(result.localMediaPaths.count, privacy: .public) local media paths"
            )
        } catch {
            MerianLog.data.error("purgeExpiredNonBiologicalScans: cleanup failed: \(error, privacy: .private)")
        }
    }

    // MARK: - Deletion

    /// Fully deletes a scan: queues a cloud deletion task, removes the `LocalScanRecord` from
    /// SwiftData, tombstones any in-flight upload, then asynchronously purges local image files.
    ///
    /// Database operations are committed first so that a file-deletion failure (non-fatal, cleanable)
    /// can never leave the database in an inconsistent state. The cloud deletion
    /// (`delete-scan` Edge function) is attempted immediately and retried on subsequent
    /// connectivity cycles via `PendingCloudDeletionTask`.
    /// The optional handle completes this deletion's file cleanup and cloud
    /// attempt. Callers need not await it for local deletion to be durable.
    @discardableResult
    func eradicateScan(record: LocalScanRecord, modelContext: ModelContext) -> Task<Void, Never>? {
        ExploreShareStateStore.setSharedPostId(nil, for: record.id)

        // Collect image paths before deleting the record.
        var imagesToErase: [String] = []
        if let jsonStr = record.capturedMediaJSON,
           let jsonData = jsonStr.data(using: .utf8),
           let items = try? JSONDecoder().decode([SerializedMediaItem].self, from: jsonData) {
            imagesToErase.append(contentsOf: items.compactMap {
                guard case .image(let reference) = $0 else { return nil }
                return reference.serializedPath
            })
        }

        // 1. Cancel/tombstone any in-flight upload for this now-deleted scan.
        offlineQueue.softDeleteQueuedScan(
            scanId: record.id,
            reason: "Scan was deleted locally.",
            errorCode: "local_scan_deleted",
            needsAttention: false
        )

        // 2. Queue cloud deletion task + remove SwiftData record atomically.
        do {
            try modelContext.ensurePendingCloudDeletionTask(scanId: record.id)
            modelContext.delete(record)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            MerianLog.data.error("🚨 eradicateScan: modelContext save failed — aborting file deletion to preserve consistency: \(error, privacy: .private)")
            // Do not proceed to file deletion; the record still exists and the queue task
            // was not persisted, so state remains consistent.
            return nil
        }

        // 3. File cleanup and the immediate cloud attempt share a completion
        // handle without delaying the already-committed local deletion.
        let localPaths = imagesToErase.filter { !$0.starts(with: "http") }
        let cleanupTask = Task { [offlineQueue] in
            await withTaskGroup(of: Void.self) { group in
                if !localPaths.isEmpty {
                    group.addTask {
                        await FileIOActor.shared.deleteImages(at: localPaths)
                    }
                }
                group.addTask {
                    await offlineQueue.syncPendingDeletions()
                }
                await group.waitForAll()
            }
        }

        AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
        return cleanupTask
    }

    /// Deletes every active SwiftData row plus verified account preferences and
    /// process-local projections. This does not replace the store file or scan
    /// the app container for unreferenced filesystem artifacts.
    /// Use only for full account deletion or hard resets.
    @discardableResult
    func purgeAllData(
        modelContext: ModelContext,
        userDefaults: UserDefaults = .standard,
        resetDerivedState: @MainActor () -> Void,
        resetRuntimeState: @MainActor () -> Void = {
            AccountScopedRuntimeState.reset()
        }
    ) -> Bool {
        resetDerivedState()
        do {
            try modelContext.delete(model: CapturedMediaEntry.self)
            try modelContext.delete(model: LocalScanRecord.self)
            try modelContext.delete(model: ScanCollection.self)
            try modelContext.delete(model: OfflineQueuedScan.self)
            try modelContext.delete(model: ActiveOfflineQueuedScanGoalHint.self)
            try modelContext.delete(model: PendingCloudDeletionTask.self)
            try modelContext.delete(model: UserSpeciesPreference.self)
            try modelContext.delete(model: OfflineJobRecord.self)
            try modelContext.delete(model: OfflineQueueEvent.self)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
            MerianLog.data.error("🚨 Failed to erase local ModelContainer: \(error.localizedDescription, privacy: .private)")
            return false
        }

        guard AccountScopedPreferences.purgeAndVerify(
            userDefaults: userDefaults
        ) else {
            AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
            MerianLog.data.error(
                "Failed to verify account-scoped preference cleanup."
            )
            return false
        }

        resetRuntimeState()
        AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
        MerianLog.data.debug(
            "✅ Successfully purged all SwiftData records and account-scoped preferences."
        )
        return true
    }
}
