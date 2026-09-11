@preconcurrency import AVFoundation
import Foundation
import os

private final class CameraCaptureStack: @unchecked Sendable {
    private struct State {
        var session: AVCaptureSession?
        var videoOutput: AVCaptureVideoDataOutput?
        var depthOutput: AVCaptureDepthDataOutput?
        var photoOutput: AVCapturePhotoOutput?
    }

    private let makeSession: @Sendable () -> AVCaptureSession
    private let makeVideoOutput: @Sendable () -> AVCaptureVideoDataOutput
    private let makeDepthOutput: @Sendable () -> AVCaptureDepthDataOutput
    private let makePhotoOutput: @Sendable () -> AVCapturePhotoOutput
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(
        makeSession: @escaping @Sendable () -> AVCaptureSession,
        makeVideoOutput: @escaping @Sendable () -> AVCaptureVideoDataOutput,
        makeDepthOutput: @escaping @Sendable () -> AVCaptureDepthDataOutput,
        makePhotoOutput: @escaping @Sendable () -> AVCapturePhotoOutput
    ) {
        self.makeSession = makeSession
        self.makeVideoOutput = makeVideoOutput
        self.makeDepthOutput = makeDepthOutput
        self.makePhotoOutput = makePhotoOutput
    }

    var session: AVCaptureSession {
        state.withLock { state in
            if let session = state.session { return session }
            let session = makeSession()
            state.session = session
            return session
        }
    }

    var existingSession: AVCaptureSession? {
        state.withLock { $0.session }
    }

    var videoOutput: AVCaptureVideoDataOutput {
        state.withLock { state in
            if let output = state.videoOutput { return output }
            let output = makeVideoOutput()
            state.videoOutput = output
            return output
        }
    }

    var depthOutput: AVCaptureDepthDataOutput {
        state.withLock { state in
            if let output = state.depthOutput { return output }
            let output = makeDepthOutput()
            state.depthOutput = output
            return output
        }
    }

    var existingDepthOutput: AVCaptureDepthDataOutput? {
        state.withLock { $0.depthOutput }
    }

    var photoOutput: AVCapturePhotoOutput {
        state.withLock { state in
            if let output = state.photoOutput { return output }
            let output = makePhotoOutput()
            state.photoOutput = output
            return output
        }
    }
}

private final class CameraSessionDelegateReferences: @unchecked Sendable {
    let video: AVCaptureVideoDataOutputSampleBufferDelegate
    let depth: AVCaptureDepthDataOutputDelegate

    init(
        video: AVCaptureVideoDataOutputSampleBufferDelegate,
        depth: AVCaptureDepthDataOutputDelegate
    ) {
        self.video = video
        self.depth = depth
    }
}

private final class CameraPhotoCaptureRequest: @unchecked Sendable {
    let settings: AVCapturePhotoSettings
    let flashEnabled: Bool
    let delegate: AVCapturePhotoCaptureDelegate
    let failure: @Sendable (Error) -> Void

    init(
        settings: AVCapturePhotoSettings,
        flashEnabled: Bool,
        delegate: AVCapturePhotoCaptureDelegate,
        failure: @escaping @Sendable (Error) -> Void
    ) {
        self.settings = settings
        self.flashEnabled = flashEnabled
        self.delegate = delegate
        self.failure = failure
    }
}

/// Owns the root capture stack and every session or active-device mutation.
///
/// `@unchecked Sendable` is limited to this AVFoundation bridge. Capture-object
/// creation is lock-backed and lazy; session, device, and output mutation is
/// confined to `queue`; and observable state returns through MainActor handlers.
final class CameraSessionController: @unchecked Sendable {
    typealias PreparedVideoHandler = @Sendable (_ rotationAngle: CGFloat?) -> Void
    typealias SessionStartedHandler = @MainActor @Sendable (CameraZoomConfiguration) -> Void
    typealias SessionStoppedHandler = @MainActor @Sendable () -> Void
    typealias TorchHandler = @MainActor @Sendable (_ enabled: Bool) -> Void
    typealias ZoomHandler = @MainActor @Sendable (_ factor: CGFloat) -> Void

    private struct State {
        var isSessionConfigured = false
        var sessionLifecycleGeneration: UInt64 = 0
        var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    }

    let queue: DispatchQueue
    private let captureStack: CameraCaptureStack
    private let makeVideoInput: @Sendable () -> AVCaptureDeviceInput?
    private let state = OSAllocatedUnfairLock(initialState: State())

