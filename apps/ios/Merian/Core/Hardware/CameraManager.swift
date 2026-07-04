import Accelerate
@preconcurrency import AVFoundation
import Combine
import CoreImage
import CoreLocation
import Foundation
import os
import UIKit

private final class CameraCaptureStack: @unchecked Sendable {
    lazy var session = AVCaptureSession()
    lazy var videoOutput = AVCaptureVideoDataOutput()
    lazy var depthOutput = AVCaptureDepthDataOutput()
    lazy var photoOutput = AVCapturePhotoOutput()
    lazy var movieOutput = AVCaptureMovieFileOutput()
}

struct CameraVideoRecording: Sendable {
    let fileURL: URL
    let duration: TimeInterval
}

private struct CameraVideoRecordingCompletion {
    let continuation: CheckedContinuation<CameraVideoRecording, Error>?
    let startedAt: Date?
    let fileURL: URL?
}

private struct CameraVideoRecordingStartHandler: Sendable {
    let action: @MainActor @Sendable () -> Void
}

// MARK: - Camera Manager

/// Manages the AVFoundation capture session, LiDAR depth mapping, photo capture,
/// and live frame delivery for viewfinder intelligence.
@MainActor
@Observable final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {

    // MARK: - Singleton Architecture
    static let shared = CameraManager()

    // MARK: - AVFoundation Stack
    @ObservationIgnored nonisolated private let captureStack = CameraCaptureStack()
    @ObservationIgnored nonisolated var session: AVCaptureSession { captureStack.session }
    @ObservationIgnored nonisolated private var videoOutput: AVCaptureVideoDataOutput { captureStack.videoOutput }
    @ObservationIgnored nonisolated private var depthOutput: AVCaptureDepthDataOutput { captureStack.depthOutput }
    @ObservationIgnored nonisolated private var photoOutput: AVCapturePhotoOutput { captureStack.photoOutput }
    @ObservationIgnored nonisolated private var movieOutput: AVCaptureMovieFileOutput { captureStack.movieOutput }

    // MARK: - Threading
    @ObservationIgnored private let queue = DispatchQueue(label: "com.merian.camera")
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    // MARK: - Lock-Protected Mutable State
    // All `nonisolated(unsafe)` vars below are exclusively read and written inside
    // `stateLock.withLock { }` closures. This is the manual synchronization contract that
    // replaces Swift actor isolation for state shared with AVFoundation nonisolated delegates.
    // INVARIANT: Never access these vars outside a `stateLock.withLock` block.
    //
    // LOCK ORDERING — STRICTLY ENFORCED:
    //   `stateLock` guards session/rotation/inference-pause state.
    //   `requestsLock` guards in-flight capture continuations (`activeCaptureRequests`).
    //   These two locks must NEVER be nested:
    //     - Do NOT acquire `requestsLock` while holding `stateLock`.
    //     - Do NOT acquire `stateLock` while holding `requestsLock`.
    //   Violation = guaranteed deadlock between the camera queue and the @MainActor timeout path.
    @ObservationIgnored nonisolated let stateLock = OSAllocatedUnfairLock()
    @ObservationIgnored nonisolated private let videoRecordingLock = OSAllocatedUnfairLock()
    /// Frame-delivery throttle timestamp — updated at most once per 300 ms from the depth delegate.
    @ObservationIgnored nonisolated(unsafe) private var lastDepthTime: CFAbsoluteTime = 0
    /// Frame-delivery throttle timestamp — updated at most once per 300 ms from the video delegate.
    @ObservationIgnored nonisolated(unsafe) private var lastCaptureTime: CFAbsoluteTime = 0
    /// Mirror of `isLiveInferencePaused` kept here for lock-safe nonisolated reads.
    @ObservationIgnored nonisolated(unsafe) private var activeInferencePaused: Bool = false
    /// Rotation coordinator — set once during `setupSession`, read inside the capture queue.
    @ObservationIgnored nonisolated(unsafe) private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    /// One-shot flag preventing `setupSession` from running twice on concurrent `startSession` calls.
    @ObservationIgnored nonisolated(unsafe) private var isSessionConfigured = false
    @ObservationIgnored nonisolated(unsafe) private var activeVideoContinuation: CheckedContinuation<CameraVideoRecording, Error>?
    @ObservationIgnored nonisolated(unsafe) private var activeVideoStartedAt: Date?
    @ObservationIgnored nonisolated(unsafe) private var activeVideoURL: URL?
    @ObservationIgnored nonisolated(unsafe) private var activeVideoStartHandler: CameraVideoRecordingStartHandler?
    @ObservationIgnored private var movieRecordingPreparationTask: Task<Bool, Error>?

    // MARK: - State
    private(set) var activeThermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

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
            stateLock.withLock { activeInferencePaused = currentVal }
        }
    }

    private var cachedInferencePreferenceTracker: Bool?

    // MARK: - Asynchronous Capture Continuations

    private struct CaptureRequest {
        let id: Int64
        let continuation: CheckedContinuation<Data, Error>
        var timeoutTask: Task<Void, Error>?
        var isResumed = false
    }

    @ObservationIgnored private let requestsLock = OSAllocatedUnfairLock()
    @ObservationIgnored nonisolated(unsafe) private var activeCaptureRequests: [Int64: CaptureRequest] = [:]

    // MARK: - Initialization

    private override init() {
        super.init()
        let initialPaused = self.isLiveInferencePaused
        self.stateLock.withLock { self.activeInferencePaused = initialPaused }

        trackFPS()

        // setupSession() is intentionally deferred to startSession() to avoid triggering
        // the camera permission dialog before the user reaches the camera screen.

        NotificationCenter.default.publisher(for: AVCaptureDevice.subjectAreaDidChangeNotification)
            .sink { [weak self] _ in self?.resetFocusAndExposure() }
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
                // Capture the target FPS before the debounce sleep — a second onChange
                // that fires during the sleep may update targetFPS again, and reading it
                // after would apply the final value correctly in any case.
                let fps = HardwareOrchestrator.shared.targetFPS
                self.isFPSTrackingRegistered = false
                // Debounce: coalesce rapid thermal-state change bursts (can fire 3–4×/s under
                // sustained load) into a single AVFoundation reconfiguration call. Without this,
                // concurrent session reconfigurations queue up and produce AVFoundation stalls.
                try? await Task.sleep(nanoseconds: 100_000_000)  // 100 ms
                guard !Task.isCancelled else { return }
                self.applyTargetFPS(fps)
                self.trackFPS()
            }
        }
    }

    // MARK: - Session Configuration

    nonisolated private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // builtInTripleCamera (Pro) exposes optical zoom across lenses AND delivers LiDAR depth
        // data via AVCaptureDepthDataOutput on devices that have LiDAR. builtInLiDARDepthCamera
        // locks videoZoomFactor at 1.0 by design (RGB/depth misalignment risk), so it is listed
        // after triple and dual to ensure zoom is available whenever the hardware supports it.
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInLiDARDepthCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )

        guard let captureDevice = discoverySession.devices.first,
              let videoInput = try? AVCaptureDeviceInput(device: captureDevice) else {
            session.commitConfiguration()
            return
        }
        
        self.stateLock.withLock {
            self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: captureDevice, previewLayer: nil)
        }

        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
            videoOutput.setSampleBufferDelegate(self, queue: queue)
        }

        let hasLiDAR = !AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInLiDARDepthCamera],
            mediaType: .video,
            position: .back
        ).devices.isEmpty

        if hasLiDAR, session.canAddOutput(depthOutput) {
            session.addOutput(depthOutput)
            depthOutput.isFilteringEnabled = true
            depthOutput.setDelegate(self, callbackQueue: queue)
            if let connection = depthOutput.connection(with: .depthData) {
                connection.isEnabled = true
            }
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)

            if #unavailable(iOS 16.0) {
                photoOutput.isHighResolutionCaptureEnabled = true
            }

            // Only enable depth data delivery for photos if the device has LiDAR.
            // Enabling stereoscopic depth on non-LiDAR dual-camera devices actively
            // locks the video zoom factor to 1.0, rendering optical/digital zoom unusable.
            if hasLiDAR, photoOutput.isDepthDataDeliverySupported {
                photoOutput.isDepthDataDeliveryEnabled = true
            }
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            configureMovieOutputConnection()
        }

        session.commitConfiguration()
    }

    /// Guards the recursive `withObservationTracking` chain against double-registration.
    /// Two rapid thermal/power-state changes can both fire `onChange` before either
    /// `trackFPS()` re-registers, spawning two parallel tracking chains that each call
    /// `applyTargetFPS`. This flag ensures at most one active registration at a time.
    @ObservationIgnored private var isFPSTrackingRegistered = false

    private struct ZoomConfig {
        let maxZoom: CGFloat
        let stops: [CGFloat]
        let currentZoom: CGFloat
    }

    /// Reads zoom configuration from the active video device after `session.startRunning()`.
    /// Returns a capped max zoom and the optical lens-switch stops.
    ///
    /// `maxAvailableVideoZoomFactor` can reach 189× (pure digital pixel-stretch). We cap at 15×
    /// to match the useful quality range; Apple's Camera app applies a similar soft cap.
    /// `virtualDeviceSwitchOverVideoZoomFactors` gives the exact factors where the hardware
    /// physically changes lenses — these become the tappable dots on the slider.
    nonisolated private func readZoomConfig() -> ZoomConfig {
        #if targetEnvironment(simulator)
        return ZoomConfig(maxZoom: 5.0, stops: [1.0, 2.0, 5.0], currentZoom: 2.0)
        #else
        let activeVideoDevice = session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first(where: { $0.device.hasMediaType(.video) })?.device
        guard let activeVideoDevice else { return ZoomConfig(maxZoom: 1.0, stops: [], currentZoom: 1.0) }
        let available = activeVideoDevice.maxAvailableVideoZoomFactor
        let cap = min(available, 15.0)
        let rawStops = activeVideoDevice.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) }
        let stops = ([1.0] + rawStops).filter { $0 <= cap }
        let formatMax = activeVideoDevice.activeFormat.videoMaxZoomFactor
        let isVirtual = activeVideoDevice.isVirtualDevice
        MerianLog.hardware.debug("Zoom device: \(activeVideoDevice.localizedName, privacy: .public), available=\(available, privacy: .public), cap=\(cap, privacy: .public)")
        MerianLog.hardware.debug("Zoom format: formatMax=\(formatMax, privacy: .public), isVirtual=\(isVirtual, privacy: .public)")
        
        // AVFoundation natively defaults the builtInTripleCamera to the standard Wide lens 
        // (usually 2.0x videoZoomFactor, where 1.0x is the Ultra-Wide).
        // By capturing it here, we sync the UI without forcing a hardware lens ramp.
        return ZoomConfig(maxZoom: cap, stops: stops, currentZoom: CGFloat(activeVideoDevice.videoZoomFactor))
        #endif
    }

    // MARK: - Session Lifecycle

    /// Starts the capture session on the dedicated background queue.
    ///
    /// `session.isRunning` is intentionally evaluated inside `queue.async` rather than
    /// on the caller's thread. `AVCaptureSession.isRunning` is highly synchronous; querying it
    /// from the Main Thread while it spins up/down on a background thread risks deadlocking
    /// the session pipeline.
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
        queue.async {
            guard !self.session.isRunning else { return }
            let needsConfig = self.stateLock.withLock { () -> Bool in
                if !self.isSessionConfigured {
                    self.isSessionConfigured = true
                    return true
                }
                return false
            }
            if needsConfig {
                self.setupSession()
            }
            self.session.startRunning()

            // maxAvailableVideoZoomFactor is only accurate after startRunning() —
            // the active format is not fully resolved until the session is live.
            let config = self.readZoomConfig()

            Task { @MainActor in
                if !self.hasResolvedNativeZoomFactor {
                    self.nativeZoomFactor = config.currentZoom
                    self.hasResolvedNativeZoomFactor = true
                }

                self.isSessionRunning = true
                self.maxZoomFactor = config.maxZoom
                self.opticalZoomStops = config.stops
                if self.shouldResetZoomOnNextSessionStart {
                    self.shouldResetZoomOnNextSessionStart = false
                    self.applyZoom(factor: self.nativeZoomFactor, ramp: false)
                } else {
                    self.zoomFactor = config.currentZoom // Sync UI silently without ramping hardware away from its current lens.
                }
                MerianLog.hardware.debug("Zoom: native=\(self.nativeZoomFactor, privacy: .public), current=\(config.currentZoom, privacy: .public), maxZoomFactor=\(config.maxZoom, privacy: .public), stops=\(config.stops, privacy: .public)")
                self.applyTargetFPS(HardwareOrchestrator.shared.targetFPS)
                ViewfinderIntelligence.shared.pauseAnalysis(for: 2.5)
            }
        }
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
        queue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            Task { @MainActor in
                self.isSessionRunning = false
                self.isFlashEnabled = false
            }
        }
        #endif
    }

    // MARK: - Frame Rate Control

    func applyTargetFPS(_ fps: Int) {
        guard !HardwareOrchestrator.shared.isIdleLocked else { return }
        // Capture session reference so the inputs lookup runs on the session queue,
        // where AVFoundation mandates AVCaptureSession.inputs must be accessed.
        let capturedSession = session
        queue.async { [weak self] in
            guard let self else { return }
            guard let deviceInput = capturedSession.inputs
                .first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true })
                as? AVCaptureDeviceInput else { return }
            let device = deviceInput.device
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                let rate = CMTime(value: 1, timescale: Int32(fps))
                self.applyFrameRate(rate, to: device)
            } catch {
                MerianLog.hardware.debug("Failed to lock device for configuration: \(error, privacy: .private)")
            }
        }
    }

    func throttleToIdleState() {
        HardwareOrchestrator.shared.isIdleLocked = true
        cachedInferencePreferenceTracker = isLiveInferencePaused
        isLiveInferencePaused = true
        let capturedSession = session
        queue.async { [weak self] in
            guard let self else { return }
            guard let deviceInput = capturedSession.inputs
                .first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true })
                as? AVCaptureDeviceInput else { return }
            let device = deviceInput.device
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                let idleRate = CMTime(value: 1, timescale: 1)
                self.applyFrameRate(idleRate, to: device)
            } catch {
                MerianLog.hardware.debug("Failed to lock device for idle state: \(error, privacy: .private)")
            }
        }
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

    /// Clamps a frame duration to the format's supported range before applying it to the device.
    nonisolated private func applyFrameRate(_ rate: CMTime, to device: AVCaptureDevice) {
        var clampedRate = rate

        if let range = device.activeFormat.videoSupportedFrameRateRanges.first {
            if CMTimeCompare(clampedRate, range.minFrameDuration) < 0 {
                clampedRate = range.minFrameDuration
            } else if CMTimeCompare(clampedRate, range.maxFrameDuration) > 0 {
                clampedRate = range.maxFrameDuration
            }
        }

        let currentMin = device.activeVideoMinFrameDuration
        if CMTimeCompare(clampedRate, currentMin) > 0 {
            device.activeVideoMaxFrameDuration = clampedRate
            device.activeVideoMinFrameDuration = clampedRate
        } else {
            device.activeVideoMinFrameDuration = clampedRate
            device.activeVideoMaxFrameDuration = clampedRate
        }
    }

    // MARK: - LiDAR Depth Engine

    nonisolated func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        // Throttle depth processing to ~3Hz to avoid saturating the CPU.
        let now = CFAbsoluteTimeGetCurrent()
        let shouldProcess = stateLock.withLock { () -> Bool in
            if now - lastDepthTime < 0.3 { return false }
            lastDepthTime = now
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
        guard let deviceInput = session.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) as? AVCaptureDeviceInput else {
            return
        }
        let device = deviceInput.device
        guard device.hasTorch else { return }

        queue.async {
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                let targetTorchMode: AVCaptureDevice.TorchMode = device.torchMode == .off ? .on : .off
                device.torchMode = targetTorchMode

                Task { @MainActor [weak self] in
                    self?.isFlashEnabled = (targetTorchMode == .on)
                }
            } catch {
                MerianLog.hardware.debug("Failed to lock device for torch: \(error, privacy: .private)")
            }
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
        guard let deviceInput = session.inputs.first(where: {
            ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true
        }) as? AVCaptureDeviceInput else {
            MerianLog.hardware.debug("setZoom: no video device input found")
            return
        }

        let device = deviceInput.device
        let clamped = min(max(factor, 1.0), maxZoomFactor)
        MerianLog.hardware.debug("setZoom: requested=\(factor, privacy: .public), clamped=\(clamped, privacy: .public), max=\(self.maxZoomFactor, privacy: .public)")
        zoomFactor = clamped

        queue.async {
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.cancelVideoZoomRamp()
                let hardwareClamped = min(max(clamped, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
                if ramp {
                    // ramp() lets the capture pipeline prepare for the upcoming lens switch,
                    // which eliminates the jump visible in the preview around optical stops like 2×.
                    // A rate of 300×/sec is imperceptible as lag but smooths the hardware transition.
                    device.ramp(toVideoZoomFactor: hardwareClamped, withRate: 300)
                } else {
                    device.videoZoomFactor = hardwareClamped
                }
            } catch {
                MerianLog.hardware.debug("setZoom: lockForConfiguration failed: \(error, privacy: .private)")
            }
        }
    }

    func resetZoom() {
        shouldResetZoomOnNextSessionStart = true
        applyZoom(factor: nativeZoomFactor, ramp: false)
    }

    func setFocusPoint(_ devicePoint: CGPoint) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let deviceInput = self.session.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) as? AVCaptureDeviceInput else {
                return
            }
            let device = deviceInput.device
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }

                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }

                device.isSubjectAreaChangeMonitoringEnabled = true
            } catch {
                MerianLog.hardware.debug("Failed to lock device for focus: \(error, privacy: .private)")
            }
        }
    }

    private func resetFocusAndExposure() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let deviceInput = self.session.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) as? AVCaptureDeviceInput else {
                return
            }
            let device = deviceInput.device
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
                MerianLog.hardware.debug("Failed to lock device for resetting focus: \(error, privacy: .private)")
            }
        }
    }

    // MARK: - Video Frame Delegate

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let isPaused = stateLock.withLock { activeInferencePaused }
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
        let shouldProcess = stateLock.withLock { () -> Bool in
            if now - lastCaptureTime < 0.3 { return false }
            lastCaptureTime = now
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

        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                var request = CaptureRequest(id: requestId, continuation: continuation, timeoutTask: nil)

                // 5-second timeout in case the hardware shutter never fires.
                request.timeoutTask = Task { [weak self] in
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    guard let self = self else { return }

                    let expired = self.requestsLock.withLock { () -> CaptureRequest? in
                        guard var r = self.activeCaptureRequests[requestId], !r.isResumed else { return nil }
                        r.isResumed = true
                        self.activeCaptureRequests.removeValue(forKey: requestId)
                        return r
                    }

                    if let expired = expired {
                        expired.continuation.resume(throwing: NSError(domain: "CameraManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Hardware shutter timed out"]))
                    }
                }

                let finalRequest = request
                self.requestsLock.withLock {
                    self.activeCaptureRequests[requestId] = finalRequest
                }

                queue.async {
                    guard let connection = self.photoOutput.connection(with: .video), connection.isActive && connection.isEnabled else {
                        let failed = self.requestsLock.withLock { () -> CaptureRequest? in
                            guard var r = self.activeCaptureRequests[requestId], !r.isResumed else { return nil }
                            r.isResumed = true
                            self.activeCaptureRequests.removeValue(forKey: requestId)
                            return r
                        }

                        if let failed = failed {
                            failed.timeoutTask?.cancel()
                            failed.continuation.resume(throwing: NSError(domain: "CameraManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Camera is not ready."]))
                        }
                        return
                    }

                    let targetFlashMode: AVCaptureDevice.FlashMode = flashStatus ? .on : .off
                    if self.photoOutput.supportedFlashModes.contains(targetFlashMode) {
                        settings.flashMode = targetFlashMode
                    }

                    // Hardware-level rotation guarantees the buffer is physically rotated before delivery
                    // so the EXIF orientation is simply "Up". This overrides any app-level orientation locks.
                    if let rotationAngle = self.stateLock.withLock({ self.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture }),
                       connection.isVideoRotationAngleSupported(rotationAngle) {
                        connection.videoRotationAngle = rotationAngle
                    }

                    if #available(iOS 16.0, *) {
                        settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
                    } else {
                        settings.isHighResolutionPhotoEnabled = self.photoOutput.isHighResolutionCaptureEnabled
                    }

                    if let depthConnection = self.depthOutput.connection(with: .depthData), depthConnection.isEnabled, self.photoOutput.isDepthDataDeliverySupported {
                        settings.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliveryEnabled
                    }

                    self.photoOutput.capturePhoto(with: settings, delegate: self)
                }
            }
        } onCancel: {
            Task { [weak self] in
                guard let self = self else { return }

                let cancelled = self.requestsLock.withLock { () -> CaptureRequest? in
                    guard var r = self.activeCaptureRequests[requestId], !r.isResumed else { return nil }
                    r.isResumed = true
                    self.activeCaptureRequests.removeValue(forKey: requestId)
                    return r
                }

                if let cancelled = cancelled {
                    cancelled.timeoutTask?.cancel()
                    cancelled.continuation.resume(throwing: CancellationError())
                }
            }
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
        _ = try await preparedVideoRecordingAudioAllowed()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)_video.mp4")

        try? FileManager.default.removeItem(at: outputURL)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let existingContinuation = videoRecordingLock.withLock { () -> CheckedContinuation<CameraVideoRecording, Error>? in
                    if let activeVideoContinuation {
                        return activeVideoContinuation
                    }
                    activeVideoContinuation = continuation
                    activeVideoStartedAt = nil
                    activeVideoURL = outputURL
                    activeVideoStartHandler = onStarted.map { CameraVideoRecordingStartHandler(action: $0) }
                    return nil
                }

                if let existingContinuation {
                    continuation.resume(throwing: NSError(
                        domain: "CameraManager",
                        code: -7,
                        userInfo: [NSLocalizedDescriptionKey: "Video recording is already in progress."]
                    ))
                    _ = existingContinuation
                    return
                }

                queue.async {
                    self.movieOutput.startRecording(to: outputURL, recordingDelegate: self)
                }

                Task { @MainActor [weak self] in
                    let durationNanos = UInt64(maxDuration * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: durationNanos)
                    self?.stopVideoRecording()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.stopVideoRecording()
            }
        }
        #endif
    }

    func stopVideoRecording() {
        #if !targetEnvironment(simulator)
        queue.async {
            guard self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
        #endif
    }

    private func preparedVideoRecordingAudioAllowed() async throws -> Bool {
        if let movieRecordingPreparationTask {
            return try await movieRecordingPreparationTask.value
        }

        let task = Task<Bool, Error> {
            let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
            try await self.configureMovieRecording(includeAudio: microphoneAllowed)
            return microphoneAllowed
        }
        movieRecordingPreparationTask = task

        do {
            return try await task.value
        } catch {
            movieRecordingPreparationTask = nil
            throw error
        }
    }

    private func configureMovieRecording(includeAudio: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }

                if !self.session.outputs.contains(self.movieOutput) {
                    guard self.session.canAddOutput(self.movieOutput) else {
                        continuation.resume(throwing: NSError(
                            domain: "CameraManager",
                            code: -8,
                            userInfo: [NSLocalizedDescriptionKey: "Video recording is not supported by this camera session."]
                        ))
                        return
                    }
                    self.session.addOutput(self.movieOutput)
                }

                self.configureMovieOutputConnection()

                if includeAudio,
                   !self.session.inputs.contains(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true }),
                   let audioDevice = AVCaptureDevice.default(for: .audio),
                   let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
                   self.session.canAddInput(audioInput) {
                    self.session.addInput(audioInput)
                }

                continuation.resume(returning: ())
            }
        }
    }

    nonisolated private func configureMovieOutputConnection() {
        movieOutput.maxRecordedDuration = CMTime(seconds: 5, preferredTimescale: 600)
        if let connection = movieOutput.connection(with: .video),
           let rotationAngle = stateLock.withLock({ rotationCoordinator?.videoRotationAngleForHorizonLevelCapture }),
           connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let requestId = photo.resolvedSettings.uniqueID

        let request = self.requestsLock.withLock { () -> CaptureRequest? in
            guard var r = self.activeCaptureRequests[requestId], !r.isResumed else { return nil }
            r.isResumed = true
            self.activeCaptureRequests.removeValue(forKey: requestId)
            return r
        }

        guard let request = request else { return }
        request.timeoutTask?.cancel()

        if let error = error {
            request.continuation.resume(throwing: error)
        } else if let data = autoreleasepool(invoking: { photo.fileDataRepresentation() }) {
            request.continuation.resume(returning: data)
        } else {
            request.continuation.resume(throwing: NSError(domain: "CameraManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to generate file data representation"]))
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        let handler = videoRecordingLock.withLock { () -> CameraVideoRecordingStartHandler? in
            activeVideoStartedAt = Date()
            let handler = activeVideoStartHandler
            activeVideoStartHandler = nil
            return handler
        }

        Task { @MainActor in
            self.isRecordingVideo = true
            handler?.action()
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let result = videoRecordingLock.withLock { () -> CameraVideoRecordingCompletion in
            let captured = CameraVideoRecordingCompletion(
                continuation: activeVideoContinuation,
                startedAt: activeVideoStartedAt,
                fileURL: activeVideoURL
            )
            activeVideoContinuation = nil
            activeVideoStartedAt = nil
            activeVideoURL = nil
            activeVideoStartHandler = nil
            return captured
        }

        Task { @MainActor in
            self.isRecordingVideo = false
        }

        guard let continuation = result.continuation else { return }

        if let error {
            continuation.resume(throwing: error)
            return
        }

        let fileURL = result.fileURL ?? outputFileURL
        let duration = result.startedAt.map { Date().timeIntervalSince($0) } ?? 0
        continuation.resume(returning: CameraVideoRecording(fileURL: fileURL, duration: duration))
    }
}
