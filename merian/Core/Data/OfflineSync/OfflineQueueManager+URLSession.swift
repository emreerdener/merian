import CoreLocation
import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - URLSession Delegate

extension OfflineQueueManager: URLSessionTaskDelegate, URLSessionDownloadDelegate {

    /// Fires when an inference background download task delivers its response body to a temp file.
    ///
    /// The temp file is only valid for the duration of this callback — copy it immediately.
    /// All result processing happens in `processInferenceDownloadResult` via a BackgroundTaskWrapper
    /// so iOS grants extended execution time to complete the SwiftData write and push notification.
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskDescription = downloadTask.taskDescription,
              taskDescription.hasPrefix("inference_") else { return }

        let scanId = String(taskDescription.dropFirst("inference_".count))
        let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode

        // Copy the temp file before the system deletes it at callback return.
        let tempDestination = URL.temporaryDirectory.appendingPathComponent("\(scanId)_inference.json")
        try? FileManager.default.removeItem(at: tempDestination)
        do {
            try FileManager.default.copyItem(at: location, to: tempDestination)
        } catch {
            MerianLog.data.error("Background inference download: failed to preserve temp file for \(scanId, privacy: .private): \(error, privacy: .private)")
            BackgroundTaskWrapper.execute(name: "OfflineInferenceError") { _ in
                await OfflineQueueManager.shared.handleInferenceTaskNetworkFailure(scanId: scanId, error: error)
            }
            return
        }

        BackgroundTaskWrapper.execute(name: "OfflineInferenceResult") { _ in
            await OfflineQueueManager.shared.processInferenceDownloadResult(
                scanId: scanId,
                resultFileURL: tempDestination,
                statusCode: statusCode
            )
        }
    }

    /// Fires when the background URLSession completes transmission of a task (upload or download).
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Capture non-Sendable properties before crossing isolation boundaries.
        let taskDescription = task.taskDescription
        let originalRequestUrlPath = task.originalRequest?.url?.path
        let responseStatusCode = (task.response as? HTTPURLResponse)?.statusCode
        let taskIdentifier = task.taskIdentifier

        BackgroundTaskWrapper.execute(
            name: "OfflineInference",
            expirationHandler: { MerianLog.data.debug("OfflineInference background task expired") }
        ) { _ in
            // Route inference download task failures.
            // On success, didFinishDownloadingTo already handled the result — skip here.
            if let taskDesc = taskDescription, taskDesc.hasPrefix("inference_") {
                if let error {
                    let scanId = String(taskDesc.dropFirst("inference_".count))
                    await OfflineQueueManager.shared.handleInferenceTaskNetworkFailure(scanId: scanId, error: error)
                }
                // Inference tasks are not counted in the upload isSyncing state machine.
                return
            }

            // handleResult is a local async closure so that early returns from upload
            // processing don't bypass the activeTasks completion check that follows it.
            let handleResult: @Sendable () async -> Void = {
                await OfflineQueueManager.shared.processUploadCompletion(
                    taskDescription: taskDescription,
                    originalRequestUrlPath: originalRequestUrlPath,
                    responseStatusCode: responseStatusCode,
                    uploadError: error,
                    taskIdentifier: taskIdentifier,
                    session: session
                )
            }

            await handleResult()

            // Signal sync completion once all background upload tasks have settled.
            // Exclude inference download tasks — they have their own lifecycle.
            let remaining = await session.allTasks
            let activeUploadTasks = remaining.filter {
                $0.taskIdentifier != taskIdentifier &&
                !($0.taskDescription?.hasPrefix("inference_") ?? false)
            }
            if activeUploadTasks.isEmpty {
                await MainActor.run {
                    OfflineQueueManager.shared.isSyncing = false
                    if OfflineQueueManager.shared.unsyncedItemsCount > 0 {
                        OfflineQueueManager.shared.syncPendingScans()
                    } else {
                        SyncStateManager.shared.completeUploadPhase()
                    }
                }
            }
        }
    }

    /// Called by iOS when all background session events have been delivered.
    /// Invokes the stored completion handler so the system knows it's safe to suspend the app.
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            guard let handler = OfflineQueueManager.shared.backgroundCompletionHandler else { return }
            OfflineQueueManager.shared.backgroundCompletionHandler = nil
            handler()
        }
    }
}

