import SwiftData
import SwiftUI

extension CaptureWorkspaceViewModel {

    // MARK: - Submit Describe (entry point from DescribeInputView)

    /// Routes the observation based on what else is staged.
    ///
    /// - **Images staged**: stages the description into `stagedCapture.observationContext`
    ///   and delegates to `submitStagedCapture` → combined image + description path.
    /// - **No images staged**: solo description-only path via `submitDescribeSolo`.
    ///
    /// Includes a 1.5s debounce to prevent duplicate enqueuing on rapid physical taps.
    @discardableResult
    func submitDescribe(observationContext: ObservationContext, modelContext: ModelContext) -> Bool {
        // Prevent rapid duplicate taps from spawning identical offline queue records
        let now = CFAbsoluteTimeGetCurrent()
        guard (now - (stagedCapture.lastSubmitTime ?? 0)) > 1.5 else { return false }
        stagedCapture.lastSubmitTime = now

        guard !observationContext.isEmpty else { return false }

        // The observationContext originates from a long-lived @State binding in
        // CaptureWorkspaceView. We must mint a brand new generation timestamp here right
        // as the user formally submits it to staging to guarantee chronological accuracy.
        var stagedContext = observationContext
        stagedContext.addedAt = Date()

        let isMultiCaptureEnabled = UserDefaults.standard.bool(forKey: "isMultiCaptureEnabled")

        if isMultiCaptureEnabled {
            stagedCapture.observationContext = stagedContext
            let limit = 2 // Current capacity limit for multi-capture items
            let totalItems = stagedCapture.images.count + 1
            
            if !UserDefaults.standard.bool(forKey: "requiresScanConfirmation") && totalItems >= limit {
                submitStagedCapture(modelContext: modelContext)
            }
            return true
        } else {
            if !stagedCapture.images.isEmpty {
                // Images already staged — add the description to the toolbar without submitting.
                // The ActiveScanToolbar's Identify button owns submission in this state.
                stagedCapture.observationContext = stagedContext
                return true
            } else {
                if UserDefaults.standard.bool(forKey: "requiresScanConfirmation") {
                    // Stage as a solo node so the user confirms via Identify before submitting.
                    // submitStagedCapture routes description-only back through submitDescribeSolo.
                    stagedCapture.observationContext = stagedContext
                } else {
                    let targetEradicationRecord = baseRefinementRecord
                    baseRefinementRecord = nil
                    submitDescribeSolo(observationContext: stagedContext, modelContext: modelContext, targetEradicationRecord: targetEradicationRecord)
                }
                return true
            }
        }
    }

    // MARK: - Solo Describe Path (description only, no images)

    /// Routes a solo describe submission through the live `/identify-describe` edge function
    /// when online, or enqueues it as a `.staged` `OfflineQueuedScan` for background retry when
    /// offline — mirroring the resilience guarantee of the image capture path.
    ///
    /// Call order (online):
    /// 1. Reset `InferenceEngine` display state and open the insight sheet.
    /// 2. Snapshot the `ObservationContext` (value type — no race risk).
    /// 3. Generate a stable `scanId`.
    /// 4. Resolve full telemetry from the environment context manager.
    /// 5. Fire `InferenceEngine.analyzeDescribe`.
    ///
    /// Call order (offline):
    /// 1. Reset `InferenceEngine` state (ensures a clean slate for the next online attempt).
    /// 2. Enqueue via `OfflineQueueManager.enqueueDescribe` with cached GPS telemetry.
    ///    WeatherKit backfill is deferred to `dispatchInferenceDownloadTask` on retry.
    /// 3. Show "No network connection. Queued for upload." toast.
    func submitDescribeSolo(observationContext: ObservationContext, modelContext: ModelContext, targetEradicationRecord: LocalScanRecord? = nil) {
        guard !observationContext.isEmpty else { return }

        // Reset inference state synchronously so a previous result is never shown in the sheet.
        diContainer.inferenceEngine.prepareForNewScan()
        diContainer.cameraManager.resetZoom()

        let isOnline = diContainer.offlineQueueManager.isOnline

        let capturedContext      = observationContext
        let capturedPreFetchTask = preFetchTask

        let scanId = UUID().uuidString.lowercased()
        pendingAnalyzeScanId = scanId
        preFetchTask = nil

        // Offline intercept — enqueue with cached GPS and show a toast.
        // WeatherKit backfill runs in dispatchInferenceDownloadTask when connectivity restores.
        guard isOnline else {
            let cachedLocation = diContainer.environmentContextManager.lastKnownLocation
            diContainer.offlineQueueManager.enqueueDescribe(
                observationContext: capturedContext,
                telemetry: CaptureTelemetry(
                    subjectDistanceInMeters: nil,
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
                ),
                scanId: scanId
            )
            offlineToastMessage = "No network connection. Queued for upload."
            return
        }

        // Online: open the insight sheet and fire live inference.
        activeSheet = .insight

        Task {
            let resolvedContext = await capturedPreFetchTask?.value
            let cachedLocation  = diContainer.environmentContextManager.lastKnownLocation

            let telemetry: CaptureTelemetry
            if let env = resolvedContext {
                telemetry = CaptureTelemetry(from: env, distance: nil)
            } else {
                telemetry = CaptureTelemetry(
                    subjectDistanceInMeters: nil,
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
            }

            await MainActor.run {
                guard self.pendingAnalyzeScanId == scanId else { return }
                self.diContainer.inferenceEngine.analyzeDescribe(
                    scanId: scanId,
                    observationContext: capturedContext,
                    telemetry: telemetry,
                    modelContext: modelContext,
                    targetEradicationRecord: targetEradicationRecord
                )
            }
        }
    }
}
