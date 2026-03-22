import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import SwiftData
import Photos
import Combine
import Observation

@Observable
@MainActor
final class CameraViewModel {
    
    // MARK: - Types
    enum ActiveSheet: String, Identifiable {
        case insight, paywall, scans, profile
        var id: String { rawValue }
    }
    
    // MARK: - Dependencies
    @ObservationIgnored let diContainer = AppDIContainer.shared
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    
    // MARK: - UI & Navigation State
    var activeSheet: ActiveSheet? = nil
    var imageToCrop: IdentifiableImage? = nil
    var selectedPhotoItem: PhotosPickerItem? = nil
    
    // MARK: - Camera & Scanning State
    var isCapturing: Bool = false
    var flashOpacity: Double = 0.0
    var isAnalyzingFullscreen: Bool = false
    var scanningPhaseText: String = "Analyzing subject..."
    var analysisImage: UIImage? = nil
    
    // MARK: - Asynchronous Jobs
    @ObservationIgnored var preFetchTask: Task<EnvironmentContext, Never>? = nil
    @ObservationIgnored private var focusTask: Task<Void, Never>? = nil
    
    // MARK: - Lifecycle
    init() {
        NotificationCenter.default.publisher(for: NSNotification.Name("AppDidEnterInactivePhase"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resetModalsForBackground() }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSNotification.Name("TriggerPaywall"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.activeSheet = .paywall
                self?.isAnalyzingFullscreen = false
            }
            .store(in: &cancellables)
    }
    
    private func resetModalsForBackground() {
        // Reset sheet boundaries so the user always returns to a clean camera view
        activeSheet = nil
        imageToCrop = nil
        
        // Do not violently kill the analyzing overlay natively if the Inference Engine is actively mid-scan in the background thread.
        if isAnalyzingFullscreen && !diContainer.inferenceEngine.isProcessing {
            isAnalyzingFullscreen = false
            scanningPhaseText = "Analyzing subject..."
            analysisImage = nil
            // Note: We deliberately DO NOT call `diContainer.inferenceEngine.cancelActiveRequest()` here.
        }
    }
    
    // MARK: - User Intents
    
    func handlePhotoPickerSelection(newItem: PhotosPickerItem?, modelContext: ModelContext) {
        Task { [weak self] in
            guard let self = self,
                  let newItem = newItem else { return }
            guard let wrapper = try? await newItem.loadTransferable(type: ImageFileWrapper.self) else { return }
            let validUrl = wrapper.url
            defer { try? FileManager.default.removeItem(at: validUrl) }
            
            // Attempt to retrieve native PHAsset context to map historical GPS / Weather
            var historicalContext: EnvironmentContext? = nil
            if let localId = newItem.itemIdentifier {
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil)
                if let asset = fetchResult.firstObject, let location = asset.location, let creationDate = asset.creationDate {
                    historicalContext = await self.diContainer.environmentContextManager.fetchHistoricalContext(location: location, date: creationDate)
                }
            }
            
            if self.diContainer.usageManager.canPerformScan(isProActive: self.diContainer.revenueCatManager.isProActive) {
                let detatchedDownsample = await Task.detached(priority: .userInitiated) {
                    ImageDownsampler.downsample(url: validUrl, maxSize: 4000)
                }.value
                
                if let cgImage = detatchedDownsample {
                    let rawImage = UIImage(cgImage: cgImage)
                    await MainActor.run {
                        self.imageToCrop = IdentifiableImage(image: rawImage, environmentContext: historicalContext, isFromGallery: true)
                        self.selectedPhotoItem = nil
                    }
                }
            } else {
                await MainActor.run {
                    AppTelemetry.trackPaywallImpression()
                    self.activeSheet = .paywall
                }
            }
        }
    }
    
    func handleSheetAppear() {
        diContainer.cameraManager.stopSession()
    }
    
    func handleSheetDismiss() {
        diContainer.cameraManager.startSession()
    }
}
