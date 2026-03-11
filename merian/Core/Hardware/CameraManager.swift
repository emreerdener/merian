import Foundation
import AVFoundation
import CoreImage
import Combine

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
    
    @Published var isSessionRunning = false
    @Published var subjectDistanceInMeters: Float? = nil
    @Published var isFlashEnabled = false
    
    @Published var videoZoomFactor: CGFloat = 1.0
    @Published var availableZoomFactors: [CGFloat] = [1.0]
    @Published var displayZoomMultiplier: CGFloat = 1.0
    
    private var minZoom: CGFloat = 1.0
    private var maxZoom: CGFloat = 5.0
    
    // CoreML inferred state
    var isLiveInferencePaused: Bool = false
    
    // VUI Throttle parameters
    private var lastVUIAnalysisTime = Date()
    
    // Photo capture state
    private var activePhotoContinuation: CheckedContinuation<Data, Error>?
    
    private override init() {
        super.init()
        setupSession()
        
        HardwareOrchestrator.shared.$targetFPS
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] fps in
                self?.applyTargetFPS(fps)
            }
            .store(in: &cancellables)
    }
    
    private func setupSession() {
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
            photoOutput.isHighResolutionCaptureEnabled = true
            
            if photoOutput.isDepthDataDeliverySupported {
                photoOutput.isDepthDataDeliveryEnabled = true
            }
        }
        
        // Extract optical switchover points for the active physical camera
        let minZ = captureDevice.minAvailableVideoZoomFactor
        // Cap max digital zoom to 10.0 to prevent severe pixelation destroying AI inference
        let maxZ = min(captureDevice.maxAvailableVideoZoomFactor, 10.0)
        
        var factors: [CGFloat] = [minZ]
        if captureDevice.isVirtualDevice {
            factors.append(contentsOf: captureDevice.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.floatValue) })
        }
        
        // If the base lens is an Ultra-Wide, iOS maps the physical 1.0 hardware factor to "0.5x" in the UI.
        let multiplier: CGFloat = (captureDevice.deviceType == .builtInTripleCamera || captureDevice.deviceType == .builtInDualWideCamera) ? 0.5 : 1.0
        
        var uniqueFactors = Array(Set(factors)).sorted()
        
        // Fallback UX: If it's a single-lens iPhone, explicitly provide a 2.0x digital zoom stop to emulate Pro devices
        if uniqueFactors.count == 1 && maxZ >= 2.0 {
            uniqueFactors.append(2.0)
        }
        
        Task { @MainActor in
            self.minZoom = minZ
            self.maxZoom = maxZ
            self.videoZoomFactor = captureDevice.videoZoomFactor
            self.availableZoomFactors = uniqueFactors
            self.displayZoomMultiplier = multiplier
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
    
    func throttleToIdleState() {
        HardwareOrchestrator.shared.isIdleLocked = true
        isLiveInferencePaused = true
        
        guard let deviceInput = session.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) as? AVCaptureDeviceInput else {
            return
        }
        let device = deviceInput.device
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
    
    func restoreFromIdleState() {
        HardwareOrchestrator.shared.isIdleLocked = false
        isLiveInferencePaused = false
        applyTargetFPS(HardwareOrchestrator.shared.targetFPS)
    }
    
    nonisolated func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
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
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        Task { @MainActor in
            guard !self.isLiveInferencePaused else { return }
            
            // Throttle rendering to only occur once every third of a second for optimal thermal/battery preservation
            let now = Date()
            guard now.timeIntervalSince(self.lastVUIAnalysisTime) > 0.3 else { return }
            self.lastVUIAnalysisTime = now
            
            ViewfinderIntelligence.shared.analyze(pixelBuffer: pixelBuffer, distance: self.subjectDistanceInMeters)
        }
    }
    
    func captureImage() async throws -> Data {
        // safely extract the MainActor state natively passing into the sendable closure
        let flashStatus = self.isFlashEnabled
        
        return try await withCheckedThrowingContinuation { continuation in
            guard activePhotoContinuation == nil else {
                continuation.resume(throwing: NSError(domain: "CameraManager", code: -1, userInfo: [NSLocalizedDescriptionKey : "Capture already in progress"]))
                return
            }
            self.activePhotoContinuation = continuation
            
            queue.async {
                guard let connection = self.photoOutput.connection(with: .video), connection.isActive && connection.isEnabled else {
                    Task { @MainActor in
                        self.activePhotoContinuation = nil
                        continuation.resume(throwing: NSError(domain: "CameraManager", code: -3, userInfo: [NSLocalizedDescriptionKey : "Camera hardware is not dynamically ready or powered down."]))
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
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                
                settings.isHighResolutionPhotoEnabled = self.photoOutput.isHighResolutionCaptureEnabled
                
                if let depthConnection = self.depthOutput.connection(with: .depthData), depthConnection.isEnabled, self.photoOutput.isDepthDataDeliverySupported {
                    settings.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliveryEnabled
                }
                
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
    
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        Task { @MainActor in
            if let error = error {
                activePhotoContinuation?.resume(throwing: error)
            } else if let data = photo.fileDataRepresentation() {
                activePhotoContinuation?.resume(returning: data)
            } else {
                activePhotoContinuation?.resume(throwing: NSError(domain: "CameraManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to generate file data representation"]))
            }
            
            activePhotoContinuation = nil
        }
    }
    
    /// Safely orchestrates zoom interactions across the physical hardware without blocking the Main Thread
    func setZoomFactor(_ factor: CGFloat, animated: Bool = false) {
        let clamped = min(max(factor, minZoom), maxZoom)
        self.videoZoomFactor = clamped // Optimistic UI update instantly ensures 120Hz gesture fluidity
        
        queue.async { [weak self] in
            guard let self = self,
                  let deviceInput = self.session.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) as? AVCaptureDeviceInput else { return }
            
            let device = deviceInput.device
            do {
                try device.lockForConfiguration()
                if animated {
                    // Smooth motorized transition (Ideal for tapping UI pills)
                    device.ramp(toVideoZoomFactor: clamped, withRate: 5.0) 
                } else {
                    // Instant linear snap (Ideal for Pinch/Drag scrubbing)
                    device.videoZoomFactor = clamped
                }
                device.unlockForConfiguration()
            } catch {
                print("⚠️ Failed to lock AV device for zoom: \(error.localizedDescription)")
            }
        }
    }
}