// MARK: - Upload Completion & Inference Pipeline

extension OfflineQueueManager {

    /// Processes the result of a completed background upload, then kicks off inference
    /// for the scan once all of its image files have landed in R2 staging.
    func processUploadCompletion(
        taskDescription: String?,
        originalRequestUrlPath: String?,
        responseStatusCode: Int?,
        uploadError: Error?,
        taskIdentifier: Int,
        session: URLSession
    ) async {
        guard let taskDesc = taskDescription else { return }

        let components = taskDesc.components(separatedBy: "_")
        let scanId = components[0]

        // 1. Compute completion state universally upfront to prevent state-machine deadlocks.
        let remainingTasks = await session.allTasks
        let hasActiveTasksForScan = remainingTasks.contains {
            $0.taskIdentifier != taskIdentifier &&
            ($0.taskDescription?.starts(with: "\(scanId)_") ?? false)
        }

        let didFail = await handleUploadFallback(scanId: scanId, uploadError: uploadError, responseStatusCode: responseStatusCode)
        guard !didFail else { return }

        // Only trigger inference for files that landed in the staging bucket.
        guard let urlPath = originalRequestUrlPath, urlPath.contains("staging/") else { return }

        // Ensure no other upload tasks for this specific scan ID are still in flight.
        // If they are, allow them to finish (the last one handles the inference triggering).
        // Guard here — before the main-actor metadata fetch and auth session lookup — so that
        // multi-image scans don't pay those costs on every intermediate completion (only the last).
        guard !hasActiveTasksForScan else { return }

        // Fetch scan metadata on the main actor before handing off to background inference.
        let extracted = await fetchScanMetadata(for: scanId)
        guard let extracted else { return }

        // Compute the R2 object keys using the auth session active at upload time and persist
        // them atomically with the .staged transition. Storing keys now eliminates the
        // auth-expiry 403 edge case that occurred when keys were reconstructed at inference time.
        let authUserId = try? await SupabaseManager.shared.client.auth.session.user.id.uuidString
        let deviceId = await MainActor.run { DeviceIdentityManager.shared.deviceId }
        let userId = (authUserId ?? deviceId).lowercased()
        let r2Keys = extracted.localImagePaths.map { "staging/\(userId)/\(scanId)_\($0)" }

        // Use the same shared actor as replayInferenceForUploadedScans so that
        // markScanAsStaged and tryClaimForInference are serialized on a single executor.
        // This closes the race where processUploadCompletion and replayInferenceForUploadedScans
        // could both see the scan in .staged and both dispatch concurrent inference tasks.
        let inferenceActor = resolvedInferenceDbActor(container: extracted.container)
        await inferenceActor.markScanAsStaged(scanId: scanId, r2Keys: r2Keys)

        // Atomically claim the scan for inference. If replayInferenceForUploadedScans already
        // claimed it between markScanAsStaged and here (same actor, so serialized), skip —
        // the replay path already dispatched the background download task.
        guard await inferenceActor.tryClaimForInference(scanId: scanId) else { return }

        // Rebuild extracted with the confirmed R2 keys before dispatching.
        let extractedWithKeys = ExtractedScanData(
            telemetry: extracted.telemetry,
            localImagePaths: extracted.localImagePaths,
            r2Keys: r2Keys,
            container: extracted.container,
            originalTimestamp: extracted.originalTimestamp
        )
        await dispatchInferenceDownloadTask(scanId: scanId, extracted: extractedWithKeys)
    }

    // MARK: - Post-Upload Helpers

