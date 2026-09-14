import Foundation
import Testing

@testable import Merian

@MainActor
@Suite("Inference Live Submission Coordinator")
struct InferenceLiveSubmissionCoordinatorTests {
    @Test func visualSubmissionStagesPresentationAndRegistersTask() async {
        let harness = InferenceLiveSubmissionHarness()
        let scanId = "visual-submission"
        let generation = UUID()
        let imageData = Data([0x01])
        let displayData = Data([0x11])
        let renderStart: CFAbsoluteTime = 42
        harness.presentation.lifecycle.prepareForNewScan(
            scanId: scanId,
            attemptGeneration: generation,
            modality: .visual
        )

        harness.subject.startVisual(.init(
            scanId: scanId,
            foregroundInferenceGeneration: generation,
            imageDatas: [imageData],
            displayDatas: [displayData],
            audioFilePaths: nil,
            videoFilePaths: nil,
            telemetry: harness.telemetry(distance: 1.75),
            observationContexts: [],
            mediaTimeline: nil,
            visualMediaItems: [.image(sourceIndex: 0)],
            preferredGoal: nil,
            modelContext: nil,
            targetEradicationScanId: nil,
            userPerceivedStart: renderStart
        ))

        #expect(harness.presentation.attempt.activeScanId == scanId)
        #expect(
            harness.presentation.attempt.activeAttemptGeneration
                == generation
        )
        #expect(
            harness.presentation.attempt.activeForegroundGeneration
                == generation
        )
        #expect(harness.presentation.state.isProcessing)
        #expect(
            harness.presentation.state.activeMedia.items
                == [.liveImage(displayData)]
        )
        #expect(
            harness.presentation.state.activeDistanceInMeters == 1.75
        )
        #expect(harness.presentation.state.activeLocationName == "Prairie")
        #expect(
            harness.presentation.presentation.isActiveVisual(
                attemptGeneration: generation
            )
        )
        harness.subject.recordFirstRenderedFrame(
            scanId: "another-scan",
            now: 44
        )
        #expect(harness.benchmarks.values.isEmpty)
        harness.subject.recordFirstRenderedFrame(scanId: scanId, now: 45)
        harness.subject.recordFirstRenderedFrame(scanId: scanId, now: 46)
        #expect(
            harness.benchmarks.values == [.tapToFirstRenderedFrame(3)]
        )
        #expect(harness.presentation.attempt.task != nil)
        #expect(harness.presentation.queueEvents.isEmpty)

        await harness.cancelTask()
    }

    @Test func audioSubmissionStagesListeningPresentationAndTask() async {
        let harness = InferenceLiveSubmissionHarness()
        let scanId = "audio-submission"
        let generation = UUID()

        harness.subject.startNonVisual(.init(
            scanId: scanId,
            foregroundInferenceGeneration: generation,
            audioFilePaths: ["clip.m4a"],
            videoFilePaths: nil,
            observationContexts: [],
            mediaTimeline: nil,
            telemetry: harness.telemetry(distance: 3.5),
            modelContext: nil,
            targetEradicationScanId: nil,
            userPerceivedStart: nil
        ))

        #expect(harness.presentation.attempt.activeScanId == scanId)
        #expect(
            harness.presentation.attempt.activeAttemptGeneration
                == generation
        )
        #expect(harness.presentation.state.isProcessing)
        #expect(harness.presentation.state.scanningPhaseText == "Listening")
        #expect(harness.presentation.state.activeDistanceInMeters == nil)
        #expect(
            harness.presentation.state.activeMedia.items
                == [.audio("/temporary/clip.m4a")]
        )
        #expect(
            !harness.presentation.presentation.isActiveVisual(
                attemptGeneration: generation
            )
        )
        #expect(harness.presentation.attempt.task != nil)

        await harness.cancelTask()
    }

    @Test func visualReplacementRejectsDisplacedFirstRenderMetric() async {
        let harness = InferenceLiveSubmissionHarness()
        let scanId = "same-scan-replacement"
        let generation = UUID()
        harness.presentation.presentation.activate(
            scanId: scanId,
            attemptGeneration: UUID(),
            modality: .visual
        )
        harness.presentation.presentation.beginFirstRenderMetric(
            scanId: scanId,
            startedAt: 12
        )

        harness.subject.startVisual(.init(
            scanId: scanId,
            foregroundInferenceGeneration: generation,
            imageDatas: [Data([0x01])],
            displayDatas: [],
            audioFilePaths: nil,
            videoFilePaths: nil,
            telemetry: harness.telemetry(),
            observationContexts: [],
            mediaTimeline: nil,
            visualMediaItems: nil,
            preferredGoal: nil,
            modelContext: nil,
            targetEradicationScanId: nil,
            userPerceivedStart: nil
        ))

        harness.subject.recordFirstRenderedFrame(scanId: scanId, now: 15)

        #expect(harness.benchmarks.values.isEmpty)
        await harness.cancelTask()
    }

    @Test func descriptionSubmissionPreservesDescribeCopy() async {
        let harness = InferenceLiveSubmissionHarness()

        harness.subject.startNonVisual(.init(
            scanId: nil,
            foregroundInferenceGeneration: nil,
            audioFilePaths: nil,
            videoFilePaths: nil,
            observationContexts: [
                ObservationContext(freeText: "orange wings")
            ],
            mediaTimeline: nil,
            telemetry: harness.telemetry(),
            modelContext: nil,
            targetEradicationScanId: nil,
            userPerceivedStart: nil
        ))

        #expect(
            harness.presentation.state.scanningPhaseText
                == "Identifying describe"
        )
        #expect(harness.presentation.attempt.task != nil)

        await harness.cancelTask()
    }

    @Test func authFenceReleasesAndRetiresVisualOwner() {
        let harness = InferenceLiveSubmissionHarness()
        let generation = UUID()
        #expect(harness.presentation.writes.beginAuthTransitionFence())
        defer {
            harness.presentation.writes.finishAuthTransitionFence()
        }

        harness.subject.startVisual(.init(
            scanId: "auth-fenced",
            foregroundInferenceGeneration: generation,
            imageDatas: [Data([0x01])],
            displayDatas: [],
            audioFilePaths: nil,
            videoFilePaths: nil,
            telemetry: harness.telemetry(),
            observationContexts: [],
            mediaTimeline: nil,
            visualMediaItems: nil,
            preferredGoal: nil,
            modelContext: nil,
            targetEradicationScanId: nil,
            userPerceivedStart: nil
        ))

        #expect(harness.presentation.queueEvents == [
            .release(
                "auth-fenced",
                generation,
                "auth_transition_active"
            ),
            .retire(
                "auth-fenced",
                generation,
                true,
                "auth_transition_active"
            )
        ])
        #expect(harness.presentation.attempt.task == nil)
        #expect(harness.presentation.attempt.activeScanId == nil)
    }

    @Test func emptyVisualReleasesThenRetiresDurableOwner() {
        let harness = InferenceLiveSubmissionHarness()
        let generation = UUID()

        harness.subject.startVisual(.init(
            scanId: "empty-visual",
            foregroundInferenceGeneration: generation,
            imageDatas: [],
            displayDatas: [],
            audioFilePaths: nil,
            videoFilePaths: nil,
            telemetry: harness.telemetry(),
            observationContexts: [],
            mediaTimeline: nil,
            visualMediaItems: nil,
            preferredGoal: nil,
            modelContext: nil,
            targetEradicationScanId: nil,
            userPerceivedStart: nil
        ))

        #expect(harness.presentation.queueEvents == [
            .release(
                "empty-visual",
                generation,
                "live_visual_payload_empty"
            ),
            .retire(
                "empty-visual",
                generation,
                true,
                "live_visual_payload_empty"
            )
        ])
        #expect(harness.presentation.attempt.task == nil)
    }

    @Test func emptyNonVisualRetiresWithoutReleasingUpload() {
        let harness = InferenceLiveSubmissionHarness()
        let generation = UUID()

        harness.subject.startNonVisual(.init(
            scanId: "empty-nonvisual",
            foregroundInferenceGeneration: generation,
            audioFilePaths: nil,
            videoFilePaths: nil,
            observationContexts: [],
            mediaTimeline: nil,
            telemetry: harness.telemetry(),
            modelContext: nil,
            targetEradicationScanId: nil,
            userPerceivedStart: nil
        ))

        #expect(harness.presentation.queueEvents == [
            .retire(
                "empty-nonvisual",
                generation,
                true,
                "live_nonvisual_payload_empty"
            )
        ])
        #expect(harness.presentation.attempt.task == nil)
    }
}

