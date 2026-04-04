import SwiftData
import SwiftUI
import Vision

extension CameraViewModel {

    // MARK: - Submit Active Scan

    /// Kicks off the inference pipeline for the accumulated `activeScanImages`.
    ///
    /// Call order:
    /// 1. Snapshot images into the analysis overlay and show fullscreen scanning UI.
    /// 2. **Immediately enqueue to disk + SwiftData** with GPS from the already-cached
    ///    location, so the scan is durable before any async work begins. This guarantees
    ///    the background URLSession upload is dispatched while the app is still in the
    ///    foreground — no rescue logic needed.
    /// 3. Clear the staging buffers so the user cannot double-submit.
    /// 4. Await the pre-fetched `EnvironmentContext` (started at shutter press) to build
    ///    full telemetry, then fire `InferenceEngine.analyze`. The live inference path and
    ///    the background upload race: whichever completes first wins. On live success,
    ///    `analyze` cancels the queued upload; on live failure/cancellation the background
    ///    upload continues uninterrupted.
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
            let capturedZoom: CGFloat? = diContainer.cameraManager.zoomFactor > 1.0
                ? diContainer.cameraManager.zoomFactor
                : nil
            let resolvedContext = await capturedPreFetchTask?.value

            let telemetry: CaptureTelemetry
            if let context = resolvedContext {
                let distance = diContainer.cameraManager.subjectDistanceInMeters
                var estimatedSizeCm: Double?

                if let dist = distance, let firstData = datasToAnalyze.first {
                    estimatedSizeCm = await SizeEstimator.estimateSize(imageData: firstData, distanceMeters: dist)
                }

                telemetry = CaptureTelemetry(
                    from: context,
                    distance: distance,
                    zoom: capturedZoom,
                    estimatedSizeCm: estimatedSizeCm
                )
            } else if let historicalContext = capturedOriginals.first?.environmentContext {
                // Library photo — zoom at original capture time is unknown; omit.
                telemetry = CaptureTelemetry(
                    from: historicalContext,
                    distance: nil
                )
            } else if capturedOriginals.first?.isFromGallery == true {
                // Library photo with absolutely no EXIF (no location, no date).
                telemetry = CaptureTelemetry(
                    subjectDistanceInMeters: nil,
                    gpsLatitude: nil,
                    gpsLongitude: nil,
                    gpsElevation: nil,
                    locationName: nil,
                    weatherCondition: nil,
                    weatherTemperatureF: nil,
                    timeOfDay: nil,
                    timestamp: DateUtilities.iso8601Formatter.string(from: Date()),
                    zoomFactor: nil,
                    estimatedSizeCm: nil
                )
            } else {
                let distance = diContainer.cameraManager.subjectDistanceInMeters
                var estimatedSizeCm: Double?

                if let dist = distance, let firstData = datasToAnalyze.first {
                    estimatedSizeCm = await SizeEstimator.estimateSize(imageData: firstData, distanceMeters: dist)
                }

                telemetry = CaptureTelemetry(
                    subjectDistanceInMeters: distance,
                    gpsLatitude: nil,
                    gpsLongitude: nil,
                    gpsElevation: nil,
                    locationName: nil,
                    weatherCondition: nil,
                    weatherTemperatureF: nil,
                    timeOfDay: nil,
                    timestamp: DateUtilities.iso8601Formatter.string(from: Date()),
                    zoomFactor: capturedZoom,
                    estimatedSizeCm: estimatedSizeCm
                )
            }

            // Guard: if the user backgrounded or dismissed during the preFetchTask await,
            // `isProcessing` may still be true (no rescue cancels it anymore — the scan
            // is already safely in the offline queue). We still fire analyze() so the live
            // inference path can deliver a result faster than the background upload path.
            // Only skip if isProcessing was reset by a subsequent `prepareForNewScan` call
            // (user fired a second scan), which means this scan's images are stale.
            await MainActor.run {
                guard self.diContainer.inferenceEngine.isProcessing else { return }
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
