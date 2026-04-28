import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Queue Maintenance

extension OfflineQueueManager {

    /// Deletes an `OfflineQueuedScan` from the **main context** and saves, reliably triggering
    /// `@Query queuedScans` (and `@Query rawRecords`) in any open sheet to re-evaluate.
    ///
    /// **Why main-actor deletion is the only reliable trigger**: `BackgroundDatabaseActor` saves
    /// propagate via `NSPersistentStoreRemoteChangeNotification`, but SwiftData's `@Query` in a
    /// presented `.sheet` does not reliably respond to those remote notifications. A main-context
    /// `save()` with actual pending changes (this deletion) is the only guaranteed trigger.
    ///
    /// **Contract**: `BackgroundDatabaseActor.processAndCleanupOfflineScan` intentionally skips
    /// deleting the `OfflineQueuedScan` from its own context — that work is always delegated here
    /// so this function always finds and deletes a live record. If `wasCleaned == false` (save
    /// failed in the background actor), this function is never called, leaving the record in the
    /// queue for the next retry cycle.
    ///
    /// When `@Query` re-evaluates after this save it fetches fresh data from the persistent store,
    /// picking up both the deleted `OfflineQueuedScan` and the newly inserted `LocalScanRecord`
    /// (committed earlier by the background actor) in a single pass.
    func flushOfflineQueuedScan(scanId: String) {
        guard let context = modelContext else { return }
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        // The background actor intentionally leaves the OfflineQueuedScan alive so this
        // deletion is always a real pending change on the main context. Guard defensively
        // in case of an unexpected concurrent deletion (e.g. deleteQueuedScan racing).
        if let scan = (try? context.fetch(descriptor))?.first {
            context.delete(scan)
        }
        try? context.save()
        updateUnsyncedItemCount()
    }

