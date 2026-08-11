import CoreLocation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import Vision

struct EnvironmentContextGraceResult: @unchecked Sendable {
    let context: EnvironmentContext?
    let timedOut: Bool
}

enum CaptureScanAdmissionRoute: Sendable, Equatable {
    case foreground
    case queued
}

enum CaptureScanAdmissionResolution: Sendable, Equatable {
    case proceed(CaptureScanAdmissionRoute)
    case paywall
    case retryRequired
}

enum CaptureScanAdmissionPolicy {
    nonisolated static func resolve(
        isOnline: Bool,
        canStartLocally: Bool,
        previewResult: ScanAdmissionPreviewResult?
    ) -> CaptureScanAdmissionResolution {
        guard isOnline else {
            return canStartLocally ? .proceed(.queued) : .paywall
        }
        guard let previewResult else { return .retryRequired }

        switch previewResult {
        case .available(let preview):
            switch preview.decision {
            case .allowed:
                return .proceed(.foreground)
            case .dailyQuotaExhausted, .proRequired:
                return .paywall
            }
        case .connectivityUnavailable:
            return canStartLocally ? .proceed(.queued) : .paywall
        case .unavailable:
            return .retryRequired
        }
    }
}

final class EnvironmentContextGraceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<EnvironmentContextGraceResult, Never>?

    init(_ continuation: CheckedContinuation<EnvironmentContextGraceResult, Never>) {
        self.continuation = continuation
    }

    func resolve(_ result: EnvironmentContextGraceResult) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}

private struct StagedCaptureAdmissionSnapshot: Equatable {
    let imageIDs: [UUID]
    let imagePayloads: [Data]
    let audioFilePaths: [String]
    let audioAddedAt: [Date]
    let videoFilePaths: [String]
    let videoAddedAt: [Date]
    let observationContexts: [ObservationContext]
    let observationAddedAt: [Date]

