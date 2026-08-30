import Foundation
import UIKit

extension CaptureWorkspaceViewModel {
    static let videoMaxDuration: TimeInterval = 5

    private static let videoStagingFailureMessage =
        "Video couldn't be staged. Please try recording again."

    func startVideoCapture() {
        guard activeSheet == nil,
              !isCapturing,
              !isVideoRecording,
              hasAvailableStagedCaptureSlot,
              imageToCrop == nil else { return }
        guard dependencies.scan.canStartProScan() else { return }

        isCapturing = true
        videoRecordingProgress = 0

        let generation = scanOperationState.beginVideoRecording()
        let recordingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var recordedFileURL: URL?
            var cameraRollSaveTask: Task<Void, Never>?
            defer {
                self.finishVideoCaptureUI(
                    for: generation,
                    resetProgress: true
                )
            }

            guard await self.requestScanAdmission(
                flashFallbackEligible: false
            ) != nil else {
                return
            }

            do {
                async let shutterLocation = self.dependencies.scan.context
                    .requestCurrentLocation()
                let composingCenter = self.composingZoneVerticalCenter
                let recording = try await self.dependencies.scan.camera
                    .recordVideo(Self.videoMaxDuration) { [weak self] in
                        guard let self,
                              self.scanOperationState.isCurrent(generation),
                              self.isCapturing else { return }
                        self.isVideoRecording = true
                        self.videoRecordingProgress = 0
                        self.dependencies.scan.feedback.videoStarted()
                        self.startVideoRecordingProgressTimer(
                            for: generation
                        )
                    }
                recordedFileURL = recording.fileURL
                guard !Task.isCancelled,
                      self.scanOperationState.isCurrent(generation) else {
                    try? FileManager.default.removeItem(
                        at: recording.fileURL
                    )
                    throw CancellationError()
                }

                self.dependencies.scan.feedback.videoCompleted()
                let resolvedShutterLocation = await shutterLocation
                let instantLocation = resolvedShutterLocation
                    ?? self.dependencies.scan.context.lastKnownLocation()
                let saveVideo = self.dependencies.scan.library.saveVideo
                cameraRollSaveTask = Task { @MainActor in
                    await saveVideo(recording.fileURL, instantLocation)
                }

                let preparedVideo = try await self.dependencies.scan.media
                    .prepareVideo(CaptureScanVideoPreparationRequest(
                        videoURL: recording.fileURL,
                        duration: recording.duration,
                        composingCenter: composingCenter,
                        isProActive:
                            self.dependencies.scan.canStartProScan()
                    ))
                guard !Task.isCancelled,
                      self.scanOperationState.isCurrent(generation) else {
                    self.discardPreparedVideo(preparedVideo)
                    throw CancellationError()
                }

                let fetchDeferredContext = self.dependencies.scan.context
                    .fetchDeferredContext
                let contextTask = Task {
                    await fetchDeferredContext(instantLocation)
                }

                self.preFetchTask = contextTask
                let stagedFrames = preparedVideo.sampledFrames.map { frame in
                    let previewImage = UIImage(
                        cgImage: frame.previewCGImage.image,
                        scale: 1.0,
                        orientation: .up
                    )
                    return StagedImage(
                        compressedData: frame.inferenceData,
                        displayData: frame.displayData,
                        uiImage: previewImage,
                        original: IdentifiableImage(
                            image: previewImage,
                            environmentContext: nil,
                            isFromGallery: false
                        )
                    )
                }
                self.stagedCapture.videos.append(StagedVideo(
                    filePath: preparedVideo.playback.fileURL.path,
                    sampledImages: stagedFrames,
                    audioFilePath: preparedVideo.audioFilePath
                ))
                self.beginAutomaticStagedSubmissionIfEligible()
                MerianLog.hardware.debug(
                    """
                    Video staged: frames=\(stagedFrames.count, privacy: .public), \
                    file=\(preparedVideo.playback.fileURL.lastPathComponent, privacy: .public), \
                    source=\(preparedVideo.playback.sourceDescription, privacy: .public), \
                    originalBytes=\(preparedVideo.playback.originalBytes, privacy: .public), \
                    playbackBytes=\(preparedVideo.playback.playbackBytes, privacy: .public), \
                    compressionRatio=\(String(format: "%.3f", preparedVideo.playback.compressionRatio), privacy: .public), \
                    preparationDuration=\(String(format: "%.3f", preparedVideo.playback.preparationDuration), privacy: .public)s, \
                    fallback=\(!preparedVideo.playback.isCompressed, privacy: .public).
                    """
                )
                self.dependencies.scan.feedback.success()
                self.finishVideoCaptureUI(
                    for: generation,
                    resetProgress: true
                )

                await cameraRollSaveTask?.value
                if preparedVideo.playback.isCompressed {
                    try? FileManager.default.removeItem(
                        at: recording.fileURL
                    )
                }
            } catch is CancellationError {
                await cameraRollSaveTask?.value
                if let recordedFileURL {
                    try? FileManager.default.removeItem(at: recordedFileURL)
                }
                if self.scanOperationState.isCurrent(generation) {
                    self.dependencies.scan.camera.cancelVideoRecording()
                }
            } catch {
                await cameraRollSaveTask?.value
                if let recordedFileURL {
                    try? FileManager.default.removeItem(at: recordedFileURL)
                }
                guard self.scanOperationState.isCurrent(generation) else {
                    return
                }
                MerianLog.hardware.error(
                    "Video shutter failure: \(error, privacy: .private)"
                )
                self.offlineToastMessage = .error(
                    Self.videoStagingFailureMessage
                )
                self.dependencies.scan.feedback.error()
            }
        }
        scanOperationState.installVideoRecordingTask(
            recordingTask,
            for: generation
        )
    }

    func stopVideoCapture() {
        guard isVideoRecording else { return }
        dependencies.scan.camera.stopVideoRecording()
    }

    func cancelVideoCapture() {
        guard isVideoRecording || isCapturing else { return }
        scanOperationState.cancelVideoRecording()
        dependencies.scan.camera.cancelVideoRecording()
        finishVideoCaptureUIAfterCancellation()
    }

    private func startVideoRecordingProgressTimer(
        for generation: CaptureScanVideoGeneration
    ) {
        let progressTask = Task { @MainActor [weak self] in
            let tickNanoseconds: UInt64 = 50_000_000
            let tickDuration = 0.05
            var elapsed: TimeInterval = 0

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: tickNanoseconds)
                guard !Task.isCancelled,
                      let self,
                      self.scanOperationState.isCurrent(generation) else {
                    return
                }
                elapsed += tickDuration
                self.videoRecordingProgress = min(
                    1,
                    elapsed / Self.videoMaxDuration
                )

                if elapsed >= Self.videoMaxDuration {
                    return
                }
            }
        }
        scanOperationState.replaceVideoRecordingProgressTask(
            progressTask,
            for: generation
        )
    }

    private func finishVideoCaptureUI(
        for generation: CaptureScanVideoGeneration,
        resetProgress: Bool
    ) {
        guard scanOperationState.finishVideoRecording(generation) else {
            return
        }
        if resetProgress {
            videoRecordingProgress = 0
        }
        isCapturing = false
        isVideoRecording = false
    }

    private func finishVideoCaptureUIAfterCancellation() {
        videoRecordingProgress = 0
        isCapturing = false
        isVideoRecording = false
    }

    private func discardPreparedVideo(
        _ preparedVideo: PreparedCaptureScanVideo
    ) {
        if preparedVideo.playback.isCompressed {
            try? FileManager.default.removeItem(
                at: preparedVideo.playback.fileURL
            )
        }
        if let audioFilePath = preparedVideo.audioFilePath {
            try? FileManager.default.removeItem(
                at: URL.documentsDirectory
                    .appendingPathComponent(audioFilePath)
            )
        }
    }
}
