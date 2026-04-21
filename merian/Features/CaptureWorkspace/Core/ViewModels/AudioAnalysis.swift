import SwiftData
import SwiftUI

extension CaptureWorkspaceViewModel {

    // MARK: - Submit Audio

    /// Routes a finished audio recording to the offline queue (durable) and, when online,
    /// opens the insight sheet and fires live inference in parallel.
    ///
    /// Mirrors `submitDescribe` structurally:
    /// - Always calls `enqueueAudio` first — moves the WAV to Documents and creates a
    ///   `.staged` queue record, providing offline durability.
    /// - If offline: shows a toast and stops. The replay cycle dispatches when connectivity restores.
    /// - If online: eagerly opens the insight sheet (showing the "Analyzing" skeleton) and
    ///   fires `analyzeAudio` so the result appears without switching to another screen.
    ///
    /// Includes a 1.5 s debounce to prevent duplicate submissions on rapid taps.
    func submitAudio(audioFileName: String, observationContext: ObservationContext? = nil, modelContext: ModelContext) {
        guard !audioFileName.isEmpty else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard (now - (stagedCapture.lastSubmitTime ?? 0)) > 1.5 else { return }
        stagedCapture.lastSubmitTime = now

        let scanId = UUID().uuidString.lowercased()
        pendingAnalyzeScanId = scanId
        let capturedPreFetchTask = preFetchTask
        preFetchTask = nil

        diContainer.cameraManager.resetZoom()

        let isOnline = diContainer.offlineQueueManager.isOnline

        Task {
            let resolvedContext = await capturedPreFetchTask?.value
            let cachedLocation = diContainer.environmentContextManager.lastKnownLocation

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
                // Always enqueue first — moves WAV from tmp → Documents, creates the DB record.
                // If enqueue fails (disk I/O error, quota exhausted, context unavailable) abort:
                // there is no durable record so neither the offline toast nor live inference is safe.
                let enqueued = self.diContainer.offlineQueueManager.enqueueAudio(
                    audioFileName: audioFileName,
                    telemetry: telemetry,
                    observationContext: observationContext,
                    scanId: scanId
                )
                guard enqueued else {
                    self.offlineToastMessage = "Unable to save recording. Please try again."
                    return
                }
                self.stagedCapture.clearAll()

                guard isOnline else {
                    self.offlineToastMessage = "No network connection. Queued for analysis."
                    return
                }

                // Open the insight sheet immediately so the "Analyzing" skeleton appears,
                // then fire live inference. AnalyzingContentView sets isProcessing = true on appear.
                guard self.pendingAnalyzeScanId == scanId else { return }
                self.activeSheet = .insight
                self.diContainer.inferenceEngine.analyzeAudio(
                    scanId: scanId,
                    audioFileName: audioFileName,
                    telemetry: telemetry,
                    observationContext: observationContext,
                    modelContext: modelContext
                )
            }
        }
    }
}
