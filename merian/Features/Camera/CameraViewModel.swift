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
    
    // Analysis State
    @Published var isAnalyzingFullscreen: Bool = false
    @Published var scanningPhaseText: String = "Analyzing Subject..."
    @Published var analysisImage: UIImage? = nil
    
    // Dependencies
    private let diContainer = AppDIContainer.shared
    
    func handlePhotoPickerSelection(newItem: PhotosPickerItem?, modelContext: ModelContext) {
        Task {
            guard let newItem = newItem,
                  let data = try? await newItem.loadTransferable(type: Data.self) else { return }
            
            if diContainer.usageManager.canPerformScan(isProActive: diContainer.revenueCatManager.isProActive) {
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
        diContainer.inferenceEngine.analyze(imageData: croppedData, modelContext: modelContext)
        isAnalyzingFullscreen = true
    }
    
    func synchronizeAnalysisState(isFullscreen: Bool) {
        if isFullscreen {
            if let payload = diContainer.inferenceEngine.activePayload {
                analysisImage = UIImage(data: payload)
            }
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
}
