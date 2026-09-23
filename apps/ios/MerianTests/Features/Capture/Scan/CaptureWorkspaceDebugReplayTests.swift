#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftData
import XCTest

@testable import Merian

extension CaptureWorkspaceViewModelRefinementTests {
    func testDebugReplayStagesAudioForManualIdentifyWithoutSubmitting() async throws {
        let viewModel = try await makeDebugReplayWorkspace()
        let url = URL.documentsDirectory.appendingPathComponent("replay-test-\(UUID().uuidString).wav")
        try makeInferenceTestPCM16WAVData().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let task = try XCTUnwrap(viewModel.startDebugReplay(
            .audio, profile: .audioMinimalV1, prepare: { _, _, _ in .audio(url) }
        ))
        await task.value

        XCTAssertEqual(viewModel.stagedCapture.audios.map(\.filePath), [url.lastPathComponent])
        XCTAssertTrue(viewModel.shouldPresentActiveScanToolbar)
        XCTAssertFalse(viewModel.isAutomaticStagedSubmissionPending)
        XCTAssertFalse(viewModel.isCapturing)
        XCTAssertNil(viewModel.pendingAnalyzeScanId)
        XCTAssertNil(viewModel.activeSheet)
        XCTAssertTrue(viewModel.hasFixedContextDebugReplay)
        XCTAssertTrue(viewModel.canSubmitFixedContextDebugReplay)
        XCTAssertNil(viewModel.startDebugReplay(.audio))
        viewModel.clearStagedCaptureAndCropState(discardStagedMediaFiles: true)
        XCTAssertFalse(viewModel.hasFixedContextDebugReplay)
    }