    /// Handles transport-level and HTTP-level upload errors.
    /// Returns `true` if an error was found and handled (caller should abort), `false` on success.
    private func handleUploadFallback(scanId: String, uploadError: Error?, responseStatusCode: Int?) async -> Bool {
        if let uploadError {
            let nsError = uploadError as NSError
            let isFileMissing = nsError.domain == NSURLErrorDomain
                && (nsError.code == NSURLErrorFileDoesNotExist || nsError.code == NSURLErrorCannotOpenFile)
            
            if isFileMissing {
                MerianLog.data.debug("Terminal file corruption — tombstoning \(scanId, privacy: .private)")
                await MainActor.run { OfflineQueueManager.shared.softDeleteQueuedScan(scanId: scanId) }
                return true
            }

            let transientCodes: Set<Int> = [
                NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet,
                NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff
            ]
            if nsError.domain == NSURLErrorDomain && transientCodes.contains(nsError.code) {
                let retries = await MainActor.run { () -> Int in
                    let next = (OfflineQueueManager.shared.uploadRetryCount[scanId] ?? 0) + 1
                    OfflineQueueManager.shared.uploadRetryCount[scanId] = next
                    return next
                }
                let max = OfflineQueueManager.maxUploadRetries
                if retries >= max {
                    MerianLog.data.debug("Upload retry limit reached (\(retries)/\(max)) — tombstoning \(scanId, privacy: .private)")
                    await MainActor.run {
                        OfflineQueueManager.shared.uploadRetryCount.removeValue(forKey: scanId)
                        OfflineQueueManager.shared.softDeleteQueuedScan(scanId: scanId)
                    }
                } else {
                    MerianLog.data.debug("Transient upload error \(retries)/\(max) for \(scanId, privacy: .private) — retaining in queue")
                }
            } else {
                MerianLog.data.debug("Background upload failed: \(uploadError, privacy: .private)")
            }
            return true
        }

        guard let statusCode = responseStatusCode, statusCode == 200 else {
            let code = responseStatusCode ?? 0
            let recoverableCodes: Set<Int> = [429, 500, 502, 503, 504]
            if recoverableCodes.contains(code) {
                MerianLog.data.debug("Background upload recoverable (\(code, privacy: .public)) — retaining in queue")
            } else {
                MerianLog.data.debug("Background upload rejected (\(code, privacy: .public)) — tombstoning scan")
                await MainActor.run { OfflineQueueManager.shared.softDeleteQueuedScan(scanId: scanId) }
            }
            return true
        }

        return false
    }

    /// Fetches the queued scan's snapshot and maps it to ExtractedScanData on the main actor.
    private func fetchScanMetadata(for scanId: String) async -> ExtractedScanData? {
        return await MainActor.run { () -> ExtractedScanData? in
            guard let context = OfflineQueueManager.shared.modelContext else { return nil }
            let container = context.container
            var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
            descriptor.fetchLimit = 1
            let scan: OfflineQueuedScan?
            do {
                scan = try context.fetch(descriptor).first
            } catch {
                MerianLog.data.debug("urlSession: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)")
                return nil
            }
            guard let scan else { return nil }
            return OfflineQueueManager.shared.buildExtractedScanData(from: scan, container: container)
        }
    }

    // MARK: - Scan Data Extraction

    /// Maps a queued scan record to a Sendable `ExtractedScanData` snapshot.
    /// Must be called while `scan` is accessible on the main actor.
    func buildExtractedScanData(from scan: OfflineQueuedScan, container: ModelContainer) -> ExtractedScanData {
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
        return ExtractedScanData(
            telemetry: telemetry,
            localImagePaths: scan.localImagePaths,
            r2Keys: scan.stagedR2Keys ?? [],
            container: container,
            originalTimestamp: scan.timestamp
        )
    }

    // MARK: - Background Inference Dispatch

