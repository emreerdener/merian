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
              activeScanImages.count < 2,
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
                    Task {
                        await AppDIContainer.shared.photoLibraryManager.saveImageToLibrary(imageData: captureData, location: instantLocation)
                    }
                    // 4. Detached Memory Pipeline
                    // Downsamples the 12MP buffer globally off the UI thread to massively drop the footprint
                    // Instantly executes native `generateAutoCenterCrop` natively isolating UIImage and CGImage pointers 
                    // cleanly inside the background securely, exporting solely safe raw `.Data` out bypassing JetSam limits globally
                    
                    let safeCGImage = ImageDownsampler.shared.downsample(data: captureData, maxSize: 4000)
                    
                    let finalSafeData: Data = {
                        guard let cgImage = safeCGImage else { return Data() }
                        return autoreleasepool {
                            // kCGImageSourceCreateThumbnailWithTransform already bakes the EXIF
                            // orientation into the CGImage pixels — use .up to avoid a second rotation.
                            let tempRawImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
                            return tempRawImage.jpegData(compressionQuality: 0.8) ?? Data()
                        }
                    }()


                    if !finalSafeData.isEmpty, let validCGImage = safeCGImage {
                        // 5. Environmental Pre-Fetching
                        // Maps historical location caching before pushing to identity pipeline
                        let task = Task {
                            return await AppDIContainer.shared.environmentContextManager.fetchDeferredContext(preLockedLocation: instantLocation)
                        }

                        // 6. MainActor Routing
                        // Injecting the raw safe bytes bounds back strictly on the UI thread
                        await MainActor.run {
                            self.preFetchTask = task
                            let backgroundRawImage = UIImage(cgImage: validCGImage, scale: 1.0, orientation: .up)
                            let identifiable = IdentifiableImage(image: backgroundRawImage, environmentContext: nil, isFromGallery: false)
                            self.activeOriginals.append(identifiable)
                            self.activeScannedDatas.append(finalSafeData)
                            if let thumbnail = UIImage(data: finalSafeData) {
                                self.activeScanImages.append(thumbnail)
                            }
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
