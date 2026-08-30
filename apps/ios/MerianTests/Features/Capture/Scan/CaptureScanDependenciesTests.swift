import CoreLocation
import Testing

@testable import Merian

@Suite("Capture scan dependencies")
@MainActor
struct CaptureScanDependenciesTests {
    @Test func testFocusUsesInjectedCameraAndFeedbackActions() {
        let spy = CaptureScanDependencySpy()
        let viewModel = makeViewModel(spy: spy)
        let point = CGPoint(x: 0.25, y: 0.75)

        viewModel.handleFocusTap(devicePoint: point)

        #expect(spy.focusPoints == [point])
        #expect(spy.selectionCount == 1)
    }

    @Test func testVideoStopAndCancelUseInjectedCameraActions() {
        let spy = CaptureScanDependencySpy()
        let viewModel = makeViewModel(spy: spy)

        viewModel.stopVideoCapture()
        #expect(spy.stopVideoCount == 0)

        viewModel.isVideoRecording = true
        viewModel.stopVideoCapture()
        #expect(spy.stopVideoCount == 1)

        viewModel.isCapturing = true
        viewModel.videoRecordingProgress = 0.75
        viewModel.cancelVideoCapture()

        #expect(spy.cancelVideoCount == 1)
        #expect(!viewModel.isCapturing)
        #expect(!viewModel.isVideoRecording)
        #expect(viewModel.videoRecordingProgress == 0)
    }

    @Test func testZoomFeedbackUsesInjectedSemanticActions() {
        let spy = CaptureScanDependencySpy()
        let viewModel = makeViewModel(spy: spy)

        viewModel.triggerZoomOpticalStopFeedback()
        viewModel.triggerZoomTickFeedback()

        #expect(spy.zoomOpticalStopCount == 1)
        #expect(spy.zoomTickCount == 1)
    }

    @Test func testLifecycleInterruptionFencesOverlappingStillCapture() async {
        let spy = CaptureScanDependencySpy()
        let controlledCapture = ControlledStillCapture()
        let viewModel = makeViewModel(
            spy: spy,
            captureImage: { try await controlledCapture.capture() }
        )

        viewModel.executeCapture(emitHaptic: false)
        #expect(await waitUntil { controlledCapture.hasStarted })

        viewModel.handleVisualCaptureInterruption()
        controlledCapture.succeed(with: Data([1, 2, 3]))
        #expect(await waitUntil { !viewModel.isCapturing })
        await Task.yield()

        #expect(!viewModel.isCapturing)
        #expect(viewModel.stagedCapture.isEmpty)
        #expect(spy.saveImageCount == 0)
        #expect(spy.prepareStillCount == 0)
    }

    @Test func testLifecycleInterruptionCancelsVideoWaitingOnAdmission() async {
        let spy = CaptureScanDependencySpy()
        let controlledAdmission = ControlledScanAdmission()
        let viewModel = makeViewModel(
            spy: spy,
            admissionIsOnline: true,
            admissionPreview: {
                await controlledAdmission.preview()
            }
        )

        viewModel.startVideoCapture()
        #expect(await waitUntil { controlledAdmission.hasStarted })

        viewModel.handleVisualCaptureInterruption()
        controlledAdmission.succeed()
        #expect(await waitUntil { !viewModel.isCapturing })
        await Task.yield()

        #expect(!viewModel.isCapturing)
        #expect(!viewModel.isVideoRecording)
        #expect(viewModel.stagedCapture.isEmpty)
        #expect(spy.recordVideoCount == 0)
        #expect(spy.cancelVideoCount == 1)
    }

