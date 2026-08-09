import SwiftData
import SwiftUI

extension CaptureWorkspaceViewModel {

    /// Starts location/weather resolution while the user records so confirming the clip can
    /// still enter the durable queue promptly. A new recording replaces any abandoned lookup.
    func prepareNonVisualCaptureContext() {
        preFetchTask?.cancel()
        let captureLocation = diContainer.environmentContextManager.lastKnownLocation
        preFetchTask = Task {
            await diContainer.environmentContextManager.fetchDeferredContext(
                preLockedLocation: captureLocation
            )
        }
    }

    // MARK: - Submit Audio

    /// Routes a finished audio recording through the shared non-visual submission path.
    ///
    /// Audio always queues durably before live inference so the capture survives interruption
    /// and can be replayed by the offline pipeline if the live task loses the race.
    @discardableResult
    func submitAudio(audioFileName: String, modelContext: ModelContext) async -> Bool {
        guard !audioFileName.isEmpty else { return false }

        let now = CFAbsoluteTimeGetCurrent()
        guard (now - (stagedCapture.lastSubmitTime ?? 0)) > 1.5 else {
            return false
        }
        stagedCapture.lastSubmitTime = now

        return await submitNonVisualCapture(
            audioFileNames: [audioFileName],
            observationContexts: [],
            mediaTimeline: [.audio(audioFileName)],
            modelContext: modelContext,
            userPerceivedStart: now
        )
    }

    // MARK: - Shared Non-Visual Submission

