import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import Vision

extension CaptureWorkspaceViewModel {

    // MARK: - Submit Staged Capture

    /// Kicks off the inference pipeline for everything currently in `stagedCapture`.
    ///
    /// Routing logic:
    /// - Any submission with images → shared visual pipeline (`InferenceEngine.analyze`)
    /// - Any submission without images → shared non-visual pipeline (`submitNonVisualCapture`)
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
        let stagedNodes = stagedCapture.orderedNodes
        var capturedMediaTimeline: [CaptureSubmissionMediaItem] = []
        var capturedDisplayImages: [StagedImage] = []
        var capturedInferenceImages: [StagedImage] = []
        var capturedVisualMediaItems: [IdentifyVisualMediaItem] = []
        var capturedAudioMediaItems: [IdentifyAudioMediaItem] = []
        var stillImageSourceIndex = 0
        var standaloneAudioSourceIndex = 0
        var videoClipIndex = 0

        for node in stagedNodes {
            switch node {
            case .image(_, let stagedImage):
                let imageIndex = capturedDisplayImages.count
                capturedDisplayImages.append(stagedImage)
                capturedInferenceImages.append(stagedImage)
                capturedVisualMediaItems.append(.image(sourceIndex: stillImageSourceIndex))
                stillImageSourceIndex += 1
                capturedMediaTimeline.append(.image(index: imageIndex))
            case .video(_, let stagedVideo):
                var posterImageIndex: Int?
                if let coverImage = stagedVideo.coverImage {
                    let imageIndex = capturedDisplayImages.count
                    capturedDisplayImages.append(coverImage)
                    posterImageIndex = imageIndex
                }
                capturedInferenceImages.append(contentsOf: stagedVideo.sampledImages)
                for frameIndex in stagedVideo.sampledImages.indices {
                    capturedVisualMediaItems.append(.videoFrame(clipIndex: videoClipIndex, frameIndex: frameIndex))
                }
                if let audioFilePath = stagedVideo.audioFilePath, !audioFilePath.isEmpty {
                    capturedAudioMediaItems.append(.videoAudio(clipIndex: videoClipIndex))
                }
                videoClipIndex += 1
                capturedMediaTimeline.append(.video(
                    stagedVideo.filePath,
                    posterImageIndex: posterImageIndex,
                    audioFilePath: stagedVideo.audioFilePath
                ))
            case .audio(_, let stagedAudio):
                capturedAudioMediaItems.append(.audio(sourceIndex: standaloneAudioSourceIndex))
                standaloneAudioSourceIndex += 1
                capturedMediaTimeline.append(.audio(stagedAudio.filePath))
            case .description(_, let stagedObservationContext):
                capturedMediaTimeline.append(.description(stagedObservationContext.context))
            }
        }

        let capturedAudioFilePaths = capturedMediaTimeline.audioFilePaths
        let capturedVideoFilePaths = capturedMediaTimeline.videoFilePaths
        let capturedObservationContexts = capturedMediaTimeline.observationContexts

        guard stagedCapture.hasVisualMedia else {
            submitNonVisualCapture(
                audioFileNames: capturedAudioFilePaths,
                observationContexts: capturedObservationContexts,
                videoFileNames: capturedVideoFilePaths,
                mediaTimeline: capturedMediaTimeline,
                modelContext: modelContext,
                targetEradicationScanId: baseRefinementContext?.scanId
            )
            clearStagedCaptureAndCropState()
            baseRefinementContext = nil
            refinementSubjectId = nil
            return
        }

        // 2. Capture the context needed for inference before clearing the staging buffers.
        let capturedPreFetchTask       = preFetchTask
        let targetEradicationScanId    = baseRefinementContext?.scanId
        let capturedZoomFactor         = diContainer.cameraManager.zoomFactor
        let defaultZoomFactor          = diContainer.cameraManager.nativeZoomFactor
        let primaryImageIsGalleryPhoto = capturedDisplayImages.first?.original.isFromGallery == true

        // 3. Clear the staging buffers immediately so the UI resets behind the overlay.
        clearStagedCaptureAndCropState()
        baseRefinementContext = nil
        refinementSubjectId = nil
        preFetchTask = nil
        diContainer.cameraManager.resetZoom()

