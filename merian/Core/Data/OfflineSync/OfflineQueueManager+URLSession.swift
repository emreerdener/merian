import Foundation
import SwiftData
import CoreLocation
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
                    uploadError: error
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
        uploadError: Error?
    ) async {
        guard let taskDesc = taskDescription else { return }

        let components = taskDesc.components(separatedBy: "_")
        let scanId = components[0]
        let indexPart = components.count > 1 ? components[1] : ""

        // Clean up the temp staging file regardless of upload outcome.
        let tempFileName = indexPart.isEmpty
            ? "\(scanId)_temp_upload.jpg"
            : "\(scanId)_\(indexPart)_temp_upload.jpg"
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

        // Clear any prior transient-error retry count now that this upload succeeded.
        await MainActor.run { _ = OfflineQueueManager.shared.uploadRetryCount.removeValue(forKey: scanId) }

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

        // Only trigger inference after the last image file for this scan is confirmed uploaded.
        guard indexPart == "\(extracted.localImagePaths.count - 1)" else { return }

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
    private func runInferencePipeline(scanId: String, extracted: ExtractedScanData) async {
        var finalTelemetry = extracted.telemetry

        // Backfill historical weather for scans captured offline without a connection.
        if finalTelemetry.weatherCondition == nil,
           let lat = finalTelemetry.gpsLatitude,
           let lon = finalTelemetry.gpsLongitude {
            let pastLocation = CLLocation(latitude: lat, longitude: lon)
            let historicalContext = await EnvironmentContextManager.shared.fetchHistoricalContext(
                location: pastLocation,
                date: extracted.originalTimestamp
            )
            finalTelemetry = CaptureTelemetry(
                subjectDistanceInMeters: finalTelemetry.subjectDistanceInMeters,
                gpsLatitude: finalTelemetry.gpsLatitude,
                gpsLongitude: finalTelemetry.gpsLongitude,
                gpsElevation: finalTelemetry.gpsElevation,
                locationName: finalTelemetry.locationName ?? historicalContext.locationName,
                weatherCondition: historicalContext.weatherCondition,
                weatherTemperatureF: historicalContext.weatherTemperature,
                timeOfDay: finalTelemetry.timeOfDay,
                timestamp: finalTelemetry.timestamp
            )
            MerianLog.data.debug("Hydrated offline scan with historical weather: \(historicalContext.weatherCondition ?? "none", privacy: .public)")
        }

        do {
            let pipelineStart = CFAbsoluteTimeGetCurrent()
            let userId = await MainActor.run { SupabaseManager.shared.currentUser?.id.uuidString ?? DeviceIdentityManager.shared.deviceId }
            let resolvedKeys = extracted.localImagePaths.map { "staging/\(userId)/\(scanId)_\($0)" }

            await MainActor.run { SyncStateManager.shared.beginInferencing() }
            let resultData = try await MerianNetworkClient.shared.analyzeSubject(
                r2ObjectKeys: resolvedKeys,
                base64ImageDatas: nil,
                telemetry: finalTelemetry
            )
            MerianLog.data.debug("⏱️ Inference: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - pipelineStart), privacy: .public)s")

            await MainActor.run { SyncStateManager.shared.beginFinalizing() }
            let dbActor = BackgroundDatabaseActor(modelContainer: extracted.container)
            let resultTuple = await dbActor.processAndCleanupOfflineScan(
                resultData: resultData,
                originalImagePaths: extracted.localImagePaths,
                scanId: scanId,
                originalTimestamp: extracted.originalTimestamp,
                telemetry: finalTelemetry
            )

            if let speciesName = resultTuple.resolvedSpeciesName {
                let profileActor = ProfileDatabaseActor(modelContainer: extracted.container)
                let updatedAwards = await profileActor.calculateAwards()
                await MainActor.run {
                    if resultTuple.isNewDiscovery {
                        GamificationManager.shared.recordNewSpeciesDiscovered()
                    }
                    GamificationManager.shared.evaluateAchievementsForNotifications(awards: updatedAwards)
                    if UserDefaults.standard.bool(forKey: UserDefaultsKeys.isPushNotificationsEnabled) {
                        #if canImport(UIKit)
                        if UIApplication.shared.applicationState != .active {
                            PushNotificationManager.shared.sendInferenceCompleteNotification(speciesName: speciesName, scanId: scanId)
                        }
                        #endif
                    }
                }
            }

            MerianLog.data.debug("⏱️ Pipeline total: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - pipelineStart), privacy: .public)s")
            await MainActor.run {
                OfflineQueueManager.shared.updateUnsyncedItemCount()
                CircuitBreakerManager.shared.recordSuccess()
            }
        } catch {
            MerianLog.data.debug("Inference failed for \(scanId, privacy: .private): \(error, privacy: .private)")
        }
    }
}
