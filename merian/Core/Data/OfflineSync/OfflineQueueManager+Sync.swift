import Foundation
import SwiftData

// MARK: - Sync Operations

extension OfflineQueueManager {

    // MARK: - Cloud Deletions

    /// Drains the `PendingCloudDeletionTask` queue, calling the delete Edge function for each record.
    ///
    /// On `MerianError.invalidResponse` the task is tombstoned immediately — the remote resource
    /// is already gone, so retrying would be pointless. All other errors retain the task for the
    /// next connectivity cycle.
    func syncPendingDeletions() async {
        guard isOnline, let context = modelContext else { return }

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

        // Fetch O(n) results using the batch dispatcher
        let scanIds = pendingTasks.map(\.scanId)
        let allResults = await dispatchDeleteBatches(scanIds: scanIds)

        // Build an O(1) lookup so the per-result loop below doesn't scan the full
        // pendingTasks array for each result (was O(n²) when the batch was large).
        let taskById = Dictionary(uniqueKeysWithValues: pendingTasks.map { ($0.scanId, $0) })
        var didMutate = false
        for (scanId, error) in allResults {
            guard let task = taskById[scanId] else { continue }
            if let error {
                MerianLog.data.error("syncPendingDeletions: failed for \(scanId, privacy: .private): \(error, privacy: .private)")
                if case MerianError.invalidResponse = error {
                    // Remote resource already gone — tombstone locally.
                    context.delete(task)
                    didMutate = true
                }
                // All other errors: retain in queue for the next connectivity cycle.
            } else {
                MerianLog.data.debug("✅ Deleted \(scanId, privacy: .private) from Edge")
                context.delete(task)
                didMutate = true
            }
        }

        if didMutate {
            do {
                try context.save()
            } catch {
                MerianLog.data.error("syncPendingDeletions: save failed: \(error, privacy: .private)")
            }
        }
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

    // MARK: - Uploads

    /// Fetches `.pending` scans and schedules background `PUT` uploads to Cloudflare R2 staging.
    ///
    /// Upload tasks are tracked by `MediaStagingContract.uploadTaskDescription(scanId:uploadIndex:)`.
    /// Scans are atomically transitioned to `.uploading` state before tasks are dispatched,
    /// so `syncPendingScans` never re-dispatches in-flight uploads after an app restart.
    /// Confirmed R2 keys are persisted on the record at upload completion (in URLSession delegate).
    ///
    /// Guards: expedition mode, connectivity, and an in-flight sync must all clear.
    func syncPendingScans() {
        guard !HardwareOrchestrator.shared.isExpeditionModeActive else { return }
        guard isOnline else { return }
        guard !isSyncing else { return }
        guard let container = modelContext?.container else { return }

        isSyncing = true

        syncTask = BackgroundTaskWrapper.execute(
            name: "OfflineQueueSync",
            expirationHandler: {
                MerianLog.data.debug("OfflineQueueSync background task expired")
                Task { @MainActor in
                    OfflineQueueManager.shared.isSyncing = false
                    SyncStateManager.shared.completeUploadPhase()
                }
            }
        ) { [weak self] _ in
            guard let self else { return }

            let dbActor = BackgroundDatabaseActor(modelContainer: container)
            let scanData = await dbActor.fetchPendingScans(limit: MerianConfig.pendingScanFetchLimit)
            let session  = await MainActor.run { self.backgroundSession }

            let filteredScans = self.selectUploadBatch(from: scanData)

            guard !filteredScans.isEmpty else {
                await MainActor.run {
                    self.isSyncing = false
                    if scanData.isEmpty { SyncStateManager.shared.completeUploadPhase() }
                }
                return
            }

            await MainActor.run {
                SyncStateManager.shared.beginSync(itemCount: filteredScans.count)
            }

            let stagingUserId = await self.currentMediaStagingUserId()
            let preparation = self.prepareUploadItems(from: filteredScans, userId: stagingUserId)

            if !preparation.rejectedScanIds.isEmpty {
                await MainActor.run {
                    for scanId in preparation.rejectedScanIds {
                        self.softDeleteQueuedScan(scanId: scanId)
                    }
                }
            }

            let uploadItems = preparation.uploadItems

            guard !uploadItems.isEmpty else {
                await MainActor.run {
                    self.isSyncing = false
                    SyncStateManager.shared.completeUploadPhase()
                }
                return
            }

            await dbActor.markScansAsUploading(scanIds: Array(Set(uploadItems.map(\.scanId))))

            do {
                let presignedUrls = try await MerianNetworkClient.shared.generateUploadURLs(
                    uploadFiles: preparation.uploadFiles
                )
                await MainActor.run { self.uploadRetryDelay = 0 }

                let dispatchedScanIDs = await self.dispatchUploadTasks(
                    session: session,
                    uploadItems: uploadItems,
                    presignedUrls: presignedUrls
                )

                if dispatchedScanIDs.isEmpty {
                    let taskCount = await session.allTasks.count
                    if taskCount == 0 {
                        await MainActor.run {
                            self.isSyncing = false
                            SyncStateManager.shared.completeUploadPhase()
                        }
                    }
                }
            } catch {
                await self.handleSyncNetworkFailure(error: error, session: session, dbActor: dbActor)
                return
            }

            // Failsafe: if no tasks were spawned, unlock manually.
            let activeTaskCount = await session.allTasks.count
            if activeTaskCount == 0 {
                await MainActor.run {
                    self.isSyncing = false
                    SyncStateManager.shared.completeUploadPhase()
                }
            }
        }
    }

    // MARK: - Upload Helpers

    nonisolated func currentMediaStagingUserId() async -> String {
        await MainActor.run {
            (SupabaseManager.shared.currentUser?.id.uuidString ?? DeviceIdentityManager.shared.deviceId).lowercased()
        }
    }

    nonisolated private func prepareUploadItems(
        from scans: [PendingScanPayload],
        userId: String
    ) -> MediaStagingPreparation {
        var uploadItems: [ScanUploadItem] = []
        var uploadFiles: [StagingUploadFile] = []
        var rejectedScanIds: [String] = []

        for scan in scans {
            let scanItems = MediaStagingContract.uploadItems(for: scan, userId: userId)
            do {
                try MediaStagingContract.validateUploadBudget(scanItems)
                let scanUploadFiles = try MediaStagingContract.uploadFiles(for: scanItems)
                uploadItems.append(contentsOf: scanItems)
                uploadFiles.append(contentsOf: scanUploadFiles)
            } catch {
                MerianLog.data.error("prepareUploadItems: rejecting staged media for \(scan.id, privacy: .private): \(error, privacy: .private)")
                rejectedScanIds.append(scan.id)
            }
        }

        return MediaStagingPreparation(
            uploadItems: uploadItems,
            uploadFiles: uploadFiles,
            rejectedScanIds: rejectedScanIds
        )
    }

    nonisolated private func selectUploadBatch(from scans: [PendingScanPayload]) -> [PendingScanPayload] {
        let maxPresignedURLsPerRequest = MediaStagingContract.maxUploadItemsPerRequest
        var selected: [PendingScanPayload] = []
        selected.reserveCapacity(MerianConfig.uploadBatchSize)
        var uploadItemCount = 0

        for scan in scans.prefix(MerianConfig.uploadBatchSize) {
            let scanUploadCount = scan.localUploadPaths.count
            guard scanUploadCount > 0 else { continue }
            if !selected.isEmpty, uploadItemCount + scanUploadCount > maxPresignedURLsPerRequest {
                break
            }
            selected.append(scan)
            uploadItemCount += scanUploadCount
            if uploadItemCount >= maxPresignedURLsPerRequest {
                break
            }
        }

        return selected
    }

    private func dispatchUploadTasks(
        session: URLSession,
        uploadItems: [ScanUploadItem],
        presignedUrls: [PreSignedURL]
    ) async -> Set<String> {
        return await withTaskGroup(of: String?.self) { group in
            for (index, presignedURL) in presignedUrls.enumerated() {
                guard !Task.isCancelled else { break }
                guard index < uploadItems.count else {
                    MerianLog.data.debug("dispatchUploadTasks: index \(index) out of bounds — skipping")
                    continue
                }
                guard let remoteUrl = URL(string: presignedURL.signedUrl) else {
                    MerianLog.data.debug("dispatchUploadTasks: invalid signed URL at index \(index) — skipping")
                    continue
                }

                let item = uploadItems[index]

                guard presignedURL.fileName == item.fileName,
                      presignedURL.objectKey == item.objectKey else {
                    MerianLog.data.error("dispatchUploadTasks: staging contract mismatch for \(item.scanId, privacy: .private)")
                    Task { @MainActor in self.softDeleteQueuedScan(scanId: item.scanId) }
                    continue
                }

                guard FileManager.default.fileExists(atPath: item.fileURL.path) else {
                    MerianLog.data.debug("dispatchUploadTasks: source missing for \(item.fileURL.lastPathComponent, privacy: .private)")
                    Task { @MainActor in self.softDeleteQueuedScan(scanId: item.scanId) }
                    continue
                }

                group.addTask { () -> String? in
                    var request = URLRequest(url: remoteUrl)
                    request.httpMethod = "PUT"
                    request.setValue(item.contentType, forHTTPHeaderField: "Content-Type")
                    let uploadTask = session.uploadTask(with: request, fromFile: item.fileURL)
                    uploadTask.taskDescription = MediaStagingContract.uploadTaskDescription(
                        scanId: item.scanId,
                        uploadIndex: item.uploadIndex
                    )
                    uploadTask.resume()
                    MerianLog.data.debug("🚀 BACKGROUND UPLOAD: Dispatched upload task for \(item.scanId, privacy: .public)")
                    return item.scanId
                }
            }

            var dispatchedIds = Set<String>()
            for await successfulScanId in group {
                if let id = successfulScanId { dispatchedIds.insert(id) }
            }
            return dispatchedIds
        }
    }

    private func handleSyncNetworkFailure(error: Error, session: URLSession, dbActor: BackgroundDatabaseActor) async {
        MerianLog.data.debug("syncPendingScans: staging URL request failed: \(error, privacy: .private)")
        
        // Reset orphaned uploads
        let liveTasks = await session.allTasks
        let activeUploadIds = Set(liveTasks.compactMap { task in
            MediaStagingContract.parseUploadTaskDescription(task.taskDescription)?.scanId
        })
        await dbActor.reconcileOrphanedUploadingScans(activeScanIds: activeUploadIds)
        
        // Exponential backoff
        let delay: TimeInterval = await MainActor.run {
            let current = self.uploadRetryDelay
            let next = current == 0 ? 1.0 : min(current * 2.0, OfflineQueueManager.maxUploadRetryDelay)
            self.uploadRetryDelay = next
            return next
        }
        
        await MainActor.run {
            self.isSyncing = false
            SyncStateManager.shared.completeUploadPhase()
            self.retryBackoffTask?.cancel()
            self.retryBackoffTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self.syncPendingScans()
            }
        }
    }

