import CoreLocation
import XCTest

@testable import Merian

@MainActor
final class CaptureScanDependenciesTests: XCTestCase {
    func testFocusUsesInjectedCameraAndFeedbackActions() {
        let spy = CaptureScanDependencySpy()
        let viewModel = makeViewModel(spy: spy)
        let point = CGPoint(x: 0.25, y: 0.75)

        viewModel.handleFocusTap(devicePoint: point)

        XCTAssertEqual(spy.focusPoints, [point])
        XCTAssertEqual(spy.selectionCount, 1)
    }

    func testVideoStopAndCancelUseInjectedCameraActions() {
        let spy = CaptureScanDependencySpy()
        let viewModel = makeViewModel(spy: spy)

        viewModel.stopVideoCapture()
        XCTAssertEqual(spy.stopVideoCount, 0)

        viewModel.isVideoRecording = true
        viewModel.stopVideoCapture()
        XCTAssertEqual(spy.stopVideoCount, 1)

        viewModel.isCapturing = true
        viewModel.videoRecordingProgress = 0.75
        viewModel.cancelVideoCapture()

        XCTAssertEqual(spy.cancelVideoCount, 1)
        XCTAssertFalse(viewModel.isCapturing)
        XCTAssertFalse(viewModel.isVideoRecording)
        XCTAssertEqual(viewModel.videoRecordingProgress, 0)
    }

    func testZoomFeedbackUsesInjectedSemanticActions() {
        let spy = CaptureScanDependencySpy()
        let viewModel = makeViewModel(spy: spy)

        viewModel.triggerZoomOpticalStopFeedback()
        viewModel.triggerZoomTickFeedback()

        XCTAssertEqual(spy.zoomOpticalStopCount, 1)
        XCTAssertEqual(spy.zoomTickCount, 1)
    }

    private func makeViewModel(
        spy: CaptureScanDependencySpy
    ) -> CaptureWorkspaceViewModel {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let scanDependencies = CaptureScanDependencies(
            camera: CaptureScanCameraDependencies(
                setFocusPoint: { spy.focusPoints.append($0) },
                captureImage: { Data() },
                recordVideo: { _, _ in throw CancellationError() },
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
                saveImage: { _, _ in },
                saveVideo: { _, _ in }
            ),
            media: CaptureScanMediaDependencies(
                prepareStill: { _ in nil },
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
        let dependencies = CaptureWorkspaceDependencies(
            scan: scanDependencies,
            submission: .live(diContainer: AppDIContainer.shared),
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
}

@MainActor
private final class CaptureScanDependencySpy {
    var focusPoints: [CGPoint] = []
    var selectionCount = 0
    var zoomOpticalStopCount = 0
    var zoomTickCount = 0
    var stopVideoCount = 0
    var cancelVideoCount = 0
}
