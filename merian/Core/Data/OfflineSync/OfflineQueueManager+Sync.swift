import Foundation
import SwiftData

// MARK: - Sync Operations

extension OfflineQueueManager {

    // MARK: - Cloud Deletions

    /// Drains the `PendingCloudDeletionTask` queue, calling the delete Edge function for each record.
    ///
    /// On `NetworkError.invalidResponse` the task is tombstoned immediately — the remote resource
    /// is already gone, so retrying would be pointless. All other errors retain the task for the
    /// next connectivity cycle.
    func syncPendingDeletions() async {
        guard isOnline, let context = modelContext else { return }

        let pendingTasks: [PendingCloudDeletionTask]
        do {
            let descriptor = FetchDescriptor<PendingCloudDeletionTask>(sortBy: [SortDescriptor(\.timestamp)])
            pendingTasks = try context.fetch(descriptor)
        } catch {
            MerianLog.data.debug("syncPendingDeletions: fetch failed: \(error, privacy: .private)")
            return
        }

        for task in pendingTasks {
            do {
                try await MerianNetworkClient.shared.deleteScan(scanId: task.scanId)
                context.delete(task)
                try context.save()
                MerianLog.data.debug("✅ Deleted \(task.scanId, privacy: .private) from Edge")
            } catch {
                // Retain in queue; will retry on next connectivity cycle.
                MerianLog.data.error("syncPendingDeletions: failed for \(task.scanId, privacy: .private): \(error, privacy: .private)")
                if case NetworkError.invalidResponse = error {
                    context.delete(task)
                    do {
                        try context.save()
                    } catch {
                        MerianLog.data.error("syncPendingDeletions: save failed after invalidResponse for \(task.scanId, privacy: .private): \(error, privacy: .private)")
                    }
                }
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
                Task { @MainActor in SyncStateManager.shared.completeSync() }
            }
        ) { [weak self] _ in
            guard let self else { return }
            let dbActor = BackgroundDatabaseActor(modelContainer: container)
            let scanData = await dbActor.fetchPendingScans(limit: MerianConfig.pendingScanFetchLimit)
            let session = await MainActor.run { self.backgroundSession }

            let activeScanIDs = Set(
                await session.allTasks.compactMap {
                    $0.taskDescription?.components(separatedBy: "_").first ?? $0.taskDescription
                }
            )
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

            // Flatten scan → image-file pairs. Total is bounded by prefix(5) above.
            let documentsDirectory = URL.documentsDirectory
            var fileNames: [String] = []
            var fileURLs: [URL] = []
            var scanIDs: [String] = []

            for scan in filteredScans {
                for path in scan.localImagePaths {
                    fileNames.append("\(scan.id)_\(path)")
                    fileURLs.append(documentsDirectory.appendingPathComponent(path))
                    scanIDs.append(scan.id)
                }
            }

            guard !fileNames.isEmpty else {
                await MainActor.run {
                    self.isSyncing = false
                    SyncStateManager.shared.completeSync()
                }
                return
            }

            do {
                // Fetch Cloudflare R2 pre-signed staging URLs.
                // Gemini inference is triggered by a Supabase Storage webhook once files land.
                let presignedUrls = try await MerianNetworkClient.shared.generateUploadURLs(fileNames: fileNames)

                for (index, presignedURL) in presignedUrls.enumerated() {
                    guard !Task.isCancelled else { break }
                    guard index < fileURLs.count else {
                        MerianLog.data.debug("syncPendingScans: index \(index) out of bounds — skipping")
                        continue
                    }
                    guard let remoteUrl = URL(string: presignedURL.signedUrl) else {
                        MerianLog.data.debug("syncPendingScans: invalid signed URL at index \(index) — skipping")
                        continue
                    }

                    let scanId = scanIDs[index]
                    let originalFileURL = fileURLs[index]

                    guard FileManager.default.fileExists(atPath: originalFileURL.path) else {
                        MerianLog.data.debug("syncPendingScans: source file missing for \(originalFileURL.lastPathComponent, privacy: .private) — tombstoning")
                        Task { @MainActor in OfflineQueueManager.shared.softDeleteQueuedScan(scanId: scanId) }
                        continue
                    }

                    let tempFileURL = URL.cachesDirectory.appendingPathComponent("\(scanId)_\(index)_temp_upload.jpg")
                    try? FileManager.default.removeItem(at: tempFileURL)

                    do {
                        try FileManager.default.copyItem(at: originalFileURL, to: tempFileURL)
                    } catch {
                        MerianLog.data.debug("syncPendingScans: temp file staging failed: \(error, privacy: .private)")
                        continue
                    }

                    var request = URLRequest(url: remoteUrl)
                    request.httpMethod = "PUT"
                    request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")

                    let uploadTask = session.uploadTask(with: request, fromFile: tempFileURL)
                    uploadTask.taskDescription = "\(scanId)_\(index)"
                    uploadTask.resume()
                }
            } catch {
                MerianLog.data.debug("syncPendingScans: staging URL request failed: \(error, privacy: .private)")
            }
        }
    }

    // MARK: - Collections

    /// Pushes local `ScanCollection` records to the `sync-collections` Edge function.
    /// No-ops when offline or unauthenticated. The "Favorites" collection is excluded — it is managed locally only.
    func syncCollections() {
        guard isOnline, SupabaseManager.shared.isAuthenticated else { return }
        guard let container = modelContext?.container else { return }
        Task {
            let dbActor = BackgroundDatabaseActor(modelContainer: container)
            await dbActor.pushCollectionsToEdge()
        }
    }
}