    func testCancelledDebugReplayCannotStageLateResultOrResetReplacementCapture() async throws {
        let viewModel = try await makeDebugReplayWorkspace()
        let url = URL.documentsDirectory.appendingPathComponent("replay-test-\(UUID().uuidString).wav")
        try makeInferenceTestPCM16WAVData().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let gate = ReplayWorkspaceGate()
        let task = try XCTUnwrap(viewModel.startDebugReplay(.audio, profile: .audioMinimalV1, prepare: { _, _, _ in
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
        XCTAssertFalse(viewModel.hasFixedContextDebugReplay)
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
        let task = try XCTUnwrap(viewModel.startDebugReplay(.audio, profile: .audioMinimalV1, prepare: { _, _, _ in
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
        XCTAssertFalse(viewModel.hasFixedContextDebugReplay)
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

    func testFixedContextReplayRejectsMixedEvidenceBeforeAdmission() async throws {
        let viewModel = try await makeDebugReplayWorkspace()
        XCTAssertNil(viewModel.startDebugReplay(.video, profile: .audioMinimalV1))
        viewModel.stagedCapture.audios = [StagedAudio(
            filePath: "synthetic.wav", debugReplayProfile: .audioMinimalV1
        )]
        let originalSnapshot = CaptureSubmissionAdmissionSnapshot(viewModel.stagedCapture)
        viewModel.stagedCapture.audios[0].debugReplayProfile = nil
        XCTAssertNotEqual(CaptureSubmissionAdmissionSnapshot(viewModel.stagedCapture), originalSnapshot)
        viewModel.stagedCapture.audios[0].debugReplayProfile = .audioMinimalV1
        viewModel.stagedCapture.observationContexts = [StagedObservationContext(
            context: ObservationContext(freeText: "Synthetic observation")
        )]
        await viewModel.submitStagedCapture(modelContext: try makeModelContext())
        XCTAssertEqual(viewModel.offlineToastMessage?.title,
                       "Fixed-context replay requires one audio sample with no other staged items.")
        XCTAssertEqual(viewModel.stagedCapture.totalItemCount, 2)
        XCTAssertFalse(viewModel.isCheckingScanAdmission)
        XCTAssertNil(viewModel.pendingAnalyzeScanId)
    }

    func testFixedContextQueueOmitsLiveContextAndOrdinaryCaptureRemainsIndependent() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }
        let probe = ReplayContextProbe()
        let viewModel = makeContextReplayWorkspace(probe: probe)
        let queue = viewModel.diContainer.offlineQueueManager
        let previousOnline = queue.isOnline
        let context = try makeModelContext()
        queue.modelContext = context
        queue.isOnline = false
        defer {
            cleanupQueuedScans(in: context)
            queue.isOnline = previousOnline
        }
        let filename = try makeTempAudioFilename()
        viewModel.stagedCapture.audios = [StagedAudio(
            filePath: filename, debugReplayProfile: .audioMinimalV1
        )]
        let prefetch = Task { EnvironmentContext(location: nil, locationName: "Synthetic prefetched context") }
        viewModel.preFetchTask = prefetch
        let accepted = await viewModel.submitNonVisualCapture(
            audioFileNames: [filename], observationContexts: [], mediaTimeline: [.audio(filename)],
            modelContext: context, admissionRoute: .queued
        )
        XCTAssertTrue(accepted)
        XCTAssertTrue(prefetch.isCancelled)
        XCTAssertEqual(probe.locationReads, 0)
        XCTAssertEqual(probe.contextFetches, 0)
        XCTAssertEqual(probe.deferredWrites, 0)
        XCTAssertEqual(viewModel.offlineToastMessage?.title, "Comparison queued; excluded from controlled results.")
        let scan = try XCTUnwrap(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        XCTAssertNil(scan.gpsLatitude)
        XCTAssertNil(scan.gpsLongitude)
        XCTAssertNil(scan.gpsElevation)
        XCTAssertNil(scan.locationName)
        XCTAssertNil(scan.weatherCondition)
        XCTAssertNil(scan.weatherTemperatureF)
        let recovered = try queue.buildExtractedScanData(from: scan, container: context.container)
        XCTAssertNil(recovered.telemetry.debugReplayProfile, "Recovery is ordinary queue work, not a fixed-context attempt.")

        viewModel.clearStagedCaptureAndCropState()
        let ordinaryFilename = try makeTempAudioFilename()
        let ordinaryAccepted = await viewModel.submitNonVisualCapture(
            audioFileNames: [ordinaryFilename], observationContexts: [], mediaTimeline: [.audio(ordinaryFilename)],
            modelContext: context, admissionRoute: .queued
        )
        XCTAssertTrue(ordinaryAccepted)
        XCTAssertFalse(viewModel.hasFixedContextDebugReplay)
        XCTAssertEqual(probe.locationReads, 1, "Normal capture must retain its existing context policy.")
        XCTAssertEqual(viewModel.offlineToastMessage?.title, "No network connection. Queued for analysis.")
        _ = await prefetch.value
    }

    func testFixedContextForegroundReachesSerializedRequestWithoutEnrichment() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }
        let probe = ReplayContextProbe()
        let viewModel = makeContextReplayWorkspace(probe: probe)
        let container = viewModel.diContainer
        let queue = container.offlineQueueManager
        let previousOnline = queue.isOnline
        let previousEngine = container.inferenceEngine
        let context = try makeModelContext()
        queue.modelContext = context
        queue.isOnline = true
        let fixture = NetworkEndpointFixture()
        fixture.client.overridingInferenceConsentCheck = {}
        let source = URL.documentsDirectory.appendingPathComponent("fixed-context-\(UUID().uuidString).wav")
        let sourceBytes = makeInferenceTestPCM16WAVData()
        try sourceBytes.write(to: source)
        let requestGate = InferenceOperationGate()
        let engine = InferenceEngine(liveRequestService: InferenceLiveRequestService(dependencies: .init(
            encodeVisualImages: { _ in XCTFail("Audio replay must not encode images"); return [] },
            uploadStagedVideoFiles: { _, _ in XCTFail("Audio replay must not upload video"); return [] },
            identify: { request, _ in
                XCTAssertEqual(request.telemetry.debugReplayProfile, .audioMinimalV1)
                XCTAssertTrue(request.observationContextsJSON.isEmpty)
                _ = try await fixture.client.identifyMultiModal(
                    audioFilePaths: request.audioFilePaths,
                    audioMediaItems: request.audioMediaItems,
                    ownerMediaTimeline: request.ownerMediaTimeline,
                    telemetry: request.telemetry, clientScanId: request.clientScanId,
                    durableQueueOwnsRecovery: request.durableQueueOwnsRecovery,
                    isProFunded: request.isProFunded
                )
                probe.completedRequests += 1
                await requestGate.wait()
                // Stop before result hydration/persistence; transport above is fully mocked.
                throw CancellationError()
            }
        )))
        container.inferenceEngine = engine
        defer {
            engine.cancelActiveRequest()
            container.inferenceEngine = previousEngine
            queue.isOnline = previousOnline
            cleanupQueuedScans(in: context)
            fixture.close()
            try? FileManager.default.removeItem(at: source)
        }
        fixture.transport.register(path: "/identify-multimodal") { request in
            let body = try XCTUnwrap(MockURLProtocol.bodyData(for: request))
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(payload["deviceLocale"] as? String, "en")
            XCTAssertEqual(payload["deviceTimeZone"] as? String, "UTC")
            XCTAssertEqual(payload["currentMonth"] as? Int, 1)
            XCTAssertEqual(payload["timeOfDay"] as? String, "12:00 PM")
            for key in ["deviceRegion", "gpsLatitude", "gpsLongitude", "gpsElevation", "semanticLocation",
                        "publicLocationLabel", "weatherCondition", "weatherTemperatureF", "timestamp",
                        "depthScaleText", "zoomFactor", "estimated_size_cm", "observation_contexts", "preferred_goal"] {
                XCTAssertNil(payload[key], "Unexpected context field: \(key)")
            }
            let audio = try XCTUnwrap((payload["audioBase64s"] as? [String])?.first)
            XCTAssertEqual(Data(base64Encoded: audio), sourceBytes)
            return try NetworkEndpointTestSupport.response(to: request, json: #"{"success":true}"#)
        }
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) { viewModel.canStartDebugReplay }
        let task = try XCTUnwrap(viewModel.startDebugReplay(
            .audio, profile: .audioMinimalV1, prepare: { _, _, _ in .audio(source) }
        ))
        await task.value
        let prefetch = Task { EnvironmentContext(location: nil, locationName: "Synthetic stale context") }
        viewModel.preFetchTask = prefetch
        await viewModel.submitStagedCapture(modelContext: context)
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) { probe.completedRequests == 1 }
        let inferenceTask = engine.inferenceTask
        await requestGate.release()
        if let inferenceTask { _ = try? await inferenceTask.value }
        XCTAssertEqual(probe.completedRequests, 1)
        XCTAssertEqual(probe.locationReads, 0)
        XCTAssertEqual(probe.contextFetches, 0)
        XCTAssertEqual(probe.deferredWrites, 0)
        XCTAssertTrue(prefetch.isCancelled)
        XCTAssertTrue(viewModel.stagedCapture.isEmpty)
        _ = await prefetch.value
    }

    private func makeContextReplayWorkspace(probe: ReplayContextProbe) -> CaptureWorkspaceViewModel {
        let container = AppDIContainer.preview
        let live = CaptureWorkspaceDependencies.live(diContainer: container)
        let dependencies = CaptureWorkspaceDependencies(
            scan: live.scan,
            submission: CaptureSubmissionDependencies(
                context: .init(lastKnownLocation: {
                    probe.locationReads += 1
                    return nil
                }, fetchDeferredContext: { _ in
                    probe.contextFetches += 1
                    return EnvironmentContext(location: nil, locationName: "Synthetic live context",
                                              weatherCondition: "Synthetic weather", weatherTemperature: 72)
                }),
                admission: .init(isOnline: { container.offlineQueueManager.isOnline },
                                 canStartLocally: { _ in true }, preview: { _ in
                                     .available(ScanAdmissionPreview(
                                         decision: .allowed, effectivePlan: "pro", dailyLimit: nil, dailyRemaining: nil
                                     ))
                                 }),
                deferredContext: .init(persistLocally: { _, _ in probe.deferredWrites += 1 },
                                       endpoint: .init(update: { _, _ in probe.deferredWrites += 1 }), waitBeforeRetry: {})
            ),
            controls: live.controls, navigation: live.navigation, stagingToolbar: live.stagingToolbar,
            prepareImage: live.prepareImage, prepareHistoricalAudio: live.prepareHistoricalAudio,
            externalImageImports: live.externalImageImports, downloadRefinementImage: live.downloadRefinementImage,
            prewarmConnections: {}, sharedExplorePostId: live.sharedExplorePostId,
            captureGoalAccountId: live.captureGoalAccountId,
            requestNotificationAuthorization: live.requestNotificationAuthorization, feedback: live.feedback
        )
        return CaptureWorkspaceViewModel(diContainer: container, dependencies: dependencies, prewarmHeadersOnInit: false)
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

@MainActor
private final class ReplayContextProbe {
    var locationReads = 0
    var contextFetches = 0
    var deferredWrites = 0
    var completedRequests = 0
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
