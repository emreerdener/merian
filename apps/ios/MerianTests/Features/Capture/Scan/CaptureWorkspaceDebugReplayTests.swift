#if DEBUG && targetEnvironment(simulator)
import Foundation
import XCTest

@testable import Merian

extension CaptureWorkspaceViewModelRefinementTests {
    func testDebugReplayStagesAudioForManualIdentifyWithoutSubmitting() async throws {
        let viewModel = try await makeDebugReplayWorkspace()
        let url = URL.documentsDirectory.appendingPathComponent("replay-test-\(UUID().uuidString).wav")
        try makeInferenceTestPCM16WAVData().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let task = try XCTUnwrap(viewModel.startDebugReplay(.audio, prepare: { _, _, _ in .audio(url) }))
        await task.value

        XCTAssertEqual(viewModel.stagedCapture.audios.map(\.filePath), [url.lastPathComponent])
        XCTAssertTrue(viewModel.shouldPresentActiveScanToolbar)
        XCTAssertFalse(viewModel.isAutomaticStagedSubmissionPending)
        XCTAssertFalse(viewModel.isCapturing)
        XCTAssertNil(viewModel.pendingAnalyzeScanId)
        XCTAssertNil(viewModel.activeSheet)
        XCTAssertNil(viewModel.startDebugReplay(.audio))
        viewModel.clearStagedCaptureAndCropState(discardStagedMediaFiles: true)
    }

    func testCancelledDebugReplayCannotStageLateResultOrResetReplacementCapture() async throws {
        let viewModel = try await makeDebugReplayWorkspace()
        let url = URL.documentsDirectory.appendingPathComponent("replay-test-\(UUID().uuidString).wav")
        try makeInferenceTestPCM16WAVData().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let gate = ReplayWorkspaceGate()
        let task = try XCTUnwrap(viewModel.startDebugReplay(.audio, prepare: { _, _, _ in
            await gate.suspend()
            return .audio(url) // Deliberately ignores cancellation.
        }))
        await gate.waitForStart()
        viewModel.handleVisualCaptureInterruption()
        XCTAssertFalse(viewModel.isCapturing)
        viewModel.isCapturing = true // A replacement shutter now owns the busy state.
        await gate.release()
        await task.value

        XCTAssertTrue(viewModel.stagedCapture.isEmpty)
        XCTAssertTrue(viewModel.isCapturing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(viewModel.offlineToastMessage)
        viewModel.isCapturing = false
    }

    func testDebugReplayRejectsResultAfterAccountChanges() async throws {
        let viewModel = try await makeDebugReplayWorkspace()
        let url = URL.documentsDirectory.appendingPathComponent("replay-test-\(UUID().uuidString).wav")
        try makeInferenceTestPCM16WAVData().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let gate = ReplayWorkspaceGate()
        let task = try XCTUnwrap(viewModel.startDebugReplay(.audio, prepare: { _, _, _ in
            await gate.suspend()
            return .audio(url)
        }))
        await gate.waitForStart()
        viewModel.diContainer.appRouteCoordinator.beginAccountSession(
            accountID: "synthetic-replay-account", origin: .runtimeTransition, now: Date()
        )
        await gate.release()
        await task.value

        XCTAssertTrue(viewModel.stagedCapture.isEmpty)
        XCTAssertFalse(viewModel.isCapturing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDebugVideoReplayStagesFiveFramesWithoutAutomaticSubmission() async throws {
        let viewModel = try await makeDebugReplayWorkspace()
        let previousConfirmation = viewModel.diContainer.appSettings.requiresScanConfirmation
        let previousMultiCapture = viewModel.diContainer.appSettings.isMultiCaptureEnabled
        viewModel.diContainer.appSettings.requiresScanConfirmation = false
        viewModel.diContainer.appSettings.isMultiCaptureEnabled = false
        defer {
            viewModel.diContainer.appSettings.requiresScanConfirmation = previousConfirmation
            viewModel.diContainer.appSettings.isMultiCaptureEnabled = previousMultiCapture
        }
        let frame = PreparedCaptureScanStill(
            inferenceData: makePNGData(), displayData: makePNGData(),
            previewCGImage: SendableCGImage(image: makePreviewCGImage())
        )
        let video = PreparedCaptureScanVideo(
            sampledFrames: Array(repeating: frame, count: 5), audioFilePath: "synthetic-companion.wav",
            playback: .init(fileURL: URL.documentsDirectory.appendingPathComponent("synthetic-playback.mp4"),
                            isCompressed: true, originalBytes: 2, playbackBytes: 1, preparationDuration: 0)
        )
        let task = try XCTUnwrap(viewModel.startDebugReplay(.video, prepare: { _, _, _ in .video(video) }))
        await task.value
        let staged = try XCTUnwrap(viewModel.stagedCapture.videos.first)
        XCTAssertEqual(staged.sampledImages.count, 5)
        XCTAssertTrue(staged.sampledImages.allSatisfy { $0.original.isFromGallery })
        XCTAssertEqual(staged.audioFilePath, video.audioFilePath)
        XCTAssertTrue(viewModel.shouldAutoSubmitStagedCapture)
        XCTAssertFalse(viewModel.isAutomaticStagedSubmissionPending)
        XCTAssertTrue(viewModel.shouldPresentActiveScanToolbar)
        XCTAssertNil(viewModel.pendingAnalyzeScanId)
    }

    private func makeDebugReplayWorkspace() async throws -> CaptureWorkspaceViewModel {
        let container = AppDIContainer.preview
        let viewModel = CaptureWorkspaceViewModel(
            diContainer: container,
            dependencies: .live(diContainer: container),
            prewarmHeadersOnInit: false
        )
        // The native test host can still be completing its launch account restoration.
        // Exercise replay only after the same local readiness guard used by its menu.
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) { viewModel.canStartDebugReplay }
        return viewModel
    }
}

private actor ReplayWorkspaceGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation {
            continuation = $0
            started?.resume()
            started = nil
        }
    }

    func waitForStart() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
#endif
