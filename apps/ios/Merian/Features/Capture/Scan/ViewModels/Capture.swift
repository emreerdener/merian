import AVFoundation
import SwiftUI

private struct PreparedCameraCapture: Sendable {
    let inferenceData: Data
    let displayData: Data
    let previewCGImage: SendableCGImage
}

extension CaptureWorkspaceViewModel {
    static let videoMaxDuration: TimeInterval = 5

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

    nonisolated private static func prepareVideoFrames(
        videoURL: URL,
        duration: TimeInterval,
        composingCenter: CGFloat,
        isProActive: Bool
    ) async throws -> [PreparedCameraCapture] {
        try await DetachedWork.value(
            priority: .userInitiated,
            category: .imagePreparation
        ) {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(
                width: MerianConfig.displayImageMaxSize,
                height: MerianConfig.displayImageMaxSize
            )

            let resolvedDuration = max(duration, 0.1)
            let sampleOffsets = [0.1, 0.5, 0.9].map { min(max(resolvedDuration * $0, 0.05), max(resolvedDuration - 0.05, 0.05)) }
            let times = sampleOffsets.map { CMTime(seconds: $0, preferredTimescale: 600) }
            let inferenceMaxSize = MerianConfig.inferenceImageMaxSize(isProActive: isProActive)

            return times.compactMap { time -> PreparedCameraCapture? in
                autoreleasepool {
                    guard let frame = try? generator.copyCGImage(at: time, actualTime: nil) else {
                        return nil
                    }
                    let displayFrame = ImageCropProcessor.squareCrop(
                        frame,
                        verticalCenterFraction: composingCenter
                    ) ?? frame
                    guard let displayData = ImageCropProcessor.encode(displayFrame),
                          !displayData.isEmpty else {
                        return nil
                    }

                    let inferenceFrame = ImageDownsampler.downsample(
                        data: displayData,
                        maxSize: inferenceMaxSize
                    ) ?? displayFrame
                    let inferenceCropped = ImageCropProcessor.squareCrop(
                        inferenceFrame,
                        verticalCenterFraction: composingCenter
                    ) ?? inferenceFrame
                    guard let inferenceData = ImageCropProcessor.encode(inferenceCropped),
                          !inferenceData.isEmpty else {
                        return nil
                    }

                    return PreparedCameraCapture(
                        inferenceData: inferenceData,
                        displayData: displayData,
                        previewCGImage: SendableCGImage(image: displayFrame)
                    )
                }
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

    func startVideoCapture() {
        guard activeSheet == nil,
              !isCapturing,
              !isVideoRecording,
              hasAvailableStagedCaptureSlot,
              imageToCrop == nil else { return }
        guard diContainer.revenueCatManager.isProActive else { return }

        isCapturing = true
        isVideoRecording = true
        videoRecordingProgress = 0
        diContainer.hapticManager.triggerHeavyImpact(intensity: 1.0)
        startVideoRecordingProgressTimer()

        videoRecordingTask?.cancel()
        videoRecordingTask = Task {
            do {
                async let shutterLocation = diContainer.environmentContextManager.requestCurrentLocation()
                let composingCenter = composingZoneVerticalCenter
                let recording = try await diContainer.cameraManager.recordVideo(maxDuration: Self.videoMaxDuration)
                let resolvedShutterLocation = await shutterLocation
                let instantLocation = resolvedShutterLocation ?? diContainer.environmentContextManager.lastKnownLocation
                let preparedFrames = try await Self.prepareVideoFrames(
                    videoURL: recording.fileURL,
                    duration: recording.duration,
                    composingCenter: composingCenter,
                    isProActive: diContainer.revenueCatManager.isProActive
                )
                guard !preparedFrames.isEmpty else {
                    throw NSError(
                        domain: "CaptureWorkspaceViewModel",
                        code: -20,
                        userInfo: [NSLocalizedDescriptionKey: "Unable to sample frames from the recorded video."]
                    )
                }

                let task = Task {
                    await AppDIContainer.shared.environmentContextManager.fetchDeferredContext(preLockedLocation: instantLocation)
                }

                await MainActor.run {
                    self.preFetchTask = task
                    let stagedFrames = preparedFrames.map { frame in
                        let previewImage = UIImage(cgImage: frame.previewCGImage.image, scale: 1.0, orientation: .up)
                        return StagedImage(
                            compressedData: frame.inferenceData,
                            displayData: frame.displayData,
                            uiImage: previewImage,
                            original: IdentifiableImage(image: previewImage, environmentContext: nil, isFromGallery: false)
                        )
                    }
                    self.stagedCapture.videos.append(StagedVideo(
                        filePath: recording.fileURL.path,
                        sampledImages: stagedFrames
                    ))
                    AppDIContainer.shared.hapticManager.triggerSuccessPulse()
                }
            } catch is CancellationError {
                diContainer.cameraManager.stopVideoRecording()
            } catch {
                MerianLog.hardware.error("Video shutter failure: \(error, privacy: .private)")
                await MainActor.run {
                    AppDIContainer.shared.hapticManager.triggerErrorThump()
                }
            }

            await MainActor.run {
                self.stopVideoRecordingProgressTimer(reset: true)
                self.isCapturing = false
                self.isVideoRecording = false
            }
        }
    }

    func stopVideoCapture() {
        guard isVideoRecording else { return }
        AppDIContainer.shared.hapticManager.triggerMediumPulse()
        diContainer.cameraManager.stopVideoRecording()
    }

    private func startVideoRecordingProgressTimer() {
        videoRecordingProgressTask?.cancel()
        videoRecordingProgressTask = Task { @MainActor in
            let tickNanoseconds: UInt64 = 50_000_000
            let tickDuration = 0.05
            var elapsed: TimeInterval = 0

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: tickNanoseconds)
                guard !Task.isCancelled else { return }
                elapsed += tickDuration
                videoRecordingProgress = min(1, elapsed / Self.videoMaxDuration)

                if elapsed >= Self.videoMaxDuration {
                    HapticManager.shared.triggerHeavyImpact(intensity: 1.0)
                    return
                }
            }
        }
    }

    private func stopVideoRecordingProgressTimer(reset: Bool) {
        videoRecordingProgressTask?.cancel()
        videoRecordingProgressTask = nil
        if reset {
            videoRecordingProgress = 0
        }
    }
}
