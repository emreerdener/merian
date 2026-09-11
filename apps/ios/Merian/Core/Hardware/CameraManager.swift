import Accelerate
@preconcurrency import AVFoundation
import Combine
import Foundation
import os
import UIKit

// MARK: - Camera Manager

/// Exposes observable camera state and bridges capture delegates to app-owned
/// photo, video, depth, and viewfinder-intelligence workflows.
@MainActor
@Observable final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate, AVCapturePhotoCaptureDelegate {

    // MARK: - Singleton Architecture
    static let shared = CameraManager()

    // MARK: - AVFoundation Ownership
    @ObservationIgnored nonisolated private let sessionController: CameraSessionController
    @ObservationIgnored nonisolated var session: AVCaptureSession { sessionController.session }
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    // MARK: - Frame Analysis State
    private struct AnalysisState {
        var lastDepthTime: CFAbsoluteTime = 0
        var lastCaptureTime: CFAbsoluteTime = 0
        var isInferencePaused = false
    }

    @ObservationIgnored nonisolated private let stateLock =
        OSAllocatedUnfairLock(initialState: AnalysisState())
    @ObservationIgnored private var videoRecordingPresentationGeneration: UUID?
    @ObservationIgnored private let targetFPSDebouncer = CameraTargetFPSDebouncer()
    @ObservationIgnored nonisolated private let photoCaptureCoordinator = CameraPhotoCaptureCoordinator()
    @ObservationIgnored nonisolated private let videoRecordingService: CameraVideoRecordingService
    @ObservationIgnored private var sessionPresentationState =
        CameraSessionPresentationState()

    // MARK: - State
    var isSessionRunning = false
    var subjectDistanceInMeters: Float?
    var isFlashEnabled = false
    private(set) var isRecordingVideo = false

    // MARK: - Zoom
    private(set) var zoomFactor: CGFloat = 1.0
    private(set) var maxZoomFactor: CGFloat = 1.0
    private(set) var nativeZoomFactor: CGFloat = 1.0
    @ObservationIgnored private var hasResolvedNativeZoomFactor = false
    @ObservationIgnored private var shouldResetZoomOnNextSessionStart = false
    /// Zoom factors at which the device physically switches lenses (e.g. [2.0, 6.0] on a triple-camera Pro).
    /// Populated after the session starts. Used by ZoomSliderView for tappable optical stop dots.
    private(set) var opticalZoomStops: [CGFloat] = []
    var isZoomSupported: Bool { maxZoomFactor >= 2.0 }

    // MARK: - Live Inference State

    var isLiveInferencePaused: Bool = UserDefaults.standard.object(forKey: UserDefaultsKeys.isLiveInferencePaused) as? Bool ?? UIDevice.current.isModernIPhone {
        didSet {
            let currentVal = isLiveInferencePaused
            stateLock.withLock { $0.isInferencePaused = currentVal }
        }
    }

    private var cachedInferencePreferenceTracker: Bool?

    // MARK: - Initialization

    private override init() {
        let sessionController = CameraSessionController()
        self.sessionController = sessionController
        self.videoRecordingService = CameraVideoRecordingService(
            sessionProvider: { sessionController.session },
            queue: sessionController.queue
        )
        super.init()
        let initialPaused = self.isLiveInferencePaused
        self.stateLock.withLock { $0.isInferencePaused = initialPaused }

        trackFPS()

        // setupSession() is intentionally deferred to startSession() to avoid triggering
        // the camera permission dialog before the user reaches the camera screen.

        NotificationCenter.default.publisher(for: AVCaptureDevice.subjectAreaDidChangeNotification)
            .sinkOnMainActor { [weak self] _ in self?.resetFocusAndExposure() }
            .store(in: &cancellables)

        // AVCaptureDevice.RotationCoordinator automatically handles physical device rotation dynamically.
    }

    private func trackFPS() {
        guard !isFPSTrackingRegistered else { return }
        isFPSTrackingRegistered = true
        withObservationTracking {
            _ = HardwareOrchestrator.shared.targetFPS
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Observation tracking is one-shot. Re-arm before awaiting so every
                // target change during the debounce window can replace pending work.
                self.isFPSTrackingRegistered = false
                self.trackFPS()

                // Debounce: coalesce rapid thermal-state change bursts (can fire 3–4×/s
                // under sustained load) into one AVFoundation reconfiguration. The
                // debouncer reads targetFPS only after the delay and rejects replaced
                // generations even when cancellation has not finished cooperatively.
                self.targetFPSDebouncer.schedule(
                    currentTargetFPS: {
                        HardwareOrchestrator.shared.targetFPS
                    },
                    apply: { [weak self] fps in
                        self?.applyTargetFPS(fps)
                    }
                )
            }
        }
    }

    nonisolated private func currentVideoRotationAngle() -> CGFloat? {
        sessionController.currentVideoRotationAngle()
    }

    /// Guards the recursive `withObservationTracking` chain against double-registration.
    /// The one-shot observation is re-armed as the first operation in `onChange`;
    /// this flag ensures that re-arming still produces at most one active registration.
    @ObservationIgnored private var isFPSTrackingRegistered = false

    // MARK: - Session Lifecycle

    /// Starts the capture session on the controller's serial queue.
    func startSession() {
        #if targetEnvironment(simulator)
        guard !isSessionRunning else { return }
        isSessionRunning = true
        nativeZoomFactor = 1.0
        hasResolvedNativeZoomFactor = true
        maxZoomFactor = 1.0
        opticalZoomStops = []
        zoomFactor = 1.0
        ViewfinderIntelligence.shared.pauseAnalysis(for: 2.5)
        MerianLog.hardware.debug("Camera session using simulator no-preview mode.")
        return
        #else
        let presentationGeneration = sessionPresentationState.register(
            requestsRunning: true
        )
        sessionController.startSession(
            videoDelegate: self,
            depthDelegate: self,
            prepareVideoOutput: { [videoRecordingService] rotationAngle in
                videoRecordingService.configurePreparedOutputIfSupported(
                    maxDuration: 5,
                    rotationAngle: rotationAngle
                )
            },
            onStarted: { [weak self] configuration in
                guard let self,
                      sessionPresentationState.owns(presentationGeneration)
                else { return }
                if !hasResolvedNativeZoomFactor {
                    nativeZoomFactor = configuration.currentFactor
                    hasResolvedNativeZoomFactor = true
                }
                isSessionRunning = true
                maxZoomFactor = configuration.maximumFactor
                opticalZoomStops = configuration.opticalStops
                if shouldResetZoomOnNextSessionStart {
                    shouldResetZoomOnNextSessionStart = false
                    applyZoom(factor: nativeZoomFactor, ramp: false)
                } else {
                    zoomFactor = configuration.currentFactor
                }
                MerianLog.hardware.debug(
                    "Zoom: native=\(nativeZoomFactor, privacy: .public), current=\(configuration.currentFactor, privacy: .public), maxZoomFactor=\(configuration.maximumFactor, privacy: .public), stops=\(configuration.opticalStops, privacy: .public)"
                )
                applyTargetFPS(HardwareOrchestrator.shared.targetFPS)
                ViewfinderIntelligence.shared.pauseAnalysis(for: 2.5)
            }
        )
        #endif
    }

    /// Stops the capture session securely.
    /// Safely queued to avoid main-thread blocking if `stopRunning` is blocked.
    func stopSession() {
        #if targetEnvironment(simulator)
        isSessionRunning = false
        isFlashEnabled = false
        return
        #else
        let presentationGeneration = sessionPresentationState.register(
            requestsRunning: false
        )
        sessionController.stopSession { [weak self] in
            guard let self,
                  sessionPresentationState.owns(presentationGeneration)
            else { return }
            isSessionRunning = false
            isFlashEnabled = false
        }
        #endif
    }

    /// Stops the capture session and returns only after AVFoundation has released it.
    /// Use this before handing camera-owned hardware to another capture pipeline.
    func stopSessionAndWait() async {
        #if targetEnvironment(simulator)
        isSessionRunning = false
        isFlashEnabled = false
        #else
        let presentationGeneration = sessionPresentationState.register(
            requestsRunning: false
        )
        await sessionController.stopSessionAndWait()
        guard sessionPresentationState.owns(presentationGeneration) else {
            return
        }
        isSessionRunning = false
        isFlashEnabled = false
        #endif
    }

    // MARK: - Frame Rate Control

    func applyTargetFPS(_ fps: Int) {
        guard !HardwareOrchestrator.shared.isIdleLocked else { return }
        sessionController.applyTargetFPS(fps)
    }

    func throttleToIdleState() {
        HardwareOrchestrator.shared.isIdleLocked = true
        cachedInferencePreferenceTracker = isLiveInferencePaused
        isLiveInferencePaused = true
        sessionController.applyIdleFrameRate()
    }

    func restoreFromIdleState() {
        HardwareOrchestrator.shared.isIdleLocked = false
        if let originalPreference = cachedInferencePreferenceTracker {
            isLiveInferencePaused = originalPreference
            cachedInferencePreferenceTracker = nil
        } else {
            isLiveInferencePaused = false
        }
        applyTargetFPS(HardwareOrchestrator.shared.targetFPS)
        ViewfinderIntelligence.shared.pauseAnalysis(for: 2.5)
    }

    // MARK: - LiDAR Depth Engine

    nonisolated func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        // Throttle depth processing to ~3Hz to avoid saturating the CPU.
        let now = CFAbsoluteTimeGetCurrent()
        let shouldProcess = stateLock.withLock { state -> Bool in
            if now - state.lastDepthTime < 0.3 { return false }
            state.lastDepthTime = now
            return true
        }
        if !shouldProcess { return }

        // Guarantee 32-bit Cartesian Depth (meters), even if hardware defaulted to Parallax Disparity (1/meters) or 16-bit.
        let convertedDepthData: AVDepthData
        if depthData.depthDataType == kCVPixelFormatType_DepthFloat32 {
            convertedDepthData = depthData
        } else {
            convertedDepthData = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        }

        let depthPixelBuffer = convertedDepthData.depthDataMap
        CVPixelBufferLockBaseAddress(depthPixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthPixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(depthPixelBuffer)
        let height = CVPixelBufferGetHeight(depthPixelBuffer)

        let baseAddress = CVPixelBufferGetBaseAddress(depthPixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthPixelBuffer)

        let centerX = width / 2
        let centerY = height / 2

        var distanceSum: Float = 0.0
        var validPixelCount: Int = 0

        let startX = max(0, centerX - 2)
        let endX = min(width - 1, centerX + 2)
        let startY = max(0, centerY - 2)
        let endY = min(height - 1, centerY + 2)

        for y in startY...endY {
            guard let base = baseAddress else { continue }
            let rowData = base.advanced(by: y * bytesPerRow)
            let pixelData = rowData.assumingMemoryBound(to: Float32.self)

            for x in startX...endX {
                let depth = pixelData[x]
                if depth > 0 && !depth.isNaN {
                    distanceSum += depth
                    validPixelCount += 1
                }
            }
        }

        if validPixelCount > 0 {
            let averageDistance = distanceSum / Float(validPixelCount)
            let clampedDistance = min(averageDistance, 5.0)
            Task { @MainActor in self.subjectDistanceInMeters = clampedDistance }
        } else {
            Task { @MainActor in self.subjectDistanceInMeters = nil }
        }
    }

    // MARK: - Flash & Focus

    func toggleFlash() {
        sessionController.toggleTorch { [weak self] isEnabled in
            self?.isFlashEnabled = isEnabled
        }
    }

    /// Snaps zoom to the nearest optical stop when within `threshold` zoom units.
    /// Call this at gesture end to give optical stops a magnetic quality without
    /// interfering with smooth tracking during the gesture itself.
    func snapToNearestOpticalStop(threshold: CGFloat = 0.1) {
        guard let nearest = opticalZoomStops.min(by: { abs($0 - zoomFactor) < abs($1 - zoomFactor) }),
              abs(nearest - zoomFactor) <= threshold else { return }
        setZoom(factor: nearest)
    }

    func setZoom(factor: CGFloat) {
        shouldResetZoomOnNextSessionStart = false
        applyZoom(factor: factor, ramp: true)
    }

    private func applyZoom(factor: CGFloat, ramp: Bool) {
        sessionController.applyZoom(
            requestedFactor: factor,
            maximumFactor: maxZoomFactor,
            ramp: ramp
        ) { [weak self] appliedFactor in
            self?.zoomFactor = appliedFactor
        }
    }

    func resetZoom() {
        shouldResetZoomOnNextSessionStart = true
        applyZoom(factor: nativeZoomFactor, ramp: false)
    }

    func setFocusPoint(_ devicePoint: CGPoint) {
        sessionController.setFocusPoint(devicePoint)
    }

    private func resetFocusAndExposure() {
        sessionController.resetFocusAndExposure()
    }

    // MARK: - Video Frame Delegate

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let isPaused = stateLock.withLock { $0.isInferencePaused }
        if isPaused {
            CMSampleBufferInvalidate(sampleBuffer)
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            CMSampleBufferInvalidate(sampleBuffer)
            return
        }

        // Throttle on the background queue before jumping to the main thread —
        // reduces context switches from 60fps to ~3fps and saves battery.
        let now = CFAbsoluteTimeGetCurrent()
        let shouldProcess = stateLock.withLock { state -> Bool in
            if now - state.lastCaptureTime < 0.3 { return false }
            state.lastCaptureTime = now
            return true
        }
        if !shouldProcess {
            CMSampleBufferInvalidate(sampleBuffer)
            return
        }

        // Calculate luma brightness and std dev via Accelerate histogram — avoids manual byte-stride loops.
        var brightness: Float = 1.0
        var lumaStdDev: Float = 0.0
        var wellLitPixelRatio: Float = 0.0
        if CVPixelBufferGetPlaneCount(pixelBuffer) > 0 {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

            if let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
                let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
                let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
                let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

                var vImageBuffer = vImage_Buffer(
                    data: baseAddress,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: bytesPerRow
                )

                var error = kvImageNoError
                var histogram = [vImagePixelCount](repeating: 0, count: 256)

                histogram.withUnsafeMutableBufferPointer { histPtr in
                    error = vImageHistogramCalculation_Planar8(&vImageBuffer, histPtr.baseAddress!, vImage_Flags(kvImageNoFlags))
                }

                if error == kvImageNoError {
                    let wellLitLumaBin = Int(0.20 * 255.0)
                    var totalLuma: UInt64 = 0
                    var totalLumaSq: UInt64 = 0
                    var totalPixels: UInt64 = 0
                    var wellLitPixels: UInt64 = 0
                    for i in 0..<256 {
                        let count = UInt64(histogram[i])
                        let luma = UInt64(i)
                        totalLuma += count * luma
                        totalLumaSq += count * luma * luma
                        totalPixels += count
                        if i >= wellLitLumaBin {
                            wellLitPixels += count
                        }
                    }
                    if totalPixels > 0 {
                        let averageLuma = Float(totalLuma) / Float(totalPixels)
                        brightness = averageLuma / 255.0
                        wellLitPixelRatio = Float(wellLitPixels) / Float(totalPixels)
                        // Variance = E[X²] - E[X]² — std dev on 0-255 scale, proxy for sharpness
                        let meanSq = Float(totalLumaSq) / Float(totalPixels)
                        let variance = max(0, meanSq - averageLuma * averageLuma)
                        lumaStdDev = variance.squareRoot()
                    }
                }
            }
        }

        CMSampleBufferInvalidate(sampleBuffer)

        Task { @MainActor in
            guard !self.isLiveInferencePaused else { return }
            ViewfinderIntelligence.shared.analyze(
                brightness: brightness,
                distance: self.subjectDistanceInMeters,
                lumaStdDev: lumaStdDev,
                wellLitPixelRatio: wellLitPixelRatio
            )
        }
    }

    // MARK: - Photo Capture

    func captureImage() async throws -> Data {
        #if targetEnvironment(simulator)
        throw NSError(
            domain: "CameraManager",
            code: -5,
            userInfo: [NSLocalizedDescriptionKey: "Camera capture is unavailable in the iOS Simulator."]
        )
        #else
        let flashStatus = self.isFlashEnabled
        let settings = AVCapturePhotoSettings()
        let requestId = settings.uniqueID
        let captureCoordinator = photoCaptureCoordinator

        guard captureCoordinator.reserve(id: requestId) else {
            throw CameraPhotoCaptureCoordinator.requestStateError()
        }

        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                guard captureCoordinator.register(
                    id: requestId,
                    continuation: continuation
                ) else { return }

                sessionController.capturePhoto(
                    settings: settings,
                    flashEnabled: flashStatus,
                    delegate: self
                ) { error in
                    captureCoordinator.resolve(id: requestId) {
                        .failure(error)
                    }
                }
            }
        } onCancel: {
            captureCoordinator.cancel(id: requestId)
        }
        #endif
    }

    // MARK: - Video Capture

    func recordVideo(
        maxDuration: TimeInterval = 5,
        onStarted: (@MainActor @Sendable () -> Void)? = nil
    ) async throws -> CameraVideoRecording {
        #if targetEnvironment(simulator)
        throw NSError(
            domain: "CameraManager",
            code: -6,
            userInfo: [NSLocalizedDescriptionKey: "Video capture is unavailable in the iOS Simulator."]
        )
        #else
        let generationID = UUID()
        let generation = CameraVideoRecordingGeneration(
            id: generationID,
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("\(generationID.uuidString)_video.mp4")
        )

        defer {
            finishVideoRecordingPresentation(for: generation.id)
        }

        return try await videoRecordingService.recordVideo(
            generation: generation,
            maxDuration: maxDuration,
            rotationAngle: { [weak self] in
                self?.currentVideoRotationAngle()
            },
            onInstalled: { [weak self] in
                guard let self else { return }
                self.videoRecordingPresentationGeneration = generation.id
                self.isRecordingVideo = false
            },
            onStarted: { [weak self] in
                self?.startVideoRecordingPresentation(
                    for: generation.id,
                    handler: onStarted
                )
            }
        )
        #endif
    }

    func stopVideoRecording() {
        #if !targetEnvironment(simulator)
        videoRecordingService.stopVideoRecording()
        #endif
    }

    func cancelVideoRecording() {
        #if !targetEnvironment(simulator)
        videoRecordingService.cancelVideoRecording()
        #endif
    }

    private func finishVideoRecordingPresentation(for generationID: UUID) {
        guard videoRecordingPresentationGeneration == generationID else { return }
        videoRecordingPresentationGeneration = nil
        isRecordingVideo = false
    }

    private func startVideoRecordingPresentation(
        for generationID: UUID,
        handler: CameraVideoRecordingCoordinator.StartHandler?
    ) {
        guard videoRecordingPresentationGeneration == generationID else { return }
        isRecordingVideo = true
        handler?()
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let requestId = photo.resolvedSettings.uniqueID

        photoCaptureCoordinator.resolve(id: requestId) {
            if let error {
                return .failure(error)
            }
            if let data = autoreleasepool(invoking: { photo.fileDataRepresentation() }) {
                return .success(data)
            }
            return .failure(NSError(
                domain: "CameraManager",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to generate file data representation"]
            ))
        }
    }
}