    private func makeViewModel(
        spy: CaptureScanDependencySpy,
        captureImage: @escaping @MainActor @Sendable () async throws -> Data = {
            Data()
        },
        admissionIsOnline: Bool = false,
        admissionPreview: @escaping @MainActor @Sendable () async ->
            ScanAdmissionPreviewResult = {
                .unavailable
            }
    ) -> CaptureWorkspaceViewModel {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let scanDependencies = CaptureScanDependencies(
            camera: CaptureScanCameraDependencies(
                setFocusPoint: { spy.focusPoints.append($0) },
                captureImage: captureImage,
                recordVideo: { _, _ in
                    spy.recordVideoCount += 1
                    throw CancellationError()
                },
                stopVideoRecording: { spy.stopVideoCount += 1 },
                cancelVideoRecording: { spy.cancelVideoCount += 1 }
            ),
            context: CaptureScanContextDependencies(
                requestCurrentLocation: { nil },
                lastKnownLocation: { nil },
                fetchDeferredContext: {
                    EnvironmentContext(location: $0)
                }
            ),
            library: CaptureScanLibraryDependencies(
                saveImage: { _, _ in spy.saveImageCount += 1 },
                saveVideo: { _, _ in }
            ),
            media: CaptureScanMediaDependencies(
                prepareStill: { _ in
                    await MainActor.run {
                        spy.prepareStillCount += 1
                    }
                    return nil
                },
                prepareVideo: { _ in throw CancellationError() }
            ),
            canStartProScan: { true },
            feedback: CaptureScanFeedbackDependencies(
                selection: { spy.selectionCount += 1 },
                zoomOpticalStop: { spy.zoomOpticalStopCount += 1 },
                zoomTick: { spy.zoomTickCount += 1 },
                photoCapture: {},
                videoStarted: {},
                videoCompleted: {},
                success: {},
                error: {}
            )
        )
        let submissionDependencies = CaptureSubmissionDependencies(
            context: CaptureSubmissionContextDependencies(
                lastKnownLocation: { nil },
                fetchDeferredContext: {
                    EnvironmentContext(location: $0)
                }
            ),
            admission: CaptureSubmissionAdmissionDependencies(
                isOnline: { admissionIsOnline },
                canStartLocally: { _ in true },
                preview: { _ in await admissionPreview() }
            ),
            deferredContext: CaptureSubmissionDeferredContextService(
                persistLocally: { _, _ in },
                endpoint: CaptureSubmissionDeferredContextEndpoint(
                    update: { _, _ in }
                ),
                waitBeforeRetry: {}
            )
        )
        let dependencies = CaptureWorkspaceDependencies(
            scan: scanDependencies,
            submission: submissionDependencies,
            prepareImage: { _ in nil },
            prepareHistoricalAudio: { _ in nil },
            externalImageImports: ExternalImageImportStore(rootURL: rootURL),
            downloadRefinementImage: { _ in nil },
            prewarmConnections: {},
            sharedExplorePostId: { _ in nil },
            captureGoalAccountId: { $0?.uuidString },
            feedback: CaptureWorkspaceFeedback(
                selection: { _ in },
                sheet: { _ in },
                medium: {},
                error: {}
            )
        )

        return CaptureWorkspaceViewModel(
            diContainer: AppDIContainer.shared,
            dependencies: dependencies,
            prewarmHeadersOnInit: false
        )
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
        return condition()
    }
}

@MainActor
private final class CaptureScanDependencySpy {
    var focusPoints: [CGPoint] = []
    var selectionCount = 0
    var zoomOpticalStopCount = 0
    var zoomTickCount = 0
    var stopVideoCount = 0
    var cancelVideoCount = 0
    var recordVideoCount = 0
    var saveImageCount = 0
    var prepareStillCount = 0
}

@MainActor
private final class ControlledStillCapture {
    private var continuation: CheckedContinuation<Data, Error>?

    var hasStarted: Bool {
        continuation != nil
    }

    func capture() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func succeed(with data: Data) {
        continuation?.resume(returning: data)
        continuation = nil
    }
}

@MainActor
private final class ControlledScanAdmission {
    private var continuation:
        CheckedContinuation<ScanAdmissionPreviewResult, Never>?

    var hasStarted: Bool {
        continuation != nil
    }

    func preview() async -> ScanAdmissionPreviewResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func succeed() {
        continuation?.resume(returning: .available(ScanAdmissionPreview(
            decision: .allowed,
            effectivePlan: "pro_paid",
            dailyLimit: nil,
            dailyRemaining: nil
        )))
        continuation = nil
    }
}