    // MARK: - Collections

    /// Marks collections as needing sync and attempts to push them immediately if online.
    /// The "Favorites" collection is excluded — it is managed locally only.
    func enqueueCollectionSync() {
        markCollectionSyncPending()
        syncCollectionsIfPending()
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
        while UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync) {
            guard isOnline, SupabaseManager.shared.isAuthenticated else { return false }

            if let existingTask = collectionSyncTask {
                let didSucceed = await existingTask.value
                guard didSucceed else { return false }
                continue
            }

            guard let container = modelContext?.container else { return false }

            let capturedRevision = collectionSyncRevision
            isCollectionSyncing = true

            let task = BackgroundTaskWrapper.execute(name: "CollectionSync") { [weak self] _ in
                guard let self else { return false }
                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                let success = await dbActor.pushCollectionsToEdge()

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

    func markCollectionSyncPending() {
        collectionSyncRevision &+= 1
        // ALWAYS set the flag when enqueued (so offline edits are remembered)
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.needsCollectionSync)
    }

    func finishCollectionSyncAttempt(success: Bool, capturedRevision: UInt64) {
        isCollectionSyncing = false
        collectionSyncTask = nil

        // Only clear the pending bit if no newer collection mutation was enqueued while
        // this network request was in flight. Otherwise the next drain loop must run again.
        if success, collectionSyncRevision == capturedRevision {
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.needsCollectionSync)
        }
    }
}
