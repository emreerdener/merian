import SwiftData
import SwiftUI

extension CameraViewModel {

    // MARK: - Submit Sighting (entry point from SightingInputView)

    /// Routes the observation based on what else is staged.
    ///
    /// - **Images staged**: stages the description into `stagedCapture.observationContext`
    ///   and delegates to `submitStagedCapture` → combined image + description path.
    /// - **No images staged**: solo description-only path via `submitSightingSolo`.
    func submitSighting(observationContext: ObservationContext, modelContext: ModelContext) {
        guard !observationContext.isEmpty else { return }

        let isMultiCaptureEnabled = UserDefaults.standard.bool(forKey: "isMultiCaptureEnabled")

        if isMultiCaptureEnabled {
            stagedCapture.observationContext = observationContext
            let limit = 2 // Current capacity limit for multi-capture items
            let totalItems = stagedCapture.images.count + 1
            
            if !UserDefaults.standard.bool(forKey: "requiresScanConfirmation") && totalItems >= limit {
                submitStagedCapture(modelContext: modelContext)
            }
        } else {
            if !stagedCapture.images.isEmpty {
                stagedCapture.observationContext = observationContext
                submitStagedCapture(modelContext: modelContext)
            } else {
                submitSightingSolo(observationContext: observationContext, modelContext: modelContext)
            }
        }
    }

    // MARK: - Solo Sighting Path (description only, no images)

    /// Routes a solo sighting submission through the live `/identify-sighting` edge function
    /// when online, or enqueues it as a `.staged` `OfflineQueuedScan` for background retry when
    /// offline — mirroring the resilience guarantee of the image capture path.
    ///
    /// Call order (online):
    /// 1. Reset `InferenceEngine` display state and open the insight sheet.
    /// 2. Snapshot the `ObservationContext` (value type — no race risk).
    /// 3. Generate a stable `scanId`.
    /// 4. Resolve full telemetry from the environment context manager.
    /// 5. Fire `InferenceEngine.analyzeSighting`.
    ///
    /// Call order (offline):
    /// 1. Reset `InferenceEngine` state (ensures a clean slate for the next online attempt).
    /// 2. Enqueue via `OfflineQueueManager.enqueueSighting` with cached GPS telemetry.
    ///    WeatherKit backfill is deferred to `dispatchInferenceDownloadTask` on retry.
    /// 3. Show "No network connection. Queued for upload." toast.
    func submitSightingSolo(observationContext: ObservationContext, modelContext: ModelContext) {
        guard !observationContext.isEmpty else { return }

        // Reset inference state synchronously so a previous result is never shown in the sheet.
        diContainer.inferenceEngine.prepareForNewScan()

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
            diContainer.offlineQueueManager.enqueueSighting(
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
                self.diContainer.inferenceEngine.analyzeSighting(
                    scanId: scanId,
                    observationContext: capturedContext,
                    telemetry: telemetry,
                    modelContext: modelContext
                )
            }
        }
    }
}
