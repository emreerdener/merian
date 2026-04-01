import SwiftData
import SwiftUI
import Vision

extension CameraViewModel {

    // MARK: - Submit Active Scan

    /// Kicks off the inference pipeline for the accumulated `activeScanImages`.
    ///
    /// Call order:
    /// 1. Snapshot images into the analysis overlay and show fullscreen scanning UI.
    /// 2. Await the pre-fetched `EnvironmentContext` (started at shutter press) to build telemetry.
    /// 3. Clear the staging buffers so the user cannot double-submit.
    /// 4. Fire `InferenceEngine.analyze` — `handleInferenceProcessingChange` will dismiss the overlay when done.
    func submitActiveScan(modelContext: ModelContext) {
        guard !activeScannedDatas.isEmpty else { return }

        // 1. Eagerly set the Insight sheet to open in its "Analyzing" skeleton state.
        activeSheet = .insight

        // 2. Capture the context needed for inference before clearing the staging buffers.
        let datasToAnalyze = activeScannedDatas
        let displayDatasToAnalyze = activeDisplayDatas
        let capturedOriginals = activeOriginals
        let capturedPreFetchTask = preFetchTask

        // 3. Clear the staging buffers immediately so the UI resets behind the overlay.
        activeScanImages.removeAll()
        activeScannedDatas.removeAll()
        activeDisplayDatas.removeAll()
        activeOriginals.removeAll()
        preFetchTask = nil

        // 4. Fire the inference pipeline.

        Task {
            // 5. Resolve the pre-fetched environment context (started at shutter press).
            // Snapshot zoom before the first await — at 1× it carries no signal, so nil is sent.
            let capturedZoom: CGFloat? = diContainer.cameraManager.zoomFactor > 1.0
                ? diContainer.cameraManager.zoomFactor
                : nil
            let resolvedContext = await capturedPreFetchTask?.value

            // Build telemetry — prefer the pre-fetched context; fall back to the
            // historical context baked into the first gallery original if present.
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
                // Do not apply live camera metrics (distance, zoom) to an old photo.
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

            // 6. Fire the inference pipeline.
            await MainActor.run {
                diContainer.inferenceEngine.analyze(
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
    ///
    func handleInferenceProcessingChange(isStillProcessing: Bool) {
        guard !isStillProcessing else { return }
        // Mark a new unread scan only for real results (scanId is nil on error placeholders
        // like "Analysis Failed" / "Network Timeout" which are not persisted to the library).
        // Skip if the insight sheet is already open — the user is actively viewing the result
        // and closing the sheet should not trigger the indicator.
        if diContainer.inferenceEngine.speciesData?.scanId != nil, activeSheet != .insight {
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasUnseenScan)
        }
    }

    // MARK: - Dismiss Analysis

    /// Re-queues the active inference request into the background offline queue,
    /// skips refunding the credit, and drops the overlay to let the user keep scanning.
    func dismissAnalysisToBackground() {
        if diContainer.inferenceEngine.isProcessing, !diContainer.inferenceEngine.activeLiveCaptureDatas.isEmpty {
            diContainer.offlineQueueManager.enqueueCapture(
                imageDatas: diContainer.inferenceEngine.activeLiveCaptureDatas,
                telemetry: CaptureTelemetry(from: diContainer.inferenceEngine),
                blurScore: nil
            )
        }

        diContainer.inferenceEngine.cancelActiveRequest(isUserInitiated: false)
    }
}
