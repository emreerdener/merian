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
    var editingCropIndex: Int? = nil
    var activeScannedDatas: [Data] = []
    var activeScanImages: [UIImage] = []
    var activeOriginals: [IdentifiableImage] = []
    var selectedPhotoItems: [PhotosPickerItem] = []
    var isTooltipVisible: Bool = false
    
    // MARK: - Camera & Scanning State
    var isCapturing: Bool = false
    var flashOpacity: Double = 0.0
    var isAnalyzingFullscreen: Bool = false
    var scanningPhaseText: String = "Analyzing subject..."
    var analysisImages: [UIImage] = []
    
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
            
        NotificationCenter.default.publisher(for: NSNotification.Name("AppDidEnterActivePhaseWithScan"))
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                if let scanId = notification.userInfo?["scanId"] as? String {
                    self?.handleDeepLinkRoute(scanId: scanId)
                }
            }
            .store(in: &cancellables)
    }
    
    private func resetModalsForBackground() {
        // Reset sheet boundaries so the user always returns to a clean camera view
        activeSheet = nil
        imageToCrop = nil
        editingCropIndex = nil
        activeScannedDatas.removeAll()
        activeScanImages.removeAll()
        activeOriginals.removeAll()
        selectedPhotoItems.removeAll()
        
        // Do not violently kill the analyzing overlay natively if the Inference Engine is actively mid-scan in the background thread.
        if isAnalyzingFullscreen && !diContainer.inferenceEngine.isProcessing {
            isAnalyzingFullscreen = false
            scanningPhaseText = "Analyzing subject..."
            analysisImages.removeAll()
            // Note: We deliberately DO NOT call `diContainer.inferenceEngine.cancelActiveRequest()` here.
        }
    }
    
    // MARK: - App Linking
    
    private func handleDeepLinkRoute(scanId: String) {
        // SwiftData Context Access boundary seamlessly leveraging the shared queue context
        guard let context = diContainer.offlineQueueManager.modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
            if let record = (try context.fetch(descriptor)).first {
                diContainer.inferenceEngine.load(from: record)
                self.activeSheet = .insight
            }
        } catch {
            print("Failed to route deeply natively to scanId \(scanId): \(error)")
        }
    }
    
    // MARK: - User Intents
    
    func handlePhotoPickerSelection(newItems: [PhotosPickerItem], modelContext: ModelContext) {
        guard !newItems.isEmpty else { return }
        
        Task { [weak self] in
            guard let self = self else { return }
            
            let itemsToProcess = newItems
            await MainActor.run { self.selectedPhotoItems.removeAll() }
            
            for newItem in itemsToProcess {
                // Fast-fail check to protect strictly against exceeding the strict 2-image limit natively
                if await MainActor.run(resultType: Bool.self, body: { self.activeScanImages.count >= 2 }) {
                    break
                }
                
                guard let wrapper = try? await newItem.loadTransferable(type: ImageFileWrapper.self) else { continue }
                let validUrl = wrapper.url
                
                // Scope the defer explicitly into an immediate do-block to guarantee memory unlocks natively per-loop
                do {
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
                        let detatchedDownsample = await ImageDownsampler.shared.downsample(url: validUrl, maxSize: 4000)
                        
                        if let cgImage = detatchedDownsample {
                            let rawImage = UIImage(cgImage: cgImage)
                            let finalSafeData = rawImage.jpegData(compressionQuality: 0.8) ?? Data()
                            
                            await MainActor.run {
                                let identifiable = IdentifiableImage(image: rawImage, environmentContext: historicalContext, isFromGallery: true)
                                self.activeOriginals.append(identifiable)
                                self.activeScannedDatas.append(finalSafeData)
                                if let thumb = UIImage(data: finalSafeData) {
                                    self.activeScanImages.append(thumb)
                                }
                            }
                        }
                    } else {
                        await MainActor.run {
                            AppTelemetry.trackPaywallImpression()
                            self.activeSheet = .paywall
                        }
                        break // Break immediately if hit paywall limits natively
                    }
                }
            }
        }
    }
    
    // MARK: - Manual Crop Routing
    func presentCrop(for index: Int) {
        guard index < activeOriginals.count else { return }
        self.editingCropIndex = index
        self.imageToCrop = activeOriginals[index]
    }
    
    // MARK: - Tooltip Orchestration
    private var tooltipTask: Task<Void, Never>? = nil
    
    func scheduleTooltipDismissal() async {
        tooltipTask?.cancel()
        
        tooltipTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                self.isTooltipVisible = true
            }
            
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.2)) {
                    self.isTooltipVisible = false
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