@MainActor
private final class InferenceLiveSubmissionHarness {
    let presentation = LivePipelinePresentationHarness()
    let benchmarks: InferenceSubmissionBenchmarkRecorder
    let subject: InferenceLiveSubmissionCoordinator

    init() {
        let benchmarks = InferenceSubmissionBenchmarkRecorder()
        self.benchmarks = benchmarks
        let completion = InferenceLiveCompletionCoordinator(
            attemptCoordinator: presentation.attempt,
            dependencies: .init(
                recordNewSpeciesDiscovered: {},
                transferReplacementMetadataAndDeleteOriginal: { _, _, _ in },
                recordCircuitSuccess: {},
                trackCompletedScan: { _, _ in },
                sendEvent: { _ in },
                notificationsEnabled: { false },
                sendInferenceCompleteNotification: { _, _ in },
                scheduleMilestoneProcessing: { _, _, _ in },
                commitFundingSettlement: { _ in true }
            )
        )
        let failure = InferenceLiveFailureCoordinator(
            attemptCoordinator: presentation.attempt,
            dependencies: .init(
                trackError: { _ in },
                recordCircuitFailure: {},
                requestPaywall: {},
                triggerErrorFeedback: {},
                logFailure: { _, _, _, _ in },
                logQueueHandoff: {}
            )
        )
        let request = InferenceLiveRequestService(dependencies: .init(
            encodeVisualImages: { images in
                images.map { _ in "encoded-image" }
            },
            uploadStagedVideoFiles: { _, _ in [] },
            identify: { _, _ in
                try await Task.sleep(for: .seconds(60))
                return Data()
            }
        ))
        let result = InferenceLiveResultService(dependencies: .init(
            parseAndSave: { _ in throw CancellationError() }
        ))
        let pipeline = InferenceLivePipelineCoordinator(
            attemptCoordinator: presentation.attempt,
            requestService: request,
            resultService: result,
            completionCoordinator: completion,
            failureCoordinator: failure,
            dependencies: .init(
                isCircuitTripped: { false },
                refundScan: { _ in },
                logAdmission: { _, _ in },
                logEmptyVisualEncoding: {},
                logBenchmark: { benchmark in
                    benchmarks.record(benchmark)
                }
            )
        )
        let mediaProjector = InferenceLiveMediaProjector(
            dependencies: .init(
                documentsDirectory: URL(
                    fileURLWithPath: "/documents",
                    isDirectory: true
                ),
                temporaryDirectory: URL(
                    fileURLWithPath: "/temporary",
                    isDirectory: true
                ),
                fileExists: { _ in false },
                secureRemoteURL: { URL(string: $0) }
            )
        )
        subject = InferenceLiveSubmissionCoordinator(
            attemptCoordinator: presentation.attempt,
            writeCoordinator: presentation.writes,
            sessionLifecycleCoordinator: presentation.lifecycle,
            presentationCoordinator: presentation.presentation,
            presentationState: presentation.state,
            localAnalysisCoordinator: presentation.localAnalysis,
            mediaProjector: mediaProjector,
            pipelineCoordinator: pipeline,
            pipelinePresentationCoordinator: presentation.subject
        )
    }

    func telemetry(distance: Float? = nil) -> CaptureTelemetry {
        CaptureTelemetry(
            subjectDistanceInMeters: distance,
            gpsLatitude: 41.88,
            gpsLongitude: -87.63,
            gpsElevation: 181,
            locationName: "Prairie",
            weatherCondition: "Clear",
            weatherTemperatureF: 72,
            timeOfDay: "afternoon",
            timestamp: "2026-09-13T12:00:00Z",
            zoomFactor: nil,
            estimatedSizeCm: nil
        )
    }

    func cancelTask() async {
        guard let task = presentation.attempt.task else { return }
        task.cancel()
        _ = await task.result
        presentation.attempt.clearCurrentTask()
    }
}

@MainActor
private final class InferenceSubmissionBenchmarkRecorder {
    private(set) var values: [InferenceLivePipelineCoordinator.Benchmark] = []

    func record(_ benchmark: InferenceLivePipelineCoordinator.Benchmark) {
        values.append(benchmark)
    }
}
