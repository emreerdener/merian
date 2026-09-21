@preconcurrency import AVFoundation
import Foundation
import os

/// Bridges one bounded video-recording request to AVFoundation.
///
/// Owns movie-output configuration, camera-queue operations, file cleanup, and
/// delegate callbacks. The injected coordinator owns request lifetime, while
/// the caller-provided MainActor handlers retain observable presentation.
/// `@unchecked Sendable` is limited to this AVFoundation bridge: audio-lifetime
/// access is MainActor-only, and capture objects are resolved and mutated only
/// on the injected serial queue.
final class CameraVideoRecordingService: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    typealias SessionProvider = @Sendable () -> AVCaptureSession
    typealias MovieOutputFactory = @Sendable () -> AVCaptureMovieFileOutput
    typealias RotationAngleProvider = @Sendable () -> CGFloat?
    typealias InstallationHandler = @MainActor @Sendable () -> Void

    private let sessionProvider: SessionProvider
    private let makeMovieOutput: MovieOutputFactory
    private lazy var movieOutput = makeMovieOutput()
    private let queue: DispatchQueue
    private let coordinator: CameraVideoRecordingCoordinator

    @MainActor private lazy var recordingAudioSession = CameraVideoAudioSession(
        sessionProvider: sessionProvider, queue: queue
    )

    init(
        sessionProvider: @escaping SessionProvider,
        queue: DispatchQueue,
        makeMovieOutput: @escaping MovieOutputFactory = { AVCaptureMovieFileOutput() },
        coordinator: CameraVideoRecordingCoordinator = CameraVideoRecordingCoordinator()
    ) {
        self.sessionProvider = sessionProvider
        self.queue = queue
        self.makeMovieOutput = makeMovieOutput
        self.coordinator = coordinator
        super.init()
    }

    /// Prepares the movie output inside an existing session configuration.
    /// The caller must invoke this on the shared camera queue between the
    /// session's `beginConfiguration()` and `commitConfiguration()` calls.
    func configurePreparedOutputIfSupported(
        maxDuration: TimeInterval,
        rotationAngle: CGFloat?
    ) {
        preconditionOnCameraQueue()
        let session = sessionProvider()
        if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        guard session.outputs.contains(movieOutput) else { return }
        configureMovieOutputConnection(
            maxDuration: maxDuration,
            rotationAngle: rotationAngle
        )
    }

    @MainActor
    func recordVideo(
        generation: CameraVideoRecordingGeneration,
        maxDuration: TimeInterval,
        rotationAngle: @escaping RotationAngleProvider,
        onInstalled: @escaping InstallationHandler,
        onStarted: CameraVideoRecordingCoordinator.StartHandler?
    ) async throws -> CameraVideoRecording {
        let includeAudio = CameraVideoAudioPermissionPolicy.shouldIncludeAudio(
            for: AVAudioApplication.shared.recordPermission
        )
        return try await recordingAudioSession.withAudio(includeAudio: includeAudio) {
            try await self.configureMovieRecording(rotationAngle: rotationAngle)
            try Task.checkCancellation()
            return try await self.recordPreparedVideo(
                generation: generation, maxDuration: maxDuration,
                rotationAngle: rotationAngle, onInstalled: onInstalled,
                onStarted: onStarted
            )
        }
    }

    @MainActor
    private func recordPreparedVideo(
        generation: CameraVideoRecordingGeneration,
        maxDuration: TimeInterval,
        rotationAngle: @escaping RotationAngleProvider,
        onInstalled: @escaping InstallationHandler,
        onStarted: CameraVideoRecordingCoordinator.StartHandler?
    ) async throws -> CameraVideoRecording {
        let resolvedMaxDuration = max(maxDuration, 0.5)
        try? FileManager.default.removeItem(at: generation.outputURL)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let installed = coordinator.install(
                    generation: generation,
                    maxDuration: resolvedMaxDuration,
                    startHandler: onStarted,
                    continuation: continuation
                )
                guard installed else {
                    continuation.resume(throwing: Self.recordingError(
                        code: -7,
                        message: "Video recording is already in progress."
                    ))
                    return
                }
                onInstalled()
                // `onCancel` may run before the continuation body installs its
                // request. Re-check after installation so an already-cancelled
                // task cannot strand a continuation.
                guard !Task.isCancelled else {
                    requestCancellation(for: generation)
                    return
                }
                scheduleTimeout(
                    for: generation,
                    after: resolvedMaxDuration + 3,
                    code: -30,
                    message: "Video recording timed out before the camera returned a file."
                )
                queue.async { [weak self] in
                    self?.startOnCameraQueue(
                        generation: generation,
                        maxDuration: resolvedMaxDuration,
                        rotationAngle: rotationAngle()
                    )
                }
            }
        } onCancel: {
            self.requestCancellation(for: generation)
        }
    }

    func stopVideoRecording() {
        guard let generation = coordinator.activeGeneration else { return }
        requestStop(for: generation)
    }

    func cancelVideoRecording() {
        guard let generation = coordinator.activeGeneration else { return }
        requestCancellation(for: generation)
    }

    private func configureMovieRecording(
        rotationAngle: @escaping RotationAngleProvider
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                preconditionOnCameraQueue()
                let session = sessionProvider()
                if !session.outputs.contains(movieOutput) {
                    guard session.canAddOutput(movieOutput) else {
                        continuation.resume(throwing: Self.recordingError(
                            code: -8,
                            message: "Video recording is not supported by this camera session."
                        ))
                        return
                    }
                    session.beginConfiguration()
                    session.addOutput(movieOutput)
                    session.commitConfiguration()
                }
                configureMovieOutputConnection(
                    maxDuration: 5,
                    rotationAngle: rotationAngle()
                )
                continuation.resume(returning: ())
            }
        }
    }

    private func configureMovieOutputConnection(
        maxDuration: TimeInterval,
        rotationAngle: CGFloat?,
        prefersVideoStabilization: Bool = false
    ) {
        preconditionOnCameraQueue()
        movieOutput.maxRecordedDuration = CMTime(seconds: max(maxDuration, 0.5), preferredTimescale: 600)
        movieOutput.maxRecordedFileSize = Int64(ScanMediaPayloadPolicy.maxSavedVideoBytes)
        guard let connection = movieOutput.connection(with: .video) else { return }

        if let rotationAngle,
           connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }

        configureRecordedVideoStabilization(
            on: connection,
            enabled: prefersVideoStabilization
        )
    }

    private func configureRecordedVideoStabilization(
        on connection: AVCaptureConnection,
        enabled: Bool
    ) {
        preconditionOnCameraQueue()
        let targetMode: AVCaptureVideoStabilizationMode
        if enabled, connection.isVideoStabilizationSupported {
            targetMode = .auto
        } else {
            targetMode = .off
        }

        if connection.preferredVideoStabilizationMode != targetMode {
            connection.preferredVideoStabilizationMode = targetMode
        }
    }

    private func disableRecordedVideoStabilization() {
        preconditionOnCameraQueue()
        guard let connection = movieOutput.connection(with: .video) else { return }
        configureRecordedVideoStabilization(on: connection, enabled: false)
    }

    private func preconditionOnCameraQueue() {
        dispatchPrecondition(condition: .onQueue(queue))
    }

    private static func recordingError(code: Int, message: String) -> NSError {
        NSError(
            domain: "CameraManager",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func startOnCameraQueue(
        generation: CameraVideoRecordingGeneration,
        maxDuration: TimeInterval,
        rotationAngle: CGFloat?
    ) {
        preconditionOnCameraQueue()
        guard coordinator.isActive(generation) else { return }

        // A cancelled or timed-out generation can still be finishing inside
        // AVCaptureMovieFileOutput. Fail a replacement without touching the old
        // output until that hardware state has drained.
        guard !movieOutput.isRecording else {
            resolveFailureOnCameraQueue(
                generation: generation,
                error: Self.recordingError(
                    code: -33,
                    message: "The camera is still finishing a previous video recording."
                ),
                removingFile: true,
                logMessage: "Video recording could not start while the movie output was busy."
            )
            return
        }

        configureMovieOutputConnection(
            maxDuration: maxDuration,
            rotationAngle: rotationAngle,
            prefersVideoStabilization: true
        )
        let session = sessionProvider()
        let videoConnection = movieOutput.connection(with: .video)
        let audioConnection = movieOutput.connection(with: .audio)
        let preferredStabilizationMode = videoConnection?.preferredVideoStabilizationMode
            .rawValue ?? AVCaptureVideoStabilizationMode.off.rawValue
        MerianLog.hardware.debug(
            """
            Video recording start requested: \
            generation=\(generation.id.uuidString, privacy: .public), \
            url=\(generation.outputURL.lastPathComponent, privacy: .private), \
            maxDuration=\(maxDuration, privacy: .public), \
            sessionRunning=\(session.isRunning, privacy: .public), \
            interrupted=\(session.isInterrupted, privacy: .public), \
            videoActive=\(videoConnection?.isActive == true, privacy: .public), \
            audioActive=\(audioConnection?.isActive == true, privacy: .public), \
            preferredStabilizationMode=\(preferredStabilizationMode, privacy: .public)
            """
        )
        movieOutput.startRecording(
            to: generation.outputURL,
            recordingDelegate: self
        )
    }

    private func requestStop(
        for generation: CameraVideoRecordingGeneration,
        scheduledAction: CameraVideoRecordingScheduledAction? = nil
    ) {
        queue.async { [weak self] in
            self?.stopOnCameraQueue(
                generation: generation,
                scheduledAction: scheduledAction
            )
        }
    }

    private func stopOnCameraQueue(
        generation: CameraVideoRecordingGeneration,
        scheduledAction: CameraVideoRecordingScheduledAction?
    ) {
        preconditionOnCameraQueue()

        guard coordinator.claimStop(
            generation: generation,
            scheduledAction: scheduledAction
        ) else { return }

        guard movieOutput.isRecording else {
            MerianLog.hardware.warning(
                "Video recording stop requested while movie output was not recording."
            )
            scheduleTimeout(
                for: generation,
                after: 1.5,
                code: -31,
                message: "Video recording stopped before the camera returned a file."
            )
            return
        }

        MerianLog.hardware.debug(
            "Video recording stop requested for generation \(generation.id.uuidString, privacy: .public)."
        )
        movieOutput.stopRecording()
        scheduleTimeout(
            for: generation,
            after: 3,
            code: -32,
            message: "Video recording did not finish after stop."
        )
    }

    private func requestCancellation(
        for generation: CameraVideoRecordingGeneration
    ) {
        queue.async { [weak self] in
            self?.cancelOnCameraQueue(generation: generation)
        }
    }

    private func cancelOnCameraQueue(
        generation: CameraVideoRecordingGeneration
    ) {
        preconditionOnCameraQueue()
        guard coordinator.isActive(generation) else { return }

        if movieOutput.isRecording {
            MerianLog.hardware.debug(
                "Video recording cancel requested for generation \(generation.id.uuidString, privacy: .public); stopping movie output."
            )
            movieOutput.stopRecording()
        } else {
            MerianLog.hardware.debug(
                "Video recording cancel requested for generation \(generation.id.uuidString, privacy: .public) while movie output was not recording."
            )
        }

        resolveFailureOnCameraQueue(
            generation: generation,
            error: CancellationError(),
            removingFile: true,
            logMessage: "Video recording cancelled."
        )
    }

    private func scheduleTimeout(
        for generation: CameraVideoRecordingGeneration,
        after seconds: TimeInterval,
        code: Int,
        message: String
    ) {
        coordinator.scheduleTimeout(
            for: generation,
            after: seconds
        ) { [weak self] action in
            self?.queue.async { [weak self] in
                self?.handleTimeoutOnCameraQueue(
                    action: action,
                    code: code,
                    message: message
                )
            }
        }
    }

    private func handleTimeoutOnCameraQueue(
        action: CameraVideoRecordingScheduledAction,
        code: Int,
        message: String
    ) {
        preconditionOnCameraQueue()
        guard coordinator.isCurrentTimeout(action) else { return }

        MerianLog.hardware.error(
            "Video watchdog: recording=\(self.movieOutput.isRecording, privacy: .public), bytes=\(self.movieOutput.recordedFileSize, privacy: .public), duration=\(self.movieOutput.recordedDuration.seconds, privacy: .public)"
        )
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        resolveFailureOnCameraQueue(
            generation: action.generation,
            expectedTimeoutAction: action,
            error: Self.recordingError(
                code: code,
                message: message
            ),
            removingFile: true,
            logMessage: message
        )
    }

    private func scheduleStop(
        for generation: CameraVideoRecordingGeneration,
        after seconds: TimeInterval
    ) {
        coordinator.scheduleStop(
            for: generation,
            after: seconds
        ) { [weak self] action in
            self?.requestStop(
                for: action.generation,
                scheduledAction: action
            )
        }
    }

    private func resolveFailureOnCameraQueue(
        generation: CameraVideoRecordingGeneration,
        expectedTimeoutAction: CameraVideoRecordingScheduledAction? = nil,
        error: Error,
        removingFile: Bool,
        logMessage: String
    ) {
        preconditionOnCameraQueue()

        let result = coordinator.take(
            generation: generation,
            expectedTimeoutAction: expectedTimeoutAction
        )
        guard let result else { return }

        disableRecordedVideoStabilization()

        if removingFile {
            try? FileManager.default.removeItem(at: result.generation.outputURL)
        }

        MerianLog.hardware.error(
            "\(logMessage, privacy: .public) \(error, privacy: .private)"
        )
        result.resume(throwing: error)
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        let outputID = ObjectIdentifier(output)
        queue.async { [weak self] in
            self?.handleStartedOnCameraQueue(
                outputID: outputID,
                callbackURL: fileURL
            )
        }
    }

    private func handleStartedOnCameraQueue(
        outputID: ObjectIdentifier,
        callbackURL: URL
    ) {
        preconditionOnCameraQueue()
        guard outputID == ObjectIdentifier(movieOutput) else {
            MerianLog.hardware.warning("Video start callback ignored: output instance mismatch.")
            return
        }

        let startContext = coordinator.claimStart(callbackURL: callbackURL)
        guard let startContext else {
            let active = coordinator.activeGeneration
            MerianLog.hardware.warning("Video start callback ignored: activeRequest=\(active != nil, privacy: .public), matchesURL=\(active?.matches(callbackURL: callbackURL) == true, privacy: .public).")
            return
        }

        if startContext.stopWasRequested {
            if movieOutput.isRecording {
                movieOutput.stopRecording()
            }
            scheduleTimeout(
                for: startContext.generation,
                after: 3,
                code: -32,
                message: "Video recording did not finish after stop."
            )
        } else {
            scheduleStop(
                for: startContext.generation,
                after: startContext.maxDuration
            )
            scheduleTimeout(
                for: startContext.generation,
                after: startContext.maxDuration + 3,
                code: -30,
                message: "Video recording timed out before the camera returned a file."
            )
        }

        let activeStabilizationMode = movieOutput
            .connection(with: .video)?
            .activeVideoStabilizationMode
            .rawValue ?? AVCaptureVideoStabilizationMode.off.rawValue
        MerianLog.hardware.debug(
            """
            Video recording started: \
            generation=\(startContext.generation.id.uuidString, privacy: .public), \
            url=\(callbackURL.lastPathComponent, privacy: .private), \
            urlAliasNormalized=\(callbackURL.standardizedFileURL != startContext.generation.outputURL, privacy: .public), \
            activeStabilizationMode=\(activeStabilizationMode, privacy: .public)
            """
        )

        Task { @MainActor in
            startContext.handler?()
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let outputID = ObjectIdentifier(output)
        let capturedError = error as NSError?
        queue.async { [weak self] in
            self?.handleFinishedOnCameraQueue(
                outputID: outputID,
                callbackURL: outputFileURL,
                error: capturedError
            )
        }
    }

    private func handleFinishedOnCameraQueue(
        outputID: ObjectIdentifier,
        callbackURL: URL,
        error: NSError?
    ) {
        preconditionOnCameraQueue()
        guard outputID == ObjectIdentifier(movieOutput) else {
            MerianLog.hardware.warning("Video finish callback ignored: output instance mismatch.")
            return
        }

        // The callback URL is AVFoundation's only correlation value. A delayed
        // callback for generation A must not clear or resolve generation B.
        let result = coordinator.take(callbackURL: callbackURL)
        guard let result else {
            MerianLog.hardware.warning("Video finish callback ignored: activeRequest=\(self.coordinator.activeGeneration != nil, privacy: .public), error=\(String(describing: error), privacy: .private)")
            return
        }

        disableRecordedVideoStabilization()

        if let error {
            let didFinishSuccessfully =
                error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
            if didFinishSuccessfully {
                MerianLog.hardware.warning(
                    "Video recording finished with non-fatal AVFoundation error: \(error, privacy: .private)"
                )
            } else {
                MerianLog.hardware.error(
                    "Video recording finished with AVFoundation error: \(error, privacy: .private)"
                )
                try? FileManager.default.removeItem(at: result.generation.outputURL)
                result.resume(throwing: error)
                return
            }
        }

        let duration = result.startedAt.map { Date().timeIntervalSince($0) } ?? 0
        MerianLog.hardware.debug(
            """
            Video recording finished: \
            generation=\(result.generation.id.uuidString, privacy: .public), \
            url=\(result.generation.outputURL.lastPathComponent, privacy: .private), \
            duration=\(duration, privacy: .public)
            """
        )
        result.resume(returning: CameraVideoRecording(
            fileURL: result.generation.outputURL,
            duration: duration
        ))
    }
}
