import SwiftUI
import PhotosUI
import SwiftData

@MainActor
final class CameraViewModel: ObservableObject {
    // UI Navigation & Sheet State
    @Published var isInsightSheetOpen: Bool = false
    @Published var isPaywallOpen: Bool = false
    @Published var isLifeListOpen: Bool = false
    @Published var isUserProfileOpen: Bool = false
    @Published var imageToCrop: IdentifiableImage? = nil
    
    // Camera & Capture State
    @Published var selectedPhotoItem: PhotosPickerItem? = nil
    @Published var flashOpacity: Double = 0.0
    
    init() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppDidEnterInactivePhase"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resetModalsForBackground()
        }
    }
    
    private func resetModalsForBackground() {
        // Drop any presented sheets or camera modals immediately
        // so that returning to the app defaults specifically onto the Camera hardware.
        isInsightSheetOpen = false
        isPaywallOpen = false
        isLifeListOpen = false
        isUserProfileOpen = false
        imageToCrop = nil
        
        // Let the InferenceEngine know it must stop updating the active scanning loop on our view.
        if isAnalyzingFullscreen {
            isAnalyzingFullscreen = false
            scanningPhaseText = "Analyzing subject..."
            analysisImage = nil
            AppDIContainer.shared.inferenceEngine.cancelActiveRequest()
        }
    }
    
    // Analysis State
    @Published var isAnalyzingFullscreen: Bool = false
    @Published var scanningPhaseText: String = "Analyzing subject..."
    @Published var analysisImage: UIImage? = nil
    
    // Focus State
    @Published var focusLocation: CGPoint? = nil
    @Published var showFocusIndicator: Bool = false
    private var focusTask: Task<Void, Never>?
    
    // Dependencies
    private let diContainer = AppDIContainer.shared
    
    func handlePhotoPickerSelection(newItem: PhotosPickerItem?, modelContext: ModelContext) {
        Task { [weak self] in
            guard let self = self,
                  let newItem = newItem,
                  let data = try? await newItem.loadTransferable(type: Data.self) else { return }
            
            if self.diContainer.usageManager.canPerformScan(isProActive: self.diContainer.revenueCatManager.isProActive) {
                if let rawImage = UIImage(data: data) {
                    await MainActor.run {
                        self.imageToCrop = IdentifiableImage(image: rawImage)
                        self.selectedPhotoItem = nil
                    }
                }
            } else {
                await MainActor.run {
                    AppTelemetry.trackPaywallImpression()
                    self.isPaywallOpen = true
                }
            }
        }
    }
    
    func handleCropCompletion(croppedData: Data, modelContext: ModelContext) {
        imageToCrop = nil
        
        Task { [weak self] in
            guard let self = self else { return }
            
            // FIX: Instantly trigger scanning UI so the user doesn't see a frozen camera feed
            await MainActor.run {
                if let rawImage = UIImage(data: croppedData) {
                    self.analysisImage = rawImage
                }
                self.scanningPhaseText = "Acquiring coordinates..."
                self.isAnalyzingFullscreen = true
            }
            
            let context = await self.diContainer.environmentContextManager.fetchDeferredContext()
            
            await MainActor.run {
                self.scanningPhaseText = "Analyzing subject..."
            }
            
            self.diContainer.inferenceEngine.analyze(
                imageData: croppedData,
                subjectDistanceInMeters: self.diContainer.cameraManager.subjectDistanceInMeters,
                gpsLatitude: context.location?.coordinate.latitude,
                gpsLongitude: context.location?.coordinate.longitude,
                gpsElevation: context.location?.altitude,
                weatherCondition: context.weatherCondition,
                weatherTemperatureF: context.weatherTemperature,
                modelContext: modelContext
            )
        }
    }
    
    func synchronizeAnalysisState(isFullscreen: Bool) {
        if isFullscreen {
            diContainer.cameraManager.stopSession() // Revert viewport to off while analyzing over it
            scanningPhaseText = "Scanning..."
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.isAnalyzingFullscreen {
                    withAnimation {
                        self.scanningPhaseText = "Identifying..."
                    }
                }
            }
        } else {
            analysisImage = nil
            if !isInsightSheetOpen {
                diContainer.cameraManager.startSession()
            }
        }
    }
    
    func handleInferenceProcessingChange(isStillProcessing: Bool) {
        if !isStillProcessing && isAnalyzingFullscreen {
            withAnimation {
                isAnalyzingFullscreen = false
            }
            isInsightSheetOpen = true
        }
    }
    
    func handleSheetAppear() {
        diContainer.cameraManager.stopSession()
    }
    
    func handleSheetDismiss() {
        diContainer.cameraManager.startSession()
    }
    
    func triggerFlash() {
        flashOpacity = 1.0
        withAnimation(.easeOut(duration: 0.15)) {
            flashOpacity = 0.0
        }
    }
    
    func handleFocusTap(layerPoint: CGPoint, devicePoint: CGPoint) {
        diContainer.cameraManager.setFocusPoint(devicePoint)
        diContainer.hapticManager.triggerSelectionPulse()
        
        focusLocation = layerPoint
        showFocusIndicator = true
        
        focusTask?.cancel()
        focusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled {
                withAnimation(.easeOut) {
                    showFocusIndicator = false
                }
            }
        }
    }
    
    func executeCapture() {
        // Prevent accidental hardware captures while a modal, sheet, or crop view is actively presented
        guard !isInsightSheetOpen, 
              !isLifeListOpen, 
              !isPaywallOpen, 
              !isUserProfileOpen, 
              !isAnalyzingFullscreen, 
              imageToCrop == nil else { return }
              
        if diContainer.usageManager.canPerformScan(isProActive: diContainer.revenueCatManager.isProActive) {
            // Instant tactile UI response mirroring the Apple Camera app
            AppDIContainer.shared.hapticManager.triggerMediumPulse()
            
            triggerFlash()
            
            Task {
                do {
                    let captureData = try await diContainer.cameraManager.captureImage()
                    
                    // Actively push the original 12MP buffer down natively into the user's Camera Roll securely
                    await diContainer.photoLibraryManager.saveImageToLibrary(imageData: captureData)
                    
                    if let rawImage = UIImage(data: captureData) {
                        await MainActor.run {
                            self.imageToCrop = IdentifiableImage(image: rawImage)
                        }
                    }
                } catch {
                    print("⚠️ Hardware Shutter failure: \(error.localizedDescription)")
                }
            }
        } else {
            AppTelemetry.trackPaywallImpression()
            self.isPaywallOpen = true
        }
    }
}
