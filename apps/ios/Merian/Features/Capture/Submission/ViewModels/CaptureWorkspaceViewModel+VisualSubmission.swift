import SwiftData

extension CaptureWorkspaceViewModel {

    // MARK: - Submit Staged Capture

    /// Kicks off the inference pipeline for everything currently in `stagedCapture`.
    ///
    /// Routing logic:
    /// - Any submission with images → shared visual pipeline (`InferenceEngine.analyze`)
    /// - Any submission without images → shared non-visual pipeline (`submitNonVisualCapture`)
    ///
    /// Call order:
    /// 1. Snapshot the staging buffers and run caller-scoped scan admission.
    /// 2. If admission is exhausted, preserve the buffers and present the paywall.
    /// 3. Otherwise clear the buffers and generate one stable `scanId` shared by
    ///    the queue record and live inference task.
    /// 4. **Enqueue immediately** (still in foreground) with a source-aware context
    ///    snapshot and the serialized observation context when present. Gallery media
    ///    uses only its embedded historical context; live media can use cached device
    ///    context. For an eligible live-camera still scan, hold its duplicate queue
    ///    upload until the inline body is sent.
    /// 5. Give shutter-prefetched context a 150 ms grace period for that live still
    ///    path, then fire `InferenceEngine.analyze`. Gallery, video, and audio-bearing
    ///    visual submissions retain their full-context wait and existing upload race.
    func submitStagedCapture(
        modelContext: ModelContext,
        preferredGoal: FieldTripPreferredGoal? = nil
    ) async {
        let shouldFinishAutomaticAttempt = isAutomaticStagedSubmissionPending
        defer {
            if shouldFinishAutomaticAttempt {
                finishAutomaticStagedSubmissionAttempt()
            }
        }

        let analysisTappedAt = CFAbsoluteTimeGetCurrent()
        let stagedNodes = stagedCapture.orderedNodes
        let admissionSnapshot = CaptureSubmissionAdmissionSnapshot(stagedCapture)
        guard !stagedNodes.isEmpty, !isCheckingScanAdmission else { return }
        isCheckingScanAdmission = true
        defer { isCheckingScanAdmission = false }

        let payload = CaptureSubmissionPayload(nodes: stagedNodes)
        let capturedMediaTimeline = payload.mediaTimeline
        let capturedDisplayImages = payload.displayImages
        let capturedInferenceImages = payload.inferenceImages
        let capturedVisualMediaItems = payload.visualMediaItems

        let capturedAudioFilePaths = capturedMediaTimeline.audioFilePaths
        let capturedVideoFilePaths = capturedMediaTimeline.videoFilePaths
        let capturedObservationContexts = capturedMediaTimeline.observationContexts
        let flashFallbackEligible = CaptureSubmissionPolicy
            .isFlashFallbackEligible(
                capturedMediaTimeline,
                targetEradicationScanId: baseRefinementContext?.scanId
            )

        guard let admissionRoute = await requestScanAdmission(
            flashFallbackEligible: flashFallbackEligible
        ) else {
            return
        }
        // The preview crosses a network boundary. Never clear or submit a
        // staging buffer the user changed while that caller-scoped read ran.
        guard CaptureSubmissionAdmissionSnapshot(stagedCapture) ==
                admissionSnapshot else {
            return
        }

        guard stagedCapture.hasVisualMedia else {
            let didEnqueue = await submitNonVisualCapture(
                audioFileNames: capturedAudioFilePaths,
                observationContexts: capturedObservationContexts,
                videoFileNames: capturedVideoFilePaths,
                mediaTimeline: capturedMediaTimeline,
                modelContext: modelContext,
                targetEradicationScanId: baseRefinementContext?.scanId,
                userPerceivedStart: analysisTappedAt,
                admissionRoute: admissionRoute
            )
            guard didEnqueue else { return }
            clearStagedCaptureAndCropState()
            baseRefinementContext = nil
            refinementSubjectId = nil
            return
        }

        // 2. Capture the context needed for inference before clearing the staging buffers.
        let primaryImageIsGalleryPhoto = capturedDisplayImages.first?.original.isFromGallery == true
        let capturedPreferredGoal = CaptureSubmissionPolicy.preferredGoal(
            preferredGoal,
            hasCameraStill: payload.hasCameraStillImage,
            hasGalleryStill: payload.hasGalleryStillImage,
            hasAudio: !capturedAudioFilePaths.isEmpty,
            hasVideo: !capturedVideoFilePaths.isEmpty
        )
        let capturedPreFetchTask: Task<EnvironmentContext, Never>?
        if primaryImageIsGalleryPhoto {
            preFetchTask?.cancel()
            capturedPreFetchTask = nil
        } else {
            capturedPreFetchTask = preFetchTask
        }
        let targetEradicationScanId    = baseRefinementContext?.scanId
        let capturedZoomFactor         = diContainer.cameraManager.zoomFactor
        let defaultZoomFactor          = diContainer.cameraManager.nativeZoomFactor
        let primaryHistoricalContext   = primaryImageIsGalleryPhoto
            ? capturedDisplayImages.first?.original.environmentContext
            : nil
        let primaryInferenceImageData = capturedDisplayImages.first?
            .compressedData
        let shouldOptimizeLiveImageAnalysis = CaptureSubmissionPolicy
            .shouldOptimizeLiveImageAnalysis(
                hasStillImage: payload.stillImageCount > 0,
                hasAudio: !capturedAudioFilePaths.isEmpty,
                hasVideo: !capturedVideoFilePaths.isEmpty,
                isGalleryPhoto: primaryImageIsGalleryPhoto
            )

        // 3. Clear the staging buffers immediately so the UI resets behind the overlay.
        clearStagedCaptureAndCropState()
        baseRefinementContext = nil
        refinementSubjectId = nil
        preFetchTask = nil
        diContainer.cameraManager.resetZoom()

        // 4. Generate a stable scanId shared by the queue record and live inference.
        let scanId = UUID().uuidString.lowercased()
        let shouldStartForegroundInference =
            admissionRoute == .foreground &&
            diContainer.offlineQueueManager.isOnline
        let foregroundInferenceGeneration = shouldStartForegroundInference
            ? UUID()
            : nil
        pendingAnalyzeScanId = scanId
        if let capturedPreferredGoal {
            diContainer.scanMilestoneCoordinator.registerPreferredGoal(
                capturedPreferredGoal,
                for: scanId
            )
        }
        let capturedMediaFilePaths = capturedMediaTimeline.discardableLocalMediaFilePaths

        // 5. Enqueue immediately — in-foreground — so the scan reaches disk and SwiftData
        //    before any async boundary is crossed. Carries the observation context JSON so
        //    the offline-retry path can reconstruct the full combined payload.
        let immediateDistance = diContainer.cameraManager.subjectDistanceInMeters
        let immediateTelemetry = CaptureTelemetry.immediateForActiveScan(
            historicalContext: primaryHistoricalContext,
            isGalleryPhoto: primaryImageIsGalleryPhoto,
            cachedLocation: dependencies.submission.context
                .lastKnownLocation(),
            distanceMeters: immediateDistance,
            zoomFactor: capturedZoomFactor,
            defaultZoomFactor: defaultZoomFactor
        )
        diContainer.offlineQueueManager.enqueueCapture(
            imageDatas: capturedInferenceImages.map(\.compressedData),
            displayImageDatas: capturedDisplayImages.map(\.displayData),
            audioFilePaths: capturedAudioFilePaths,
            videoFilePaths: capturedVideoFilePaths,
            telemetry: immediateTelemetry,
            blurScore: nil,
            scanId: scanId,
            observationContexts: capturedObservationContexts,
            mediaTimeline: capturedMediaTimeline,
            visualMediaItems: capturedVisualMediaItems,
            preferredGoal: capturedPreferredGoal,
            captureDate: primaryHistoricalContext?.captureDate ?? Date(),
            foregroundInferenceGeneration:
                foregroundInferenceGeneration,
            startSyncImmediately:
                admissionRoute == .queued || !shouldOptimizeLiveImageAnalysis,
            onQueued: { [weak self] didQueue in
                guard let self else {
                    capturedPreFetchTask?.cancel()
                    return
                }
                let queueCommittedAt = CFAbsoluteTimeGetCurrent()
                MerianLog.general.debug(
                    "[⏱ BENCH] Analyze tap to durable queue commit: \(String(format: "%.3f", queueCommittedAt - analysisTappedAt), privacy: .public)s"
                )
                guard self.pendingAnalyzeScanId == scanId else {
                    capturedPreFetchTask?.cancel()
                    if didQueue {
                        self.diContainer.offlineQueueManager.releaseDeferredLiveUpload(
                            scanId: scanId,
                            foregroundInferenceGeneration:
                                foregroundInferenceGeneration,
                            reason: "live_scan_superseded_before_start"
                        )
                        if let foregroundInferenceGeneration {
                            self.diContainer.offlineQueueManager
                                .retireForegroundInference(
                                    scanId: scanId,
                                    generation:
                                        foregroundInferenceGeneration,
                                    resumeBackground: true,
                                    reason:
                                        "live_scan_superseded_before_start"
                                )
                        }
                    } else {
                        self.discardLocalMediaFiles(at: capturedMediaFilePaths)
                    }
                    return
                }

                guard didQueue else {
                    capturedPreFetchTask?.cancel()
                    self.pendingAnalyzeScanId = nil
                    self.activeSheet = nil
                    self.offlineToastMessage = .error("Unable to save capture. Please try again.")
                    self.discardLocalMediaFiles(at: capturedMediaFilePaths)
                    return
                }

                guard self.diContainer.offlineQueueManager.isOnline else {
                    capturedPreFetchTask?.cancel()
                    self.diContainer.offlineQueueManager.releaseDeferredLiveUpload(
                        scanId: scanId,
                        foregroundInferenceGeneration:
                            foregroundInferenceGeneration,
                        reason: "offline_before_live_request"
                    )
                    if let foregroundInferenceGeneration {
                        self.diContainer.offlineQueueManager
                            .retireForegroundInference(
                                scanId: scanId,
                                generation:
                                    foregroundInferenceGeneration,
                                resumeBackground: true,
                                reason: "offline_before_live_request"
                            )
                    }
                    self.pendingAnalyzeScanId = nil
                    self.offlineToastMessage = .warning(
                        "No network connection. Scan queued for later."
                    )
                    return
                }

                guard let foregroundInferenceGeneration,
                      self.diContainer.offlineQueueManager
                        .canStartForegroundInference(
                            scanId: scanId,
                            generation: foregroundInferenceGeneration
                        ) else {
                    capturedPreFetchTask?.cancel()
                    self.diContainer.offlineQueueManager
                        .releaseDeferredLiveUpload(
                            scanId: scanId,
                            foregroundInferenceGeneration:
                                foregroundInferenceGeneration,
                            reason: "foreground_owner_unavailable"
                        )
                    if let foregroundInferenceGeneration {
                        self.diContainer.offlineQueueManager
                            .retireForegroundInference(
                                scanId: scanId,
                                generation:
                                    foregroundInferenceGeneration,
                                resumeBackground: true,
                                reason: "foreground_owner_unavailable"
                            )
                    }
                    self.pendingAnalyzeScanId = nil
                    self.offlineToastMessage = .information(
                        "Scan queued for later."
                    )
                    return
                }

                self.diContainer.inferenceEngine.prepareForNewScan(
                    scanId: scanId,
                    attemptGeneration: foregroundInferenceGeneration,
                    modality: .visual
                )
                self.activeSheet = .insight

                // 6. Concurrently resolve the full telemetry and fire live inference.
                Task { [weak self] in
                    guard let self else {
                        capturedPreFetchTask?.cancel()
                        return
                    }
                    let contextWaitStartedAt = CFAbsoluteTimeGetCurrent()
                    let resolvedContextTask = capturedPreFetchTask.map { contextTask in
                        Task {
                            CaptureSubmissionContextSnapshot(
                                await contextTask.value
                            )
                        }
                    }
                    let graceResult: CaptureSubmissionContextGraceResult
                    if shouldOptimizeLiveImageAnalysis {
                        graceResult = await
                            CaptureSubmissionEnvironmentContextGrace
                                .resolve(
                                    from: resolvedContextTask,
                                    graceMilliseconds: 150
                                )
                    } else {
                        graceResult =
                            CaptureSubmissionContextGraceResult(
                                snapshot: await resolvedContextTask?.value,
                                timedOut: false
                            )
                    }
                    let telemetry: CaptureTelemetry
                    if graceResult.timedOut {
                        telemetry = immediateTelemetry
                    } else {
                        telemetry = await CaptureTelemetry.resolveForActiveScan(
                            resolvedContext: graceResult.snapshot?
                                .makeEnvironmentContext(),
                            historicalContext: primaryHistoricalContext,
                            isGalleryPhoto: primaryImageIsGalleryPhoto,
                            firstImageData: primaryInferenceImageData,
                            distanceMeters: immediateDistance,
                            zoomFactor: capturedZoomFactor,
                            defaultZoomFactor: defaultZoomFactor
                        )
                    }
                    MerianLog.general.debug(
                        "[⏱ BENCH] Context grace: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - contextWaitStartedAt), privacy: .public)s timed_out=\(graceResult.timedOut, privacy: .public)"
                    )

                    await MainActor.run {
                        guard self.pendingAnalyzeScanId == scanId else {
                            self.diContainer.offlineQueueManager
                                .releaseDeferredLiveUpload(
                                    scanId: scanId,
                                    foregroundInferenceGeneration:
                                        foregroundInferenceGeneration,
                                    reason:
                                        "live_scan_superseded_during_context_wait"
                                )
                            self.diContainer.offlineQueueManager
                                .retireForegroundInference(
                                    scanId: scanId,
                                    generation:
                                        foregroundInferenceGeneration,
                                    resumeBackground: true,
                                    reason:
                                        "live_scan_superseded_during_context_wait"
                            )
                            return
                        }
                        guard self.diContainer.offlineQueueManager.isOnline else {
                            self.diContainer.offlineQueueManager
                                .releaseDeferredLiveUpload(
                                    scanId: scanId,
                                    foregroundInferenceGeneration:
                                        foregroundInferenceGeneration,
                                    reason:
                                        "offline_during_visual_context_grace"
                                )
                            self.diContainer.offlineQueueManager
                                .retireForegroundInference(
                                    scanId: scanId,
                                    generation:
                                        foregroundInferenceGeneration,
                                    resumeBackground: true,
                                    reason:
                                        "offline_during_visual_context_grace"
                                )
                            self.pendingAnalyzeScanId = nil
                            self.diContainer.inferenceEngine
                                .transitionToQueuedPresentation(
                                    scanId: scanId,
                                    source: .prepared(
                                        attemptGeneration:
                                            foregroundInferenceGeneration
                                    )
                                )
                            self.offlineToastMessage = .warning(
                                "Connection lost. Scan queued for later."
                            )
                            return
                        }
                        guard self.diContainer.offlineQueueManager
                                .canStartForegroundInference(
                                    scanId: scanId,
                                    generation:
                                        foregroundInferenceGeneration
                                ) else {
                            self.diContainer.offlineQueueManager
                                .releaseDeferredLiveUpload(
                                    scanId: scanId,
                                    foregroundInferenceGeneration:
                                        foregroundInferenceGeneration,
                                    reason:
                                        "foreground_owner_unavailable_after_context_grace"
                                )
                            self.diContainer.offlineQueueManager
                                .retireForegroundInference(
                                    scanId: scanId,
                                    generation:
                                        foregroundInferenceGeneration,
                                    resumeBackground: true,
                                    reason:
                                        "foreground_owner_unavailable_after_context_grace"
                                )
                            self.pendingAnalyzeScanId = nil
                            self.diContainer.inferenceEngine
                                .transitionToQueuedPresentation(
                                    scanId: scanId,
                                    source: .prepared(
                                        attemptGeneration:
                                            foregroundInferenceGeneration
                                    )
                                )
                            self.offlineToastMessage = .information(
                                "Scan queued for later."
                            )
                            return
                        }
                        self.diContainer.inferenceEngine.analyze(
                            scanId: scanId,
                            foregroundInferenceGeneration:
                                foregroundInferenceGeneration,
                            imageDatas: capturedInferenceImages.map(\.compressedData),
                            displayDatas: capturedDisplayImages.map(\.displayData),
                            audioFilePaths: capturedAudioFilePaths.isEmpty ? nil : capturedAudioFilePaths,
                            videoFilePaths: capturedVideoFilePaths.isEmpty ? nil : capturedVideoFilePaths,
                            telemetry: telemetry,
                            observationContexts: capturedObservationContexts,
                            mediaTimeline: capturedMediaTimeline,
                            visualMediaItems: capturedVisualMediaItems,
                            preferredGoal: capturedPreferredGoal,
                            modelContext: modelContext,
                            targetEradicationScanId: targetEradicationScanId,
                            userPerceivedStart: analysisTappedAt
                        )
                    }

                    if graceResult.timedOut, let resolvedContextTask {
                        let deferredContextService = self.dependencies
                            .submission.deferredContext
                        Task {
                            let lateContext = await resolvedContextTask.value
                                .makeEnvironmentContext()
                            let lateTelemetry = await CaptureTelemetry
                                .resolveForActiveScan(
                                    resolvedContext: lateContext,
                                    historicalContext: primaryHistoricalContext,
                                    isGalleryPhoto: primaryImageIsGalleryPhoto,
                                    firstImageData: primaryInferenceImageData,
                                    distanceMeters: immediateDistance,
                                    zoomFactor: capturedZoomFactor,
                                    defaultZoomFactor: defaultZoomFactor
                                )
                            await deferredContextService.apply(
                                scanId: scanId,
                                telemetry: lateTelemetry
                            )
                        }
                    }
                }
            }
        )
    }

}
