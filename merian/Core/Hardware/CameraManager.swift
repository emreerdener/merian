import Foundation
import UIKit
@preconcurrency import AVFoundation
import CoreImage
import Combine
import CoreLocation
import Accelerate

/// Manages AVFoundation stack and depth mapping memory-safely
@MainActor
final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate, AVCapturePhotoCaptureDelegate {
    static let shared = CameraManager()
    
    nonisolated let session = AVCaptureSession()
    nonisolated private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated private let depthOutput = AVCaptureDepthDataOutput()
    nonisolated private let photoOutput = AVCapturePhotoOutput()
    
    private let queue = DispatchQueue(label: "com.merian.camera")
    private var cancellables = Set<AnyCancellable>()
    
    nonisolated(unsafe) private var lastDepthTime: CFAbsoluteTime = 0
    nonisolated(unsafe) private var lastCaptureTime: CFAbsoluteTime = 0
    nonisolated(unsafe) private var activeHistogram = [vImagePixelCount](repeating: 0, count: 256)
    
    @Published var isSessionRunning = false
    @Published var subjectDistanceInMeters: Float? = nil
    @Published var isFlashEnabled = false
    

    
    // CoreML inferred state
    var isLiveInferencePaused: Bool = UserDefaults.standard.object(forKey: "isLiveInferencePaused") as? Bool ?? UIDevice.current.isModernIPhone
    
    // VUI Throttle parameters
    private var cachedInferencePreferenceTracker: Bool?
    
    // Photo capture state
    private var activePhotoContinuation: CheckedContinuation<Data, Error>?
    private var activeTimeoutTask: Task<Void, Error>?
    
    private override init() {
        super.init()
        
        HardwareOrchestrator.shared.$targetFPS
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] fps in
                self?.applyTargetFPS(fps)
            }
            .store(in: &cancellables)
            
        // CRITICAL FIX: Offload heavy hardware locks off the Main Thread for instant UI booting
        queue.async {
            self.setupSession()
        }
        
        NotificationCenter.default.publisher(for: AVCaptureDevice.subjectAreaDidChangeNotification)
            .sink { [weak self] _ in
                self?.resetFocusAndExposure()
            }
            .store(in: &cancellables)
    }
    
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
            
            // Revert back to OS-managed resolution handling to prevent SIGABRT bounds
            if #available(iOS 16.0, *) {
                // maxPhotoDimensions defaults to the maximum supported by the active format natively in iOS 16+
            } else {
                photoOutput.isHighResolutionCaptureEnabled = true
            }
            
            if photoOutput.isDepthDataDeliverySupported {
                photoOutput.isDepthDataDeliveryEnabled = true
            }
        }
        

        
        session.commitConfiguration()
    }
    
    func startSession() {
        guard !session.isRunning else { return }
        queue.async {
            self.session.startRunning()
            Task { @MainActor in
                self.isSessionRunning = true
                self.applyTargetFPS(HardwareOrchestrator.shared.targetFPS)
                ViewfinderIntelligence.shared.pauseAnalysis(for: 2.5)
            }
        }
    }
    
    func stopSession() {
        guard session.isRunning else { return }
        queue.async {
            self.session.stopRunning()
            Task { @MainActor in
                self.isSessionRunning = false
            }
        }
    }
    
    func applyTargetFPS(_ fps: Int) {
        guard !HardwareOrchestrator.shared.isIdleLocked else { return }
        
        guard let deviceInput = session.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) as? AVCaptureDeviceInput else {
            return
        }
        let device = deviceInput.device
        queue.async {
            do {
                try device.lockForConfiguration()
                var rate = CMTime(value: 1, timescale: Int32(fps))
                
                // Safeguard against physically unsupported frame rates to prevent NSException hardware crashing
                if let range = device.activeFormat.videoSupportedFrameRateRanges.first {
                    if CMTimeCompare(rate, range.minFrameDuration) < 0 {
                        rate = range.minFrameDuration
                    } else if CMTimeCompare(rate, range.maxFrameDuration) > 0 {
                        rate = range.maxFrameDuration
                    }
                }
                
                let currentMin = device.activeVideoMinFrameDuration
                if CMTimeCompare(rate, currentMin) > 0 {
                    device.activeVideoMaxFrameDuration = rate
                    device.activeVideoMinFrameDuration = rate
                } else {
                    device.activeVideoMinFrameDuration = rate
                    device.activeVideoMaxFrameDuration = rate
                }
                device.unlockForConfiguration()
            } catch {
                print("Failed to lock device for configuration: \(error)")
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
        queue.async {
            do {
                try device.lockForConfiguration()
                var idleRate = CMTime(value: 1, timescale: 1)
                
                if let range = device.activeFormat.videoSupportedFrameRateRanges.first {
                    if CMTimeCompare(idleRate, range.minFrameDuration) < 0 {
                        idleRate = range.minFrameDuration
                    } else if CMTimeCompare(idleRate, range.maxFrameDuration) > 0 {
                        idleRate = range.maxFrameDuration
                    }
                }
                
                let currentMin = device.activeVideoMinFrameDuration
                if CMTimeCompare(idleRate, currentMin) > 0 {
                    device.activeVideoMaxFrameDuration = idleRate
                    device.activeVideoMinFrameDuration = idleRate
                } else {
                    device.activeVideoMinFrameDuration = idleRate
                    device.activeVideoMaxFrameDuration = idleRate
                }
                device.unlockForConfiguration()
            } catch {
                print("Failed to lock for configuration in idle state: \(error)")
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
    
    nonisolated func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        
        // CPU FLOOD FIX: Throttle the heavy Depth Map calculation natively before locking the CPU
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastDepthTime < 0.3 {
            return
        }
        lastDepthTime = now

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
            
            Task { @MainActor in
                self.subjectDistanceInMeters = clampedDistance
            }
        } else {
            Task { @MainActor in
                self.subjectDistanceInMeters = nil
            }
        }
    }
    
    func toggleFlash() {
        guard let deviceInput = session.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) as? AVCaptureDeviceInput else {
            return
        }
        let device = deviceInput.device
        guard device.hasTorch else { return }
        
        queue.async {
            do {
                try device.lockForConfiguration()
                let targetTorchMode: AVCaptureDevice.TorchMode = device.torchMode == .off ? .on : .off
                device.torchMode = targetTorchMode
                device.unlockForConfiguration()
                
                Task { @MainActor [weak self] in
                    self?.isFlashEnabled = (targetTorchMode == .on)
                }
            } catch {
                print("Failed to lock device for torch: \(error)")
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
                
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = true
                
                device.unlockForConfiguration()
            } catch {
                print("Failed to lock device for focus: \(error)")
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
                
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = false
                
                device.unlockForConfiguration()
            } catch {
                print("Failed to lock device for resetting focus: \(error)")
            }
        }
    }
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Optimize: Throttle natively on the background queue BEFORE jumping to the Main Thread
        // This drops main thread context switches from 60fps to 3fps, drastically saving battery
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastCaptureTime < 0.3 {
            return
        }
        lastCaptureTime = now
        
        // Calculate brightness synchronously via ultra-fast Accelerate vector hardware, bypassing manual CPU byte-stride loops
        var brightness: Float = 1.0
        if CVPixelBufferGetPlaneCount(pixelBuffer) > 0 {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
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
                
                activeHistogram.withUnsafeMutableBufferPointer { histPtr in
                    error = vImageHistogramCalculation_Planar8(&vImageBuffer, histPtr.baseAddress!, vImage_Flags(kvImageNoFlags))
                }
                
                if error == kvImageNoError {
                    var totalLuma: UInt64 = 0
                    var totalPixels: UInt64 = 0
                    for i in 0..<256 {
                        let count = UInt64(activeHistogram[i])
                        totalLuma += count * UInt64(i)
                        totalPixels += count
                    }
                    if totalPixels > 0 {
                        let averageLuma = Float(totalLuma) / Float(totalPixels)
                        brightness = averageLuma / 255.0
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }
        
        Task { @MainActor in
            guard !self.isLiveInferencePaused else { return }
            ViewfinderIntelligence.shared.analyze(brightness: brightness, distance: self.subjectDistanceInMeters)
        }
    }
    
    func captureImage() async throws -> Data {
        // safely extract the MainActor state natively passing into the sendable closure
        let flashStatus = self.isFlashEnabled
        
        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                guard activePhotoContinuation == nil else {
                    continuation.resume(throwing: NSError(domain: "CameraManager", code: -1, userInfo: [NSLocalizedDescriptionKey : "Capture already in progress"]))
                    return
                }
                self.activePhotoContinuation = continuation
                
                // 5-Second Hardware Timeout Fallback
                self.activeTimeoutTask = Task { @MainActor [weak self] in
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    guard let self = self, let activeCont = self.activePhotoContinuation else { return }
                    self.activePhotoContinuation = nil
                    activeCont.resume(throwing: NSError(domain: "CameraManager", code: -4, userInfo: [NSLocalizedDescriptionKey : "Hardware shutter timed out"]))
                }
                
                queue.async {
                    guard let connection = self.photoOutput.connection(with: .video), connection.isActive && connection.isEnabled else {
                        Task { @MainActor in
                            guard let cont = self.activePhotoContinuation else { return }
                            self.activePhotoContinuation = nil
                            cont.resume(throwing: NSError(domain: "CameraManager", code: -3, userInfo: [NSLocalizedDescriptionKey : "Camera hardware is not dynamically ready or powered down."]))
                        }
                        return
                    }
                    let settings = AVCapturePhotoSettings()
                    
                    // Set explicitly mapped hardware flash modes when physically firing the shutter 
                    let targetFlashMode: AVCaptureDevice.FlashMode = flashStatus ? .on : .off
                    if self.photoOutput.supportedFlashModes.contains(targetFlashMode) {
                        settings.flashMode = targetFlashMode
                    }
                    
                    // Align the physical hardware ISP explicitly to native Portrait bounds to eliminate EXIF geometry offsets 
                    if #available(iOS 17.0, *) {
                        if connection.isVideoRotationAngleSupported(90.0) {
                            connection.videoRotationAngle = 90.0
                        }
                    } else {
                        if connection.isVideoOrientationSupported {
                            connection.videoOrientation = .portrait
                        }
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
            Task { @MainActor [weak self] in
                guard let self = self, let activeCont = self.activePhotoContinuation else { return }
                self.activePhotoContinuation = nil
                activeCont.resume(throwing: CancellationError())
            }
        }
    }
    
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        Task { @MainActor in
            self.activeTimeoutTask?.cancel()
            self.activeTimeoutTask = nil
            guard let cont = self.activePhotoContinuation else { return }
            self.activePhotoContinuation = nil
            
            if let error = error {
                cont.resume(throwing: error)
            } else if let data = photo.fileDataRepresentation() {
                cont.resume(returning: data)
            } else {
                cont.resume(throwing: NSError(domain: "CameraManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to generate file data representation"]))
            }
        }
    }
    

}