    var session: AVCaptureSession { captureStack.session }

    init(
        queue: DispatchQueue = DispatchQueue(label: "com.merian.camera"),
        makeSession: @escaping @Sendable () -> AVCaptureSession = { AVCaptureSession() },
        makeVideoOutput: @escaping @Sendable () -> AVCaptureVideoDataOutput = { AVCaptureVideoDataOutput() },
        makeDepthOutput: @escaping @Sendable () -> AVCaptureDepthDataOutput = { AVCaptureDepthDataOutput() },
        makePhotoOutput: @escaping @Sendable () -> AVCapturePhotoOutput = { AVCapturePhotoOutput() },
        makeVideoInput: @escaping @Sendable () -> AVCaptureDeviceInput? = {
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [
                    .builtInTripleCamera,
                    .builtInLiDARDepthCamera,
                    .builtInDualCamera,
                    .builtInDualWideCamera,
                    .builtInWideAngleCamera
                ],
                mediaType: .video,
                position: .back
            )
            guard let captureDevice = discoverySession.devices.first else {
                return nil
            }
            return try? AVCaptureDeviceInput(device: captureDevice)
        }
    ) {
        self.queue = queue
        self.makeVideoInput = makeVideoInput
        self.captureStack = CameraCaptureStack(
            makeSession: makeSession,
            makeVideoOutput: makeVideoOutput,
            makeDepthOutput: makeDepthOutput,
            makePhotoOutput: makePhotoOutput
        )
    }

    func startSession(
        videoDelegate: AVCaptureVideoDataOutputSampleBufferDelegate,
        depthDelegate: AVCaptureDepthDataOutputDelegate,
        prepareVideoOutput: @escaping PreparedVideoHandler,
        onStarted: @escaping SessionStartedHandler
    ) {
        let delegates = CameraSessionDelegateReferences(
            video: videoDelegate,
            depth: depthDelegate
        )
        queue.async { [weak self] in
            guard let self, !session.isRunning else { return }
            let lifecycleGeneration = advanceSessionLifecycle()
            if reserveSessionConfiguration() {
                guard configureSession(
                    delegates: delegates,
                    prepareVideoOutput: prepareVideoOutput
                ) else {
                    releaseSessionConfiguration()
                    return
                }
            }
            session.startRunning()
            guard session.isRunning else { return }
            let zoomConfiguration = readZoomConfiguration()
            Task { @MainActor [weak self] in
                guard self?.ownsSessionLifecycle(
                    lifecycleGeneration
                ) == true else { return }
                onStarted(zoomConfiguration)
            }
        }
    }

    func stopSession(onStopped: @escaping SessionStoppedHandler) {
        queue.async { [weak self] in
            self?.invalidateSessionLifecycle()
            if let session = self?.captureStack.existingSession,
               session.isRunning {
                session.stopRunning()
            }
            Task { @MainActor in onStopped() }
        }
    }

    func stopSessionAndWait() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.invalidateSessionLifecycle()
                if let session = self?.captureStack.existingSession,
                   session.isRunning {
                    session.stopRunning()
                }
                continuation.resume()
            }
        }
    }

    func currentVideoRotationAngle() -> CGFloat? {
        state.withLock {
            $0.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture
        }
    }

    func applyTargetFPS(_ fps: Int) {
        queue.async { [weak self] in
            guard let self, let device = activeVideoDevice() else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                applyFrameDuration(
                    CMTime(value: 1, timescale: Int32(fps)),
                    to: device
                )
            } catch {
                MerianLog.hardware.debug(
                    "Failed to lock device for configuration: \(error, privacy: .private)"
                )
            }
        }
    }

    func applyIdleFrameRate() {
        queue.async { [weak self] in
            guard let self, let device = activeVideoDevice() else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                applyFrameDuration(
                    CMTime(value: 1, timescale: 1),
                    to: device
                )
            } catch {
                MerianLog.hardware.debug(
                    "Failed to lock device for idle state: \(error, privacy: .private)"
                )
            }
        }
    }

    func toggleTorch(onChanged: @escaping TorchHandler) {
        queue.async { [weak self] in
            guard let self,
                  let device = activeVideoDevice(),
                  device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                let targetMode: AVCaptureDevice.TorchMode =
                    device.torchMode == .off ? .on : .off
                device.torchMode = targetMode
                Task { @MainActor in onChanged(targetMode == .on) }
            } catch {
                MerianLog.hardware.debug(
                    "Failed to lock device for torch: \(error, privacy: .private)"
                )
            }
        }
    }

    func applyZoom(
        requestedFactor: CGFloat,
        maximumFactor: CGFloat,
        ramp: Bool,
        onChanged: @escaping ZoomHandler
    ) {
        queue.async { [weak self] in
            guard let self, let device = activeVideoDevice() else {
                MerianLog.hardware.debug("setZoom: no video device input found")
                return
            }
            let presentationFactor = CameraSessionPolicy.presentationZoomFactor(
                requestedFactor: requestedFactor,
                maximumFactor: maximumFactor
            )
            let hardwareFactor = CameraSessionPolicy.hardwareZoomFactor(
                presentationFactor: presentationFactor,
                minimumFactor: device.minAvailableVideoZoomFactor,
                maximumFactor: device.maxAvailableVideoZoomFactor
            )
            MerianLog.hardware.debug(
                "setZoom: requested=\(requestedFactor, privacy: .public), clamped=\(presentationFactor, privacy: .public), max=\(maximumFactor, privacy: .public)"
            )
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.cancelVideoZoomRamp()
                if ramp {
                    device.ramp(toVideoZoomFactor: hardwareFactor, withRate: 300)
                } else {
                    device.videoZoomFactor = hardwareFactor
                }
                Task { @MainActor in onChanged(presentationFactor) }
            } catch {
                MerianLog.hardware.debug(
                    "setZoom: lockForConfiguration failed: \(error, privacy: .private)"
                )
            }
        }
    }

    func setFocusPoint(_ devicePoint: CGPoint) {
        queue.async { [weak self] in
            guard let self, let device = activeVideoDevice() else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported,
                   device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported,
                   device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
                device.isSubjectAreaChangeMonitoringEnabled = true
            } catch {
                MerianLog.hardware.debug(
                    "Failed to lock device for focus: \(error, privacy: .private)"
                )
            }
        }
    }

    func resetFocusAndExposure() {
        queue.async { [weak self] in
            guard let self, let device = activeVideoDevice() else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.isSubjectAreaChangeMonitoringEnabled = false
            } catch {
                MerianLog.hardware.debug(
                    "Failed to lock device for resetting focus: \(error, privacy: .private)"
                )
            }
        }
    }

    func capturePhoto(
        settings: AVCapturePhotoSettings,
        flashEnabled: Bool,
        delegate: AVCapturePhotoCaptureDelegate,
        onFailure: @escaping @Sendable (Error) -> Void
    ) {
        let request = CameraPhotoCaptureRequest(
            settings: settings,
            flashEnabled: flashEnabled,
            delegate: delegate,
            failure: onFailure
        )
        queue.async { [weak self] in
            guard let self else {
                request.failure(CancellationError())
                return
            }
            let photoOutput = captureStack.photoOutput
            guard let connection = photoOutput.connection(with: .video),
                  connection.isActive,
                  connection.isEnabled else {
                request.failure(Self.cameraNotReadyError())
                return
            }

            let flashMode: AVCaptureDevice.FlashMode =
                request.flashEnabled ? .on : .off
            if photoOutput.supportedFlashModes.contains(flashMode) {
                request.settings.flashMode = flashMode
            }
            if let rotationAngle = currentVideoRotationAngle(),
               connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }
            if #available(iOS 16.0, *) {
                request.settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
            } else {
                request.settings.isHighResolutionPhotoEnabled =
                    photoOutput.isHighResolutionCaptureEnabled
            }
            if let depthOutput = captureStack.existingDepthOutput,
               let depthConnection = depthOutput.connection(with: .depthData),
               depthConnection.isEnabled,
               photoOutput.isDepthDataDeliverySupported {
                request.settings.isDepthDataDeliveryEnabled =
                    photoOutput.isDepthDataDeliveryEnabled
            }
            photoOutput.capturePhoto(
                with: request.settings,
                delegate: request.delegate
            )
        }
    }

    private func configureSession(
        delegates: CameraSessionDelegateReferences,
        prepareVideoOutput: PreparedVideoHandler
    ) -> Bool {
        preconditionOnCameraQueue()
        let session = captureStack.session
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let videoInput = makeVideoInput() else {
            session.commitConfiguration()
            return false
        }
        let videoOutput = captureStack.videoOutput
        let photoOutput = captureStack.photoOutput
        guard session.canAddInput(videoInput),
              session.canAddOutput(videoOutput),
              session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            return false
        }
        let captureDevice = videoInput.device
        state.withLock {
            $0.rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                device: captureDevice,
                previewLayer: nil
            )
        }
        session.addInput(videoInput)

        session.addOutput(videoOutput)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        ]
        videoOutput.setSampleBufferDelegate(delegates.video, queue: queue)

        session.addOutput(photoOutput)
        if #unavailable(iOS 16.0) {
            photoOutput.isHighResolutionCaptureEnabled = true
        }

        let hasLiDAR = !AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInLiDARDepthCamera],
            mediaType: .video,
            position: .back
        ).devices.isEmpty
        if hasLiDAR {
            let depthOutput = captureStack.depthOutput
            if session.canAddOutput(depthOutput) {
                session.addOutput(depthOutput)
                depthOutput.isFilteringEnabled = true
                depthOutput.setDelegate(delegates.depth, callbackQueue: queue)
                depthOutput.connection(with: .depthData)?.isEnabled = true
            }
        }

        if hasLiDAR, photoOutput.isDepthDataDeliverySupported {
            photoOutput.isDepthDataDeliveryEnabled = true
        }
        prepareVideoOutput(currentVideoRotationAngle())
        session.commitConfiguration()
        return true
    }

    private func reserveSessionConfiguration() -> Bool {
        state.withLock { state in
            guard !state.isSessionConfigured else { return false }
            state.isSessionConfigured = true
            return true
        }
    }

    private func releaseSessionConfiguration() {
        state.withLock {
            $0.isSessionConfigured = false
            $0.rotationCoordinator = nil
        }
    }

    private func advanceSessionLifecycle() -> UInt64 {
        state.withLock {
            $0.sessionLifecycleGeneration &+= 1
            return $0.sessionLifecycleGeneration
        }
    }

    private func invalidateSessionLifecycle() {
        _ = advanceSessionLifecycle()
    }

    private func ownsSessionLifecycle(_ generation: UInt64) -> Bool {
        state.withLock { $0.sessionLifecycleGeneration == generation }
    }

    private func readZoomConfiguration() -> CameraZoomConfiguration {
        preconditionOnCameraQueue()
        #if targetEnvironment(simulator)
        return CameraZoomConfiguration(
            maximumFactor: 5,
            opticalStops: [1, 2, 5],
            currentFactor: 2
        )
        #else
        guard let device = activeVideoDevice() else {
            return CameraZoomConfiguration(
                maximumFactor: 1,
                opticalStops: [],
                currentFactor: 1
            )
        }
        let configuration = CameraSessionPolicy.zoomConfiguration(
            maximumAvailableFactor: device.maxAvailableVideoZoomFactor,
            switchOverFactors: device.virtualDeviceSwitchOverVideoZoomFactors.map {
                CGFloat($0.doubleValue)
            },
            currentFactor: device.videoZoomFactor
        )
        MerianLog.hardware.debug(
            "Zoom device: \(device.localizedName, privacy: .public), available=\(device.maxAvailableVideoZoomFactor, privacy: .public), cap=\(configuration.maximumFactor, privacy: .public)"
        )
        MerianLog.hardware.debug(
            "Zoom format: formatMax=\(device.activeFormat.videoMaxZoomFactor, privacy: .public), isVirtual=\(device.isVirtualDevice, privacy: .public)"
        )
        return configuration
        #endif
    }

    private func activeVideoDevice() -> AVCaptureDevice? {
        preconditionOnCameraQueue()
        return captureStack.existingSession?.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first(where: { $0.device.hasMediaType(.video) })?
            .device
    }

    private func applyFrameDuration(
        _ requestedDuration: CMTime,
        to device: AVCaptureDevice
    ) {
        let range = device.activeFormat.videoSupportedFrameRateRanges.first
        let duration = CameraSessionPolicy.clampedFrameDuration(
            requestedDuration: requestedDuration,
            minimumDuration: range?.minFrameDuration,
            maximumDuration: range?.maxFrameDuration
        )
        if CameraSessionPolicy.shouldSetMaximumDurationFirst(
            targetDuration: duration,
            currentMinimumDuration: device.activeVideoMinFrameDuration
        ) {
            device.activeVideoMaxFrameDuration = duration
            device.activeVideoMinFrameDuration = duration
        } else {
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
    }

    private func preconditionOnCameraQueue() {
        dispatchPrecondition(condition: .onQueue(queue))
    }

    private static func cameraNotReadyError() -> NSError {
        NSError(
            domain: "CameraManager",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "Camera is not ready."]
        )
    }
}