    /// Fetches WeatherKit backfill, builds an authenticated request, and dispatches it as a
    /// background URLSession download task so inference results arrive while the app is suspended.
    ///
    /// Weather backfill is persisted to SwiftData before dispatch so the delegate can read the
    /// hydrated telemetry from the store when the OS delivers the result — even after a relaunch.
    ///
    /// Task description: `"inference_{scanId}"` — used by the delegate to route completion.
    func dispatchInferenceDownloadTask(scanId: String, extracted: ExtractedScanData) async {
        let baseTelemetry = extracted.telemetry

        // Run WeatherKit backfill before building the request. Weather data must be embedded
        // in the request payload at task-creation time, since there is no async opportunity
        // to fetch it after the OS takes ownership of the suspended background task.
        let needsWeather = baseTelemetry.weatherCondition == nil
            && baseTelemetry.gpsLatitude != nil
            && baseTelemetry.gpsLongitude != nil

        var finalTelemetry = baseTelemetry
        if needsWeather {
            let ctx = await EnvironmentContextManager.shared.fetchHistoricalContext(
                location: CLLocation(latitude: baseTelemetry.gpsLatitude!, longitude: baseTelemetry.gpsLongitude!),
                date: extracted.originalTimestamp
            )
            MerianLog.data.debug("Hydrated offline scan with historical weather: \(ctx.weatherCondition ?? "none", privacy: .public)")
            finalTelemetry = CaptureTelemetry(
                subjectDistanceInMeters: baseTelemetry.subjectDistanceInMeters,
                gpsLatitude: baseTelemetry.gpsLatitude,
                gpsLongitude: baseTelemetry.gpsLongitude,
                gpsElevation: baseTelemetry.gpsElevation,
                locationName: baseTelemetry.locationName ?? ctx.locationName,
                weatherCondition: ctx.weatherCondition,
                weatherTemperatureF: ctx.weatherTemperature,
                timeOfDay: baseTelemetry.timeOfDay,
                timestamp: baseTelemetry.timestamp
            )
            // Persist weather backfill so the delegate can read it on result delivery,
            // even if the app was suspended between task dispatch and receipt.
            let dbActor = resolvedInferenceDbActor(container: extracted.container)
            await dbActor.updateScanTelemetry(
                scanId: scanId,
                weatherCondition: ctx.weatherCondition,
                weatherTemperatureF: ctx.weatherTemperature,
                locationName: ctx.locationName
            )
        }

        // Build the authenticated request. On failure (e.g., Keychain read failure while
        // backgrounded), reset to .staged so the next sync cycle can retry.
        let request: URLRequest
        do {
            request = try await MerianNetworkClient.shared.buildIdentifyRequest(
                r2ObjectKeys: extracted.r2Keys,
                telemetry: finalTelemetry,
                clientScanId: scanId
            )
        } catch {
            MerianLog.data.error("dispatchInferenceDownloadTask: failed to build request for \(scanId, privacy: .private): \(error, privacy: .private)")
            let retryActor = resolvedInferenceDbActor(container: extracted.container)
            await retryActor.transitionScanToStaged(id: scanId)
            return
        }

        // Dispatch the background download task. The OS serializes the URLRequest (including
        // httpBody) at resume() time — safe to use inline httpBody on background sessions.
        let task = backgroundSession.downloadTask(with: request)
        task.taskDescription = "inference_\(scanId)"
        await MainActor.run { SyncStateManager.shared.beginInferencing() }
        task.resume()

        MerianLog.data.debug("🚀 BACKGROUND INFERENCE: Dispatched download task for \(scanId, privacy: .public)")
    }

    // MARK: - Inference Result Processing

