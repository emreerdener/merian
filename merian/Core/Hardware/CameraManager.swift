import Foundation
import os
import UIKit
@preconcurrency import AVFoundation
import CoreImage
import Combine
import CoreLocation
import Accelerate

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

    // MARK: - Render Throttling
    @ObservationIgnored private let stateLock = OSAllocatedUnfairLock()
    @ObservationIgnored nonisolated(unsafe) private var lastDepthTime: CFAbsoluteTime = 0
    @ObservationIgnored nonisolated(unsafe) private var lastCaptureTime: CFAbsoluteTime = 0

    // MARK: - State
    private(set) var activeThermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    var isSessionRunning = false
    var subjectDistanceInMeters: Float? = nil
    var isFlashEnabled = false

    // MARK: - Zoom
    private(set) var zoomFactor: CGFloat = 1.0
    private(set) var maxZoomFactor: CGFloat = 1.0
    var isZoomSupported: Bool { true } // DEBUG: force visible — revert to `maxZoomFactor >= 2.0`

    // MARK: - Live Inference State
    @ObservationIgnored nonisolated(unsafe) private var activeInferencePaused: Bool = false

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

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.isFlashEnabled = false }
            }
            .store(in: &cancellables)
    }

    private func trackFPS() {
        withObservationTracking {
            _ = HardwareOrchestrator.shared.targetFPS
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyTargetFPS(HardwareOrchestrator.shared.targetFPS)
                self?.trackFPS()
            }
        }
    }

    // MARK: - Session Configuration

    nonisolated private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInLiDARDepthCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )

        guard let captureDevice = discoverySession.devices.first,
              let videoInput = try? AVCaptureDeviceInput(device: captureDevice) else {
            session.commitConfiguration()
            return
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

        if session.canAddOutput(depthOutput) {
            session.addOutput(depthOutput)
            depthOutput.isFilteringEnabled = true
            depthOutput.setDelegate(self, callbackQueue: queue)
            if let connection = depthOutput.connection(with: .depthData) {
                connection.isEnabled = true
            }
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)

            if #available(iOS 16.0, *) {
                // maxPhotoDimensions defaults to the maximum supported by the active format on iOS 16+.
            } else {
                photoOutput.isHighResolutionCaptureEnabled = true
            }

            if photoOutput.isDepthDataDeliverySupported {
                photoOutput.isDepthDataDeliveryEnabled = true
            }
        }

        session.commitConfiguration()
    }

    @ObservationIgnored nonisolated(unsafe) private var isSessionConfigured = false

    // MARK: - Session Lifecycle

    func startSession() {
        guard !session.isRunning else { return }
        queue.async {
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
            let capturedMaxZoom: CGFloat
            #if targetEnvironment(simulator)
            capturedMaxZoom = 5.0
            #else
            capturedMaxZoom = (self.session.inputs
                .compactMap { $0 as? AVCaptureDeviceInput }
                .first { $0.device.hasMediaType(.video) }?
                .device.maxAvailableVideoZoomFactor) ?? 1.0
            #endif

            Task { @MainActor in
                self.isSessionRunning = true
                self.maxZoomFactor = capturedMaxZoom
                self.zoomFactor = 1.0
                MerianLog.hardware.debug("Zoom: maxZoomFactor = \(capturedMaxZoom, privacy: .public), isZoomSupported = \(self.isZoomSupported, privacy: .public)")
                self.applyTargetFPS(HardwareOrchestrator.shared.targetFPS)
                ViewfinderIntelligence.shared.pauseAnalysis(for: 2.5)
            }
        }
    }

    func stopSession() {
        guard session.isRunning else { return }
        queue.async {
            self.session.stopRunning()
            Task { @MainActor in self.isSessionRunning = false }
        }
    }

    // MARK: - Frame Rate Control

    func applyTargetFPS(_ fps: Int) {
        guard !HardwareOrchestrator.shared.isIdleLocked else { return }

        guard let deviceInput = session.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) as? AVCaptureDeviceInput else {
            return
        }
        let device = deviceInput.device
        queue.async { [weak self] in
            guard let self = self else { return }
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

        guard let deviceInput = session.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) as? AVCaptureDeviceInput else {
            return
        }
        let device = deviceInput.device
        queue.async { [weak self] in
            guard let self = self else { return }
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

        let depthPixelBuffer = depthData.depthDataMap
        CVPixelBufferLockBaseAddress(depthPixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthPixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(depthPixelBuffer)
        let height = CVPixelBufferGetHeight(depthPixelBuffer)

        let format = CVPixelBufferGetPixelFormatType(depthPixelBuffer)
        guard format == kCVPixelFormatType_DepthFloat32 || format == kCVPixelFormatType_DepthFloat16 else {
            return
        }

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

        let isFloat16 = format == kCVPixelFormatType_DepthFloat16

        for y in startY...endY {
            guard let base = baseAddress else { continue }
            let rowData = base.advanced(by: y * bytesPerRow)

            for x in startX...endX {
                var depth: Float = 0.0
                if isFloat16 {
                    let pixelData = rowData.assumingMemoryBound(to: Float16.self)
                    depth = Float(pixelData[x])
                } else {
                    let pixelData = rowData.assumingMemoryBound(to: Float32.self)
                    depth = pixelData[x]
                }

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

    func setZoom(factor: CGFloat) {
        guard let deviceInput = session.inputs.first(where: {
            ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true
        }) as? AVCaptureDeviceInput else { return }

        let device = deviceInput.device
        let clamped = min(max(factor, 1.0), maxZoomFactor)
        zoomFactor = clamped

        queue.async {
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.videoZoomFactor = clamped
            } catch {
                MerianLog.hardware.debug("Failed to lock device for zoom: \(error, privacy: .private)")
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

                    let expired = self.requestsLock.withLock {
                        self.activeCaptureRequests.removeValue(forKey: requestId)
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
                        let failed = self.requestsLock.withLock {
                            self.activeCaptureRequests.removeValue(forKey: requestId)
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

                let cancelled = self.requestsLock.withLock {
                    self.activeCaptureRequests.removeValue(forKey: requestId)
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

        let request = self.requestsLock.withLock {
            self.activeCaptureRequests.removeValue(forKey: requestId)
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
