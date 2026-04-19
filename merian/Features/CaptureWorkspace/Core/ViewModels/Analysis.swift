import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import Vision

extension CaptureWorkspaceViewModel {

    // MARK: - Submit Staged Capture

    /// Kicks off the inference pipeline for everything currently in `stagedCapture`.
    ///
    /// Routing logic:
    /// - Images only → `identify` endpoint (existing image path)
    /// - Images + description → `identify` endpoint with description injected as
    ///   additional Gemini context (combined path)
    /// - Description only → falls back to `analyzeDescribe` (no images to upload)
    ///
    /// Call order:
    /// 1. Reset `InferenceEngine` display state and open the insight sheet immediately.
    /// 2. Snapshot the staging buffers, then clear them to prevent double-submit.
    /// 3. Generate a stable `scanId` shared by the queue record and live inference task.
    /// 4. **Enqueue immediately** (still in foreground) with cached GPS and the
    ///    serialized observation context when present. The background URLSession
    ///    upload is dispatched inside the same `UIBackgroundTask` window.
    /// 5. Await the pre-fetched `EnvironmentContext`, build full telemetry, and fire
    ///    `InferenceEngine.analyze`. The live path and background upload race —
    ///    whichever completes first wins.
    func submitStagedCapture(modelContext: ModelContext) {
        guard !stagedCapture.images.isEmpty else {
            // No images — description-only path
            if let context = stagedCapture.observationContext, !context.isEmpty {
                submitDescribeSolo(observationContext: context, modelContext: modelContext)
            }
            return
        }

        // 1. Reset all InferenceEngine display state synchronously so the content router
        //    immediately sees `isProcessing == true && speciesData == nil`.
        diContainer.inferenceEngine.prepareForNewScan()

        let isOnline = diContainer.offlineQueueManager.isOnline

        // 2. Eagerly set the Insight sheet to open in its "Analyzing" skeleton state.
        if isOnline {
            activeSheet = .insight
        }

        // 3. Capture the context needed for inference before clearing the staging buffers.
        let capturedImages          = stagedCapture.images
        let capturedObsContext      = stagedCapture.observationContext
        let capturedPreFetchTask    = preFetchTask
        let targetEradicationRecord = baseRefinementRecord

        // 4. Clear the staging buffers immediately so the UI resets behind the overlay.
        stagedCapture.clearAll()
        baseRefinementRecord = nil
        preFetchTask = nil
        diContainer.cameraManager.resetZoom()

        // 5. Generate a stable scanId shared by the queue record and live inference.
        let scanId = UUID().uuidString.lowercased()
        pendingAnalyzeScanId = scanId

        // 6. Enqueue immediately — in-foreground — so the scan reaches disk and SwiftData
        //    before any async boundary is crossed. Carries the observation context JSON so
        //    the offline-retry path can reconstruct the full combined payload.
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
            imageDatas: capturedImages.map(\.compressedData),
            telemetry: immediateTelemetry,
            blurScore: nil,
            scanId: scanId,
            observationContext: capturedObsContext
        )

        // If completely offline, skip live inference and show a toast immediately.
        guard isOnline else {
            self.offlineToastMessage = "No network connection. Queued for upload."
            return
        }

        // 7. Concurrently resolve the full telemetry and fire live inference.
        Task {
            let resolvedContext = await capturedPreFetchTask?.value

            let telemetry = await CaptureTelemetry.resolveForActiveScan(
                resolvedContext: resolvedContext,
                historicalContext: capturedImages.first?.original.environmentContext,
                isGalleryPhoto: capturedImages.first?.original.isFromGallery == true,
                firstImageData: capturedImages.first?.compressedData,
                distanceMeters: diContainer.cameraManager.subjectDistanceInMeters,
                zoomFactor: diContainer.cameraManager.zoomFactor
            )

            await MainActor.run {
                guard self.pendingAnalyzeScanId == scanId else { return }
                self.diContainer.inferenceEngine.analyze(
                    scanId: scanId,
                    imageDatas: capturedImages.map(\.compressedData),
                    displayDatas: capturedImages.map(\.displayData),
                    telemetry: telemetry,
                    observationContext: capturedObsContext,   // non-nil when combined
                    modelContext: modelContext,
                    targetEradicationRecord: targetEradicationRecord
                )
            }
        }
    }

    // MARK: - Inference Processing Change

    /// Responds to changes in `InferenceEngine.isProcessing`.
    func handleInferenceProcessingChange(isStillProcessing: Bool) {
        guard !isStillProcessing else { return }
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
            return CaptureTelemetry(from: hc, distance: nil)
        } else if isGalleryPhoto {
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