    /// Processes the JSON file delivered by a completed background inference download task.
    ///
    /// Mirrors the success/failure routing of the former `runInferencePipeline`:
    /// - HTTP 4xx → tombstone (permanent failure)
    /// - HTTP 5xx / missing data → retry via `.staged` reset (up to `maxUploadRetries`)
    /// - HTTP 200 → persist `LocalScanRecord`, delete `OfflineQueuedScan`, fire notifications
    func processInferenceDownloadResult(scanId: String, resultFileURL: URL, statusCode: Int?) async {
        defer { try? FileManager.default.removeItem(at: resultFileURL) }

        guard let statusCode, statusCode == 200 else {
            let code = statusCode ?? 0
            if (400...499).contains(code) {
                MerianLog.data.debug("Inference failed permanently for \(scanId, privacy: .private) [\(code)] — tombstoning scan")
                await MainActor.run { OfflineQueueManager.shared.softDeleteQueuedScan(scanId: scanId) }
            } else {
                MerianLog.data.debug("Inference download non-200 [\(code)] for \(scanId, privacy: .private) — retry")
                await handleInferenceRetry(scanId: scanId)
            }
            return
        }

        guard let resultData = try? Data(contentsOf: resultFileURL), !resultData.isEmpty else {
            MerianLog.data.error("Background inference download: result file unreadable for \(scanId, privacy: .private)")
            await handleInferenceRetry(scanId: scanId)
            return
        }

        // Fetch the scan from SwiftData to read its current telemetry (may include weather
        // backfill persisted by dispatchInferenceDownloadTask before app suspension).
        let extracted: ExtractedScanData? = await MainActor.run {
            guard let context = OfflineQueueManager.shared.modelContext else { return nil }
            let container = context.container
            var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
            descriptor.fetchLimit = 1
            guard let scan = (try? context.fetch(descriptor))?.first else { return nil }
            return OfflineQueueManager.shared.buildExtractedScanData(from: scan, container: container)
        }

        guard let extracted else {
            // Scan was already cleaned up (e.g., live path completed first). Nothing to do.
            MerianLog.data.debug("Background inference: scan \(scanId, privacy: .private) already removed — skipping cleanup")
            return
        }

        let pipelineStart = CFAbsoluteTimeGetCurrent()
        await MainActor.run { SyncStateManager.shared.beginFinalizing() }

        // Use a fresh actor so a failed atomic save doesn't corrupt the shared actor's context.
        let cleanupActor = BackgroundDatabaseActor(modelContainer: extracted.container)
        let processingResult = await cleanupActor.processAndCleanupOfflineScan(
            resultData: resultData,
            originalImagePaths: extracted.localImagePaths,
            scanId: scanId,
            originalTimestamp: extracted.originalTimestamp,
            telemetry: extracted.telemetry
        )

        // Delete the OfflineQueuedScan from the main ModelContext so @Query re-evaluates in
        // any open sheet. The background actor intentionally left it alive (see wasCleaned doc);
        // this deletion guarantees the main context has a real pending change when it saves —
        // the only reliable @Query trigger in a presented sheet (SwiftData platform limitation).
        if processingResult.wasCleaned {
            await MainActor.run {
                OfflineQueueManager.shared.flushOfflineQueuedScan(scanId: scanId)
            }
        }

        if let speciesName = processingResult.resolvedSpeciesName, let dbScanId = processingResult.finalScanId {
            let capturedContainer = extracted.container
            await MainActor.run {
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasUnseenScan)
                PushNotificationManager.shared.setBadgeCount(1)
                if processingResult.isNewDiscovery {
                    GamificationManager.shared.recordNewSpeciesDiscovered()
                }
                if UserDefaults.standard.bool(forKey: UserDefaultsKeys.isPushNotificationsEnabled) {
                    #if canImport(UIKit)
                    if UIApplication.shared.applicationState != .active {
                        PushNotificationManager.shared.sendInferenceCompleteNotification(speciesName: speciesName, scanId: dbScanId)
                    }
                    #endif
                }
                // Debounce award recalculation so a burst of completions fires one pass.
                awardsDebounceTask?.cancel()
                awardsDebounceTask = Task { [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(for: .seconds(0.5))
                    guard !Task.isCancelled else { return }
                    let profileActor = self.resolvedProfileDbActor(container: capturedContainer)
                    let updatedAwards = await profileActor.calculateAwards()
                    GamificationManager.shared.evaluateAchievementsForNotifications(awards: updatedAwards)
                }

                // If the background path completed the same scan the live InferenceEngine is
                // currently processing, hydrate the engine directly. This fixes the case where
                // the user backgrounds the app immediately after capture: the live inference Task
                // is suspended (no BackgroundTaskWrapper protects it), the background URLSession
                // path races ahead and wins, but isProcessing stays true — leaving the insight
                // sheet in "Analyzing..." until the live task eventually times out and shows
                // "Network Timeout" even though the scan completed successfully.
                //
                // Cancelling inferenceTask causes its defer { isProcessing = false } to run
                // cooperatively (URLError.cancelled → catch → return). Setting isProcessing and
                // speciesData here is safe because we are on the main actor; the deferred set is
                // a later no-op on the same actor, and the cancel path never writes speciesData.
                if let speciesData = processingResult.speciesData {
                    let engine = AppDIContainer.shared.inferenceEngine
                    // Hydrate when the engine is still waiting for a result for this exact scan.
                    // `isProcessing` covers the case where the live path is still in flight.
                    // `engine.speciesData?.scanId == nil` covers the case where the live path
                    // already failed (timeout/network error) — those placeholders have scanId = nil.
                    // We must NOT overwrite a successful live result (speciesData.scanId != nil).
                    if engine.activeScanId == scanId,
                       engine.isProcessing || engine.speciesData?.scanId == nil {
                        engine.inferenceTask?.cancel()
                        engine.isProcessing = false
                        engine.speciesData = speciesData
                    }
                }
            }
        }

        MerianLog.data.debug("⏱️ Background pipeline total: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - pipelineStart), privacy: .public)s")
        await MainActor.run {
            // updateUnsyncedItemCount() is already called by flushOfflineQueuedScan above;
            // only call it here for the wasCleaned==false path (save failed) where flush was skipped.
            if !processingResult.wasCleaned {
                OfflineQueueManager.shared.updateUnsyncedItemCount()
            }
            CircuitBreakerManager.shared.recordSuccess()
            _ = OfflineQueueManager.shared.uploadRetryCount.removeValue(forKey: scanId)
            SyncStateManager.shared.completeSync()
        }
    }

