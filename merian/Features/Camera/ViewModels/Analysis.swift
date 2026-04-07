import SwiftData
import SwiftUI
import Vision

extension CameraViewModel {

    // MARK: - Submit Active Scan

    /// Kicks off the inference pipeline for the accumulated `activeScanImages`.
    ///
    /// Call order:
    /// 1. Reset `InferenceEngine` display state and open the insight sheet immediately.
    /// 2. Snapshot the staging buffers, then clear them to prevent double-submit.
    /// 3. Generate a stable `scanId` shared by the queue record and live inference task.
    /// 4. **Enqueue immediately** (still in foreground) with cached GPS. The background
    ///    URLSession upload is dispatched inside the same `UIBackgroundTask` window, so it
    ///    survives an immediate app suspension. No rescue logic is needed.
    /// 5. Await the pre-fetched `EnvironmentContext`, build full telemetry, and fire
    ///    `InferenceEngine.analyze`. The live path and background upload race — whichever
    ///    completes first wins. On live success, `analyze` cancels the upload; on failure
    ///    or cancellation the background path continues uninterrupted.
    func submitActiveScan(modelContext: ModelContext) {
        guard !activeScannedDatas.isEmpty else { return }

        // 1. Reset all InferenceEngine display state synchronously so the content router
        // immediately sees `isProcessing == true && speciesData == nil`.
        diContainer.inferenceEngine.prepareForNewScan()

        // 2. Eagerly set the Insight sheet to open in its "Analyzing" skeleton state.
        activeSheet = .insight

        // 3. Capture the context needed for inference before clearing the staging buffers.
        let datasToAnalyze = activeScannedDatas
        let displayDatasToAnalyze = activeDisplayDatas
        let capturedOriginals = activeOriginals
        let capturedPreFetchTask = preFetchTask

        // 4. Clear the staging buffers immediately so the UI resets behind the overlay.
        activeScanImages.removeAll()
        activeScannedDatas.removeAll()
        activeDisplayDatas.removeAll()
        activeOriginals.removeAll()
        preFetchTask = nil

        // 5. Generate a stable scanId shared by the queue record and live inference.
        //    This ties the two paths so that whichever completes first, the other can
        //    be idempotently skipped or cancelled.
        let scanId = UUID().uuidString.lowercased()
        pendingAnalyzeScanId = scanId

        // 6. Enqueue immediately — in-foreground — so the scan reaches disk and SwiftData
        //    before any async boundary is crossed. `enqueueCapture` wraps its work in a
        //    UIBackgroundTask, ensuring the disk write + SwiftData insert + URLSession upload
        //    dispatch complete even if the user backgrounds in the next instant.
        //
        //    Use the already-cached GPS location (live location tracking is running while
        //    the camera is active). `lastKnownLocation` prefers an accurate lock (≤30m) but
        //    falls back to any inaccurate fix so scans in poor GPS conditions still carry a
        //    macro-region coordinate — enough for WeatherKit backfill in `runInferencePipeline`.
        //    Weather and locationName are backfilled by `fetchHistoricalContext` on the offline
        //    path. For gallery photos the preFetchTask resolves the full context, but the queue
        //    record's GPS is sufficient for the background path to succeed independently.
        let cachedLocation = diContainer.environmentContextManager.lastKnownLocation
        let immediateDistance = diContainer.cameraManager.subjectDistanceInMeters
        let immediateTelemetry = CaptureTelemetry(
            subjectDistanceInMeters: immediateDistance,
            gpsLatitude: cachedLocation?.coordinate.latitude,
            gpsLongitude: cachedLocation?.coordinate.longitude,
            gpsElevation: cachedLocation?.altitude,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            timeOfDay: nil,
            timestamp: DateUtilities.iso8601Formatter.string(from: Date()),
            zoomFactor: nil,
            estimatedSizeCm: nil
        )
        diContainer.offlineQueueManager.enqueueCapture(
            imageDatas: datasToAnalyze,
            telemetry: immediateTelemetry,
            blurScore: nil,
            scanId: scanId
        )

        // 7. Concurrently resolve the full telemetry and fire live inference.
        Task {
            let resolvedContext = await capturedPreFetchTask?.value
            
            let telemetry = await CaptureTelemetry.resolveForActiveScan(
                resolvedContext: resolvedContext,
                historicalContext: capturedOriginals.first?.environmentContext,
                isGalleryPhoto: capturedOriginals.first?.isFromGallery == true,
                firstImageData: datasToAnalyze.first,
                distanceMeters: diContainer.cameraManager.subjectDistanceInMeters,
                zoomFactor: diContainer.cameraManager.zoomFactor
            )

            // Guard: skip if a newer scan has been submitted while the preFetchTask was
            // awaiting. `pendingAnalyzeScanId` is set to this scan's ID at submission time
            // and overwritten by the next `submitActiveScan` call, so an inequality here
            // means this Task is stale and the engine has already moved on.
            // The offline queue already holds this scan — the background path will complete it.
            await MainActor.run {
                guard self.pendingAnalyzeScanId == scanId else { return }
                self.diContainer.inferenceEngine.analyze(
                    scanId: scanId,
                    imageDatas: datasToAnalyze,
                    displayDatas: displayDatasToAnalyze,
                    telemetry: telemetry,
                    modelContext: modelContext
                )
            }
        }
    }

