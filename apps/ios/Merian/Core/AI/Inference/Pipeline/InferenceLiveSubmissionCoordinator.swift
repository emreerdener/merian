import Foundation
import SwiftData

/// Starts one visual or nonvisual live inference submission.
///
/// This coordinator owns admission, media and telemetry staging, presentation
/// activation, optional local visual analysis, and task launch order. The
/// focused attempt owner remains the sole task and identity owner, while the
/// pipeline and presentation coordinators retain execution and callback
/// ownership. No networking, persistence, logging, filesystem, or singleton
/// dependency is resolved here.
@MainActor
final class InferenceLiveSubmissionCoordinator {
    struct VisualSubmission {
        let scanId: String?
        let foregroundInferenceGeneration: UUID?
        let imageDatas: [Data]
        let displayDatas: [Data]
        let audioFilePaths: [String]?
        let videoFilePaths: [String]?
        let telemetry: CaptureTelemetry
        let observationContexts: [ObservationContext]
        let mediaTimeline: [CaptureSubmissionMediaItem]?
        let visualMediaItems: [IdentifyVisualMediaItem]?
        let preferredGoal: FieldTripPreferredGoal?
        let modelContext: ModelContext?
        let targetEradicationScanId: String?
        let userPerceivedStart: CFAbsoluteTime?
    }

    struct NonVisualSubmission {
        let scanId: String?
        let foregroundInferenceGeneration: UUID?
        let audioFilePaths: [String]?
        let videoFilePaths: [String]?
        let observationContexts: [ObservationContext]
        let mediaTimeline: [CaptureSubmissionMediaItem]?
        let telemetry: CaptureTelemetry
        let modelContext: ModelContext?
        let targetEradicationScanId: String?
        let userPerceivedStart: CFAbsoluteTime?
    }

    private let attemptCoordinator: InferenceLiveAttemptCoordinator
    private let writeCoordinator: InferenceWriteCoordinator
    private let sessionLifecycleCoordinator:
        InferenceSessionLifecycleCoordinator
    private let presentationCoordinator: InferencePresentationCoordinator
    private let presentationState: InferencePresentationState
    private let localAnalysisCoordinator: InferenceLocalAnalysisCoordinator
    private let mediaProjector: InferenceLiveMediaProjector
    private let pipelineCoordinator: InferenceLivePipelineCoordinator
    private let pipelinePresentationCoordinator:
        InferenceLivePresentationCoordinator

    init(
        attemptCoordinator: InferenceLiveAttemptCoordinator,
        writeCoordinator: InferenceWriteCoordinator,
        sessionLifecycleCoordinator: InferenceSessionLifecycleCoordinator,
        presentationCoordinator: InferencePresentationCoordinator,
        presentationState: InferencePresentationState,
        localAnalysisCoordinator: InferenceLocalAnalysisCoordinator,
        mediaProjector: InferenceLiveMediaProjector,
        pipelineCoordinator: InferenceLivePipelineCoordinator,
        pipelinePresentationCoordinator:
            InferenceLivePresentationCoordinator
    ) {
        self.attemptCoordinator = attemptCoordinator
        self.writeCoordinator = writeCoordinator
        self.sessionLifecycleCoordinator = sessionLifecycleCoordinator
        self.presentationCoordinator = presentationCoordinator
        self.presentationState = presentationState
        self.localAnalysisCoordinator = localAnalysisCoordinator
        self.mediaProjector = mediaProjector
        self.pipelineCoordinator = pipelineCoordinator
        self.pipelinePresentationCoordinator =
            pipelinePresentationCoordinator
    }