    // MARK: - Inference Failure Handling

    /// Handles a background inference download task network-level failure.
    ///
    /// Called from `urlSession(_:task:didCompleteWithError:)` when the download task fails
    /// with a transport error (the server never responded). Resets the scan to `.staged` below
    /// the retry threshold, or tombstones it once `maxUploadRetries` is exhausted.
    ///
    /// Code=-999 (NSURLErrorCancelled) is special-cased: it means `deleteQueuedScan` explicitly
    /// cancelled the task because the parallel live inference path already succeeded. The scan
    /// record has already been removed; no retry is needed.
    func handleInferenceTaskNetworkFailure(scanId: String, error: Error) async {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            MerianLog.data.debug("Background inference cancelled for \(scanId, privacy: .private) — live path completed first, skipping retry")
            return
        }
        MerianLog.data.debug("Background inference download failed for \(scanId, privacy: .private): \(error, privacy: .private)")
        await handleInferenceRetry(scanId: scanId)
    }

    /// Increments the retry counter for a scan and either resets it to `.staged` for the
    /// next sync cycle or tombstones it once `maxUploadRetries` is exhausted.
    private func handleInferenceRetry(scanId: String) async {
        guard let container = modelContext?.container else { return }

        let retries = await MainActor.run { () -> Int in
            let next = (uploadRetryCount[scanId] ?? 0) + 1
            uploadRetryCount[scanId] = next
            return next
        }

        if retries >= OfflineQueueManager.maxUploadRetries {
            MerianLog.data.debug("Inference retry limit reached for \(scanId, privacy: .private) — tombstoning scan")
            await MainActor.run {
                uploadRetryCount.removeValue(forKey: scanId)
                softDeleteQueuedScan(scanId: scanId)
            }
        } else {
            let retryActor = resolvedInferenceDbActor(container: container)
            await retryActor.transitionScanToStaged(id: scanId)
            MerianLog.data.debug("Inference failed for \(scanId, privacy: .private) — reset to .staged for retry (\(retries)/\(OfflineQueueManager.maxUploadRetries))")
        }
    }
}