    // MARK: - Inference Processing Change

    /// Responds to changes in `InferenceEngine.isProcessing`.
    func handleInferenceProcessingChange(isStillProcessing: Bool) {
        guard !isStillProcessing else { return }
        // Mark a new unread scan only for real results (scanId is nil on error placeholders
        // like "Analysis Failed" / "Network Timeout" which are not persisted to the library).
        // Skip if the insight sheet is already open — the user is actively viewing the result
        // and closing the sheet should not trigger the indicator.
        if diContainer.inferenceEngine.speciesData?.scanId != nil, activeSheet != .insight {
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasUnseenScan)
            PushNotificationManager.shared.setBadgeCount(1)
        }
    }
}

// MARK: - CaptureTelemetry Extension

extension CaptureTelemetry {
    static func resolveForActiveScan(
        resolvedContext: EnvironmentContext?,
        historicalContext: EnvironmentContext?,
        isGalleryPhoto: Bool,
        firstImageData: Data?,
        distanceMeters: Float?,
        zoomFactor: CGFloat?
    ) async -> CaptureTelemetry {
        let zoomToUse: CGFloat? = (zoomFactor ?? 0) > 1.0 ? zoomFactor : nil

        if let context = resolvedContext {
            var estimatedSizeCm: Double?
            if let d = distanceMeters, let fd = firstImageData {
                estimatedSizeCm = await SizeEstimator.estimateSize(imageData: fd, distanceMeters: d)
            }
            return CaptureTelemetry(from: context, distance: distanceMeters, zoom: zoomToUse, estimatedSizeCm: estimatedSizeCm)
        } else if let hc = historicalContext {
            // Library photo — zoom at original capture time is unknown; omit.
            return CaptureTelemetry(from: hc, distance: nil)
        } else if isGalleryPhoto {
            // No EXIF available — omit timestamp rather than fabricating the current date.
            // The server defaults scans.timestamp to now(), which honestly represents when
            // the scan was submitted rather than a false original capture time.
            return CaptureTelemetry(
                subjectDistanceInMeters: nil, gpsLatitude: nil, gpsLongitude: nil, gpsElevation: nil,
                locationName: nil, weatherCondition: nil, weatherTemperatureF: nil, timeOfDay: nil,
                timestamp: nil, zoomFactor: nil, estimatedSizeCm: nil
            )
        } else {
            var estimatedSizeCm: Double?
            if let d = distanceMeters, let fd = firstImageData {
                estimatedSizeCm = await SizeEstimator.estimateSize(imageData: fd, distanceMeters: d)
            }
            return CaptureTelemetry(
                subjectDistanceInMeters: distanceMeters, gpsLatitude: nil, gpsLongitude: nil, gpsElevation: nil,
                locationName: nil, weatherCondition: nil, weatherTemperatureF: nil, timeOfDay: nil,
                timestamp: DateUtilities.iso8601Formatter.string(from: Date()), zoomFactor: zoomToUse, estimatedSizeCm: estimatedSizeCm
            )
        }
    }
}
