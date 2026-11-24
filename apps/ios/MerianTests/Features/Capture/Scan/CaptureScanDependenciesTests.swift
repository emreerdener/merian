import CoreLocation
import Photos
import Testing
import UIKit

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

    @Test func videoStartsWithoutWaitingForScanAdmission() async {
        let spy = CaptureScanDependencySpy()
        var admissionCalls = 0
        let viewModel = makeViewModel(
            spy: spy,
            admissionIsOnline: true,
            admissionPreview: {
                admissionCalls += 1
                return .unavailable
            }
        )

        viewModel.startVideoCapture()
        #expect(await waitUntil { !viewModel.isCapturing })
        #expect(spy.recordVideoCount == 1)
        #expect(admissionCalls == 0)
    }

    @Test func testLifecycleInterruptionCancelsPendingVideoStartupWithoutAdmission() async throws {
        let spy = CaptureScanDependencySpy()
        let recording = ControlledVideoRecording(reportsStarted: false)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var admissionCalls = 0
        let viewModel = makeViewModel(
            spy: spy, controlledRecording: recording, admissionIsOnline: true,
            admissionPreview: { admissionCalls += 1; return .unavailable }
        )
        viewModel.startVideoCapture()
        #expect(await waitUntil { recording.hasStarted })
        #expect(spy.recordVideoCount == 1 && !viewModel.isVideoRecording)
        viewModel.handleVisualCaptureInterruption()
        #expect(spy.cancelVideoCount == 1 && spy.stopVideoCount == 0)
        #expect(!viewModel.isCapturing && !viewModel.isVideoRecording)
        viewModel.clearStagedCaptureAndCropState(discardStagedMediaFiles: true)
        let newerOperation = try #require(viewModel.beginDraftOperation())
        viewModel.descriptionDraft = ObservationContext(freeText: "Replacement draft")
        // The old recording deliberately ignores cancellation and returns late.
        recording.succeed(.init(fileURL: url, duration: 1))
        #expect(await waitUntil { !FileManager.default.fileExists(atPath: url.path) })
        #expect(viewModel.draftSession.contains(newerOperation))
        #expect(viewModel.descriptionDraft.freeText == "Replacement draft")
        #expect(viewModel.stagedCapture.isEmpty && !viewModel.isPreparingVideo)
        #expect(spy.prepareVideoCount == 0 && spy.saveVideoCount == 0)
        #expect(admissionCalls == 0 && !viewModel.isQueueingStagedCapture)
        #expect(!viewModel.isAutomaticStagedSubmissionPending)
        viewModel.completeDraftOperation(newerOperation, succeeded: false)
    }

    @Test func lifecycleInterruptionStopsStartedRecordingAndAllowsCompletion() async throws {
        let spy = CaptureScanDependencySpy()
        let recording = ControlledVideoRecording(reportsStarted: true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let viewModel = makeViewModel(spy: spy, controlledRecording: recording)
        viewModel.startVideoCapture()
        #expect(await waitUntil { recording.hasStarted })
        #expect(viewModel.isVideoRecording)
        viewModel.handleVisualCaptureInterruption()
        #expect(spy.stopVideoCount == 1 && spy.cancelVideoCount == 0)
        recording.succeed(.init(fileURL: url, duration: 1))
        #expect(await waitUntil { !viewModel.isCapturing })
        #expect(spy.prepareVideoCount == 1)
        // The default preparer fails locally; the stop path still reached it.
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func accountRecoveryAllowsPhotoStagingButHoldsIdentification() async throws {
        let spy = CaptureScanDependencySpy()
        var admissionCalls = 0
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let prepared = PreparedCaptureScanStill(
            inferenceData: Data([1]), displayData: Data([2]),
            previewCGImage: SendableCGImage(image: try #require(image.cgImage))
        )
        let viewModel = makeViewModel(
            spy: spy,
            prepareStill: { _ in prepared },
            admissionIsOnline: true,
            admissionPreview: {
                admissionCalls += 1
                return .unavailable
            },
            isLibraryAccessBlocked: { true },
            accountID: { UUID(uuidString: "00000000-0000-0000-0000-000000000001") }
        )
        viewModel.composingZoneVerticalCenter = 0.25
        viewModel.executeCapture(emitHaptic: false)
        #expect(await waitUntil { !viewModel.isCapturing })
        #expect(viewModel.stagedCapture.images.count == 1)
        let staged = try #require(viewModel.stagedCapture.images.first)
        #expect(staged.original.initialCameraVerticalCenter == 0.25)
        #expect(staged.reviewBasis == .squareCropSource)
        #expect(viewModel.draftSession.ownership == .unowned)
        #expect(admissionCalls == 0)
        #expect(!viewModel.isAutomaticStagedSubmissionPending)
        #expect(viewModel.activeSheet == nil)

        #expect(await viewModel.requestScanAdmission(flashFallbackEligible: true) == nil)
        #expect(viewModel.stagedCapture.images.count == 1)
        #expect(admissionCalls == 0)
        #expect(viewModel.activeSheet == nil)
    }

    @Test func accountChangeDuringAdmissionCannotAdoptAnExistingDraft() async {
        let admission = ControlledScanAdmission()
        var accountID: UUID? = UUID()
        let originalAccount = accountID
        let viewModel = makeViewModel(
            spy: CaptureScanDependencySpy(),
            admissionIsOnline: true,
            admissionPreview: { await admission.preview() },
            accountID: { accountID }
        )
        viewModel.updateDescriptionDraft(ObservationContext(freeText: "A new field observation"))
        let request = Task { await viewModel.requestScanAdmission(flashFallbackEligible: true) }
        #expect(await waitUntil { admission.hasStarted })
        accountID = UUID()
        admission.succeed()
        #expect(await request.value == nil)
        #expect(viewModel.draftSession.accountID == originalAccount)
        #expect(!viewModel.descriptionDraft.isEmpty)
        #expect(viewModel.activeSheet == nil)
    }

    @Test func changedAccountCannotStageAnInFlightPhoto() async {
        let spy = CaptureScanDependencySpy()
        let capture = ControlledStillCapture()
        var accountID: UUID? = UUID()
        let viewModel = makeViewModel(
            spy: spy,
            captureImage: { try await capture.capture() },
            accountID: { accountID }
        )
        viewModel.executeCapture(emitHaptic: false)
        #expect(await waitUntil { capture.hasStarted })
        accountID = UUID()
        capture.succeed(with: Data([1]))
        #expect(await waitUntil { !viewModel.isCapturing })
        #expect(viewModel.stagedCapture.isEmpty)
        #expect(spy.saveImageCount == 0)
        #expect(spy.prepareStillCount == 0)
        viewModel.handleDraftAccountChange()
        #expect(viewModel.draftSession.ownership == .unowned)
    }

    @Test func changedAccountDiscardsInFlightVideoPreparation() async throws {
        let preparation = ControlledVideoPreparation()
        var accountID: UUID? = UUID()
        let recordingURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let playbackURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: recordingURL)
        try Data([2]).write(to: playbackURL)
        defer {
            try? FileManager.default.removeItem(at: recordingURL)
            try? FileManager.default.removeItem(at: playbackURL)
        }
        let viewModel = makeViewModel(
            spy: CaptureScanDependencySpy(),
            recording: .init(fileURL: recordingURL, duration: 1),
            prepareVideo: { _ in try await preparation.prepare() },
            accountID: { accountID }
        )
        viewModel.startVideoCapture()
        #expect(await waitUntil { preparation.hasStarted })
        accountID = UUID()
        viewModel.handleDraftAccountChange()
        // Preparation can finish after cancellation; neither its media nor its
        // completion may enter the replacement account's draft.
        preparation.succeed(.init(
            sampledFrames: [],
            audioFilePath: nil,
            playback: .init(
                fileURL: playbackURL, isCompressed: true,
                originalBytes: 1, playbackBytes: 1, preparationDuration: 0
            )
        ))
        #expect(await waitUntil { !FileManager.default.fileExists(atPath: recordingURL.path) })
        #expect(!FileManager.default.fileExists(atPath: playbackURL.path))
        #expect(viewModel.stagedCapture.isEmpty)
        #expect(viewModel.draftSession.ownership == .unowned)
        #expect(!viewModel.isCapturing)
        #expect(!viewModel.isPreparingVideo)
    }

    @Test func completedRecordingLeavesRecordingChromeBeforePreparationFinishes() async throws {
        let spy = CaptureScanDependencySpy()
        let preparation = ControlledVideoPreparation()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let viewModel = makeViewModel(
            spy: spy, recording: .init(fileURL: url, duration: 1),
            prepareVideo: { _ in try await preparation.prepare() }
        )
        viewModel.startVideoCapture()
        #expect(await waitUntil { preparation.hasStarted })
        #expect(viewModel.isCapturing)
        #expect(!viewModel.isVideoRecording)
        #expect(viewModel.isPreparingVideo)
        #expect(viewModel.videoRecordingProgress == 0)
        #expect(viewModel.stagedCapture.isEmpty)

        // Ordinary interruption preserves the completed clip's staging work.
        viewModel.handleVisualCaptureInterruption()
        #expect(viewModel.isPreparingVideo)
        // Explicit discard still cancels preparation and cleans the source.
        viewModel.cancelAllVisualCaptureWork()
        preparation.cancel()
        #expect(await waitUntil { !FileManager.default.fileExists(atPath: url.path) })
        #expect(!viewModel.isCapturing)
        #expect(!viewModel.isPreparingVideo)
        #expect(viewModel.stagedCapture.isEmpty)
    }

    @Test func recordingFailureResetsCaptureAndAllowsRetry() async {
        let spy = CaptureScanDependencySpy()
        let viewModel = makeViewModel(
            spy: spy,
            recordingError: NSError(domain: "AVFoundationErrorDomain", code: -11803)
        )
        for attempt in 1...2 {
            viewModel.startVideoCapture()
            #expect(await waitUntil { !viewModel.isCapturing })
            #expect(spy.recordVideoCount == attempt)
            #expect(!viewModel.isVideoRecording)
            #expect(!viewModel.isPreparingVideo)
            #expect(viewModel.videoRecordingProgress == 0)
            #expect(viewModel.stagedCapture.isEmpty)
            #expect(viewModel.offlineToastMessage?.title == "Video couldn't be recorded. Please try again.")
        }
    }

    @Test func preparationFailureKeepsStagingMessageAndRemovesRecording() async throws {
        let spy = CaptureScanDependencySpy()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let viewModel = makeViewModel(
            spy: spy, recording: .init(fileURL: url, duration: 1),
            prepareVideo: { _ in throw NSError(domain: "VideoPreparationTest", code: 1) }
        )
        viewModel.startVideoCapture()
        #expect(await waitUntil { !viewModel.isCapturing })
        #expect(!viewModel.isVideoRecording)
        #expect(!viewModel.isPreparingVideo)
        #expect(viewModel.stagedCapture.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(viewModel.offlineToastMessage?.title == "Video couldn't be staged. Please try recording again.")
    }

    @Test func recordingSourceBecomesRemovableOnlyAfterCameraRollBorrowFinishes() async throws {
        // Production recorders/exporters hand off flat temporary files. Nested
        // private namespaces deliberately cannot be removed by generic cleanup.
        let root = FileManager.default.temporaryDirectory, prefix = UUID().uuidString
        let original = root.appendingPathComponent("\(prefix)_original.mp4")
        let playback = root.appendingPathComponent("\(prefix)_playback.mp4")
        defer { for url in [original, playback] { try? FileManager.default.removeItem(at: url) } }
        try Data([1]).write(to: original)
        try Data([2]).write(to: playback)
        let spy = CaptureScanDependencySpy()
        var release: CheckedContinuation<Void, Never>?
        let model = makeViewModel(spy: spy, recording: .init(fileURL: original, duration: 1), saveVideo: { url, _ in
            await withCheckedContinuation { release = $0 }
            #expect(FileManager.default.fileExists(atPath: url.path))
        }, prepareVideo: { _ in
            .init(sampledFrames: [], audioFilePath: nil, playback: .init(fileURL: playback,
                isCompressed: true, originalBytes: 2, playbackBytes: 1, preparationDuration: 0))
        })
        model.startVideoCapture()
        #expect(await waitUntil { release != nil && spy.prepareVideoCount == 1 })
        #expect(model.stagedCapture.videos.isEmpty)
        #expect(model.draftSession.hasUnresolvedWork && !model.canSubmitDraft)
        release?.resume()
        #expect(await waitUntil { !model.draftSession.hasUnresolvedWork })
        #expect(model.stagedCapture.videos.first?.originalFilePath == original.path)
        #expect(model.draftOwnedFiles.contains(original.path))
        model.removeStagedVideo(at: 0)
        await model.operationState.awaitStagedMediaCleanup()
        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(!FileManager.default.fileExists(atPath: playback.path))
    }

    @Test(arguments: ["commit", "failure", "dismiss", "generation"], [false, true])
    func videoReviewSwapsWholeArtifactSetOnlyForCurrentOwner(outcome: String, historySource: Bool) async throws {
        let fixture = try await VideoAudioFixture(channels: nil)
        defer { fixture.remove() }
        let root = FileManager.default.temporaryDirectory, prefix = UUID().uuidString
        let prior = root.appendingPathComponent("\(prefix)_prior.mp4")
        let candidate = root.appendingPathComponent("\(prefix)_candidate.mp4")
        let newest = root.appendingPathComponent("\(prefix)_newest.mp4")
        defer { for url in [prior, candidate, newest] { try? FileManager.default.removeItem(at: url) } }
        try Data([1]).write(to: prior)
        try Data([2]).write(to: candidate)
        let historyName = "\(UUID().uuidString)_history-staging.mp4"
        let historyURL = URL.documentsDirectory.appendingPathComponent(historyName)
        if historySource { try FileManager.default.copyItem(at: fixture.videoURL, to: historyURL) }
        defer { if historySource { try? FileManager.default.removeItem(at: historyURL) } }
        let sourcePath = historySource ? historyName : fixture.videoURL.path
        let priorPath = historySource ? historyName : prior.path
        let preparation = ControlledVideoPreparation()
        let model = makeViewModel(spy: CaptureScanDependencySpy(),
            prepareVideo: { _ in try await preparation.prepare() })
        let original = StagedVideo(filePath: priorPath, sampledImages: [],
            originalFilePath: historySource ? nil : sourcePath)
        model.stagedCapture.videos = [original]
        model.draftOwnedFiles = [priorPath, sourcePath]
        #expect(model.presentMediaReview(nodeID: "video_\(original.id)"))
        let review = try #require(model.mediaReviewSession)
        let editor = try await CaptureVideoEditorState.load(video: original)
        editor.crop.resize(to: 300)
        editor.crop.rotate(clockwise: true)
        let work = Task { await model.commitVideoReview(editor, session: review) }
        #expect(await waitUntil { preparation.hasStarted })
        #expect(model.isDraftMutationLocked)
        #expect(!model.canSubmitDraft && !model.isDraftReadyForSubmission)
        #expect(model.stagedCapture.videos.first?.filePath == priorPath)
        #expect(FileManager.default.fileExists(atPath: prior.path))
        model.removeReviewedMedia(session: review)
        #expect(model.stagedCapture.videos.count == 1)
        if outcome == "dismiss" { model.dismissMediaReview(sessionID: review.id) }
        if outcome == "generation" { model.draftSession.reset() }
        if outcome == "failure" {
            preparation.cancel()
        } else {
            preparation.succeed(.init(sampledFrames: [], audioFilePath: nil,
                playback: .init(fileURL: candidate, isCompressed: true,
                    originalBytes: 2, playbackBytes: 1, preparationDuration: 0)))
        }
        #expect(await work.value == (outcome == "commit"))
        #expect(model.videoReviewCommitID == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.videoURL.path))
        #expect(FileManager.default.fileExists(atPath: StagedVideo.localURL(for: sourcePath).path))
        let result = try #require(model.stagedCapture.videos.first)
        #expect(result.id == original.id && result.addedAt == original.addedAt)
        if outcome == "commit" {
            #expect(result.filePath == candidate.path)
            #expect(result.originalFilePath == sourcePath)
            #expect(result.framing?.quarterTurns == 1)
            #expect(model.draftOwnedFiles == [sourcePath, candidate.path])
            let second = try await CaptureVideoEditorState.load(video: result)
            second.crop.resize(to: 300)
            #expect(!second.crop.hasEdits && second.crop.quarterTurns == 1)
            second.crop.rotate(clockwise: false)
            try Data([3]).write(to: newest)
            let nextWork = Task { await model.commitVideoReview(second, session: review) }
            #expect(await waitUntil { preparation.hasStarted })
            preparation.succeed(.init(sampledFrames: [], audioFilePath: nil,
                playback: .init(fileURL: newest, isCompressed: true,
                    originalBytes: 2, playbackBytes: 1, preparationDuration: 0)))
            #expect(await nextWork.value)
            #expect(model.stagedCapture.videos.first?.originalFilePath == sourcePath)
            #expect(model.stagedCapture.videos.first?.framing?.quarterTurns == 0)
            #expect(model.draftOwnedFiles == [sourcePath, newest.path])
            await model.operationState.awaitStagedMediaCleanup()
            #expect(!FileManager.default.fileExists(atPath: candidate.path))
            #expect(FileManager.default.fileExists(atPath: StagedVideo.localURL(for: sourcePath).path))
        } else {
            #expect(result.filePath == priorPath && result.framing == nil)
            #expect(model.draftOwnedFiles == [sourcePath, priorPath])
        }
        let removed = outcome == "commit" ? prior : candidate
        if outcome != "failure", !(historySource && outcome == "commit") {
            await model.operationState.awaitStagedMediaCleanup()
            #expect(!FileManager.default.fileExists(atPath: removed.path))
        }
    }

    private func makeViewModel(
        spy: CaptureScanDependencySpy,
        captureImage: @escaping @MainActor @Sendable () async throws -> Data = {
            Data()
        },
        prepareStill: @escaping @Sendable (CaptureScanStillPreparationRequest) async throws -> PreparedCaptureScanStill? = { _ in nil },
        recording: CameraVideoRecording? = nil,
        saveVideo: (@MainActor @Sendable (URL, CLLocation?) async -> Void)? = nil,
        recordingError: NSError? = nil,
        controlledRecording: ControlledVideoRecording? = nil,
        prepareVideo: @escaping @Sendable (CaptureScanVideoPreparationRequest) async throws -> PreparedCaptureScanVideo = { _ in throw CancellationError() },
        admissionIsOnline: Bool = false,
        admissionPreview: @escaping @MainActor @Sendable () async ->
            ScanAdmissionPreviewResult = {
                .unavailable
            },
        isLibraryAccessBlocked: @escaping @MainActor @Sendable () -> Bool = { false },
        accountID: @escaping @MainActor @Sendable () -> UUID? = { nil }
    ) -> CaptureWorkspaceViewModel {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let scanDependencies = CaptureScanDependencies(
            camera: CaptureScanCameraDependencies(
                setFocusPoint: { spy.focusPoints.append($0) },
                captureImage: captureImage,
                recordVideo: { _, onStarted in
                    spy.recordVideoCount += 1
                    if let controlledRecording {
                        return await controlledRecording.record(onStarted: onStarted)
                    }
                    if let recordingError { throw recordingError }
                    guard let recording else { throw CancellationError() }
                    onStarted?()
                    return recording
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
                saveVideo: { url, location in
                    spy.saveVideoCount += 1
                    await saveVideo?(url, location)
                }
            ),
            media: CaptureScanMediaDependencies(
                prepareStill: { request in
                    await MainActor.run {
                        spy.prepareStillCount += 1
                    }
                    return try await prepareStill(request)
                },
                prepareVideo: { request in
                    await MainActor.run { spy.prepareVideoCount += 1 }
                    return try await prepareVideo(request)
                }
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
                preview: { _ in await admissionPreview() },
                accountID: accountID,
                isLibraryAccessBlocked: isLibraryAccessBlocked
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
            controls: CaptureControlDependencies(
                isVisualCaptureAllowed: { true },
                isProVideoAvailable: { true },
                dismissKeyboard: {},
                trackProVideoPaywallImpression: {},
                performHapticFeedback: { _ in }
            ),
            navigation: CaptureNavigationDependencies(
                loadBadgeSnapshot: { _ in
                    CaptureNavigationBadgeSnapshot(
                        hasUnseenExternalPost: false,
                        unreadNotificationCount: nil
                    )
                },
                setHasUnseenExplorePost: { _ in },
                performRouteFeedback: {}
            ),
            stagingToolbar: CaptureStagingToolbarDependencies(
                photoLibrary: PHPhotoLibrary.shared(),
                dismissKeyboard: {},
                performCancelFeedback: {},
                hasShownTooltip: { true },
                markTooltipShown: {},
                hasShownSubmitTooltip: { true },
                markSubmitTooltipShown: {}
            ),
            prepareImage: { _ in nil },
            prepareHistoricalAudio: { _ in nil },
            externalImageImports: ExternalImageImportStore(rootURL: rootURL),
            downloadRefinementImage: { _ in nil },
            prewarmConnections: {},
            sharedExplorePostId: { _ in nil },
            captureGoalAccountId: { $0?.uuidString },
            requestNotificationAuthorization: { _ in },
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
    var prepareVideoCount = 0
    var saveVideoCount = 0
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

@MainActor
private final class ControlledVideoPreparation {
    private var continuation: CheckedContinuation<PreparedCaptureScanVideo, Error>?
    var hasStarted: Bool { continuation != nil }

    func prepare() async throws -> PreparedCaptureScanVideo {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func cancel() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    func succeed(_ video: PreparedCaptureScanVideo) {
        continuation?.resume(returning: video)
        continuation = nil
    }
}

@MainActor
private final class ControlledVideoRecording {
    let reportsStarted: Bool
    private var continuation: CheckedContinuation<CameraVideoRecording, Never>?
    var hasStarted: Bool { continuation != nil }

    init(reportsStarted: Bool) { self.reportsStarted = reportsStarted }

    func record(onStarted: (@MainActor @Sendable () -> Void)?) async -> CameraVideoRecording {
        if reportsStarted { onStarted?() }
        return await withCheckedContinuation { continuation = $0 }
    }

    func succeed(_ recording: CameraVideoRecording) {
        continuation?.resume(returning: recording)
        continuation = nil
    }
}
