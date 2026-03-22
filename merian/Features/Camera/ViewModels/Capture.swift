import SwiftUI
extension CameraViewModel {
    
    // MARK: - UI Coordination
    
    func triggerFlash() {
        flashOpacity = 1.0
        withAnimation(.easeOut(duration: 0.15)) {
            flashOpacity = 0.0
        }
    }
    
    func handleFocusTap(devicePoint: CGPoint) {
        diContainer.cameraManager.setFocusPoint(devicePoint)
        diContainer.hapticManager.triggerSelectionPulse()
    }
    
    // MARK: - Shutter Pipeline
    
    func executeCapture() {
        // 1. Concurrency Guards
        // Prevent accidental hardware captures while a modal, sheet, or crop view is actively presented
        guard activeSheet == nil,
              !isAnalyzingFullscreen, 
              !isCapturing,
              imageToCrop == nil else { return }
              
        isCapturing = true
              
        // 2. Authorization Hooks
        if diContainer.usageManager.canPerformScan(isProActive: diContainer.revenueCatManager.isProActive) {
            // Instant tactile UI response mirroring the Apple Camera app
            AppDIContainer.shared.hapticManager.triggerMediumPulse()
            
            triggerFlash()
            
            Task {
                do {
                    // 3. Hardware Interfacing
                    // Securing the optical frame and geographical context precisely at shutter click
                    let instantLocation = diContainer.environmentContextManager.cachedLocation
                    let captureData = try await diContainer.cameraManager.captureImage()
                    
                    // Actively push the original 12MP buffer down natively into the user's Camera Roll securely without blocking UI sweeps natively
                    Task.detached(priority: .utility) {
                        await AppDIContainer.shared.photoLibraryManager.saveImageToLibrary(imageData: captureData, location: instantLocation)
                    }
                    let capturedDistance = diContainer.cameraManager.subjectDistanceInMeters
                    
                    // 4. Detached Memory Management
                    // Downsamples the 12MP buffer globally off the UI thread to massively drop the footprint
                    let detachedDownsample = await Task.detached(priority: .userInitiated) {
                        ImageDownsampler.downsample(data: captureData, maxSize: 4000)
                    }.value
                    
                    if let cgImage = detachedDownsample {
                        let rawImage = UIImage(cgImage: cgImage)
                        
                        // 5. Environmental Pre-Fetching
                        // Maps historical location caching before pushing to identity pipeline
                        let task = Task.detached(priority: .userInitiated) {
                            return await AppDIContainer.shared.environmentContextManager.fetchDeferredContext(preLockedLocation: instantLocation)
                        }
                        
                        // 6. MainActor Routing
                        // Injecting the IdentifiableImage bounds back strictly on the UI thread 
                        await MainActor.run {
                            self.preFetchTask = task
                            self.imageToCrop = IdentifiableImage(
                                image: rawImage,
                                environmentContext: instantLocation != nil ? EnvironmentContext(location: instantLocation) : nil,
                                isFromGallery: false,
                                subjectDistanceInMeters: capturedDistance
                            )
                        }
                    }
                } catch {
                    print("⚠️ Hardware shutter failure: \(error.localizedDescription)")
                }
                
                await MainActor.run {
                    self.isCapturing = false
                }
            }
        } else {
            AppTelemetry.trackPaywallImpression()
            self.activeSheet = .paywall
            self.isCapturing = false
        }
    }
}
