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

        // Fan out deletions in batches of 10 to prevent unbounded concurrent network requests.
        // Without a cap, a user returning from a week offline could fire 200+ simultaneous
        // deleteScan calls, saturating the URLSession pool and triggering server-side rate limits
        // (5xx responses are retried, making the problem self-amplifying).
        // Only the scanId (String, Sendable) crosses the task-group boundary —
        // @Model objects are not Sendable and must stay on this actor.
        let scanIds = pendingTasks.map(\.scanId)
        let batchSize = 10
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

    // MARK: - Uploads

    /// Fetches up to 5 unsynced scans and schedules a background `PUT` upload to Cloudflare R2 staging for each image file.
    ///
    /// Upload tasks are tracked by `taskDescription` (`"\(scanId)_\(imageIndex)"`). Active scan IDs
    /// are deduplicated against the live `URLSession` task list to avoid double-uploading on relaunch.
    /// Gemini inference is triggered server-side by a Supabase Storage webhook once files land.
    ///
    /// Guards: expedition mode, connectivity, and an in-flight sync must all clear.
    /// Free users are additionally gated by their daily scan quota and their queue is capped at `maxFreeScansPerDay` items.
    func syncPendingScans() {
        guard !HardwareOrchestrator.shared.isExpeditionModeActive else { return }
        guard isOnline else { return }
        guard !isSyncing else { return }
        guard let container = modelContext?.container else { return }

        let isProActive = RevenueCatManager.shared.isProActive

        // Free users must have remaining daily quota before the queue processes anything.
        if !isProActive {
            guard UsageManager.shared.canPerformScan(isProActive: false) else { return }
        }

        isSyncing = true

        syncTask = BackgroundTaskWrapper.execute(
            name: "OfflineQueueSync",
            expirationHandler: {
                MerianLog.data.debug("OfflineQueueSync background task expired")
                Task { @MainActor in
                    // Reset the latch so the next connectivity event can start a fresh sync.
                    // Without this, an expiration before URLSession tasks are dispatched leaves
                    // isSyncing = true permanently — no future syncPendingScans() call can proceed.
                    OfflineQueueManager.shared.isSyncing = false
                    SyncStateManager.shared.completeSync()
                }
            }
        ) { [weak self] _ in
            guard let self else { return }
            
            // Periodically retry any scans that successfully made it to R2 but whose inference 
            // failed transiently, so they don't remain orphaned while the app is kept open.
            await MainActor.run { self.replayInferenceForUploadedScans() }
            
            let dbActor = BackgroundDatabaseActor(modelContainer: container)
            let scanData = await dbActor.fetchPendingScans(limit: MerianConfig.pendingScanFetchLimit)
            let session = await MainActor.run { self.backgroundSession }

            // Seed `activeScanUploadIds` exactly once from the live URLSession task list on the first
            // sync after a cold launch (to re-attach tasks that survived an app restart).
            // Every subsequent call reads the locally-maintained Set directly, avoiding the O(n)
            // async `session.allTasks` enumeration on every sync cycle.
            let activeScanIDs: Set<String>
            let needsSeeding = await MainActor.run { !self.hasSeededActiveScanIds }
            if needsSeeding {
                let allTasks = await session.allTasks
                activeScanIDs = Set(allTasks.compactMap {
                    $0.taskDescription?.components(separatedBy: "_").first ?? $0.taskDescription
                })
                await MainActor.run {
                    self.activeScanUploadIds = activeScanIDs
                    self.hasSeededActiveScanIds = true
                }
            } else {
                activeScanIDs = await MainActor.run { self.activeScanUploadIds }
            }
            // For free users, cap the batch to however many scans they can still run today.
            let batchLimit = await MainActor.run {
                isProActive ? MerianConfig.uploadBatchSize : UsageManager.shared.freeScansRemaining
            }
            let filteredScans = Array(scanData.filter { !activeScanIDs.contains($0.id) }.prefix(batchLimit))

            guard !filteredScans.isEmpty else {
                await MainActor.run {
                    self.isSyncing = false
                    if scanData.isEmpty { SyncStateManager.shared.completeSync() }
                }
                return
            }

            await MainActor.run {
                SyncStateManager.shared.beginSync(itemCount: filteredScans.count)
                // Consume one scan quota slot per item being uploaded.
                // Pro users have unlimited quota; free users are deducted here so the daily
                // limit is enforced even when scans complete via background URLSession.
                if !isProActive {
                    for _ in filteredScans { UsageManager.shared.consumeScan() }
                }
            }

            // Flatten scan → image-file pairs into a typed array.
            // A single struct eliminates the class of flat-index bug that plagued the
            // previous 4-array layout: every consumer indexes into one ScanUploadItem
            // and gets the correct per-scan imageIndex together with its sibling fields.
            struct ScanUploadItem {
                let scanId: String
                let imageIndex: Int   // per-scan slot (0…N-1), NOT the flat batch index
                let fileName: String
                let fileURL: URL
            }

            let documentsDirectory = URL.documentsDirectory
            var uploadItems: [ScanUploadItem] = []
            for scan in filteredScans {
                for (imageIndex, path) in scan.localImagePaths.enumerated() {
                    uploadItems.append(ScanUploadItem(
                        scanId: scan.id,
                        imageIndex: imageIndex,
                        fileName: "\(scan.id)_\(path)",
                        fileURL: documentsDirectory.appendingPathComponent(path)
                    ))
                }
            }

            guard !uploadItems.isEmpty else {
                await MainActor.run {
                    self.isSyncing = false
                    SyncStateManager.shared.completeSync()
                }
                return
            }

            do {
                // Fetch Cloudflare R2 pre-signed staging URLs.
                // Gemini inference is triggered client-side via runInferencePipeline once
                // the last image file for a scan lands (guarded by imageIndex == count-1).
                let presignedUrls = try await MerianNetworkClient.shared.generateUploadURLs(
                    fileNames: uploadItems.map(\.fileName)
                )
                // Reset exponential backoff — this request succeeded.
                await MainActor.run { self.uploadRetryDelay = 0 }

                // File copies and upload task creation are independent per-image — fan them out
                // concurrently so NVMe writes for a 3-image scan overlap instead of queuing serially.
                let dispatchedScanIDs: Set<String> = await withTaskGroup(of: String?.self) { group in
                    for (index, presignedURL) in presignedUrls.enumerated() {
                        guard !Task.isCancelled else { break }
                        guard index < uploadItems.count else {
                            MerianLog.data.debug("syncPendingScans: index \(index) out of bounds — skipping")
                            continue
                        }
                        guard let remoteUrl = URL(string: presignedURL.signedUrl) else {
                            MerianLog.data.debug("syncPendingScans: invalid signed URL at index \(index) — skipping")
                            continue
                        }

                        let item = uploadItems[index]

                        guard FileManager.default.fileExists(atPath: item.fileURL.path) else {
                            MerianLog.data.debug("syncPendingScans: source file missing for \(item.fileURL.lastPathComponent, privacy: .private) — tombstoning")
                            // Use the already-resolved `self` from the outer [weak self] guard
                            // rather than the singleton, so the lifecycle contract is consistent.
                            let capturedSelf = self
                            Task { @MainActor in capturedSelf.softDeleteQueuedScan(scanId: item.scanId) }
                            continue
                        }

                        group.addTask { () -> String? in
                            var request = URLRequest(url: remoteUrl)
                            request.httpMethod = "PUT"
                            request.setValue("image/webp", forHTTPHeaderField: "Content-Type")
                            
                            // Pass the authoritative document-directory URL directly instead of staging
                            // it in Caches, preventing aggressive iOS memory purges from killing the task.
                            let uploadTask = session.uploadTask(with: request, fromFile: item.fileURL)
                            uploadTask.taskDescription = "\(item.scanId)_\(item.imageIndex)"
                            uploadTask.resume()
                            return item.scanId
                        }
                    }
                    
                    var dispatchedIds = Set<String>()
                    for await successfulScanId in group {
                        if let id = successfulScanId { dispatchedIds.insert(id) }
                    }
                    return dispatchedIds
                }
                // Incrementally track the IDs dispatched in this batch so future sync cycles
                // can read `activeScanUploadIds` directly without re-enumerating URLSession tasks.
                await MainActor.run { self.activeScanUploadIds.formUnion(dispatchedScanIDs) }
                
                if dispatchedScanIDs.isEmpty {
                    // If no valid URLSession tasks were created (e.g., total local cache copy failure),
                    // the URLSession delegate will never fire. We must manually unlock the queue pipeline.
                    let taskCount = await session.allTasks.count
                    if taskCount == 0 {
                        await MainActor.run {
                            self.isSyncing = false
                            SyncStateManager.shared.completeSync()
                        }
                    }
                }
            } catch {
                MerianLog.data.debug("syncPendingScans: staging URL request failed: \(error, privacy: .private)")
                // Exponential backoff: double the delay on each consecutive failure, capped at
                // maxUploadRetryDelay. This prevents the sync loop from hammering a degraded
                // presigned-URL endpoint every time connectivity is restored.
                let delay: TimeInterval = await MainActor.run {
                    let current = self.uploadRetryDelay
                    let next = current == 0 ? 1.0 : min(current * 2.0, OfflineQueueManager.maxUploadRetryDelay)
                    self.uploadRetryDelay = next
                    return next
                }
                await MainActor.run {
                    self.isSyncing = false
                    SyncStateManager.shared.completeSync()
                    // Schedule a delayed retry via a cancellable task so that connectivity loss
                    // (which cancels retryBackoffTask) prevents stale retries from firing.
                    self.retryBackoffTask?.cancel()
                    self.retryBackoffTask = Task { [weak self] in
                        guard let self else { return }
                        try? await Task.sleep(for: .seconds(delay))
                        guard !Task.isCancelled else { return }
                        self.syncPendingScans()
                    }
                }
                return
            }
            
            // Failsafe: If no tasks were spawned (e.g. generation failed, or all files missing),
            // the delegate will never fire. We must unlock syncing manually.
            let activeTaskCount = await session.allTasks.count
            if activeTaskCount == 0 {
                await MainActor.run { 
                    self.isSyncing = false 
                    SyncStateManager.shared.completeSync()
                }
            }
        }
    }

    // MARK: - Collections

    /// Marks collections as needing sync and attempts to push them immediately if online.
    /// The "Favorites" collection is excluded — it is managed locally only.
    func enqueueCollectionSync() {
        // ALWAYS set the flag when enqueued (so offline edits are remembered)
        UserDefaults.standard.set(true, forKey: "needsCollectionSync")
        syncCollectionsIfPending()
    }

    /// Pushes local `ScanCollection` records to the `sync-collections` Edge function if changes are pending.
    /// No-ops when offline or unauthenticated.
    func syncCollectionsIfPending() {
        guard UserDefaults.standard.bool(forKey: "needsCollectionSync") else { return }
        guard isOnline, SupabaseManager.shared.isAuthenticated else { return }
        guard !isCollectionSyncing else { return }
        guard let container = modelContext?.container else { return }
        
        isCollectionSyncing = true
        
        collectionSyncTask = BackgroundTaskWrapper.execute(name: "CollectionSync") { [weak self] _ in
            guard let self else { return }
            let dbActor = BackgroundDatabaseActor(modelContainer: container)
            let success = await dbActor.pushCollectionsToEdge()

            await MainActor.run {
                self.isCollectionSyncing = false
                if success {
                    UserDefaults.standard.set(false, forKey: "needsCollectionSync")
                }
            }
        }
    }
}