        // 4. Generate a stable scanId shared by the queue record and live inference.
        let scanId = UUID().uuidString.lowercased()
        pendingAnalyzeScanId = scanId
        let capturedMediaFilePaths = capturedMediaTimeline.discardableLocalMediaFilePaths

        // 5. Enqueue immediately — in-foreground — so the scan reaches disk and SwiftData
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
            zoomFactor: primaryImageIsGalleryPhoto
                ? nil
                : CaptureTelemetry.nonDefaultZoomFactor(capturedZoomFactor, defaultZoomFactor: defaultZoomFactor),
            estimatedSizeCm: nil
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
            onQueued: { [weak self] didQueue in
                guard let self else { return }
                guard self.pendingAnalyzeScanId == scanId else {
                    if !didQueue {
                        self.discardLocalMediaFiles(at: capturedMediaFilePaths)
                    }
                    return
                }

                guard didQueue else {
                    self.pendingAnalyzeScanId = nil
                    self.activeSheet = nil
                    self.offlineToastMessage = "Unable to save capture. Please try again."
                    self.discardLocalMediaFiles(at: capturedMediaFilePaths)
                    return
                }

                guard self.diContainer.offlineQueueManager.isOnline else {
                    self.pendingAnalyzeScanId = nil
                    self.offlineToastMessage = "No network connection. Queued for upload."
                    return
                }

                self.diContainer.inferenceEngine.prepareForNewScan()
                self.activeSheet = .insight

                // 6. Concurrently resolve the full telemetry and fire live inference.
                Task { [weak self] in
                    guard let self else { return }
                    let resolvedContext = await capturedPreFetchTask?.value

                    let telemetry = await CaptureTelemetry.resolveForActiveScan(
                        resolvedContext: resolvedContext,
                        historicalContext: capturedDisplayImages.first?.original.environmentContext,
                        isGalleryPhoto: primaryImageIsGalleryPhoto,
                        firstImageData: capturedDisplayImages.first?.compressedData,
                        distanceMeters: self.diContainer.cameraManager.subjectDistanceInMeters,
                        zoomFactor: capturedZoomFactor,
                        defaultZoomFactor: defaultZoomFactor
                    )

                    await MainActor.run {
                        guard self.pendingAnalyzeScanId == scanId else { return }
                        self.diContainer.inferenceEngine.analyze(
                            scanId: scanId,
                            imageDatas: capturedInferenceImages.map(\.compressedData),
                            displayDatas: capturedDisplayImages.map(\.displayData),
                            audioFilePaths: capturedAudioFilePaths.isEmpty ? nil : capturedAudioFilePaths,
                            videoFilePaths: capturedVideoFilePaths.isEmpty ? nil : capturedVideoFilePaths,
                            telemetry: telemetry,
                            observationContexts: capturedObservationContexts,
                            mediaTimeline: capturedMediaTimeline,
                            visualMediaItems: capturedVisualMediaItems,
                            audioMediaItems: capturedAudioMediaItems,
                            modelContext: modelContext,
                            targetEradicationScanId: targetEradicationScanId
                        )
                    }
                }
            }
        )
    }

    // MARK: - Inference Processing Change

    /// Responds to changes in `InferenceEngine.isProcessing`.
    func handleInferenceProcessingChange(isStillProcessing: Bool) {
        guard !isStillProcessing else { return }
        if diContainer.inferenceEngine.speciesData?.scanId != nil, activeSheet != .insight {
            diContainer.appSettings.hasUnseenScan = true
            AppIconBadgeCoordinator.updateAppIconBadge()
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
        zoomFactor: CGFloat?,
        defaultZoomFactor: CGFloat = 1.0
    ) async -> CaptureTelemetry {
        let zoomToUse = nonDefaultZoomFactor(zoomFactor, defaultZoomFactor: defaultZoomFactor)

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

    static func nonDefaultZoomFactor(_ zoomFactor: CGFloat?, defaultZoomFactor: CGFloat) -> CGFloat? {
        guard let zoomFactor else { return nil }
        return abs(zoomFactor - defaultZoomFactor) > 0.01 ? zoomFactor : nil
    }
}
