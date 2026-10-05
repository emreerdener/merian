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
    private let historicalCloudClient: HistoricalSyncCloudClient
    var appUpdateCoordinator: AppUpdateCoordinator?
    let libraryRestoration = LibraryRestorationState()
    private let mediaRecoveryRegistrationService =
        ScanMediaRecoveryRegistrationService()
    private var mediaRecoveryRegistrationTask: Task<Void, Never>?

    // MARK: - Lifecycle

    convenience init() {
        self.init(historicalCloudClient: .live)
    }

    init(historicalCloudClient: HistoricalSyncCloudClient) {
        self.historicalCloudClient = historicalCloudClient
    }

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
        offlineQueue.requestReanalysisErasureRecovery()
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
        let restorationGeneration = libraryRestoration.begin(accountID: accountWorkLease.session.userID)
        var restoredAllPages = false
        var quarantinedRows = false
        defer {
            libraryRestoration.finish(generation: restorationGeneration, complete: restoredAllPages && !quarantinedRows)
        }
        guard appUpdateCoordinator?.requiresUpdate(.history, accountID: accountWorkLease.session.userID) != true else { return }
        var didChangeExploreShareState = false

        do {
            // A failed migration save must stop hydration; a nil cloud baseline
            // cannot acknowledge or replace source-local legacy details.
            try LibraryDetailsSyncService.stageLegacyDetails(context: modelContext, ownerID: accountWorkLease.session.userID)
            await LibraryDetailsSyncService.drain(context: modelContext, manager: .shared)
            guard historicalCloudClient.isAccountWorkCurrent(accountWorkLease) else { return }

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
                    quarantinedRows = true
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
            guard historicalCloudClient.isAccountWorkCurrent(accountWorkLease) else { return }
            restoredAllPages = true
            appUpdateCoordinator?.historySucceeded(accountID: accountWorkLease.session.userID)
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
            if historicalCloudClient.isAccountWorkCurrent(accountWorkLease),
               ClientUpdateRequiredPolicy.matches(error) {
                appUpdateCoordinator?.record(.history, accountID: accountWorkLease.session.userID)
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
        guard appUpdateCoordinator?.requiresUpdate(.history, accountID: accountWorkLease.session.userID) != true else { return .clientUpdateRequired }
        let exploreShareStateSnapshot = ExploreShareStateStore
            .makeReconciliationSnapshot()

        let rawResponse: Data
        do {
            try LibraryDetailsSyncService.stageLegacyDetails(
                context: modelContext, ownerID: accountWorkLease.session.userID, scanID: scanId
            )
            rawResponse = try await historicalCloudClient.fetchScan(
                HistoricalScanRecordRequest(
                    userID: userId,
                    scanID: scanId
                )
            )
        } catch is CancellationError {
            return .transientFailure
        } catch {
            guard historicalCloudClient.isAccountWorkCurrent(accountWorkLease) else { return .transientFailure }
            if ClientUpdateRequiredPolicy.matches(error) {
                appUpdateCoordinator?.record(.history, accountID: accountWorkLease.session.userID)
                return .clientUpdateRequired
            }
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
        guard let lease = try? historicalCloudClient.beginAccountWork() else { return }
        defer { historicalCloudClient.finishAccountWork(lease) }
        guard let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -NonBiologicalRetentionPolicy.retentionDays,
            to: referenceDate
        ) else { return }

        let actor = BackgroundDatabaseActor(modelContainer: modelContainer)

        do {
            let result = try await actor.purgeExpiredNonBiologicalScans(
                cutoffDate: cutoffDate, requestingAccountID: lease.session.userID)
            // Missing rows can still commit file/tombstone work.
            guard result.committedErasureCount > 0 else { return }

            await offlineQueue.finishReanalysisErasure(result.childIDs, in: modelContainer)
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

    /// Commits local removal and account/origin-bound intent before file cleanup.
    /// Ordinary cloud failures retry; ambiguous intent and history refusals stay held.
    /// The optional handle completes cleanup and an attempt, never proof of erasure.
    @discardableResult
    func eradicateScan(record: LocalScanRecord, modelContext: ModelContext,
                       origin: CloudDeletionIntent.Origin = .explicitUserDeletion,
                       allowsMutation: @MainActor () -> Bool = HistoricalSyncCloudClient.allowsLocalMutation) -> Task<Void, Never>? {
        guard allowsMutation() else { return nil }
        return ConfirmedSpeciesReviewPersistence.transaction {
            do {
                if origin != .explicitUserDeletion,
                   try ObservationHistoryEnrollmentIntent.protects(record.id, context: ModelContext(modelContext.container)) { return nil }
            } catch { return nil }
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

            offlineQueue.softDeleteQueuedScan(
                scanId: record.id,
                reason: "Scan was deleted locally.",
                errorCode: "local_scan_deleted",
                needsAttention: false
            )

            // 2. Queue cloud deletion task + remove SwiftData record atomically.
            var childCleanup = ObservationReanalysisErasure.Cleanup()
            do {
                if origin == .explicitUserDeletion {
                    try ObservationHistoryEnrollmentIntent.supersedeForExplicitDeletion(record.id, context: modelContext)
                }
                try modelContext.ensurePendingCloudDeletionTask(scanId: record.id,
                    requestingAccountID: CloudDeletionAccountWork.captureRequestAccount(using: historicalCloudClient), origin: origin)
                childCleanup = try ObservationReanalysisErasure.removeChildren(of: record.id, context: modelContext)
                try ObservationPublicationPersistence.removeForDeletion(record.id, context: modelContext)
                modelContext.delete(record)
                try modelContext.save()
            } catch {
                modelContext.rollback()
                MerianLog.data.error("🚨 eradicateScan: modelContext save failed — aborting file deletion to preserve consistency: \(error, privacy: .private)")
                // Do not proceed to file deletion; the record still exists and the queue task
                // was not persisted, so state remains consistent.
                return nil
            }

            let localPaths = imagesToErase.filter { !$0.starts(with: "http") }
            let childIDs = childCleanup.childIDs
            let container = modelContext.container
            let cleanupTask = Task { [offlineQueue] in
                await offlineQueue.finishReanalysisErasure(childIDs, in: container)
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
        libraryRestoration.reset()
        return ScanLibraryPurgeService.purge(
            modelContext: modelContext, userDefaults: userDefaults,
            resetRuntimeState: resetRuntimeState
        )
    }
}