    func startVisual(_ submission: VisualSubmission) {
        guard !writeCoordinator.isAuthTransitionFenceActive else {
            attemptCoordinator.releaseAndRetire(
                scanId: submission.scanId,
                foregroundGeneration:
                    submission.foregroundInferenceGeneration,
                resumeBackground: true,
                reason: "auth_transition_active"
            )
            return
        }
        guard !submission.imageDatas.isEmpty else {
            attemptCoordinator.releaseAndRetire(
                scanId: submission.scanId,
                foregroundGeneration:
                    submission.foregroundInferenceGeneration,
                resumeBackground: true,
                reason: "live_visual_payload_empty"
            )
            return
        }
        guard let session = pipelineCoordinator.admit(
            scanId: submission.scanId,
            foregroundGeneration:
                submission.foregroundInferenceGeneration,
            modality: .visual
        ) else {
            return
        }

        sessionLifecycleCoordinator.prepareForVisualAnalysis()
        let mediaProjection = mediaProjector.projectVisual(
            imageDatas: submission.imageDatas,
            displayDatas: submission.displayDatas,
            audioFilePaths: submission.audioFilePaths,
            videoFilePaths: submission.videoFilePaths,
            observationContexts: submission.observationContexts,
            mediaTimeline: submission.mediaTimeline,
            visualMediaItems: submission.visualMediaItems
        )
        let projectedMediaTimeline = mediaProjection.mediaTimeline
        presentationState.stageVisualMedia(mediaProjection.activeMedia)

        pipelineCoordinator.activate(session)
        presentationCoordinator.activate(
            scanId: submission.scanId,
            attemptGeneration: session.attemptGeneration,
            modality: .visual
        )
        presentationState.applyVisualTelemetry(submission.telemetry)

        if let firstData = submission.imageDatas.first {
            startLocalClassification(
                from: firstData,
                focusRegion:
                    submission.visualMediaItems?.first?.focusRegion
            )
        }

        if let userPerceivedStart = submission.userPerceivedStart {
            presentationCoordinator.beginFirstRenderMetric(
                scanId: session.resolvedClientScanId,
                startedAt: userPerceivedStart
            )
        }

        let request = InferenceLivePipelineCoordinator.VisualRequest(
            session: session,
            compressedImages: submission.imageDatas,
            displayImages: submission.displayDatas,
            submissionProjection: mediaProjection.submission,
            ownerMediaTimeline: mediaProjection.ownerMediaTimeline,
            mediaTimeline: projectedMediaTimeline,
            visualMediaItems: submission.visualMediaItems,
            telemetry: submission.telemetry,
            preferredGoal: submission.preferredGoal,
            modelContext: submission.modelContext,
            targetEradicationScanId:
                submission.targetEradicationScanId
        )
        attemptCoordinator.replaceTask(Task { [weak self] in
            guard let self else { return }
            await self.pipelineCoordinator.executeVisual(
                request,
                callbacks: self.pipelinePresentationCoordinator
                    .makeVisualCallbacks(
                        for: session,
                        persistedMediaItems: { [weak self] imagePaths in
                            self?.mediaProjector.persistedMediaItems(
                                from: projectedMediaTimeline,
                                imagePaths: imagePaths
                            )
                        },
                        modelContainer:
                            submission.modelContext?.container,
                        referencePolicy:
                            .showLoadingWhenReferenceMissing
                    )
            )
        })
    }