    /// Refreshes `unsyncedItemsCount` from the count of active (non-failed) `OfflineQueuedScan` records.
    func updateUnsyncedItemCount() {
        guard let context = modelContext else { return }
        let failedRaw = ScanQueueState.failed.rawValue
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.scanStateRaw != failedRaw }
        )
        let count: Int
        do {
            count = try context.fetchCount(descriptor)
        } catch {
            MerianLog.data.debug("updateUnsyncedItemCount: fetchCount failed: \(error, privacy: .private)")
            return
        }
        self.unsyncedItemsCount = count
    }

    /// Tombstones a scan by transitioning it to `.failed`.
    ///
    /// Used for scans whose source files are missing or whose uploads were permanently rejected.
    /// The record is excluded from future sync attempts and cleaned up by `purgeSoftDeletedRecords()`.
    func softDeleteQueuedScan(scanId: String) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate<OfflineQueuedScan> { $0.id == scanId }
        )
        guard let match = (try? context.fetch(descriptor))?.first else { return }
        match.scanStateRaw = ScanQueueState.failed.rawValue
        do {
            try context.save()
        } catch {
            MerianLog.data.error("softDeleteQueuedScan: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
        }
        updateUnsyncedItemCount()

        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.isPushNotificationsEnabled) {
            #if canImport(UIKit)
            if UIApplication.shared.applicationState != .active {
                PushNotificationManager.shared.sendUploadFailedNotification()
            }
            #endif
        }
    }

    /// Explicitly deletes an offline queued scan immediately.
    /// Cancels any in-flight background uploads and purges the item from disk.
    func deleteQueuedScan(scanId: String, explicitlyAdoptedAudioPaths: [String] = []) async {
        // 1. Cancel in-flight URLSession tasks (both upload chunks and inference download).
        let allTasks = await backgroundSession.allTasks
        for task in allTasks {
            if let desc = task.taskDescription,
               desc.starts(with: "\(scanId)_") || desc == "inference_\(scanId)" {
                task.cancel()
            }
        }

        // 2. Delete from SwiftData and disk.
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        guard let scan = (try? context.fetch(descriptor))?.first else { return }

        let documentsDirectory = URL.documentsDirectory
        let adoptedAudioPaths = Set(explicitlyAdoptedAudioPaths)
        
        if let jsonStr = scan.capturedMediaJSON,
           let items = MediaJSONParser.serializedItems(jsonString: jsonStr) {
            for item in items {
                switch item {
                case .image(let path):
                    try? FileManager.default.removeItem(at: documentsDirectory.appendingPathComponent(path))
                case .audio(let path):
                    if !adoptedAudioPaths.contains(path) {
                        try? FileManager.default.removeItem(at: documentsDirectory.appendingPathComponent(path))
                    }
                case .description:
                    break
                }
            }
        }

        context.delete(scan)
        do {
            try context.save()
            updateUnsyncedItemCount()
        } catch {
            MerianLog.data.error("deleteQueuedScan: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
        }
    }

    /// Permanently removes all `.failed` `OfflineQueuedScan` records and their image files from disk.
    /// Called at cleanup points (e.g., after a successful sync cycle or on app foreground).
    func purgeSoftDeletedRecords() {
        guard let context = modelContext else { return }
        let failedRaw = ScanQueueState.failed.rawValue
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.scanStateRaw == failedRaw }
        )
        // Only fetch the fields needed for disk cleanup and deletion — avoids loading all
        // telemetry columns into memory for potentially large backlogs of failed scans.
        descriptor.propertiesToFetch = [\.capturedMediaJSON, \.id]
        descriptor.fetchLimit = 500
        let documentsDirectory = URL.documentsDirectory

        do {
            let failedScans = try context.fetch(descriptor)
            for scan in failedScans {
                if let jsonStr = scan.capturedMediaJSON,
                   let items = MediaJSONParser.serializedItems(jsonString: jsonStr) {
                    for item in items {
                        switch item {
                        case .image(let path), .audio(let path):
                            try? FileManager.default.removeItem(at: documentsDirectory.appendingPathComponent(path))
                        case .description:
                            break
                        }
                    }
                }
                context.delete(scan)
            }
            try context.save()
            updateUnsyncedItemCount()
        } catch {
            MerianLog.data.debug("purgeSoftDeletedRecords: operation failed: \(error, privacy: .private)")
        }
    }

    // MARK: - Uploaded Scan Replay

    /// Re-triggers inference for scans in `.staged` state — images confirmed in R2 but whose
    /// inference pipeline was interrupted by an app kill, crash, suspension, or connectivity loss.
    ///
    /// On every call: resets `.inferencing` orphans to `.staged` before querying, so scans
    /// interrupted mid-inference (e.g. by backgrounding) are immediately visible to replay.
    ///
    /// On first call per process only: runs a cold-start upload reconcile gated to that window
    /// because it must run before any new upload tasks are dispatched (ensures the live-task
    /// cross-reference captures only pre-existing tasks from the previous process).
    /// On every subsequent call: also reconciles `.uploading` orphans via a live-task
    /// cross-reference to catch scans stuck in `.uploading` when `generateUploadURLs` failed
    /// or the `syncPendingScans` Task was killed before its catch block could run.
    func replayInferenceForUploadedScans() {
        guard isOnline else { return }
        guard let context = modelContext else { return }
        let container = context.container

        // One-time cold-start reconciliation for orphaned .uploading scans.
        // Must be gated because it cross-references live URLSession tasks — only valid
        // before any upload tasks are dispatched in this process.
        if !hasReconciledStartupState {
            hasReconciledStartupState = true
            Task {
                let allTasks = await backgroundSession.allTasks
                let activeIds = Set(allTasks.compactMap {
                    $0.taskDescription?.components(separatedBy: "_").first
                })
                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                let hadOrphans = await dbActor.reconcileOrphanedUploadingScans(activeScanIds: activeIds)
                // Only call syncPendingScans if the reconcile actually reset scans from
                // .uploading → .pending. Without this, the initial syncPendingScans call
                // (from handleActivePhase) already ran and found nothing — .uploading scans
                // are invisible to its .pending-only fetch — so the reconciled scan would
                // sit in .pending permanently until the next connectivity event or foreground.
                // Guarding on hadOrphans avoids a spurious second sync when the common case
                // (no orphaned uploads) does not require one.
                await MainActor.run {
                    if hadOrphans { self.syncPendingScans() }
                    self.replayInferenceForUploadedScans()
                }
            }
            return
        }

        // Reconcile .inferencing orphans on every call by cross-referencing live background
        // URLSession inference tasks. Background download tasks survive app suspension, so a
        // simple in-process counter (activeInferencePipelineCount) can no longer tell us whether
        // an .inferencing scan is legitimately owned by a live OS task — we must ask the session.
        //
        // CRITICAL: use the shared actor (not a fresh one) for the reset. If a fresh actor
        // saves .inferencing → .staged to the persistent store, the shared actor's in-memory
        // copy of the object may still show .inferencing (Core Data returns cached faults
        // rather than hitting the store). tryClaimForInference — which runs on the shared
        // actor — would then fail its state guard and return false on every cycle, leaving
        // the scan stuck indefinitely. Running the reset on the same actor guarantees the
        // in-memory object is updated before tryClaimForInference reads it.
        let sharedActor = resolvedInferenceDbActor(container: container)
        Task {
            let allTasks = await backgroundSession.allTasks

            // Safety-net: reconcile orphaned .uploading scans on every replay.
            // The primary reset happens in syncPendingScans's catch block when
            // generateUploadURLs fails, but this covers any interruption that bypasses
            // that path (e.g. the Swift Task being killed before the catch runs).
            // Cross-referencing allTasks ensures scans with live URLSession tasks are
            // not reset — only true orphans (no task, stuck in .uploading) are affected.
            // Safety-net: run upload reconcile on sharedActor (not a fresh one) so that
            // the in-memory object graph is coherent when tryClaimForInference runs below.
            // A fresh actor's save() can invalidate sharedActor's cached fault objects
            // (§6 of swiftdata-and-api-gotchas), causing tryClaimForInference to miss a
            // scan it just transitioned if it still shows the stale pre-save state.
            let activeUploadScanIds = Set(allTasks.compactMap { task -> String? in
                guard let desc = task.taskDescription, !desc.hasPrefix("inference_") else { return nil }
                return desc.components(separatedBy: "_").first
            })
            await sharedActor.reconcileOrphanedUploadingScans(activeScanIds: activeUploadScanIds)

            let activeInferenceScanIds = Set(allTasks.compactMap { task -> String? in
                guard let desc = task.taskDescription, desc.hasPrefix("inference_") else { return nil }
                return String(desc.dropFirst("inference_".count))
            })
            await sharedActor.reconcileOrphanedInferencingScans(activeInferenceScanIds: activeInferenceScanIds)
            await MainActor.run { self.replayInferenceStagedScans() }
        }
    }

    /// Fetches all `.staged` scans and dispatches a background inference download task for each one.
    ///
    /// Called by `replayInferenceForUploadedScans` after `reconcileOrphanedInferencingScans`
    /// completes, ensuring any orphaned `.inferencing` scans (not owned by a live URLSession task)
    /// are visible as `.staged` before the query runs.
    private func replayInferenceStagedScans() {
        guard isOnline else { return }
        guard let context = modelContext else { return }
        let container = context.container

        let stagedRaw = ScanQueueState.staged.rawValue
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.scanStateRaw == stagedRaw }
        )
        guard let staged = try? context.fetch(descriptor), !staged.isEmpty else { return }

        for scan in staged {
            let scanId = scan.id
            let extracted = buildExtractedScanData(from: scan, container: container)
            Task {
                let dbActor = resolvedInferenceDbActor(container: container)
                // Atomic claim: transitions .staged → .inferencing.
                // If another path already claimed it, this returns false and we skip.
                guard await dbActor.tryClaimForInference(scanId: scanId) else { return }

#if DEBUG
                // Increment before any network work so tests can observe this as a
                // network-free signal that the replay pipeline was triggered.
                await MainActor.run { self.replayedStagedScanCount += 1 }
#endif

                // Migration fallback: pre-V33 image scans have no stagedR2Keys.
                // Reconstruct from the current auth session — safe because the userId
                // embedded in the R2 key matches the session that performed the upload.
                // Describe-only scans intentionally have both r2Keys and localImagePaths
                // empty — guard on !localImagePaths.isEmpty to skip this path for them.
                let finalExtracted: ExtractedScanData
                if extracted.r2Keys.isEmpty && !extracted.localImagePaths.isEmpty {
                    let authUserId = try? await SupabaseManager.shared.client.auth.session.user.id.uuidString
                    let deviceId = await MainActor.run { DeviceIdentityManager.shared.deviceId }
                    let userId = (authUserId ?? deviceId).lowercased()
                    let reconstructedKeys = extracted.localImagePaths.map { "staging/\(userId)/\(scanId)_\($0)" }
                    finalExtracted = ExtractedScanData(
                        telemetry: extracted.telemetry,
                        localImagePaths: extracted.localImagePaths,
                        r2Keys: reconstructedKeys,
                        container: extracted.container,
                        originalTimestamp: extracted.originalTimestamp,
                        description: extracted.description,
                        observationContextsJSON: extracted.observationContextsJSON,
                        audioFilePaths: nil
                    )
                } else {
                    finalExtracted = extracted
                }

                await self.dispatchInferenceDownloadTask(scanId: scanId, extracted: finalExtracted)
            }
        }
    }

    // MARK: - Capture Enqueue

    /// Writes image data to the Documents directory and inserts a new `OfflineQueuedScan` record.
    ///
    /// All disk I/O runs inside a `.userInitiated` `BackgroundTaskWrapper` so iOS grants extended
    /// time and the cooperative scheduler cannot starve the write on rapid app suspension.
    /// On success, `syncPendingScans()` is called immediately to dispatch the background upload
    /// while the background execution window is still active.
    ///
    /// On any failure — disk write or context save — partial image files are cleaned up atomically.
    ///
    /// - Parameters:
    ///   - imageDatas: Array of raw image data blobs pending staging constraints.
    ///   - telemetry: Core hardware and positional telemetry structured context payloads.
    ///   - blurScore: CoreML generated variance logic scoring to gate upload priority.
    ///   - scanId: A caller-supplied identifier that ties this queued record to a
    ///   concurrent live inference request. Pass the same UUID to `analyze()` so the live
    ///   path can cancel the upload if inference succeeds first. When `nil` a new UUID is
    ///   generated (used by callers that do not run a parallel live inference).
    func enqueueCapture(
        imageDatas: [Data],
        audioFilePath: String? = nil,
        telemetry: CaptureTelemetry,
        blurScore: Double? = nil,
        scanId: String? = nil,
        observationContext: ObservationContext? = nil
    ) {
        let resolvedScanId = scanId ?? UUID().uuidString
        let documentsDirectory = URL.documentsDirectory
        let pairs = imageDatas.map { _ -> (name: String, url: URL) in
            let name = "\(UUID().uuidString).webp"
            return (name, documentsDirectory.appendingPathComponent(name))
        }
        let fileNames = pairs.map(\.name)
        let fileURLs = pairs.map(\.url)

        // Encode the observation context to JSON on the calling actor — no async boundary yet.
        let contextJSON: String? = observationContext.flatMap { ctx in
            guard !ctx.isEmpty else { return nil }
            return (try? JSONEncoder().encode(ctx)).flatMap { String(data: $0, encoding: .utf8) }
        }

        BackgroundTaskWrapper.execute(name: "OfflineQueueCaptureWrite", priority: .userInitiated) { [weak self] _ in
            guard let self else { return }
            do {
                try self.writeImagesToDisk(imageDatas, urls: fileURLs)
                
                if let audioName = audioFilePath {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(audioName)
                    let destURL = documentsDirectory.appendingPathComponent(audioName)
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try FileManager.default.moveItem(at: tempURL, to: destURL)
                    }
                }
                
                await MainActor.run {
                    self.insertAndPersistRecord(
                        scanId: resolvedScanId,
                        fileNames: fileNames,
                        fileURLs: fileURLs,
                        audioFilePath: audioFilePath,
                        telemetry: telemetry,
                        blurScore: blurScore,
                        observationContextsJSON: contextJSON.map { [$0] }
                    )
                }
            } catch {
                MerianLog.data.error("enqueueCapture: image write to disk failed — scan will not be queued: \(error, privacy: .private)")
                self.cleanupImages(at: fileURLs)
            }
        }
    }

    // MARK: - Describe Enqueue

    /// Enqueues a description-only describe scan for offline retry.
    ///
    /// Describes carry no image files, so they enter the queue at `.staged` directly,
    /// bypassing the R2 upload phase entirely.  `replayInferenceStagedScans` picks them
    /// up and dispatches a `/identify-multimodal` background download task when connectivity
    /// restores — routed by `dispatchInferenceDownloadTask` which detects the empty
    /// `localImagePaths` and non-nil `observationContextsJSON`.
    ///
    /// Quota is consumed at enqueue time, mirroring `enqueueCapture`, so the scan slot
    /// is allocated before any async boundary is crossed.
    @MainActor
    func enqueueDescribe(
        observationContext: ObservationContext,
        telemetry: CaptureTelemetry,
        scanId: String? = nil
    ) {
        guard !observationContext.isEmpty else { return }

        if !RevenueCatManager.shared.isProActive {
            guard UsageManager.shared.canPerformScan(isProActive: false) else {
                MerianLog.data.debug("enqueueDescribe: free user scan quota exhausted — describe not queued")
                return
            }
            UsageManager.shared.consumeScan()
        }

        let resolvedScanId = scanId ?? UUID().uuidString.lowercased()
        let serializedItems: [SerializedMediaItem] = [
            .description(observationContext)
        ]
        let capturedMediaJSON = try? String(data: JSONEncoder().encode(serializedItems), encoding: .utf8)
        
        let scan = OfflineQueuedScan(
            id: resolvedScanId,
            timestamp: Date(),
            capturedMediaJSON: capturedMediaJSON,
            gpsLatitude: telemetry.gpsLatitude,
            gpsLongitude: telemetry.gpsLongitude,
            gpsElevation: telemetry.gpsElevation,
            weatherCondition: telemetry.weatherCondition,
            weatherTemperatureF: telemetry.weatherTemperatureF,
            blurScore: nil,
            subjectDistanceInMeters: nil,
            locationName: telemetry.locationName,
            isFlashFired: nil,
            cameraPitchDegrees: nil,
            compassHeading: nil,
            relativeHumidity: nil,
            uvIndex: nil,
            zoomFactor: telemetry.zoomFactor.map { Double($0) },
            scanState: .staged,
            stagedR2Keys: []
        )

        guard let modelContext else {
            MerianLog.data.error("enqueueDescribe: modelContext unavailable — describe not queued")
            return
        }
        modelContext.insert(scan)
        do {
            try modelContext.save()
            updateUnsyncedItemCount()
            AppTelemetry.trackOfflineQueued()
        } catch {
            MerianLog.data.error("enqueueDescribe: context.save() failed: \(error, privacy: .private)")
        }
    }

    // MARK: - Enqueue Helpers

    nonisolated private func writeImagesToDisk(_ imageDatas: [Data], urls: [URL]) throws {
        for (index, data) in imageDatas.enumerated() {
            try data.write(to: urls[index])
        }
    }

    nonisolated private func cleanupImages(at urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @MainActor
    private func insertAndPersistRecord(
        scanId: String,
        fileNames: [String],
        fileURLs: [URL],
        audioFilePath: String? = nil,
        telemetry: CaptureTelemetry,
        blurScore: Double?,
        observationContextsJSON: [String]? = nil
    ) {
        // Enforce quota at enqueue time so every scan that enters the queue is guaranteed to upload.
        // Consuming here (not at upload time) prevents silent stalls when syncPendingScans fires
        // after the experience was already granted to the user.
        if !RevenueCatManager.shared.isProActive {
            guard UsageManager.shared.canPerformScan(isProActive: false) else {
                MerianLog.data.debug("enqueueCapture: free user scan quota exhausted — scan not enqueued")
                cleanupImages(at: fileURLs)
                return
            }
            UsageManager.shared.consumeScan()
        }

        var serializedItems: [SerializedMediaItem] = []
        for name in fileNames { serializedItems.append(.image(name)) }
        if let audio = audioFilePath { serializedItems.append(.audio(audio)) }
        if let contexts = observationContextsJSON {
            for ctxStr in contexts {
                if let data = ctxStr.data(using: .utf8), let ctx = try? JSONDecoder().decode(ObservationContext.self, from: data) {
                    serializedItems.append(.description(ctx))
                }
            }
        }
        let capturedMediaJSON = try? String(data: JSONEncoder().encode(serializedItems), encoding: .utf8)
        
        let scan = OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            capturedMediaJSON: capturedMediaJSON,
            gpsLatitude: telemetry.gpsLatitude,
            gpsLongitude: telemetry.gpsLongitude,
            gpsElevation: telemetry.gpsElevation,
            weatherCondition: telemetry.weatherCondition,
            weatherTemperatureF: telemetry.weatherTemperatureF,
            blurScore: blurScore,
            subjectDistanceInMeters: telemetry.subjectDistanceInMeters,
            locationName: telemetry.locationName,
            isFlashFired: nil,
            cameraPitchDegrees: nil,
            compassHeading: nil,
            relativeHumidity: nil,
            uvIndex: nil,
            zoomFactor: telemetry.zoomFactor.map { Double($0) },
            scanState: .pending
        )
        
        guard let modelContext else {
            cleanupImages(at: fileURLs)
            return
        }
        modelContext.insert(scan)

        do {
            try modelContext.save()
            updateUnsyncedItemCount()
            AppTelemetry.trackOfflineQueued()
            syncPendingScans()
        } catch {
            MerianLog.data.error("enqueueCapture: context.save() failed — scan record lost, cleaning up image footprints: \(error, privacy: .private)")
            cleanupImages(at: fileURLs)
        }
    }
}