    init(_ stagedCapture: StagedCapture) {
        imageIDs = stagedCapture.images.map(\.original.id)
        imagePayloads = stagedCapture.images.map(\.compressedData)
        audioFilePaths = stagedCapture.audios.map(\.filePath)
        audioAddedAt = stagedCapture.audios.map(\.addedAt)
        videoFilePaths = stagedCapture.videos.map(\.filePath)
        videoAddedAt = stagedCapture.videos.map(\.addedAt)
        observationContexts = stagedCapture.observationContexts.map(\.context)
        observationAddedAt = stagedCapture.observationContexts.map(\.addedAt)
    }
}

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
        let admissionSnapshot = StagedCaptureAdmissionSnapshot(stagedCapture)
        guard !stagedNodes.isEmpty, !isCheckingScanAdmission else { return }
        isCheckingScanAdmission = true
        defer { isCheckingScanAdmission = false }

        var capturedMediaTimeline: [CaptureSubmissionMediaItem] = []
        var capturedDisplayImages: [StagedImage] = []
        var capturedInferenceImages: [StagedImage] = []
        var capturedVisualMediaItems: [IdentifyVisualMediaItem] = []
        var capturedAudioMediaItems: [IdentifyAudioMediaItem] = []
        var stillImageSourceIndex = 0
        var standaloneAudioSourceIndex = 0
        var videoClipIndex = 0
        var hasCameraStillImage = false
        var hasGalleryStillImage = false

        for node in stagedNodes {
            switch node {
            case .image(_, let stagedImage):
                let imageIndex = capturedDisplayImages.count
                capturedDisplayImages.append(stagedImage)
                capturedInferenceImages.append(stagedImage)
                let isGalleryImage = stagedImage.original.isFromGallery
                hasGalleryStillImage = hasGalleryStillImage || isGalleryImage
                hasCameraStillImage = hasCameraStillImage || !isGalleryImage
                capturedVisualMediaItems.append(.image(
                    sourceIndex: stillImageSourceIndex,
                    focusRegion: stagedImage.focusRegion,
                    captureSource: isGalleryImage ? .gallery : .camera,
                    hasEmbeddedCaptureDate: isGalleryImage
                        ? stagedImage.original.environmentContext?.captureDate != nil
                        : nil
                ))
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
        let flashFallbackEligible = Self.isFlashFallbackEligible(
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
        guard StagedCaptureAdmissionSnapshot(stagedCapture) == admissionSnapshot else {
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
        let capturedPreferredGoal = Self.preferredGoalForSubmission(
            preferredGoal,
            hasCameraStill: hasCameraStillImage,
            hasGalleryStill: hasGalleryStillImage,
            hasAudio: !capturedAudioFilePaths.isEmpty,
            hasVideo: !capturedVideoFilePaths.isEmpty
        )
        let capturedPreFetchTask       = primaryImageIsGalleryPhoto ? nil : preFetchTask
        let targetEradicationScanId    = baseRefinementContext?.scanId
        let capturedZoomFactor         = diContainer.cameraManager.zoomFactor
        let defaultZoomFactor          = diContainer.cameraManager.nativeZoomFactor
        let primaryHistoricalContext   = primaryImageIsGalleryPhoto
            ? capturedDisplayImages.first?.original.environmentContext
            : nil
        let shouldOptimizeLiveImageAnalysis = Self.shouldOptimizeLiveImageAnalysis(
            hasStillImage: stillImageSourceIndex > 0,
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
            cachedLocation: diContainer.environmentContextManager.lastKnownLocation,
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
                guard let self else { return }
                let queueCommittedAt = CFAbsoluteTimeGetCurrent()
                MerianLog.general.debug(
                    "[⏱ BENCH] Analyze tap to durable queue commit: \(String(format: "%.3f", queueCommittedAt - analysisTappedAt), privacy: .public)s"
                )
                guard self.pendingAnalyzeScanId == scanId else {
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
                    self.pendingAnalyzeScanId = nil
                    self.activeSheet = nil
                    self.offlineToastMessage = .error("Unable to save capture. Please try again.")
                    self.discardLocalMediaFiles(at: capturedMediaFilePaths)
                    return
                }

                guard self.diContainer.offlineQueueManager.isOnline else {
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

                self.diContainer.inferenceEngine.prepareForNewScan()
                self.activeSheet = .insight

                // 6. Concurrently resolve the full telemetry and fire live inference.
                Task { [weak self] in
                    guard let self else { return }
                    let contextWaitStartedAt = CFAbsoluteTimeGetCurrent()
                    let graceResult: EnvironmentContextGraceResult
                    if shouldOptimizeLiveImageAnalysis {
                        graceResult = await Self.environmentContext(
                            from: capturedPreFetchTask,
                            graceMilliseconds: 150
                        )
                    } else {
                        let resolvedContext: EnvironmentContext?
                        if let capturedPreFetchTask {
                            resolvedContext = await capturedPreFetchTask.value
                        } else {
                            resolvedContext = nil
                        }
                        graceResult = EnvironmentContextGraceResult(
                            context: resolvedContext,
                            timedOut: false
                        )
                    }
                    let telemetry: CaptureTelemetry
                    if graceResult.timedOut {
                        telemetry = immediateTelemetry
                    } else {
                        telemetry = await CaptureTelemetry.resolveForActiveScan(
                            resolvedContext: graceResult.context,
                            historicalContext: primaryHistoricalContext,
                            isGalleryPhoto: primaryImageIsGalleryPhoto,
                            firstImageData: capturedDisplayImages.first?.compressedData,
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
                                    scanId: scanId
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
                                    scanId: scanId
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
                            audioMediaItems: capturedAudioMediaItems,
                            preferredGoal: capturedPreferredGoal,
                            modelContext: modelContext,
                            targetEradicationScanId: targetEradicationScanId,
                            userPerceivedStart: analysisTappedAt
                        )
                    }

                    if graceResult.timedOut, let capturedPreFetchTask {
                        Task {
                            let lateContext = await capturedPreFetchTask.value
                            let lateTelemetry = await CaptureTelemetry.resolveForActiveScan(
                                resolvedContext: lateContext,
                                historicalContext: primaryHistoricalContext,
                                isGalleryPhoto: primaryImageIsGalleryPhoto,
                                firstImageData: capturedDisplayImages.first?.compressedData,
                                distanceMeters: immediateDistance,
                                zoomFactor: capturedZoomFactor,
                                defaultZoomFactor: defaultZoomFactor
                            )
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
                                // The context can beat the atomic ingestion claim by a few
                                // milliseconds. Retry once; the durable local queue remains
                                // the fallback if the live request never reaches Edge.
                                try? await Task.sleep(for: .milliseconds(500))
                                try? await MerianNetworkClient.shared.updateDeferredScanContext(
                                    scanId: scanId,
                                    telemetry: lateTelemetry
                                )
                            }
                        }
                    }
                }
            }
        )
    }

    /// Gates image-selection and file-preparation work before the user enters
    /// the picker or crop flow. Submission still rechecks admission because the
    /// read-only preview does not reserve quota.
    func requestImageImportEntryAdmission(
        prospectiveImageCount: Int
    ) async -> Bool {
        guard prospectiveImageCount > 0,
              prospectiveImageCount <= availableStagedCaptureSlots,
              !isCheckingScanAdmission,
              activePresentation == nil,
              !isRootPresentationDismissing else {
            return false
        }

        let existingItemCount = stagedCapture.totalItemCount
        let isRefining = baseRefinementContext != nil
        isCheckingScanAdmission = true
        defer { isCheckingScanAdmission = false }

        let flashFallbackEligible = Self.isImageImportFlashFallbackEligible(
            existingItemCount: existingItemCount,
            prospectiveImageCount: prospectiveImageCount,
            isRefining: isRefining
        )
        let route = await requestScanAdmission(
            flashFallbackEligible: flashFallbackEligible
        )
        guard route != nil,
              !Task.isCancelled,
              activePresentation == nil,
              !isRootPresentationDismissing,
              stagedCapture.totalItemCount == existingItemCount,
              (baseRefinementContext != nil) == isRefining,
              prospectiveImageCount <= availableStagedCaptureSlots else {
            return false
        }
        return true
    }

    nonisolated static func isImageImportFlashFallbackEligible(
        existingItemCount: Int,
        prospectiveImageCount: Int,
        isRefining: Bool
    ) -> Bool {
        !isRefining && existingItemCount == 0 && prospectiveImageCount == 1
    }

    /// Uses the local meter while offline or when the bounded caller-scoped
    /// preview proves transport is unavailable. Both fallbacks are queue-only;
    /// malformed, unauthorized, and server failures remain blocked. The
    /// Identify reservation remains authoritative.
    func requestScanAdmission(
        flashFallbackEligible: Bool
    ) async -> CaptureScanAdmissionRoute? {
        let canStartLocally: Bool
        if flashFallbackEligible {
            canStartLocally = diContainer.usageManager.canPerformScan(
                isProActive: diContainer.revenueCatManager.canStartProScan
            )
        } else {
            canStartLocally = diContainer.revenueCatManager.canStartProScan
        }

        let isOnline = diContainer.offlineQueueManager.isOnline
        let previewResult: ScanAdmissionPreviewResult?
        if isOnline {
            previewResult = await diContainer.scanAdmissionManager.preview(
                flashFallbackEligible: flashFallbackEligible
            )
        } else {
            previewResult = nil
        }
        guard !Task.isCancelled else { return nil }

        switch CaptureScanAdmissionPolicy.resolve(
            isOnline: isOnline,
            canStartLocally: canStartLocally,
            previewResult: previewResult
        ) {
        case .proceed(let route):
            return route
        case .paywall:
            presentScanAdmissionPaywall()
            return nil
        case .retryRequired:
            offlineToastMessage = .error(
                "Unable to check scan availability. Please try again."
            )
            return nil
        }
    }

    private func presentScanAdmissionPaywall() {
        AppTelemetry.trackPaywallImpression()
        activeSheet = .paywall
    }

    static func isFlashFallbackEligible(
        _ timeline: [CaptureSubmissionMediaItem],
        targetEradicationScanId: String? = nil
    ) -> Bool {
        guard targetEradicationScanId == nil, timeline.count == 1 else {
            return false
        }
        switch timeline[0] {
        case .image, .audio, .description:
            return true
        case .video:
            return false
        }
    }

    static func environmentContext(
        from task: Task<EnvironmentContext, Never>?,
        graceMilliseconds: Int
    ) async -> EnvironmentContextGraceResult {
        guard let task else {
            return EnvironmentContextGraceResult(context: nil, timedOut: false)
        }

        return await withCheckedContinuation { continuation in
            let gate = EnvironmentContextGraceGate(continuation)
            Task {
                gate.resolve(EnvironmentContextGraceResult(
                    context: await task.value,
                    timedOut: false
                ))
            }
            Task {
                try? await Task.sleep(for: .milliseconds(graceMilliseconds))
                gate.resolve(EnvironmentContextGraceResult(context: nil, timedOut: true))
            }
        }
    }

    nonisolated static func shouldOptimizeLiveImageAnalysis(
        hasStillImage: Bool,
        hasAudio: Bool,
        hasVideo: Bool,
        isGalleryPhoto: Bool
    ) -> Bool {
        hasStillImage && !hasAudio && !hasVideo && !isGalleryPhoto
    }

    nonisolated static func preferredGoalForSubmission(
        _ preferredGoal: FieldTripPreferredGoal?,
        hasCameraStill: Bool,
        hasGalleryStill: Bool,
        hasAudio: Bool,
        hasVideo: Bool
    ) -> FieldTripPreferredGoal? {
        guard hasCameraStill,
              !hasGalleryStill,
              !hasAudio,
              !hasVideo else {
            return nil
        }
        return preferredGoal
    }

    // MARK: - Inference Processing Change

    /// Consumes the app-wide paywall intent at the root presentation boundary.
    /// If Insight is already open, `activeSheet` performs its normal ordered
    /// dismissal and mounts the paywall only after UIKit releases that slot.
    func handlePaywallPresentationRequest(isRequested: Bool) {
        guard isRequested else { return }
        diContainer.usageManager.showPaywall = false
        AppTelemetry.trackPaywallImpression()
        activeSheet = .paywall
    }

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
    static func immediateForActiveScan(
        historicalContext: EnvironmentContext?,
        isGalleryPhoto: Bool,
        cachedLocation: CLLocation?,
        distanceMeters: Float?,
        zoomFactor: CGFloat?,
        defaultZoomFactor: CGFloat = 1.0
    ) -> CaptureTelemetry {
        if isGalleryPhoto {
            guard let historicalContext else {
                return CaptureTelemetry(
                    subjectDistanceInMeters: nil,
                    gpsLatitude: nil,
                    gpsLongitude: nil,
                    gpsElevation: nil,
                    locationName: nil,
                    weatherCondition: nil,
                    weatherTemperatureF: nil,
                    timeOfDay: nil,
                    timestamp: nil,
                    zoomFactor: nil,
                    estimatedSizeCm: nil
                )
            }
            return CaptureTelemetry(
                from: historicalContext,
                distance: nil,
                requiresExplicitCaptureDate: true
            )
        }

        return CaptureTelemetry(
            subjectDistanceInMeters: distanceMeters,
            gpsLatitude: cachedLocation?.coordinate.latitude,
            gpsLongitude: cachedLocation?.coordinate.longitude,
            gpsElevation: cachedLocation?.altitude,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            timeOfDay: nil,
            timestamp: DateUtilities.iso8601Formatter.string(from: Date()),
            zoomFactor: nonDefaultZoomFactor(zoomFactor, defaultZoomFactor: defaultZoomFactor),
            estimatedSizeCm: nil
        )
    }

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

        if isGalleryPhoto {
            guard let historicalContext else {
                return CaptureTelemetry(
                    subjectDistanceInMeters: nil, gpsLatitude: nil, gpsLongitude: nil, gpsElevation: nil,
                    locationName: nil, weatherCondition: nil, weatherTemperatureF: nil, timeOfDay: nil,
                    timestamp: nil, zoomFactor: nil, estimatedSizeCm: nil
                )
            }
            return CaptureTelemetry(
                from: historicalContext,
                distance: nil,
                requiresExplicitCaptureDate: true
            )
        } else if let context = resolvedContext {
            var estimatedSizeCm: Double?
            if let d = distanceMeters, let fd = firstImageData {
                estimatedSizeCm = await SizeEstimator.estimateSize(imageData: fd, distanceMeters: d)
            }
            return CaptureTelemetry(from: context, distance: distanceMeters, zoom: zoomToUse, estimatedSizeCm: estimatedSizeCm)
        } else if let hc = historicalContext {
            return CaptureTelemetry(from: hc, distance: nil)
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
