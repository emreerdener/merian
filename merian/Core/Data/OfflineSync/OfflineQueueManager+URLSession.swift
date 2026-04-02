import CoreLocation
import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - URLSession Delegate

extension OfflineQueueManager: URLSessionTaskDelegate {

    /// Fires when the background URLSession completes transmission of a file to R2 staging.
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Capture non-Sendable properties before crossing isolation boundaries.
        let taskDescription = task.taskDescription
        let originalRequestUrlPath = task.originalRequest?.url?.path
        let responseStatusCode = (task.response as? HTTPURLResponse)?.statusCode
        let taskIdentifier = task.taskIdentifier // Capture ID natively before passing to background

        BackgroundTaskWrapper.execute(
            name: "OfflineInference",
            expirationHandler: { MerianLog.data.debug("OfflineInference background task expired") }
        ) { _ in
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
            let remaining = await session.allTasks
            if remaining.isEmpty {
                await MainActor.run {
                    OfflineQueueManager.shared.isSyncing = false
                    if OfflineQueueManager.shared.unsyncedItemsCount > 0 {
                        OfflineQueueManager.shared.syncPendingScans()
                    } else {
                        SyncStateManager.shared.completeSync()
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
        let indexPart = components.count > 1 ? components[1] : ""

        // Clean up the temp staging file regardless of upload outcome.
        let tempFileName = indexPart.isEmpty
            ? "\(scanId)_temp_upload.webp"
            : "\(scanId)_\(indexPart)_temp_upload.webp"
        try? FileManager.default.removeItem(at: URL.cachesDirectory.appendingPathComponent(tempFileName))

        // Handle transport-level errors.
        if let uploadError {
            let nsError = uploadError as NSError

            // File-missing errors are terminal — the source data is unrecoverable.
            let isFileMissing = nsError.domain == NSURLErrorDomain
                && (nsError.code == NSURLErrorFileDoesNotExist || nsError.code == NSURLErrorCannotOpenFile)
            if isFileMissing {
                MerianLog.data.debug("Terminal file corruption — tombstoning \(scanId, privacy: .private)")
                await MainActor.run { OfflineQueueManager.shared.softDeleteQueuedScan(scanId: scanId) }
                return
            }

            // Transient connectivity errors (timeout, handoff, no signal) are retriable.
            // Track attempts in-memory and only tombstone after maxUploadRetries failures
            // so a brief WiFi handoff doesn't permanently discard a scan.
            let transientCodes: Set<Int> = [
                NSURLErrorTimedOut,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorDataNotAllowed,
                NSURLErrorInternationalRoamingOff
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
            return
        }

        // Handle HTTP-level errors.
        guard let statusCode = responseStatusCode, statusCode == 200 else {
            let code = responseStatusCode ?? 0
            // 403/401 are auth failures — permanent, not worth retrying.
            // 429 and 5xx are server/rate-limit errors that may resolve on the next sync cycle.
            let recoverableCodes: Set<Int> = [429, 500, 502, 503, 504]
            if recoverableCodes.contains(code) {
                MerianLog.data.debug("Background upload recoverable (\(code, privacy: .public)) — retaining in queue")
            } else {
                MerianLog.data.debug("Background upload rejected (\(code, privacy: .public)) — tombstoning scan")
                await MainActor.run { OfflineQueueManager.shared.softDeleteQueuedScan(scanId: scanId) }
            }
            return
        }

        // Only trigger inference for files that landed in the staging bucket.
        guard let urlPath = originalRequestUrlPath, urlPath.contains("staging/") else { return }

        // Fetch scan metadata on the main actor before handing off to background inference.
        let extracted = await MainActor.run { () -> ExtractedScanData? in
            guard let context = OfflineQueueManager.shared.modelContext else { return nil }
            let container = context.container
            let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
            let scan: OfflineQueuedScan?
            do {
                scan = try context.fetch(descriptor).first
            } catch {
                MerianLog.data.debug("urlSession: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)")
                return nil
            }
            guard let scan else { return nil }

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
                container: container,
                originalTimestamp: scan.timestamp
            )
        }
        guard let extracted else { return }

        // Look ahead and ensure no other upload tasks for this specific scan ID are still in flight.
        // Background URLSession doesn't guarantee sequential delivery, so `indexPart == count - 1`
        // is susceptible to race conditions.
        let remainingTasks = await session.allTasks
        let hasActiveTasksForScan = remainingTasks.contains {
            $0.taskIdentifier != taskIdentifier &&
            ($0.taskDescription?.starts(with: "\(scanId)_") ?? false)
        }
        guard !hasActiveTasksForScan else { return }

        // Remove from the local active-IDs set only when ALL image uploads for the scan are fully settled.
        // Doing this prematurely allows `syncPendingScans` to re-trigger parallel uploads of missing chunks.
        _ = await MainActor.run { OfflineQueueManager.shared.activeScanUploadIds.remove(scanId) }

        // Persist the isUploaded flag before inference so a mid-inference crash or app kill
        // doesn't force re-uploading already-staged files. replayInferenceForUploadedScans()
        // detects these records on the next connectivity restore and resumes from here.
        await MainActor.run {
            guard let context = OfflineQueueManager.shared.modelContext else { return }
            let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
            if let scan = try? context.fetch(descriptor).first, !scan.isUploaded {
                scan.isUploaded = true
                try? context.save()
            }
        }

        await runInferencePipeline(scanId: scanId, extracted: extracted)
    }

    // MARK: - Inference Pipeline

    /// Runs the full post-upload inference pipeline for a scan.
    ///
    /// 1. Backfills historical weather via `EnvironmentContextManager` if the scan was captured offline.
    /// 2. Calls the `analyzeSubject` Edge function with the R2 staging object keys.
    /// 3. Persists the `LocalScanRecord` and removes the `OfflineQueuedScan` via `BackgroundDatabaseActor`.
    /// 4. If a new species was discovered, recalculates awards and sends a push notification
    ///    if the app is backgrounded and the user has enabled push notifications.
    func runInferencePipeline(scanId: String, extracted: ExtractedScanData) async {
        let baseTelemetry = extracted.telemetry

        do {
            let pipelineStart = CFAbsoluteTimeGetCurrent()
            // The R2 object key must match the key the Edge Function stored on upload, which
            // deterministically aligns with the auth session active during pipeline execution.
            let authUserId = try? await SupabaseManager.shared.client.auth.session.user.id.uuidString
            let deviceId = await MainActor.run { DeviceIdentityManager.shared.deviceId }
            let userId = (authUserId ?? deviceId).lowercased()
            let resolvedKeys = extracted.localImagePaths.map { "staging/\(userId)/\(scanId)_\($0)" }

            // Run WeatherKit backfill and AI inference concurrently — weather is optional
            // metadata and must not gate the scan result. Sequential awaiting previously added
            // 200–800 ms of WeatherKit latency before the Gemini call even began.
            let needsWeather = baseTelemetry.weatherCondition == nil
                && baseTelemetry.gpsLatitude != nil
                && baseTelemetry.gpsLongitude != nil

            await MainActor.run { SyncStateManager.shared.beginInferencing() }

            async let weatherContext = needsWeather
                ? EnvironmentContextManager.shared.fetchHistoricalContext(
                    location: CLLocation(latitude: baseTelemetry.gpsLatitude!, longitude: baseTelemetry.gpsLongitude!),
                    date: extracted.originalTimestamp)
                : nil

            async let inferenceResult = MerianNetworkClient.shared.analyzeSubject(
                r2ObjectKeys: resolvedKeys,
                base64ImageDatas: nil,
                telemetry: baseTelemetry
            )

            let (historicalContext, resultData) = try await (weatherContext, inferenceResult)

            // Merge weather into telemetry only if backfill succeeded.
            let finalTelemetry: CaptureTelemetry
            if let ctx = historicalContext {
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
            } else {
                finalTelemetry = baseTelemetry
            }

            MerianLog.data.debug("⏱️ Inference: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - pipelineStart), privacy: .public)s")

            await MainActor.run { SyncStateManager.shared.beginFinalizing() }
            // Reuse the long-lived actor instead of allocating a fresh one per completion.
            // The actor serializes concurrent completions automatically via its executor,
            // so rapid-burst scenarios queue safely without racing.
            // runInferencePipeline is @MainActor-isolated, so resolvedInferenceDbActor can
            // be called directly — no MainActor.run hop needed.
            let dbActor = resolvedInferenceDbActor(container: extracted.container)
            let processingResult = await dbActor.processAndCleanupOfflineScan(
                resultData: resultData,
                originalImagePaths: extracted.localImagePaths,
                scanId: scanId,
                originalTimestamp: extracted.originalTimestamp,
                telemetry: finalTelemetry
            )

            if let speciesName = processingResult.resolvedSpeciesName, let dbScanId = processingResult.finalScanId {
                let capturedContainer = extracted.container
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasUnseenScan)
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
                    // Debounce award recalculation so a 5-scan burst fires one calculateAwards()
                    // pass instead of five. Per-completion side-effects (notification, discovery
                    // tracking) fire immediately above; only the heavier DB read is coalesced.
                    awardsDebounceTask?.cancel()
                    awardsDebounceTask = Task { [weak self] in
                        guard let self else { return }
                        try? await Task.sleep(for: .seconds(0.5))
                        guard !Task.isCancelled else { return }
                        // Task inherits @MainActor isolation (created inside MainActor.run),
                        // so resolvedProfileDbActor and evaluateAchievementsForNotifications
                        // can be called directly — no MainActor.run hops needed.
                        let profileActor = self.resolvedProfileDbActor(container: capturedContainer)
                        let updatedAwards = await profileActor.calculateAwards()
                        GamificationManager.shared.evaluateAchievementsForNotifications(awards: updatedAwards)
                    }
                }
            }

            MerianLog.data.debug("⏱️ Pipeline total: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - pipelineStart), privacy: .public)s")
            await MainActor.run {
                OfflineQueueManager.shared.updateUnsyncedItemCount()
                CircuitBreakerManager.shared.recordSuccess()
                _ = OfflineQueueManager.shared.uploadRetryCount.removeValue(forKey: scanId)
            }
        } catch let MerianError.httpError(code, message) where (400...499).contains(code) {
            MerianLog.data.debug("Inference failed permanently for \(scanId, privacy: .private) [\(code)]: \(message, privacy: .private) — tombstoning scan")
            await MainActor.run { OfflineQueueManager.shared.softDeleteQueuedScan(scanId: scanId) }
        } catch {
            let retries = await MainActor.run { () -> Int in
                let next = (OfflineQueueManager.shared.uploadRetryCount[scanId] ?? 0) + 1
                OfflineQueueManager.shared.uploadRetryCount[scanId] = next
                return next
            }
            if retries >= OfflineQueueManager.maxUploadRetries {
                MerianLog.data.debug("Inference retry limit reached for \(scanId, privacy: .private) — tombstoning scan")
                await MainActor.run {
                    OfflineQueueManager.shared.uploadRetryCount.removeValue(forKey: scanId)
                    OfflineQueueManager.shared.softDeleteQueuedScan(scanId: scanId)
                }
            } else {
                MerianLog.data.debug("Inference failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            }
        }
    }
}
