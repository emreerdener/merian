import SwiftUI

private struct PreparedCameraCapture: Sendable {
    let inferenceData: Data
    let displayData: Data
    let previewCGImage: SendableCGImage
}

extension CaptureWorkspaceViewModel {

    nonisolated private static func prepareCameraCapture(
        captureData: Data,
        composingCenter: CGFloat,
        isProActive: Bool
    ) async throws -> PreparedCameraCapture? {
        try await DetachedWork.value(
            priority: .userInitiated,
            category: .imagePreparation
        ) {
            autoreleasepool {
                let inferenceMaxSize = MerianConfig.inferenceImageMaxSize(isProActive: isProActive)
                guard let safeCGImage = ImageDownsampler.downsample(data: captureData, maxSize: inferenceMaxSize) else {
                    return nil
                }

                let croppedCGImage = ImageCropProcessor.squareCrop(
                    safeCGImage,
                    verticalCenterFraction: composingCenter
                ) ?? safeCGImage

                guard let finalSafeData = ImageCropProcessor.encode(croppedCGImage),
                      !finalSafeData.isEmpty else {
                    return nil
                }

                let displaySafeData: Data = {
                    guard let displayCGImage = ImageDownsampler.downsample(
                        data: captureData,
                        maxSize: MerianConfig.displayImageMaxSize
                    ) else {
                        return finalSafeData
                    }
                    let croppedDisplayCGImage = ImageCropProcessor.squareCrop(
                        displayCGImage,
                        verticalCenterFraction: composingCenter
                    ) ?? displayCGImage
                    return ImageCropProcessor.encode(croppedDisplayCGImage) ?? finalSafeData
                }()

                return PreparedCameraCapture(
                    inferenceData: finalSafeData,
                    displayData: displaySafeData,
                    previewCGImage: SendableCGImage(image: safeCGImage)
                )
            }
        }
    }
    
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
              hasAvailableStagedCaptureSlot,
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
                    async let shutterLocation = diContainer.environmentContextManager.requestCurrentLocation()
                    let composingCenter = composingZoneVerticalCenter
                    let captureData = try await diContainer.cameraManager.captureImage()
                    let resolvedShutterLocation = await shutterLocation
                    let instantLocation = resolvedShutterLocation ?? diContainer.environmentContextManager.lastKnownLocation
                    
                    // Actively push the original 12MP buffer down natively into the user's Camera Roll securely without blocking UI sweeps natively
                    Task {
                        await AppDIContainer.shared.photoLibraryManager.saveImageToLibrary(imageData: captureData, location: instantLocation)
                    }
                    // 4. Detached Memory Pipeline
                    // Downsamples the 12MP buffer globally off the UI thread to massively drop the footprint
                    // Instantly executes native `generateAutoCenterCrop` natively isolating UIImage and CGImage pointers 
                    // cleanly inside the background securely, exporting solely safe raw `.Data` out bypassing JetSam limits globally
                    
                    let preparedCapture = try await Self.prepareCameraCapture(
                        captureData: captureData,
                        composingCenter: composingCenter,
                        isProActive: diContainer.revenueCatManager.isProActive
                    )

                    if let preparedCapture {
                        // 5. Environmental Pre-Fetching
                        // Maps historical location caching before pushing to identity pipeline
                        let task = Task {
                            return await AppDIContainer.shared.environmentContextManager.fetchDeferredContext(preLockedLocation: instantLocation)
                        }

                        // 6. MainActor Routing
                        // Injecting the raw safe bytes bounds back strictly on the UI thread
                        await MainActor.run {
                            self.preFetchTask = task
                            let backgroundRawImage = UIImage(cgImage: preparedCapture.previewCGImage.image, scale: 1.0, orientation: .up)
                            let identifiable = IdentifiableImage(image: backgroundRawImage, environmentContext: nil, isFromGallery: false)
                            self.stagedCapture.images.append(StagedImage(
                                compressedData: preparedCapture.inferenceData,
                                displayData: preparedCapture.displayData,
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
