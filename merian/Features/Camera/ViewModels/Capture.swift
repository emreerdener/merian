import SwiftUI
extension CaptureWorkspaceViewModel {
    
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
              !isCapturing,
              stagedCapture.images.count < stagedImageCapacity,
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
                    let composingCenter = composingZoneVerticalCenter
                    let captureData = try await diContainer.cameraManager.captureImage()
                    
                    // Actively push the original 12MP buffer down natively into the user's Camera Roll securely without blocking UI sweeps natively
                    Task {
                        await AppDIContainer.shared.photoLibraryManager.saveImageToLibrary(imageData: captureData, location: instantLocation)
                    }
                    // 4. Detached Memory Pipeline
                    // Downsamples the 12MP buffer globally off the UI thread to massively drop the footprint
                    // Instantly executes native `generateAutoCenterCrop` natively isolating UIImage and CGImage pointers 
                    // cleanly inside the background securely, exporting solely safe raw `.Data` out bypassing JetSam limits globally
                    
                    // Inference payload: tier-conditional longest edge — 768 px (single Gemini
                    // vision tile, ~75% token savings) for Flash/free tier, 1024 px (four tiles,
                    // full morphological detail) for Pro. The full-resolution photo was already
                    // saved to Camera Roll above.
                    let safeCGImage = ImageDownsampler.downsample(data: captureData, maxSize: MerianConfig.inferenceImageMaxSize(isProActive: diContainer.revenueCatManager.isProActive))

                    // Crop to a square centered on the composing zone — the visible area between
                    // the mode toggle (top) and the capture button row (bottom). Falls back to the
                    // uncropped downsampled image if cropping fails (should never happen in practice).
                    let croppedCGImage = safeCGImage.flatMap {
                        ImageCropProcessor.squareCrop($0, verticalCenterFraction: composingCenter)
                    } ?? safeCGImage

                    // kCGImageSourceCreateThumbnailWithTransform already bakes the EXIF
                    // orientation into the CGImage pixels — no orientation option needed.
                    let finalSafeData: Data = croppedCGImage.flatMap {
                        ImageCropProcessor.encode($0)
                    } ?? Data()

                    // Display payload: 2048 px longest edge — written to disk so the insight
                    // sheet and scan library render crisp. The AI never sees this data;
                    // only finalSafeData is base64-encoded for Gemini.
                    // Same composing-zone crop applied for visual consistency with the inference frame.
                    let displaySafeData: Data = {
                        guard let displayCGImage = ImageDownsampler.downsample(data: captureData, maxSize: MerianConfig.displayImageMaxSize) else {
                            return finalSafeData // fallback to inference quality
                        }
                        let croppedDisplayCGImage = ImageCropProcessor.squareCrop(displayCGImage, verticalCenterFraction: composingCenter) ?? displayCGImage
                        return ImageCropProcessor.encode(croppedDisplayCGImage) ?? finalSafeData
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
                            self.stagedCapture.images.append(StagedImage(
                                compressedData: finalSafeData,
                                displayData: displaySafeData,
                                uiImage: backgroundRawImage,
                                original: identifiable
                            ))
                        }
                    }
                } catch {
                    MerianLog.hardware.error("Hardware shutter failure: \(error, privacy: .private)")
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
