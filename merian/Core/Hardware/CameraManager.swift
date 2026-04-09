import Accelerate
@preconcurrency import AVFoundation
import Combine
import CoreImage
import CoreLocation
import Foundation
import os
import UIKit

// MARK: - Camera Manager

/// Manages the AVFoundation capture session, LiDAR depth mapping, photo capture,
/// and live frame delivery for viewfinder intelligence.
@MainActor
@Observable final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate, AVCapturePhotoCaptureDelegate {

    // MARK: - Singleton Architecture
    static let shared = CameraManager()

    // MARK: - AVFoundation Stack
    @ObservationIgnored nonisolated let session = AVCaptureSession()
    @ObservationIgnored nonisolated private let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored nonisolated private let depthOutput = AVCaptureDepthDataOutput()
    @ObservationIgnored nonisolated private let photoOutput = AVCapturePhotoOutput()

    // MARK: - Threading
    @ObservationIgnored private let queue = DispatchQueue(label: "com.merian.camera")
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    // MARK: - Lock-Protected Mutable State
    // All `nonisolated(unsafe)` vars below are exclusively read and written inside
    // `stateLock.withLock { }` closures. This is the manual synchronization contract that
    // replaces Swift actor isolation for state shared with AVFoundation nonisolated delegates.
    // INVARIANT: Never access these vars outside a `stateLock.withLock` block.
    @ObservationIgnored nonisolated let stateLock = OSAllocatedUnfairLock()
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

    // MARK: - State
    private(set) var activeThermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    var isSessionRunning = false
    var subjectDistanceInMeters: Float?
    var isFlashEnabled = false

    // MARK: - Zoom
    private(set) var zoomFactor: CGFloat = 1.0
    private(set) var maxZoomFactor: CGFloat = 1.0
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
                self.isFPSTrackingRegistered = false
                self.applyTargetFPS(HardwareOrchestrator.shared.targetFPS)
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
        let nativeZoom: CGFloat
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
        return ZoomConfig(maxZoom: 5.0, stops: [1.0, 2.0, 5.0], nativeZoom: 2.0)
        #else
        let activeVideoDevice = session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first(where: { $0.device.hasMediaType(.video) })?.device
        guard let activeVideoDevice else { return ZoomConfig(maxZoom: 1.0, stops: [], nativeZoom: 1.0) }
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
        return ZoomConfig(maxZoom: cap, stops: stops, nativeZoom: CGFloat(activeVideoDevice.videoZoomFactor))
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
                self.isSessionRunning = true
                self.maxZoomFactor = config.maxZoom
                self.opticalZoomStops = config.stops
                self.zoomFactor = config.nativeZoom // Sync UI silently without ramping hardware away from its natural default
                MerianLog.hardware.debug("Zoom: native=\(config.nativeZoom, privacy: .public), maxZoomFactor=\(config.maxZoom, privacy: .public), stops=\(config.stops, privacy: .public)")
                self.applyTargetFPS(HardwareOrchestrator.shared.targetFPS)
                ViewfinderIntelligence.shared.pauseAnalysis(for: 2.5)
            }
        }
    }

    /// Stops the capture session securely.
    /// Safely queued to avoid main-thread blocking if `stopRunning` is blocked.
    func stopSession() {
        queue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            Task { @MainActor in
                self.isSessionRunning = false
                self.isFlashEnabled = false
            }
        }
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
                // ramp() lets the capture pipeline prepare for the upcoming lens switch,
                // which eliminates the jump visible in the preview around optical stops like 2×.
                // A rate of 300×/sec is imperceptible as lag but smooths the hardware transition.
                device.cancelVideoZoomRamp()
                device.ramp(toVideoZoomFactor: clamped, withRate: 300)
            } catch {
                MerianLog.hardware.debug("setZoom: lockForConfiguration failed: \(error, privacy: .private)")
            }
        }
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
        if isPaused { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Throttle on the background queue before jumping to the main thread —
        // reduces context switches from 60fps to ~3fps and saves battery.
        let now = CFAbsoluteTimeGetCurrent()
        let shouldProcess = stateLock.withLock { () -> Bool in
            if now - lastCaptureTime < 0.3 { return false }
            lastCaptureTime = now
            return true
        }
        if !shouldProcess { return }

        // Calculate luma brightness and std dev via Accelerate histogram — avoids manual byte-stride loops.
        var brightness: Float = 1.0
        var lumaStdDev: Float = 0.0
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
                    var totalLuma: UInt64 = 0
                    var totalLumaSq: UInt64 = 0
                    var totalPixels: UInt64 = 0
                    for i in 0..<256 {
                        let count = UInt64(histogram[i])
                        let luma = UInt64(i)
                        totalLuma += count * luma
                        totalLumaSq += count * luma * luma
                        totalPixels += count
                    }
                    if totalPixels > 0 {
                        let averageLuma = Float(totalLuma) / Float(totalPixels)
                        brightness = averageLuma / 255.0
                        // Variance = E[X²] - E[X]² — std dev on 0-255 scale, proxy for sharpness
                        let meanSq = Float(totalLumaSq) / Float(totalPixels)
                        let variance = max(0, meanSq - averageLuma * averageLuma)
                        lumaStdDev = variance.squareRoot()
                    }
                }
            }
        }

        Task { @MainActor in
            guard !self.isLiveInferencePaused else { return }
            ViewfinderIntelligence.shared.analyze(brightness: brightness, distance: self.subjectDistanceInMeters, lumaStdDev: lumaStdDev)
        }
    }

    // MARK: - Photo Capture

    func captureImage() async throws -> Data {
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

                    // Dynamically align the capture connection with the physical device orientation
                    let rotationAngle = self.stateLock.withLock { self.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90.0 }
                    
                    if let photoConnection = self.photoOutput.connection(with: .video) {
                        if photoConnection.isVideoRotationAngleSupported(rotationAngle) {
                            photoConnection.videoRotationAngle = rotationAngle
                        }
                    }

                    // Relying on AVCapturePhotoOutput's native EXIF metadata integration.
                    // Forcing connection.videoRotationAngle = 90 causes double-rotations.
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
        } else if let data = photo.fileDataRepresentation() {
            request.continuation.resume(returning: data)
        } else {
            request.continuation.resume(throwing: NSError(domain: "CameraManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to generate file data representation"]))
        }
    }
}
