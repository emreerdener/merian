import SwiftData
import SwiftUI

extension CaptureWorkspaceViewModel {

    // MARK: - Submit Audio

    /// Routes a finished audio recording through the shared non-visual submission path.
    ///
    /// Audio always queues durably before live inference so the capture survives interruption
    /// and can be replayed by the offline pipeline if the live task loses the race.
    func submitAudio(audioFileName: String, modelContext: ModelContext) {
        guard !audioFileName.isEmpty else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard (now - (stagedCapture.lastSubmitTime ?? 0)) > 1.5 else { return }
        stagedCapture.lastSubmitTime = now

        submitNonVisualCapture(
            audioFileNames: [audioFileName],
            observationContexts: [],
            mediaTimeline: [.audio(audioFileName)],
            modelContext: modelContext
        )
    }

    // MARK: - Shared Non-Visual Submission

    /// Submits audio-only, description-only, or mixed non-visual captures.
    ///
    /// - Audio-bearing captures always enqueue first for durability.
    /// - Description-only captures keep the current behavior: online runs live immediately,
    ///   offline falls back to the durable queued path.
    func submitNonVisualCapture(
        audioFileNames: [String],
        observationContexts: [ObservationContext],
        mediaTimeline: [CaptureSubmissionMediaItem],
        modelContext: ModelContext,
        targetEradicationRecord: LocalScanRecord? = nil
    ) {
        guard !mediaTimeline.isEmpty else { return }

        diContainer.inferenceEngine.prepareForNewScan()
        diContainer.cameraManager.resetZoom()

        let filteredAudioFileNames = audioFileNames.filter { !$0.isEmpty }
        let filteredObservationContexts = observationContexts.filter { !$0.isEmpty }
        let isOnline = diContainer.offlineQueueManager.isOnline
        let shouldEnqueueDurably = !filteredAudioFileNames.isEmpty || !isOnline

        let capturedPreFetchTask = preFetchTask
        preFetchTask = nil

        let scanId = UUID().uuidString.lowercased()
        pendingAnalyzeScanId = scanId

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
                if shouldEnqueueDurably {
                    let enqueued = self.diContainer.offlineQueueManager.enqueueNonVisualCapture(
                        audioFileNames: filteredAudioFileNames,
                        observationContexts: filteredObservationContexts,
                        mediaTimeline: mediaTimeline,
                        telemetry: telemetry,
                        scanId: scanId
                    )
                    guard enqueued else {
                        self.offlineToastMessage = "Unable to save capture. Please try again."
                        return
                    }
                }

                guard isOnline else {
                    self.offlineToastMessage = "No network connection. Queued for analysis."
                    return
                }

                guard self.pendingAnalyzeScanId == scanId else { return }
                self.activeSheet = .insight
                self.diContainer.inferenceEngine.analyzeNonVisual(
                    scanId: scanId,
                    audioFilePaths: filteredAudioFileNames.isEmpty ? nil : filteredAudioFileNames,
                    observationContexts: filteredObservationContexts,
                    mediaTimeline: mediaTimeline,
                    telemetry: telemetry,
                    modelContext: modelContext,
                    targetEradicationRecord: targetEradicationRecord
                )
            }
        }
    }
}
