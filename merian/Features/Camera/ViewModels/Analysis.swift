import SwiftUI
import SwiftData

// MARK: - Pipeline Orchestration
extension CameraViewModel {
    
    // MARK: - ML Analysis Sequence
    
    func handleCropCompletion(croppedData: Data, modelContext: ModelContext) {
        // 1. Cache Extraction
        let historicalContext = imageToCrop?.environmentContext
        let isFromGallery = imageToCrop?.isFromGallery == true
        let capturedDistance = imageToCrop?.subjectDistanceInMeters
        imageToCrop = nil
        
        Task { [weak self] in
            guard let self = self else { return }
            
            // 2. Optical Presentation Hook
            // Instantly trigger scanning UI so the user doesn't see a frozen camera feed
            await MainActor.run {
                if let rawImage = UIImage(data: croppedData) {
                    self.analysisImage = rawImage
                }
                self.scanningPhaseText = "Acquiring coordinates..."
                self.isAnalyzingFullscreen = true
            }
            
            // 3. Environmental Synthesis Pipeline
            // Resolves historical EXIF data against live deferred hardware coordinates
            let context: EnvironmentContext
            if let historical = historicalContext, isFromGallery {
                context = historical
            } else if isFromGallery {
                // Prevent current GPS from overwriting a gallery photo lacking EXIF data
                context = EnvironmentContext(location: nil, weatherCondition: nil, weatherTemperature: nil)
            } else {
                if let activeTask = self.preFetchTask {
                    context = await activeTask.value
                    self.preFetchTask = nil
                } else {
                    let lockedLocation = historicalContext?.location
                    context = await self.diContainer.environmentContextManager.fetchDeferredContext(preLockedLocation: lockedLocation)
                }
            }
            
            await MainActor.run {
                self.scanningPhaseText = "Analyzing subject..."
            }
            
            // 4. Rate Cap Consumption
            // Consume the strict free quota immediately upon commitment to prevent offline hoarding 
            self.diContainer.usageManager.consumeScan()
            
            // 5. Generative Telemetry Parsing
            // Bundles context strictly scoped via ISO standards mapped directly into ML prompt sequences
            // Filter elevation based on hardware confidence to prevent 10m+ indoor drifts
            var reliableElevation: Double? = nil
            if let location = context.location, location.verticalAccuracy >= 0 && location.verticalAccuracy <= 25 {
                reliableElevation = location.altitude
            }
            
            let telemetry = CaptureTelemetry(
                subjectDistanceInMeters: capturedDistance,
                gpsLatitude: context.location?.coordinate.latitude,
                gpsLongitude: context.location?.coordinate.longitude,
                gpsElevation: reliableElevation,
                locationName: context.locationName,
                weatherCondition: context.weatherCondition,
                weatherTemperatureF: context.weatherTemperature,
                timeOfDay: nil,
                timestamp: ISO8601DateFormatter().string(from: context.location?.timestamp ?? Date())
            )
            
            // 6. ML Inference Execution
            // Ships payload globally to Supabase Edge logic
            self.diContainer.inferenceEngine.analyze(
                imageData: croppedData,
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
            analysisImage = nil
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