    func startNonVisual(_ submission: NonVisualSubmission) {
        guard !writeCoordinator.isAuthTransitionFenceActive else {
            attemptCoordinator.releaseAndRetire(
                scanId: submission.scanId,
                foregroundGeneration:
                    submission.foregroundInferenceGeneration,
                resumeBackground: true,
                reason: "auth_transition_active"
            )
            return
        }
        let mediaProjection = mediaProjector.projectNonVisual(
            audioFilePaths: submission.audioFilePaths,
            videoFilePaths: submission.videoFilePaths,
            observationContexts: submission.observationContexts,
            mediaTimeline: submission.mediaTimeline
        )

        guard !mediaProjection.media.mediaTimeline.isEmpty else {
            if let scanId = submission.scanId,
               let foregroundInferenceGeneration =
                   submission.foregroundInferenceGeneration {
                attemptCoordinator.retireForegroundInference(
                    scanId: scanId,
                    generation: foregroundInferenceGeneration,
                    resumeBackground: true,
                    reason: "live_nonvisual_payload_empty"
                )
            }
            return
        }
        guard let session = pipelineCoordinator.admit(
            scanId: submission.scanId,
            foregroundGeneration:
                submission.foregroundInferenceGeneration,
            modality: .nonVisual(
                hasAudio: mediaProjection.hasAudioInput
            )
        ) else {
            return
        }

        sessionLifecycleCoordinator.prepareForNonVisualAnalysis(
            scanId: submission.scanId,
            attemptGeneration: session.attemptGeneration
        )
        presentationState.setScanningPhaseText(
            mediaProjection.media.submission.audioFilePaths.isEmpty
                ? "Identifying describe"
                : "Listening"
        )

        pipelineCoordinator.activate(session)
        presentationCoordinator.activate(
            scanId: submission.scanId,
            attemptGeneration: session.attemptGeneration,
            modality: .nonVisual
        )
        presentationState.applyNonVisualTelemetry(submission.telemetry)
        presentationState.replaceActiveMedia(
            mediaProjection.media.activeMedia
        )

        if let userPerceivedStart = submission.userPerceivedStart {
            presentationCoordinator.beginFirstRenderMetric(
                scanId: session.resolvedClientScanId,
                startedAt: userPerceivedStart
            )
        }

        let request = InferenceLivePipelineCoordinator.NonVisualRequest(
            session: session,
            submissionProjection: mediaProjection.media.submission,
            ownerMediaTimeline:
                mediaProjection.media.ownerMediaTimeline,
            mediaTimeline: mediaProjection.media.mediaTimeline,
            telemetry: submission.telemetry,
            modelContext: submission.modelContext,
            targetEradicationScanId:
                submission.targetEradicationScanId
        )
        attemptCoordinator.replaceTask(Task { [weak self] in
            guard let self else { return }
            await self.pipelineCoordinator.executeNonVisual(
                request,
                callbacks: self.pipelinePresentationCoordinator
                    .makeCallbacks(
                        for: session,
                        persistedMediaItems: { _ in nil },
                        modelContainer:
                            submission.modelContext?.container,
                        referencePolicy: .none
                    )
            )
        })
    }

    func recordFirstRenderedFrame(
        scanId: String,
        now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    ) {
        guard let startedAt = presentationCoordinator
            .consumeFirstRenderStart(scanId: scanId) else {
            return
        }
        pipelineCoordinator.recordBenchmark(
            .tapToFirstRenderedFrame(now - startedAt)
        )
    }

    @discardableResult
    private func startLocalClassification(
        from data: Data,
        focusRegion: NormalizedImageFocusRegion?
    ) -> Task<Void, Never>? {
        guard let attemptGeneration =
            attemptCoordinator.activeAttemptGeneration else {
            return nil
        }
        let session = InferenceLocalAnalysisCoordinator.Session(
            scanId: attemptCoordinator.activeScanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration:
                attemptCoordinator.activeForegroundGeneration
        )
        return localAnalysisCoordinator.start(
            imageData: data,
            focusRegion: focusRegion,
            session: session,
            isCurrent: { [weak self] session in
                self?.isLocalAnalysisCurrent(session) == true
            },
            publishPhrase: { [weak self] phrase in
                self?.presentationState.setScanningPhaseText(phrase)
            }
        )
    }

    private func isLocalAnalysisCurrent(
        _ session: InferenceLocalAnalysisCoordinator.Session
    ) -> Bool {
        guard presentationCoordinator.isActiveVisual(
            attemptGeneration: session.attemptGeneration
        ) else {
            return false
        }
        return attemptCoordinator.isAttemptCurrent(
            scanId: session.scanId,
            attemptGeneration: session.attemptGeneration,
            foregroundGeneration: session.foregroundGeneration
        )
    }

    #if DEBUG
    @discardableResult
    func debugStartLocalClassification(
        from data: Data,
        focusRegion: NormalizedImageFocusRegion?
    ) -> Task<Void, Never>? {
        startLocalClassification(from: data, focusRegion: focusRegion)
    }

    func debugIsLocalAnalysisCurrent(
        _ session: InferenceLocalAnalysisCoordinator.Session
    ) -> Bool {
        isLocalAnalysisCurrent(session)
    }
    #endif
}
