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
        videoFileNames: [String] = [],
        mediaTimeline: [CaptureSubmissionMediaItem],
        modelContext: ModelContext,
        targetEradicationScanId: String? = nil
    ) {
        guard !mediaTimeline.isEmpty else { return }

        diContainer.cameraManager.resetZoom()

        let filteredAudioFileNames = audioFileNames.filter { !$0.isEmpty }
        let filteredVideoFileNames = videoFileNames.filter { !$0.isEmpty }
        let filteredObservationContexts = observationContexts.filter { !$0.isEmpty }
        let isOnline = diContainer.offlineQueueManager.isOnline
        let shouldEnqueueDurably = !filteredAudioFileNames.isEmpty || !filteredVideoFileNames.isEmpty || !isOnline

        let capturedPreFetchTask = preFetchTask
        preFetchTask = nil

        let scanId = UUID().uuidString.lowercased()
        pendingAnalyzeScanId = scanId

        Task {
            let cachedLocation = diContainer.environmentContextManager.lastKnownLocation
            // Audio and description captures do not pass through the camera shutter path,
            // which normally starts `preFetchTask`. Resolve the cached coordinate here so
            // non-visual scans persist the same semantic/public location label as visual scans.
            // Pinning the lookup to `cachedLocation` keeps the context tied to capture time.
            let resolvedContext: EnvironmentContext
            if let capturedPreFetchTask {
                resolvedContext = await capturedPreFetchTask.value
            } else {
                resolvedContext = await diContainer.environmentContextManager.fetchDeferredContext(
                    preLockedLocation: cachedLocation
                )
            }

            let telemetry: CaptureTelemetry
            if resolvedContext.location != nil || resolvedContext.locationName != nil {
                telemetry = CaptureTelemetry(from: resolvedContext, distance: nil)
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
                        videoFilePaths: filteredVideoFileNames,
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
                    self.pendingAnalyzeScanId = nil
                    self.offlineToastMessage = "No network connection. Queued for analysis."
                    return
                }

                guard self.pendingAnalyzeScanId == scanId else { return }
                self.diContainer.inferenceEngine.prepareForNewScan()
                self.activeSheet = .insight
                self.diContainer.inferenceEngine.analyzeNonVisual(
                    scanId: scanId,
                    audioFilePaths: filteredAudioFileNames.isEmpty ? nil : filteredAudioFileNames,
                    videoFilePaths: filteredVideoFileNames.isEmpty ? nil : filteredVideoFileNames,
                    observationContexts: filteredObservationContexts,
                    mediaTimeline: mediaTimeline,
                    telemetry: telemetry,
                    modelContext: modelContext,
                    targetEradicationScanId: targetEradicationScanId
                )
            }
        }
    }
}
