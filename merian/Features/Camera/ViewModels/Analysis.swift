import SwiftUI
import SwiftData

// MARK: - Pipeline Orchestration
extension CameraViewModel {
    
    // MARK: - ML Analysis Sequence
    
    func submitActiveScan(modelContext: ModelContext) {
        let capturedDatas = self.activeScannedDatas
        let displayImages = self.activeScanImages
        
        // 1. State Clear
        self.activeScannedDatas.removeAll()
        self.activeScanImages.removeAll()
        self.activeOriginals.removeAll()
        
        guard !capturedDatas.isEmpty else { return }
        
        let capturedDistance = diContainer.cameraManager.subjectDistanceInMeters
        
        Task { [weak self] in
            guard let self = self else { return }
            
            // 2. Optical Presentation Hook
            // Instantly trigger scanning UI so the user doesn't see a frozen camera feed
            await MainActor.run {
                self.analysisImages = displayImages
                self.scanningPhaseText = "Acquiring coordinates..."
                self.isAnalyzingFullscreen = true
            }
            
            // NEW: Enforce crop constraints cleanly before analysis!
            // We lazily defer cropping until submission or manual edit to dramatically accelerate the Camera Shutter UX!
            var inferenceDatas: [Data] = []
            var finalUIImages: [UIImage] = []
            
            for (index, image) in displayImages.enumerated() {
                // If it was manually cropped via ImageCropperView, it's saved strictly capped at 768px bounds
                let physicalMax = max(image.size.width, image.size.height) * image.scale
                if physicalMax <= 800 && index < capturedDatas.count {
                    inferenceDatas.append(capturedDatas[index])
                    finalUIImages.append(image)
                } else {
                    // It's still a raw 4000px uncropped capture and needs perfectly 1:1 auto-bounding right now
                    let centerCropped = await ImageCropProcessor.generateAutoCenterCrop(image: image)
                    inferenceDatas.append(centerCropped)
                    if let croppedThumb = UIImage(data: centerCropped) {
                        finalUIImages.append(croppedThumb)
                    } else {
                        finalUIImages.append(image)
                    }
                }
            }
            
            await MainActor.run {
                // Instantly snap the visual Optical bounds to exactly what Gemini is looking at organically
                self.analysisImages = finalUIImages
            }
            
            // 3. Environmental Synthesis Pipeline
            let context: EnvironmentContext
            if let activeTask = self.preFetchTask {
                context = await activeTask.value
                self.preFetchTask = nil
            } else {
                context = await self.diContainer.environmentContextManager.fetchDeferredContext(preLockedLocation: nil)
            }
            
            await MainActor.run {
                self.scanningPhaseText = "Analyzing subject..."
            }
            
            // 4. Rate Cap Consumption
            // Consume the strict free quota immediately upon commitment to prevent offline hoarding dynamically
            // Bound strictly to the submit Active Scan hook to support up to 2 frames simultaneously counting as 1 organic Scan natively 
            self.diContainer.usageManager.consumeScan()
            
            // 5. Generative Telemetry Parsing
            let telemetry = CaptureTelemetry(from: context, distance: capturedDistance)
            
            // 6. ML Inference Execution
            // Ships strict array payload globally to dynamically evaluated Supabase Edge logic natively 
            self.diContainer.inferenceEngine.analyze(
                imageDatas: inferenceDatas,
                telemetry: telemetry,
                modelContext: modelContext
            )
        }
    }
    
    // MARK: - State Listeners & Dispatch Context
    
    func synchronizeAnalysisState(isFullscreen: Bool) {
        if isFullscreen {
            diContainer.cameraManager.stopSession() // Revert viewport to off while analyzing over it
            
            // Dynamically rotate processing labels natively so the user feels active execution pacing during long 5-10 second global inference requests
            let engagingPrompts = [
                "Scanning image...",
                "Analyzing subject...",
                "Processing context...",
                "Evaluating matches...",
                "Identifying species...",
                "Finalizing result..."
            ]
            
            for (index, prompt) in engagingPrompts.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index + 1) * 1.6) {
                    if self.isAnalyzingFullscreen {
                        withAnimation(.easeIn(duration: 0.35)) {
                            self.scanningPhaseText = prompt
                        }
                    }
                }
            }
        } else {
            analysisImages.removeAll()
            if activeSheet != .insight {
                diContainer.cameraManager.startSession()
            }
        }
    }
    
    func handleInferenceProcessingChange(isStillProcessing: Bool) {
        if !isStillProcessing && isAnalyzingFullscreen {
            withAnimation {
                isAnalyzingFullscreen = false
            }
            // Safely defer the insight sheet presentation strictly forcing SwiftUI to stabilize
            // any hardware interactions from leaking `.paywall` checks concurrently
            DispatchQueue.main.async { [weak self] in
                self?.activeSheet = .insight
            }
        }
    }
}
