import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Queue Maintenance

extension OfflineQueueManager {

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
    func deleteQueuedScan(scanId: String) async {
        // 1. Cancel in-flight URLSession tasks (both upload chunks and inference download).
        let allTasks = await backgroundSession.allTasks
        for task in allTasks {
            if let desc = task.taskDescription,
               desc.starts(with: "\(scanId)_") || desc == "inference_\(scanId)" {
                task.cancel()
            }
        }

        // 2. Eradicate from SwiftData and Disk
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        guard let scan = (try? context.fetch(descriptor))?.first else { return }

        let documentsDirectory = URL.documentsDirectory
        for path in scan.localImagePaths {
            try? FileManager.default.removeItem(at: documentsDirectory.appendingPathComponent(path))
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
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.scanStateRaw == failedRaw }
        )
        let documentsDirectory = URL.documentsDirectory

        do {
            let failedScans = try context.fetch(descriptor)
            for scan in failedScans {
                for path in scan.localImagePaths {
                    do {
                        try FileManager.default.removeItem(at: documentsDirectory.appendingPathComponent(path))
                    } catch {
                        MerianLog.data.debug("purgeSoftDeletedRecords: removeItem failed: \(error, privacy: .private)")
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
            let r2Keys = scan.stagedR2Keys ?? []
            var telemetry = CaptureTelemetry(
                subjectDistanceInMeters: scan.subjectDistanceInMeters,
                gpsLatitude: scan.gpsLatitude,
                gpsLongitude: scan.gpsLongitude,
                gpsElevation: scan.gpsElevation,
                locationName: scan.locationName,
                weatherCondition: scan.weatherCondition,
                weatherTemperatureF: scan.weatherTemperatureF,
                timeOfDay: nil,
                timestamp: DateUtilities.iso8601Formatter.string(from: scan.timestamp)
            )
            telemetry.zoomFactor = scan.zoomFactor.map { CGFloat($0) }
            let extracted = ExtractedScanData(
                telemetry: telemetry,
                localImagePaths: scan.localImagePaths,
                r2Keys: r2Keys,
                container: container,
                originalTimestamp: scan.timestamp
            )
            Task {
                let dbActor = resolvedInferenceDbActor(container: container)
                // Atomic claim: transitions .staged → .inferencing.
                // If another path already claimed it, this returns false and we skip.
                guard await dbActor.tryClaimForInference(scanId: scanId) else { return }

                // Migration fallback: scans promoted from V32's isUploaded=true have no
                // stagedR2Keys (the field didn't exist). Reconstruct from the current auth
                // session — same approach as the pre-V33 code, safe because the userId
                // embedded in the R2 key matches the session that performed the upload.
                let finalExtracted: ExtractedScanData
                if extracted.r2Keys.isEmpty {
                    let authUserId = try? await SupabaseManager.shared.client.auth.session.user.id.uuidString
                    let deviceId = await MainActor.run { DeviceIdentityManager.shared.deviceId }
                    let userId = (authUserId ?? deviceId).lowercased()
                    let reconstructedKeys = extracted.localImagePaths.map { "staging/\(userId)/\(scanId)_\($0)" }
                    finalExtracted = ExtractedScanData(
                        telemetry: extracted.telemetry,
                        localImagePaths: extracted.localImagePaths,
                        r2Keys: reconstructedKeys,
                        container: extracted.container,
                        originalTimestamp: extracted.originalTimestamp
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
    /// - Parameter scanId: A caller-supplied identifier that ties this queued record to a
    ///   concurrent live inference request. Pass the same UUID to `analyze()` so the live
    ///   path can cancel the upload if inference succeeds first. When `nil` a new UUID is
    ///   generated (used by callers that do not run a parallel live inference).
    func enqueueCapture(imageDatas: [Data], telemetry: CaptureTelemetry, blurScore: Double? = nil, scanId: String? = nil) {
        let resolvedScanId = scanId ?? UUID().uuidString
        let documentsDirectory = URL.documentsDirectory
        let pairs = imageDatas.map { _ -> (name: String, url: URL) in
            let name = "\(UUID().uuidString).webp"
            return (name, documentsDirectory.appendingPathComponent(name))
        }
        let fileNames = pairs.map(\.name)
        let fileURLs = pairs.map(\.url)

        // .userInitiated ensures the disk write and URLSession upload dispatch complete
        // before the cooperative scheduler can be frozen by an app suspension. .background
        // priority can be starved if the user swipes away within milliseconds of capture.
        BackgroundTaskWrapper.execute(name: "OfflineQueueCaptureWrite", priority: .userInitiated) { _ in
            do {
                for (index, data) in imageDatas.enumerated() {
                    try data.write(to: fileURLs[index])
                }

                await MainActor.run {
                    // Free users are capped at their daily scan limit to prevent scan hoarding.
                    // If the cap is already hit, clean up the files we just wrote and bail.
                    if !RevenueCatManager.shared.isProActive,
                       let modelContext = OfflineQueueManager.shared.modelContext {
                        let failedRaw = ScanQueueState.failed.rawValue
                        let capDescriptor = FetchDescriptor<OfflineQueuedScan>(
                            predicate: #Predicate { $0.scanStateRaw != failedRaw }
                        )
                        let currentCount = (try? modelContext.fetchCount(capDescriptor)) ?? 0
                        if currentCount >= UsageManager.shared.maxFreeScansPerDay {
                            MerianLog.data.debug("enqueueCapture: free user queue cap reached — scan not enqueued")
                            for url in fileURLs { try? FileManager.default.removeItem(at: url) }
                            return
                        }
                    }

                    let scan = OfflineQueuedScan(
                        id: resolvedScanId,
                        timestamp: Date(),
                        localImagePaths: fileNames,
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
                    guard let modelContext = OfflineQueueManager.shared.modelContext else { return }
                    modelContext.insert(scan)
                    do {
                        try modelContext.save()
                        OfflineQueueManager.shared.updateUnsyncedItemCount()
                        AppTelemetry.trackOfflineQueued()
                        // Kick off sync immediately while iOS has an active background window.
                        OfflineQueueManager.shared.syncPendingScans()
                    } catch {
                        MerianLog.data.error("enqueueCapture: context.save() failed — scan record lost, cleaning up image footprints: \(error, privacy: .private)")
                        for url in fileURLs {
                            do { try FileManager.default.removeItem(at: url) } catch {
                                MerianLog.data.debug("enqueueCapture: cleanup removeItem failed: \(error, privacy: .private)")
                            }
                        }
                    }
                }
            } catch {
                MerianLog.data.error("enqueueCapture: image write to disk failed — scan will not be queued: \(error, privacy: .private)")
                for url in fileURLs {
                    do { try FileManager.default.removeItem(at: url) } catch {
                        MerianLog.data.debug("enqueueCapture: cleanup removeItem failed: \(error, privacy: .private)")
                    }
                }
            }
        }
    }
}
