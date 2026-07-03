import CoreLocation
import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

private enum InferencePreparationFailure: Error {
    case timedOut
}

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
        MerianLog.data.debug(
            "urlSession didFinishDownloadingTo: inference scanId=\(scanId, privacy: .public) status=\(statusCode ?? -1, privacy: .public)"
        )

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
                let scanId = String(taskDesc.dropFirst("inference_".count))
                MerianLog.data.debug(
                    "urlSession didCompleteWithError: inference scanId=\(scanId, privacy: .public) status=\(responseStatusCode ?? -1, privacy: .public) error=\((error?.localizedDescription ?? "nil"), privacy: .public)"
                )
                if let error {
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
            // Re-query allTasks here (not reusing the snapshot from processUploadCompletion)
            // because dispatchInferenceDownloadTask may have added new download tasks during
            // handleResult — those must be excluded from the upload-completion gate.
            let remaining = await session.allTasks
            let activeUploadTasks = remaining.filter {
                $0.taskIdentifier != taskIdentifier &&
                MediaStagingContract.parseUploadTaskDescription($0.taskDescription) != nil
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
        guard let uploadIdentity = MediaStagingContract.parseUploadTaskDescription(taskDescription) else { return }
        let scanId = uploadIdentity.scanId
        _ = uploadCompletionScanIds.insert(scanId)
        defer {
            _ = uploadCompletionScanIds.remove(scanId)
            MerianLog.data.debug(
                "processUploadCompletion: cleared upload completion lock scanId=\(scanId, privacy: .public)"
            )
        }
        let uploadIndex = uploadIdentity.uploadIndex ?? -1
        MerianLog.data.debug(
            "processUploadCompletion: scanId=\(scanId, privacy: .public) uploadIndex=\(uploadIndex, privacy: .public) status=\(responseStatusCode ?? -1, privacy: .public) error=\((uploadError?.localizedDescription ?? "nil"), privacy: .public)"
        )

        // 1. Compute completion state universally upfront to prevent state-machine deadlocks.
        let remainingTasks = await session.allTasks
        let hasActiveTasksForScan = remainingTasks.contains {
            $0.taskIdentifier != taskIdentifier &&
            MediaStagingContract.uploadTaskDescription($0.taskDescription, belongsTo: scanId)
        }
        MerianLog.data.debug(
            "processUploadCompletion: scanId=\(scanId, privacy: .public) hasActiveTasksForScan=\(hasActiveTasksForScan, privacy: .public) remainingTasks=\(remainingTasks.count, privacy: .public)"
        )

        let didFail = await handleUploadFallback(scanId: scanId, uploadError: uploadError, responseStatusCode: responseStatusCode)
        guard !didFail else { return }

        // Only trigger inference for files that landed in the staging bucket.
        guard let urlPath = originalRequestUrlPath, urlPath.contains("staging/") else {
            MerianLog.data.debug(
                "processUploadCompletion: scanId=\(scanId, privacy: .public) completed non-staging URL path=\(originalRequestUrlPath ?? "nil", privacy: .public)"
            )
            return
        }

        // Ensure no other upload tasks for this specific scan ID are still in flight.
        // If they are, allow them to finish (the last one handles the inference triggering).
        // Guard here — before the main-actor metadata fetch and auth session lookup — so that
        // multi-image scans don't pay those costs on every intermediate completion (only the last).
        guard !hasActiveTasksForScan else {
            MerianLog.data.debug(
                "processUploadCompletion: scanId=\(scanId, privacy: .public) waiting for remaining upload tasks"
            )
            return
        }

        // Fetch scan metadata on the main actor before handing off to background inference.
        let extracted = await fetchScanMetadata(for: scanId)
        guard let extracted else {
            MerianLog.data.error(
                "processUploadCompletion: missing queued scan metadata scanId=\(scanId, privacy: .public)"
            )
            return
        }

        // Compute confirmed object keys through the shared media staging contract so
        // completion, replay, and request construction cannot drift on filename rules.
        let stagingUserId = await currentMediaStagingUserId()
        let stagedKeys = MediaStagingContract.splitObjectKeys(
            [],
            scanId: scanId,
            userId: stagingUserId,
            localImagePaths: extracted.localImagePaths,
            localAudioPaths: extracted.audioFilePaths ?? []
        )
        let r2Keys = stagedKeys.all
        MerianLog.data.debug(
            "processUploadCompletion: scanId=\(scanId, privacy: .public) staging complete keys=\(r2Keys.count, privacy: .public)"
        )

        // Use the same shared actor as replayInferenceForUploadedScans so that
        // markScanAsStaged and tryClaimForInference are serialized on a single executor.
        // This closes the race where processUploadCompletion and replayInferenceForUploadedScans
        // could both see the scan in .staged and both dispatch concurrent inference tasks.
        let inferenceActor = resolvedInferenceDbActor(container: extracted.container)
        await inferenceActor.markScanAsStaged(scanId: scanId, r2Keys: r2Keys)

        // Atomically claim the scan for inference. If replayInferenceForUploadedScans already
        // claimed it between markScanAsStaged and here (same actor, so serialized), skip —
        // the replay path already dispatched the background download task.
        await MainActor.run { _ = self.inferencePreparationScanIds.insert(scanId) }
        let didClaimInference = await inferenceActor.tryClaimForInference(scanId: scanId)
        if !didClaimInference {
            MerianLog.data.debug(
                "processUploadCompletion: inference claim skipped scanId=\(scanId, privacy: .public)"
            )
            await MainActor.run { _ = self.inferencePreparationScanIds.remove(scanId) }
            return
        }
        MerianLog.data.debug(
            "processUploadCompletion: inference claimed scanId=\(scanId, privacy: .public)"
        )

        // Rebuild extracted with the confirmed R2 keys before dispatching.
        let extractedWithKeys = ExtractedScanData(
            telemetry: extracted.telemetry,
            r2Keys: r2Keys,
            container: extracted.container,
            originalTimestamp: extracted.originalTimestamp,
            capturedMediaItems: extracted.capturedMediaItems
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
                await MainActor.run { _ = OfflineQueueManager.shared.softDeleteQueuedScan(scanId: scanId) }
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
                await MainActor.run { _ = OfflineQueueManager.shared.softDeleteQueuedScan(scanId: scanId) }
            }
            return true
        }

        // Success — evict the retry counter so it does not accumulate across long sessions.
        // The entry is only written on transient failures; on a clean first-attempt upload
        // this is a no-op removeValue on a key that was never inserted.
        await MainActor.run { _ = OfflineQueueManager.shared.uploadRetryCount.removeValue(forKey: scanId) }

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
            r2Keys: scan.stagedR2Keys ?? [],
            container: container,
            originalTimestamp: scan.timestamp,
            capturedMediaItems: scan.serializedCapturedMediaItems
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
        defer {
            inferencePreparationScanIds.remove(scanId)
        }
        MerianLog.data.debug(
            "dispatchInferenceDownloadTask: requested scanId=\(scanId, privacy: .public) r2Keys=\(extracted.r2Keys.count, privacy: .public)"
        )

        let existingInferenceTasks = await backgroundSession.allTasks
        if existingInferenceTasks.contains(where: { isLiveInferenceTask($0, scanId: scanId) }) {
            MerianLog.data.debug("dispatchInferenceDownloadTask: inference task already active for \(scanId, privacy: .private); skipping duplicate dispatch")
            return
        }

        let request: URLRequest
        do {
            request = try await prepareInferenceDownloadRequestWithTimeout(
                scanId: scanId,
                extracted: extracted
            )
        } catch InferencePreparationFailure.timedOut {
            MerianLog.data.error(
                "dispatchInferenceDownloadTask: preparation timed out scanId=\(scanId, privacy: .public)"
            )
            await handleInferenceRetry(scanId: scanId, reason: "pre-dispatch timeout")
            return
        } catch is CancellationError {
            MerianLog.data.error(
                "dispatchInferenceDownloadTask: preparation cancelled scanId=\(scanId, privacy: .public)"
            )
            await handleInferenceRetry(scanId: scanId, reason: "pre-dispatch cancelled")
            return
        } catch {
            MerianLog.data.error("dispatchInferenceDownloadTask: failed to build request for \(scanId, privacy: .private): \(error, privacy: .private)")
            await handleInferenceRetry(scanId: scanId, reason: "request build failed")
            return
        }

        // Dispatch the background download task. The OS serializes the URLRequest (including
        // httpBody) at resume() time — safe to use inline httpBody on background sessions.
        let tasksBeforeDispatch = await backgroundSession.allTasks
        if tasksBeforeDispatch.contains(where: { isLiveInferenceTask($0, scanId: scanId) }) {
            MerianLog.data.debug("dispatchInferenceDownloadTask: inference task appeared for \(scanId, privacy: .private); skipping duplicate dispatch")
            return
        }

        let task = backgroundSession.downloadTask(with: request)
        task.taskDescription = "inference_\(scanId)"
        await MainActor.run { SyncStateManager.shared.beginInferencing() }
        inferenceDispatchDates[scanId] = Date()
        task.resume()
        scheduleInferenceStatusProbe(scanId: scanId)

        MerianLog.data.debug("🚀 BACKGROUND INFERENCE: Dispatched download task for \(scanId, privacy: .public)")
    }

    private func prepareInferenceDownloadRequestWithTimeout(
        scanId: String,
        extracted: ExtractedScanData
    ) async throws -> URLRequest {
        let preparationTask = Task { @MainActor in
            try await self.buildInferenceDownloadRequest(scanId: scanId, extracted: extracted)
        }

        defer {
            preparationTask.cancel()
        }

        return try await withThrowingTaskGroup(of: URLRequest.self) { group in
            group.addTask {
                try await preparationTask.value
            }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                preparationTask.cancel()
                throw InferencePreparationFailure.timedOut
            }

            guard let request = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return request
        }
    }

    private func buildInferenceDownloadRequest(
        scanId: String,
        extracted: ExtractedScanData
    ) async throws -> URLRequest {
        let baseTelemetry = extracted.telemetry

        // Background replay must never make the scan library wait on WeatherKit or geocoding.
        // The queued scan already has the R2 media keys needed for identification; optional
        // weather can be absent without blocking inference request construction.
        let hasWeatherBackfillCandidate = baseTelemetry.weatherCondition == nil
            && baseTelemetry.gpsLatitude != nil
            && baseTelemetry.gpsLongitude != nil
        let shouldFetchWeatherBackfill = false

        var finalTelemetry = baseTelemetry
        if hasWeatherBackfillCandidate && !shouldFetchWeatherBackfill {
            MerianLog.data.debug(
                "dispatchInferenceDownloadTask: skipping weather backfill during background replay scanId=\(scanId, privacy: .public)"
            )
        }
        if shouldFetchWeatherBackfill && hasWeatherBackfillCandidate {
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

            let hasBackfill = ctx.weatherCondition != nil
                || ctx.weatherTemperature != nil
                || ctx.locationName != nil
            if hasBackfill {
                let container = extracted.container
                Task {
                    let dbActor = BackgroundDatabaseActor(modelContainer: container)
                    await dbActor.updateScanTelemetry(
                        scanId: scanId,
                        weatherCondition: ctx.weatherCondition,
                        weatherTemperatureF: ctx.weatherTemperature,
                        locationName: ctx.locationName
                    )
                }
            } else {
                MerianLog.data.debug(
                    "dispatchInferenceDownloadTask: skipping empty weather backfill scanId=\(scanId, privacy: .public)"
                )
            }
        }

        MerianLog.data.debug(
            "dispatchInferenceDownloadTask: building request scanId=\(scanId, privacy: .public)"
        )

        // All scans natively route through the unified /identify-multimodal endpoint,
        // securely supporting arrays over legacy properties.
        let audioPaths = extracted.audioFilePaths ?? []
        let videoPaths = extracted.videoFilePaths ?? []
        let stagedKeys = MediaStagingContract.splitObjectKeys(
            extracted.r2Keys,
            scanId: scanId,
            localImagePaths: extracted.localImagePaths,
            localAudioPaths: audioPaths,
            localVideoPaths: videoPaths
        )
        let request = try await MerianNetworkClient.shared.buildMultiModalRequest(
            r2ObjectKeys: stagedKeys.imageR2ObjectKeys,
            audioR2ObjectKeys: stagedKeys.audioR2ObjectKeys,
            videoR2ObjectKeys: stagedKeys.videoR2ObjectKeys,
            base64ImageDatas: [], // Uploads rely purely on references through R2 object keys.
            audioFilePaths: stagedKeys.audioR2ObjectKeys.isEmpty ? audioPaths : [],
            observationContextsJSON: extracted.observationContextsJSON ?? [],
            telemetry: finalTelemetry,
            clientScanId: scanId
        )
        MerianLog.data.debug(
            "dispatchInferenceDownloadTask: built request scanId=\(scanId, privacy: .public) imageKeys=\(stagedKeys.imageR2ObjectKeys.count, privacy: .public) audioKeys=\(stagedKeys.audioR2ObjectKeys.count, privacy: .public) videoKeys=\(stagedKeys.videoR2ObjectKeys.count, privacy: .public)"
        )
        return request
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
        _ = inferenceCompletionScanIds.insert(scanId)
        defer {
            _ = inferenceCompletionScanIds.remove(scanId)
            MerianLog.data.debug(
                "processInferenceDownloadResult: cleared inference completion lock scanId=\(scanId, privacy: .public)"
            )
        }
        cancelInferenceStatusProbe(scanId: scanId)
        MerianLog.data.debug(
            "processInferenceDownloadResult: scanId=\(scanId, privacy: .public) status=\(statusCode ?? -1, privacy: .public) file=\(resultFileURL.path, privacy: .public)"
        )

        guard let statusCode, statusCode == 200 else {
            let code = statusCode ?? 0
            if (400...499).contains(code) {
                MerianLog.data.debug("Inference failed permanently for \(scanId, privacy: .private) [\(code)] — tombstoning scan")
                await MainActor.run { _ = OfflineQueueManager.shared.softDeleteQueuedScan(scanId: scanId) }
            } else {
                MerianLog.data.debug("Inference download non-200 [\(code)] for \(scanId, privacy: .private) — retry")
                await handleInferenceRetry(scanId: scanId)
            }
            return
        }

        guard let resultData = try? Data(contentsOf: resultFileURL), !resultData.isEmpty else {
            MerianLog.data.error("Background inference download: result file unreadable for \(scanId, privacy: .private)")
            await handleInferenceRetry(scanId: scanId, reason: "empty response file")
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
            telemetry: extracted.telemetry,
            observationContextsJSON: extracted.observationContextsJSON,
            audioFilePaths: extracted.audioFilePaths,
            capturedMediaJSON: extracted.capturedMediaJSON
        )

        // Delete the OfflineQueuedScan from the main ModelContext so @Query re-evaluates in
        // any open sheet. The background actor intentionally left it alive (see wasCleaned doc);
        // this deletion guarantees the main context has a real pending change when it saves —
        // the only reliable @Query trigger in a presented sheet (SwiftData platform limitation).
        let didFlushQueuedScan: Bool
        if processingResult.wasCleaned {
            didFlushQueuedScan = await MainActor.run {
                OfflineQueueManager.shared.flushOfflineQueuedScan(scanId: scanId)
            }
        } else {
            didFlushQueuedScan = false
        }

        if didFlushQueuedScan,
           let speciesName = processingResult.resolvedSpeciesName,
           let dbScanId = processingResult.finalScanId {
            MerianLog.data.debug(
                "processInferenceDownloadResult: finalized scanId=\(scanId, privacy: .public) dbScanId=\(dbScanId, privacy: .public) species=\(speciesName, privacy: .public)"
            )
            let capturedContainer = extracted.container
            await MainActor.run {
                // Only set the badge when the insight sheet is not already open.
                // If suppressInferenceBanners is true the user is viewing results in the
                // sheet — the badge would appear and immediately need clearing on dismiss.
                if !AppSettings.shared.suppressInferenceBanners {
                    AppSettings.shared.hasUnseenScan = true
                    AppIconBadgeCoordinator.updateAppIconBadge()
                }
                if processingResult.isNewDiscovery {
                    GamificationManager.shared.recordNewSpeciesDiscovered()
                }
                if AppSettings.shared.isPushNotificationsEnabled {
                    PushNotificationManager.shared.sendInferenceCompleteNotification(speciesName: speciesName, scanId: dbScanId)
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

        if !didFlushQueuedScan {
            MerianLog.data.debug(
                "processInferenceDownloadResult: did not flush queued scanId=\(scanId, privacy: .public) wasCleaned=\(processingResult.wasCleaned, privacy: .public)"
            )
        }
        MerianLog.data.debug("⏱️ Background pipeline total: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - pipelineStart), privacy: .public)s")
        await MainActor.run {
            // updateUnsyncedItemCount() is already called by flushOfflineQueuedScan above;
            // only call it here when flush was skipped or failed.
            if !didFlushQueuedScan {
                OfflineQueueManager.shared.updateUnsyncedItemCount()
            }
            CircuitBreakerManager.shared.recordSuccess()
            _ = OfflineQueueManager.shared.uploadRetryCount.removeValue(forKey: scanId)
            SyncStateManager.shared.completeSync()
        }
    }

    // MARK: - Inference Failure Handling

    private func scheduleInferenceStatusProbe(scanId: String) {
        inferenceStatusProbeTasks[scanId]?.cancel()
        inferenceStatusProbeTasks[scanId] = Task { [weak self] in
            // Cumulative ~105s: longer than the 90s inference request timeout, so the
            // watchdog only fires when URLSession did not deliver either success or failure.
            let delays: [Duration] = [.seconds(10), .seconds(30), .seconds(65)]
            for delay in delays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let recovered = await self.recoverCompletedInferenceFromServer(
                    scanId: scanId,
                    reason: "delayed probe"
                )
                if recovered { return }
                let activeTaskCount = await self.activeInferenceTaskCount(scanId: scanId)
                MerianLog.data.debug(
                    "scheduleInferenceStatusProbe: scan still pending scanId=\(scanId, privacy: .public) activeTasks=\(activeTaskCount, privacy: .public)"
                )
            }

            await MainActor.run {
                guard let self else { return }
                let elapsed = self.inferenceDispatchDates[scanId]
                    .map { Date().timeIntervalSince($0) } ?? -1
                self.inferenceStatusProbeTasks[scanId] = nil
                self.inferenceDispatchDates[scanId] = nil
                MerianLog.data.debug(
                    "scheduleInferenceStatusProbe: watchdog firing scanId=\(scanId, privacy: .public) elapsed=\(String(format: "%.1f", elapsed), privacy: .public)s"
                )
            }

            guard let self else { return }
            let cancelledCount = await self.cancelActiveInferenceTasks(scanId: scanId)
            MerianLog.data.debug(
                "scheduleInferenceStatusProbe: cancelled hung inference tasks scanId=\(scanId, privacy: .public) count=\(cancelledCount, privacy: .public)"
            )
            await self.handleInferenceRetry(scanId: scanId, reason: "watchdog")
        }
        MerianLog.data.debug("scheduleInferenceStatusProbe: scheduled scanId=\(scanId, privacy: .public)")
    }

    private func cancelInferenceStatusProbe(scanId: String) {
        inferenceStatusProbeTasks[scanId]?.cancel()
        inferenceStatusProbeTasks[scanId] = nil
        inferenceDispatchDates[scanId] = nil
        MerianLog.data.debug("cancelInferenceStatusProbe: cancelled scanId=\(scanId, privacy: .public)")
    }

    private func isLiveInferenceTask(_ task: URLSessionTask, scanId: String) -> Bool {
        task.taskDescription == "inference_\(scanId)"
            && task.state != .canceling
            && task.state != .completed
    }

    private func cancelActiveInferenceTasks(scanId: String) async -> Int {
        let tasks = await backgroundSession.allTasks
        let matchingTasks = tasks.filter {
            $0.taskDescription == "inference_\(scanId)" && $0.state != .completed
        }
        for task in matchingTasks {
            task.cancel()
        }
        return matchingTasks.count
    }

    private func activeInferenceTaskCount(scanId: String) async -> Int {
        let tasks = await backgroundSession.allTasks
        return tasks.filter { isLiveInferenceTask($0, scanId: scanId) }.count
    }

    private func recoverCompletedInferenceFromServer(scanId: String, reason: String) async -> Bool {
        let status: String
        do {
            status = try await MerianNetworkClient.shared.checkScanStatus(scanId: scanId)
        } catch {
            MerianLog.data.debug(
                "recoverCompletedInferenceFromServer: status check failed scanId=\(scanId, privacy: .public) reason=\(reason, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return false
        }

        MerianLog.data.debug(
            "recoverCompletedInferenceFromServer: scanId=\(scanId, privacy: .public) reason=\(reason, privacy: .public) status=\(status, privacy: .public)"
        )
        guard status == "found" else { return false }

        cancelInferenceStatusProbe(scanId: scanId)
        uploadRetryCount.removeValue(forKey: scanId)
        let didSyncTarget: Bool
        if let context = modelContext {
            didSyncTarget = await AppDIContainer.shared.scanRepository.syncHistoricalScanDown(
                scanId: scanId,
                modelContext: context
            )
        } else {
            didSyncTarget = false
        }

        let didPromoteLocalRecord = promoteRecoveredLocalScan(scanId: scanId)
        guard didPromoteLocalRecord else {
            MerianLog.data.debug(
                "recoverCompletedInferenceFromServer: server found scan but no local record after sync scanId=\(scanId, privacy: .public) targetedSync=\(didSyncTarget, privacy: .public)"
            )
            if !didSyncTarget, let context = modelContext {
                await AppDIContainer.shared.scanRepository.syncHistoricalScansDown(modelContext: context)
                ScanLibraryEvents.postLibraryDidUpdate()
            }
            return false
        }

        let didDeleteQueue = await deleteQueuedScan(scanId: scanId)
        updateUnsyncedItemCount()
        ScanLibraryEvents.postLibraryDidUpdate()
        MerianLog.data.debug(
            "recoverCompletedInferenceFromServer: recovered scanId=\(scanId, privacy: .public) targetedSync=\(didSyncTarget, privacy: .public) promotedLocal=\(didPromoteLocalRecord, privacy: .public) deletedQueue=\(didDeleteQueue, privacy: .public)"
        )

        SyncStateManager.shared.completeSync()
        return true
    }

    private func promoteRecoveredLocalScan(scanId: String) -> Bool {
        guard let context = modelContext else { return false }
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let record: LocalScanRecord?
        do {
            record = try context.fetch(descriptor).first
        } catch {
            MerianLog.data.debug(
                "promoteRecoveredLocalScan: fetch failed scanId=\(scanId, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return false
        }

        guard let record else { return false }
        if record.captureDate == nil {
            record.captureDate = record.timestamp
        }
        record.timestamp = Date()
        do {
            try context.save()
            MerianLog.data.debug("promoteRecoveredLocalScan: promoted scanId=\(scanId, privacy: .public)")
            return true
        } catch {
            context.rollback()
            MerianLog.data.error(
                "promoteRecoveredLocalScan: save failed scanId=\(scanId, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    /// Handles a background inference download task network-level failure.
    ///
    /// Called from `urlSession(_:task:didCompleteWithError:)` when the download task fails
    /// with a transport error (the server never responded). Resets the scan to `.staged` below
    /// the retry threshold, or tombstones it once `maxUploadRetries` is exhausted.
    ///
    /// Code=-999 (NSURLErrorCancelled) is special-cased: it means an owner path explicitly
    /// cancelled the task. Either the parallel live inference path already succeeded, the user
    /// deleted the queued scan, or the inference watchdog reset the scan to `.staged`.
    func handleInferenceTaskNetworkFailure(scanId: String, error: Error) async {
        cancelInferenceStatusProbe(scanId: scanId)
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            MerianLog.data.debug("Background inference cancelled for \(scanId, privacy: .private) — owner path handled retry or cleanup")
            return
        }
        MerianLog.data.debug("Background inference download failed for \(scanId, privacy: .private): \(error, privacy: .private)")
        await handleInferenceRetry(scanId: scanId, reason: "network failure")
    }

    /// Increments the retry counter for a scan and either resets it to `.staged` for the
    /// next sync cycle or tombstones it once `maxUploadRetries` is exhausted.
    ///
    /// Before retrying, polls `/check-scan-status` to detect the outbox gap: if the edge
    /// function already persisted the scan but the background download task never delivered
    /// the response, a naive retry would re-run inference and insert a duplicate row. When
    /// the scan is found server-side, the queue entry is tombstoned and historical sync
    /// recovers the `LocalScanRecord` on the next active-phase foreground transition.
    private func handleInferenceRetry(scanId: String, reason: String = "retry") async {
        guard let container = modelContext?.container else { return }

        if await recoverCompletedInferenceFromServer(scanId: scanId, reason: reason) {
            return
        }

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
            MerianLog.data.debug("Inference failed for \(scanId, privacy: .private) — reset to .staged for retry (\(retries)/\(OfflineQueueManager.maxUploadRetries)) reason=\(reason, privacy: .public)")
            updateUnsyncedItemCount()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.replayInferenceForUploadedScans()
            }
        }
    }
}