    /// Submits audio-only, description-only, or mixed non-visual captures.
    ///
    /// Every capture is durably queued before live inference. Description-only
    /// jobs contain no media bytes and enter `.staged` directly.
    @discardableResult
    func submitNonVisualCapture(
        audioFileNames: [String],
        observationContexts: [ObservationContext],
        videoFileNames: [String] = [],
        mediaTimeline: [CaptureSubmissionMediaItem],
        modelContext: ModelContext,
        targetEradicationScanId: String? = nil,
        userPerceivedStart: CFAbsoluteTime? = nil,
        admissionWasChecked: Bool = false
    ) async -> Bool {
        guard !mediaTimeline.isEmpty else { return false }

        let ownsAdmissionCheck = !admissionWasChecked
        if ownsAdmissionCheck {
            guard !isCheckingScanAdmission else { return false }
            isCheckingScanAdmission = true
        }
        defer {
            if ownsAdmissionCheck {
                isCheckingScanAdmission = false
            }
        }
        if ownsAdmissionCheck {
            guard await requestScanAdmission(
                flashFallbackEligible: Self.isFlashFallbackEligible(
                    mediaTimeline,
                    targetEradicationScanId: targetEradicationScanId
                )
            ) else {
                return false
            }
        }

        diContainer.cameraManager.resetZoom()

        let filteredAudioFileNames = audioFileNames.filter { !$0.isEmpty }
        let filteredVideoFileNames = videoFileNames.filter { !$0.isEmpty }
        let filteredObservationContexts = observationContexts.filter { !$0.isEmpty }
        let isOnline = diContainer.offlineQueueManager.isOnline
        let foregroundInferenceGeneration = isOnline ? UUID() : nil

        let capturedPreFetchTask = preFetchTask
        preFetchTask = nil

        let scanId = UUID().uuidString.lowercased()
        pendingAnalyzeScanId = scanId
        let cachedLocation = diContainer.environmentContextManager.lastKnownLocation
        let immediateTelemetry = CaptureTelemetry.immediateForActiveScan(
            historicalContext: nil,
            isGalleryPhoto: false,
            cachedLocation: cachedLocation,
            distanceMeters: nil,
            zoomFactor: nil
        )

        // Commit the capture before crossing any async boundary. Location names,
        // WeatherKit, and authentication are optional enrichment; none may decide
        // whether irreplaceable audio/video bytes reach the durable queue.
        let enqueued = diContainer.offlineQueueManager.enqueueNonVisualCapture(
            audioFileNames: filteredAudioFileNames,
            observationContexts: filteredObservationContexts,
            videoFilePaths: filteredVideoFileNames,
            mediaTimeline: mediaTimeline,
            telemetry: immediateTelemetry,
            scanId: scanId,
            foregroundInferenceGeneration: foregroundInferenceGeneration
        )
        guard enqueued else {
            capturedPreFetchTask?.cancel()
            pendingAnalyzeScanId = nil
            offlineToastMessage = .error("Unable to save capture. Please try again.")
            return false
        }
        if let userPerceivedStart {
            MerianLog.general.debug(
                "[⏱ BENCH] Analyze tap to durable queue commit: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - userPerceivedStart), privacy: .public)s"
            )
        }

        guard let foregroundInferenceGeneration else {
            capturedPreFetchTask?.cancel()
            pendingAnalyzeScanId = nil
            offlineToastMessage = .warning("No network connection. Queued for analysis.")
            return true
        }
        guard diContainer.offlineQueueManager.isOnline else {
            capturedPreFetchTask?.cancel()
            pendingAnalyzeScanId = nil
            diContainer.offlineQueueManager.retireForegroundInference(
                scanId: scanId,
                generation: foregroundInferenceGeneration,
                resumeBackground: true,
                reason: "live_nonvisual_offline_before_start"
            )
            offlineToastMessage = .warning("No network connection. Queued for analysis.")
            return true
        }

        let contextTask = capturedPreFetchTask ?? Task {
            await diContainer.environmentContextManager.fetchDeferredContext(
                preLockedLocation: cachedLocation
            )
        }
        Task { [weak self] in
            guard let self else { return }
            let contextWaitStartedAt = CFAbsoluteTimeGetCurrent()
            let graceResult = await Self.environmentContext(
                from: contextTask,
                graceMilliseconds: 150
            )
            let telemetry: CaptureTelemetry
            if let resolvedContext = graceResult.context,
               resolvedContext.location != nil || resolvedContext.locationName != nil {
                telemetry = CaptureTelemetry(from: resolvedContext, distance: nil)
                self.diContainer.offlineQueueManager.updateDeferredContext(
                    scanId: scanId,
                    telemetry: telemetry
                )
            } else {
                telemetry = immediateTelemetry
            }
            MerianLog.general.debug(
                "[⏱ BENCH] Non-visual context grace: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - contextWaitStartedAt), privacy: .public)s timed_out=\(graceResult.timedOut, privacy: .public)"
            )

            guard self.diContainer.offlineQueueManager.isOnline else {
                contextTask.cancel()
                self.pendingAnalyzeScanId = nil
                self.diContainer.offlineQueueManager.retireForegroundInference(
                    scanId: scanId,
                    generation: foregroundInferenceGeneration,
                    resumeBackground: true,
                    reason: "live_nonvisual_offline_during_context_grace"
                )
                self.offlineToastMessage = .warning("No network connection. Queued for analysis.")
                return
            }
            guard self.pendingAnalyzeScanId == scanId else {
                contextTask.cancel()
                self.diContainer.offlineQueueManager.retireForegroundInference(
                    scanId: scanId,
                    generation: foregroundInferenceGeneration,
                    resumeBackground: true,
                    reason: "live_nonvisual_superseded_before_start"
                )
                return
            }
            guard self.diContainer.offlineQueueManager.canStartForegroundInference(
                scanId: scanId,
                generation: foregroundInferenceGeneration
            ) else {
                contextTask.cancel()
                self.pendingAnalyzeScanId = nil
                self.offlineToastMessage = .information("Capture queued for analysis.")
                return
            }

            self.diContainer.inferenceEngine.prepareForNewScan()
            self.activeSheet = .insight
            self.diContainer.inferenceEngine.analyzeNonVisual(
                scanId: scanId,
                foregroundInferenceGeneration: foregroundInferenceGeneration,
                audioFilePaths: filteredAudioFileNames.isEmpty ? nil : filteredAudioFileNames,
                videoFilePaths: filteredVideoFileNames.isEmpty ? nil : filteredVideoFileNames,
                observationContexts: filteredObservationContexts,
                mediaTimeline: mediaTimeline,
                telemetry: telemetry,
                modelContext: modelContext,
                targetEradicationScanId: targetEradicationScanId,
                userPerceivedStart: userPerceivedStart
            )

            if graceResult.timedOut {
                Task {
                    let lateContext = await contextTask.value
                    guard lateContext.location != nil || lateContext.locationName != nil else {
                        return
                    }
                    let lateTelemetry = CaptureTelemetry(from: lateContext, distance: nil)
                    self.diContainer.offlineQueueManager.updateDeferredContext(
                        scanId: scanId,
                        telemetry: lateTelemetry
                    )
                    do {
                        try await MerianNetworkClient.shared.updateDeferredScanContext(
                            scanId: scanId,
                            telemetry: lateTelemetry
                        )
                    } catch {
                        try? await Task.sleep(for: .milliseconds(500))
                        try? await MerianNetworkClient.shared.updateDeferredScanContext(
                            scanId: scanId,
                            telemetry: lateTelemetry
                        )
                    }
                }
            }
        }
        return true
    }
}
