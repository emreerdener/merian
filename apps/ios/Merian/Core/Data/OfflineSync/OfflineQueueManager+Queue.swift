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
    @discardableResult
    func flushOfflineQueuedScan(scanId: String) -> Bool {
        guard let context = modelContext else { return false }
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        // The background actor intentionally leaves the OfflineQueuedScan alive so this
        // deletion is always a real pending change on the main context. Guard defensively
        // in case of an unexpected concurrent deletion (e.g. deleteQueuedScan racing).
        let scan: OfflineQueuedScan?
        do {
            scan = try context.fetch(descriptor).first
        } catch {
            MerianLog.data.debug("flushOfflineQueuedScan: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return false
        }

        guard let scan else {
            updateUnsyncedItemCount()
            return true
        }

        context.delete(scan)
        do {
            try context.save()
            updateUnsyncedItemCount()
            ScanLibraryEvents.postLibraryDidUpdate()
            MerianLog.data.debug("flushOfflineQueuedScan: deleted queue scanId=\(scanId, privacy: .public)")
            return true
        } catch {
            context.rollback()
            MerianLog.data.error("flushOfflineQueuedScan: save failed for \(scanId, privacy: .private); rolled back queue deletion: \(error, privacy: .private)")
            updateUnsyncedItemCount()
            return false
        }
    }

    /// Refreshes `unsyncedItemsCount` from the count of locally runnable queue records.
    func updateUnsyncedItemCount() {
        guard let context = modelContext else { return }
        let firstNonRunnableRaw = ScanQueueState.externalImport.rawValue
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.scanStateRaw < firstNonRunnableRaw }
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
    @discardableResult
    func softDeleteQueuedScan(scanId: String) -> Bool {
        guard let context = modelContext else { return false }
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate<OfflineQueuedScan> { $0.id == scanId }
        )
        let match: OfflineQueuedScan?
        do {
            match = try context.fetch(descriptor).first
        } catch {
            MerianLog.data.debug("softDeleteQueuedScan: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return false
        }
        guard let match else { return false }
        match.scanStateRaw = ScanQueueState.failed.rawValue
        do {
            try context.save()
        } catch {
            context.rollback()
            MerianLog.data.error("softDeleteQueuedScan: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            updateUnsyncedItemCount()
            return false
        }
        updateUnsyncedItemCount()

        if AppSettings.shared.isPushNotificationsEnabled {
            #if canImport(UIKit)
            if UIApplication.shared.applicationState != .active {
                PushNotificationManager.shared.sendUploadFailedNotification()
            }
            #endif
        }
        return true
    }

    /// Explicitly deletes an offline queued scan immediately.
    /// Cancels any in-flight background uploads and purges the item from disk.
    @discardableResult
    func deleteQueuedScan(scanId: String, explicitlyAdoptedAudioPaths: [String] = []) async -> Bool {
        // 1. Cancel in-flight URLSession tasks (both upload chunks and inference download).
        let allTasks = await backgroundSession.allTasks
        for task in allTasks {
            if let desc = task.taskDescription,
               MediaStagingContract.uploadTaskDescription(desc, belongsTo: scanId) || desc == "inference_\(scanId)" {
                task.cancel()
            }
        }

        // 2. Delete from SwiftData and disk.
        guard let context = modelContext else { return false }
        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        let scan: OfflineQueuedScan?
        do {
            scan = try context.fetch(descriptor).first
        } catch {
            MerianLog.data.debug("deleteQueuedScan: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return false
        }
        guard let scan else { return true }

        let adoptedAudioPaths = Set(explicitlyAdoptedAudioPaths)
        var pathsToDelete: [String] = []

        for item in scan.capturedMediaSnapshot.items {
            switch item {
            case .image(let reference):
                if let targetURL = reference.resolvedURL, !reference.isRemote {
                    pathsToDelete.append(targetURL.path)
                } else {
                    pathsToDelete.append(reference.serializedPath)
                }
            case .audio(let reference):
                if !adoptedAudioPaths.contains(reference.serializedPath),
                   let targetURL = reference.resolvedURL {
                    pathsToDelete.append(targetURL.path)
                }
            case .video(let reference):
                if let targetURL = reference.resolvedURL, !reference.isRemote {
                    pathsToDelete.append(targetURL.path)
                } else {
                    pathsToDelete.append(reference.serializedPath)
                }
            case .description:
                break
            }
        }

        context.delete(scan)
        do {
            try context.save()
            await FileIOActor.shared.deleteFiles(at: pathsToDelete)
            updateUnsyncedItemCount()
            return true
        } catch {
            context.rollback()
            MerianLog.data.error("deleteQueuedScan: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            updateUnsyncedItemCount()
            return false
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
        descriptor.fetchLimit = 500

        do {
            let failedScans = try context.fetch(descriptor)
            guard !failedScans.isEmpty else { return }
            var pathsToDelete: [String] = []
            for scan in failedScans {
                for item in scan.capturedMediaSnapshot.items {
                    switch item {
                    case .image(let reference), .audio(let reference), .video(let reference):
                        if let targetURL = reference.resolvedURL, !reference.isRemote {
                            pathsToDelete.append(targetURL.path)
                        } else {
                            pathsToDelete.append(reference.serializedPath)
                        }
                    case .description:
                        break
                    }
                }
                context.delete(scan)
            }
            try context.save()
            Task {
                await FileIOActor.shared.deleteFiles(at: pathsToDelete)
            }
            updateUnsyncedItemCount()
        } catch {
            context.rollback()
            MerianLog.data.debug("purgeSoftDeletedRecords: operation failed: \(error, privacy: .private)")
            updateUnsyncedItemCount()
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
        MerianLog.data.debug(
            "replayInferenceForUploadedScans: requested isOnline=\(self.isOnline, privacy: .public) startupReconciled=\(self.hasReconciledStartupState, privacy: .public)"
        )
        guard isOnline else {
            MerianLog.data.debug("replayInferenceForUploadedScans: skipped because network is offline")
            return
        }
        guard let context = modelContext else {
            MerianLog.data.error("replayInferenceForUploadedScans: skipped because modelContext is nil")
            return
        }
        let container = context.container

        // One-time cold-start reconciliation for orphaned .uploading scans.
        // Must be gated because it cross-references live URLSession tasks — only valid
        // before any upload tasks are dispatched in this process.
        if !hasReconciledStartupState {
            hasReconciledStartupState = true
            Task {
                let allTasks = await backgroundSession.allTasks
                let activeIds = Set(allTasks.compactMap {
                    MediaStagingContract.parseUploadTaskDescription($0.taskDescription)?.scanId
                })
                let preparingUploadIds = await MainActor.run { self.uploadPreparationScanIds }
                let completingUploadIds = await MainActor.run { self.uploadCompletionScanIds }
                MerianLog.data.debug(
                    "replayInferenceForUploadedScans: cold-start live upload tasks=\(activeIds.count, privacy: .public) preparing=\(preparingUploadIds.count, privacy: .public) completing=\(completingUploadIds.count, privacy: .public)"
                )
                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                let hadOrphans = await dbActor.reconcileOrphanedUploadingScans(
                    activeScanIds: activeIds.union(preparingUploadIds).union(completingUploadIds)
                )
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
            let activeUploadScanIds = Set(allTasks.compactMap { task in
                MediaStagingContract.parseUploadTaskDescription(task.taskDescription)?.scanId
            })
            let preparingUploadScanIds = await MainActor.run { self.uploadPreparationScanIds }
            let completingUploadScanIds = await MainActor.run { self.uploadCompletionScanIds }
            MerianLog.data.debug(
                "replayInferenceForUploadedScans: activeUploadTasks=\(activeUploadScanIds.count, privacy: .public) preparingUpload=\(preparingUploadScanIds.count, privacy: .public) completingUpload=\(completingUploadScanIds.count, privacy: .public)"
            )
            await sharedActor.reconcileOrphanedUploadingScans(
                activeScanIds: activeUploadScanIds.union(preparingUploadScanIds).union(completingUploadScanIds)
            )

            let activeInferenceScanIds = Set(allTasks.compactMap { task -> String? in
                guard task.state != .canceling,
                      task.state != .completed,
                      let desc = task.taskDescription,
                      desc.hasPrefix("inference_") else { return nil }
                return String(desc.dropFirst("inference_".count))
            })
            let preparingInferenceScanIds = await MainActor.run { self.inferencePreparationScanIds }
            let completingInferenceScanIds = await MainActor.run { self.inferenceCompletionScanIds }
            MerianLog.data.debug(
                "replayInferenceForUploadedScans: activeInferenceTasks=\(activeInferenceScanIds.count, privacy: .public) preparing=\(preparingInferenceScanIds.count, privacy: .public) completing=\(completingInferenceScanIds.count, privacy: .public)"
            )
            await sharedActor.reconcileOrphanedInferencingScans(
                activeInferenceScanIds: activeInferenceScanIds
                    .union(preparingInferenceScanIds)
                    .union(completingInferenceScanIds)
            )
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
        guard let staged = try? context.fetch(descriptor), !staged.isEmpty else {
            MerianLog.data.debug("replayInferenceStagedScans: no staged scans")
            return
        }
        MerianLog.data.debug("replayInferenceStagedScans: staged scans=\(staged.count, privacy: .public)")

        for scan in staged {
            let scanId = scan.id
            let extracted = buildExtractedScanData(from: scan, container: container)
            Task {
                let dbActor = resolvedInferenceDbActor(container: container)
                // Atomic claim: transitions .staged → .inferencing.
                // If another path already claimed it, this returns false and we skip.
                await MainActor.run { _ = self.inferencePreparationScanIds.insert(scanId) }
                let didClaim = await dbActor.tryClaimForInference(scanId: scanId)
                if !didClaim {
                    MerianLog.data.debug(
                        "replayInferenceStagedScans: claim skipped scanId=\(scanId, privacy: .public)"
                    )
                    await MainActor.run { _ = self.inferencePreparationScanIds.remove(scanId) }
                    return
                }
                MerianLog.data.debug(
                    "replayInferenceStagedScans: claimed scanId=\(scanId, privacy: .public)"
                )

#if DEBUG
                // Increment before any network work so tests can observe this as a
                // network-free signal that the replay pipeline was triggered.
                await MainActor.run { self.replayedStagedScanCount += 1 }
#endif

                // Migration fallback: pre-V33 media scans have no stagedR2Keys.
                // Reconstruct from the current auth session — safe because the userId
                // embedded in the R2 key matches the session that performed the upload.
                // Describe-only scans intentionally have both r2Keys and localUploadPaths
                // empty — guard on !localImagePaths.isEmpty to skip this path for them.
                let finalExtracted: ExtractedScanData
                if extracted.r2Keys.isEmpty && !extracted.localUploadPaths.isEmpty {
                    let stagingUserId = await self.currentMediaStagingUserId()
                    let reconstructedKeys = MediaStagingContract.splitObjectKeys(
                        [],
                        scanId: scanId,
                        userId: stagingUserId,
                        localImagePaths: extracted.localImagePaths,
                        localAudioPaths: extracted.audioFilePaths ?? [],
                        localVideoPaths: extracted.videoFilePaths ?? []
                    ).all
                    finalExtracted = ExtractedScanData(
                        telemetry: extracted.telemetry,
                        r2Keys: reconstructedKeys,
                        container: extracted.container,
                        originalTimestamp: extracted.originalTimestamp,
                        capturedMediaItems: extracted.capturedMediaItems
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
        audioFilePaths: [String] = [],
        videoFilePaths: [String] = [],
        telemetry: CaptureTelemetry,
        blurScore: Double? = nil,
        scanId: String? = nil,
        observationContexts: [ObservationContext] = [],
        mediaTimeline: [CaptureSubmissionMediaItem]? = nil,
        captureDate: Date = Date(),
        onQueued: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        let resolvedScanId = scanId ?? UUID().uuidString
        let documentsDirectory = URL.documentsDirectory
        MerianLog.data.debug(
            "enqueueCapture: requested scanId=\(resolvedScanId, privacy: .public) images=\(imageDatas.count, privacy: .public) bytes=\(imageDatas.reduce(0) { $0 + $1.count }, privacy: .public)"
        )
        let timeline = mediaTimeline ?? CaptureSubmissionMediaItem.defaultTimeline(
            imageCount: imageDatas.count,
            observationContexts: observationContexts,
            audioFilePaths: audioFilePaths,
            videoFilePaths: videoFilePaths
        )

        BackgroundTaskWrapper.execute(name: "OfflineQueueCaptureWrite", priority: .userInitiated) { [weak self] _ in
            guard let self else {
                if let onQueued {
                    await MainActor.run { onQueued(false) }
                }
                return
            }
            var fileURLs: [URL] = []
            do {
                let fileNames = await FileIOActor.shared.writeTemporaryImages(imageDatas: imageDatas)
                guard fileNames.count == imageDatas.count else {
                    await FileIOActor.shared.deleteImages(at: fileNames)
                    MerianLog.data.error("enqueueCapture: failed to persist the full staged image set — scan will not be queued.")
                    if let onQueued {
                        await MainActor.run { onQueued(false) }
                    }
                    return
                }

                fileURLs = fileNames.map { documentsDirectory.appendingPathComponent($0) }
                MerianLog.data.debug(
                    "enqueueCapture: persisted temp files scanId=\(resolvedScanId, privacy: .public) files=\(fileNames.joined(separator: ","), privacy: .public)"
                )
                let persistedAudioNamesBySourcePath = try self.persistQueuedAudioFiles(
                    audioFilePaths,
                    documentsDirectory: documentsDirectory
                )
                let persistedVideoNamesBySourcePath = try self.persistQueuedVideoFiles(
                    videoFilePaths,
                    documentsDirectory: documentsDirectory
                )
                let capturedMediaJSON = self.makeCapturedMediaJSON(
                    mediaTimeline: timeline,
                    imageFileNames: fileNames,
                    persistedAudioNamesBySourcePath: persistedAudioNamesBySourcePath,
                    persistedVideoNamesBySourcePath: persistedVideoNamesBySourcePath
                )

                let didQueue = await self.insertAndPersistRecord(
                    scanId: resolvedScanId,
                    fileURLs: fileURLs,
                    capturedMediaJSON: capturedMediaJSON,
                    telemetry: telemetry,
                    blurScore: blurScore,
                    timestamp: captureDate
                )
                if let onQueued {
                    await MainActor.run { onQueued(didQueue) }
                }
                MerianLog.data.debug(
                    "enqueueCapture: insert complete scanId=\(resolvedScanId, privacy: .public) didQueue=\(didQueue, privacy: .public)"
                )
            } catch {
                MerianLog.data.error("enqueueCapture: image write to disk failed — scan will not be queued: \(error, privacy: .private)")
                if !fileURLs.isEmpty {
                    await self.cleanupPersistedCaptureFiles(fileURLs)
                }
                if let onQueued {
                    await MainActor.run { onQueued(false) }
                }
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
        _ = enqueueNonVisualCapture(
            audioFileNames: [],
            observationContexts: [observationContext],
            mediaTimeline: [.description(observationContext)],
            telemetry: telemetry,
            scanId: scanId
        )
    }

    // MARK: - Enqueue Helpers

    private func cleanupPersistedCaptureFiles(_ urls: [URL]) async {
        await FileIOActor.shared.deleteFiles(at: urls.map(\.path))
    }

    @MainActor
    @discardableResult
    func enqueueNonVisualCapture(
        audioFileNames: [String],
        observationContexts: [ObservationContext],
        videoFilePaths: [String] = [],
        mediaTimeline: [CaptureSubmissionMediaItem]? = nil,
        telemetry: CaptureTelemetry,
        scanId: String? = nil
    ) -> Bool {
        let filteredAudioFileNames = audioFileNames.filter { !$0.isEmpty }
        let filteredVideoFilePaths = videoFilePaths.filter { !$0.isEmpty }
        let filteredObservationContexts = observationContexts.filter { !$0.isEmpty }
        let timeline = mediaTimeline ?? CaptureSubmissionMediaItem.defaultTimeline(
            imageCount: 0,
            observationContexts: filteredObservationContexts,
            audioFilePaths: filteredAudioFileNames,
            videoFilePaths: filteredVideoFilePaths
        )

        guard !timeline.isEmpty else { return false }

        let persistedAudioNamesBySourcePath: [String: String]
        do {
            persistedAudioNamesBySourcePath = try persistQueuedAudioFiles(
                filteredAudioFileNames,
                documentsDirectory: URL.documentsDirectory
            )
        } catch {
            MerianLog.data.error("enqueueNonVisualCapture: failed to persist audio file — scan not queued: \(error, privacy: .private)")
            return false
        }

        let persistedVideoNamesBySourcePath: [String: String]
        do {
            persistedVideoNamesBySourcePath = try persistQueuedVideoFiles(
                filteredVideoFilePaths,
                documentsDirectory: URL.documentsDirectory
            )
        } catch {
            MerianLog.data.error("enqueueNonVisualCapture: failed to persist video file — scan not queued: \(error, privacy: .private)")
            for persistedAudioName in persistedAudioNamesBySourcePath.values {
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(persistedAudioName))
            }
            return false
        }

        guard let modelContext else {
            MerianLog.data.error("enqueueNonVisualCapture: modelContext unavailable — scan not queued")
            for persistedAudioName in persistedAudioNamesBySourcePath.values {
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(persistedAudioName))
            }
            for persistedVideoName in persistedVideoNamesBySourcePath.values {
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(persistedVideoName))
            }
            return false
        }

        var didConsumeQuota = false
        if !RevenueCatManager.shared.isProActive {
            guard UsageManager.shared.canPerformScan(isProActive: false) else {
                for persistedAudioName in persistedAudioNamesBySourcePath.values {
                    try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(persistedAudioName))
                }
                for persistedVideoName in persistedVideoNamesBySourcePath.values {
                    try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(persistedVideoName))
                }
                MerianLog.data.debug("enqueueNonVisualCapture: free user scan quota exhausted — scan not queued")
                return false
            }
            UsageManager.shared.consumeScan()
            didConsumeQuota = true
        }

        let capturedMediaJSON = makeCapturedMediaJSON(
            mediaTimeline: timeline,
            imageFileNames: [],
            persistedAudioNamesBySourcePath: persistedAudioNamesBySourcePath,
            persistedVideoNamesBySourcePath: persistedVideoNamesBySourcePath
        )
        let hasAudio = !persistedAudioNamesBySourcePath.isEmpty
        let hasUploadableMedia = hasAudio || !persistedVideoNamesBySourcePath.isEmpty

        let resolvedScanId = scanId ?? UUID().uuidString.lowercased()
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
            scanState: hasUploadableMedia ? .pending : .staged,
            stagedR2Keys: []
        )
        if let capturedMediaJSON,
           let items = MediaJSONParser.serializedItems(jsonString: capturedMediaJSON) {
            scan.replaceCapturedMedia(with: items)
        }

        modelContext.insert(scan)
        do {
            try modelContext.save()
            updateUnsyncedItemCount()
            AppTelemetry.trackOfflineQueued()
            if hasUploadableMedia {
                syncPendingScans()
            } else if isOnline {
                replayInferenceForUploadedScans()
            }
            return true
        } catch {
            modelContext.rollback()
            if didConsumeQuota {
                UsageManager.shared.refundScan()
            }
            MerianLog.data.error("enqueueNonVisualCapture: context.save() failed: \(error, privacy: .private)")
            for persistedAudioName in persistedAudioNamesBySourcePath.values {
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(persistedAudioName))
            }
            for persistedVideoName in persistedVideoNamesBySourcePath.values {
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(persistedVideoName))
            }
            return false
        }
    }

    nonisolated private func persistQueuedAudioFiles(
        _ audioFilePaths: [String],
        documentsDirectory: URL
    ) throws -> [String: String] {
        guard !audioFilePaths.isEmpty else { return [:] }

        var persistedAudioNamesBySourcePath: [String: String] = [:]
        for audioFilePath in audioFilePaths {
            persistedAudioNamesBySourcePath[audioFilePath] = try persistQueuedAudioFile(
                audioFilePath,
                documentsDirectory: documentsDirectory
            )
        }
        return persistedAudioNamesBySourcePath
    }

    nonisolated private func persistQueuedVideoFiles(
        _ videoFilePaths: [String],
        documentsDirectory: URL
    ) throws -> [String: String] {
        guard !videoFilePaths.isEmpty else { return [:] }

        var persistedVideoNamesBySourcePath: [String: String] = [:]
        for videoFilePath in videoFilePaths {
            persistedVideoNamesBySourcePath[videoFilePath] = try persistQueuedAudioFile(
                videoFilePath,
                documentsDirectory: documentsDirectory
            )
        }
        return persistedVideoNamesBySourcePath
    }

    nonisolated private func persistQueuedAudioFile(
        _ audioFilePath: String,
        documentsDirectory: URL
    ) throws -> String {
        let normalizedPath = audioFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }

        let sourceURL = URL(fileURLWithPath: normalizedPath)
        let destinationName = sourceURL.lastPathComponent
        let destinationURL = documentsDirectory.appendingPathComponent(destinationName)

        let candidateURLs: [URL]
        if normalizedPath.hasPrefix("/") {
            candidateURLs = [sourceURL]
        } else {
            candidateURLs = [
                destinationURL,
                FileManager.default.temporaryDirectory.appendingPathComponent(normalizedPath)
            ]
        }

        for candidateURL in candidateURLs {
            guard FileManager.default.fileExists(atPath: candidateURL.path) else { continue }
            if candidateURL.path == destinationURL.path {
                return destinationName
            }
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: candidateURL, to: destinationURL)
            return destinationName
        }

        throw CocoaError(.fileNoSuchFile)
    }

    nonisolated private func makeCapturedMediaJSON(
        mediaTimeline: [CaptureSubmissionMediaItem],
        imageFileNames: [String],
        persistedAudioNamesBySourcePath: [String: String],
        persistedVideoNamesBySourcePath: [String: String] = [:]
    ) -> String? {
        var serializedItems: [SerializedMediaItem] = []

        for item in mediaTimeline {
            switch item {
            case .image(let index):
                guard imageFileNames.indices.contains(index) else { continue }
                serializedItems.append(.image(.documents(imageFileNames[index])))
            case .audio(let sourcePath):
                let persistedName = persistedAudioNamesBySourcePath[sourcePath]
                    ?? URL(fileURLWithPath: sourcePath).lastPathComponent
                guard !persistedName.isEmpty else { continue }
                serializedItems.append(.audio(.documents(persistedName)))
            case .video(let sourcePath):
                let persistedName = persistedVideoNamesBySourcePath[sourcePath]
                    ?? URL(fileURLWithPath: sourcePath).lastPathComponent
                guard !persistedName.isEmpty else { continue }
                serializedItems.append(.video(.documents(persistedName)))
            case .description(let context):
                guard !context.isEmpty else { continue }
                serializedItems.append(.description(context))
            }
        }

        guard !serializedItems.isEmpty else { return nil }
        return try? String(data: JSONEncoder().encode(serializedItems), encoding: .utf8)
    }

    @MainActor
    private func insertAndPersistRecord(
        scanId: String,
        fileURLs: [URL],
        capturedMediaJSON: String?,
        telemetry: CaptureTelemetry,
        blurScore: Double?,
        timestamp: Date
    ) async -> Bool {
        // Enforce quota at enqueue time so every scan that enters the queue is guaranteed to upload.
        // Consuming here (not at upload time) prevents silent stalls when syncPendingScans fires
        // after the experience was already granted to the user.
        guard let modelContext else {
            MerianLog.data.error(
                "insertAndPersistRecord: modelContext missing scanId=\(scanId, privacy: .public)"
            )
            await cleanupPersistedCaptureFiles(fileURLs)
            return false
        }

        var didConsumeQuota = false
        if !RevenueCatManager.shared.isProActive {
            guard UsageManager.shared.canPerformScan(isProActive: false) else {
                MerianLog.data.debug("enqueueCapture: free user scan quota exhausted — scan not enqueued")
                await cleanupPersistedCaptureFiles(fileURLs)
                return false
            }
            UsageManager.shared.consumeScan()
            didConsumeQuota = true
        }
        
        let scan = OfflineQueuedScan(
            id: scanId,
            timestamp: timestamp,
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
        if let capturedMediaJSON,
           let items = MediaJSONParser.serializedItems(jsonString: capturedMediaJSON) {
            scan.replaceCapturedMedia(with: items)
        }
        
        modelContext.insert(scan)

        do {
            try modelContext.save()
            updateUnsyncedItemCount()
            AppTelemetry.trackOfflineQueued()
            MerianLog.data.debug(
                "insertAndPersistRecord: saved queue scanId=\(scanId, privacy: .public) state=pending images=\(fileURLs.count, privacy: .public)"
            )
            syncPendingScans()
            return true
        } catch {
            modelContext.rollback()
            if didConsumeQuota {
                UsageManager.shared.refundScan()
            }
            MerianLog.data.error("enqueueCapture: context.save() failed — scan record lost, cleaning up image footprints: \(error, privacy: .private)")
            await cleanupPersistedCaptureFiles(fileURLs)
            return false
        }
    }
}
