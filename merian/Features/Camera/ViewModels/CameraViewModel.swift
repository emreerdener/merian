import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import SwiftData
import Photos
import Combine

struct ImageFileWrapper: Transferable, Sendable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { wrapper in
            SentTransferredFile(wrapper.url)
        } importing: { received in
            let tempDir = FileManager.default.temporaryDirectory
            let tempDst = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: tempDst)
            return Self(url: tempDst)
        }
    }
}

@MainActor
final class CameraViewModel: ObservableObject {
    enum ActiveSheet: String, Identifiable {
        case insight
        case paywall
        case scans
        case profile
        case settings
        
        var id: String { rawValue }
    }
    
    // UI Navigation & Sheet State
    @Published var activeSheet: ActiveSheet? = nil
    @Published var imageToCrop: IdentifiableImage? = nil
    
    // Camera & Capture State
    @Published var selectedPhotoItem: PhotosPickerItem? = nil
    @Published var flashOpacity: Double = 0.0
    @Published var isCapturing: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        NotificationCenter.default.publisher(for: NSNotification.Name("AppDidEnterInactivePhase"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.resetModalsForBackground()
            }
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
        diContainer.gamificationManager.showTerrariumSheet = false
        
        // Do not violently kill the analyzing overlay natively if the Inference Engine is actively mid-scan in the background thread.
        // Otherwise, the user returns to empty UI while `isProcessing` silently completes offscreen dropping the UI presentation logic entirely.
        if isAnalyzingFullscreen && !diContainer.inferenceEngine.isProcessing {
            isAnalyzingFullscreen = false
            scanningPhaseText = "Analyzing subject..."
            analysisImage = nil
            // Note: We deliberately DO NOT call `diContainer.inferenceEngine.cancelActiveRequest()` here.
            // If we did, it would nil out the active payload before `AppDIContainer.handleBackgroundPhase`
            // could actually securely rescue the payload into the OfflineQueueManager natively.
        }
    }
    
    // Analysis State
    @Published var isAnalyzingFullscreen: Bool = false
    @Published var scanningPhaseText: String = "Analyzing subject..."
    @Published var analysisImage: UIImage? = nil
    
    // Asynchronous Context Pipeline
    @Published var preFetchedContext: EnvironmentContext? = nil
    
    // Focus State
    @Published var focusLocation: CGPoint? = nil
    @Published var showFocusIndicator: Bool = false
    private var focusTask: Task<Void, Never>?
    
    // Dependencies
    private let diContainer = AppDIContainer.shared
    
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
    
    func handleCropCompletion(croppedData: Data, modelContext: ModelContext) {
        let historicalContext = imageToCrop?.environmentContext
        let isFromGallery = imageToCrop?.isFromGallery == true
        let flashFired = imageToCrop?.isFlashFired
        let capturedDistance = imageToCrop?.subjectDistanceInMeters
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
            
            let context: EnvironmentContext
            if let historical = historicalContext, isFromGallery {
                context = historical
            } else if isFromGallery {
                // Prevent current GPS from overwriting a gallery photo lacking EXIF data
                context = EnvironmentContext(location: nil, weatherCondition: nil, weatherTemperature: nil)
            } else {
                if let mappedContext = self.preFetchedContext {
                    context = mappedContext
                    self.preFetchedContext = nil
                } else {
                    let lockedLocation = historicalContext?.location
                    context = await self.diContainer.environmentContextManager.fetchDeferredContext(preLockedLocation: lockedLocation)
                }
            }
            
            await MainActor.run {
                self.scanningPhaseText = "Analyzing subject..."
            }
            
            // Consume the strict free quota immediately upon commitment to prevent offline hoarding 
            self.diContainer.usageManager.consumeScan()
            
            let telemetry = CaptureTelemetry(
                subjectDistanceInMeters: capturedDistance,
                gpsLatitude: context.location?.coordinate.latitude,
                gpsLongitude: context.location?.coordinate.longitude,
                gpsElevation: context.location?.altitude,
                locationName: context.locationName,
                weatherCondition: context.weatherCondition,
                weatherTemperatureF: context.weatherTemperature,
                cameraPitchDegrees: context.cameraPitchDegrees,
                compassHeading: context.compassHeading,
                relativeHumidity: context.relativeHumidity,
                uvIndex: context.uvIndex,
                isFlashFired: flashFired
            )
            
            self.diContainer.inferenceEngine.analyze(
                imageData: croppedData,
                telemetry: telemetry,
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
            activeSheet = .insight
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
        guard activeSheet == nil,
              !isAnalyzingFullscreen, 
              !isCapturing,
              imageToCrop == nil else { return }
              
        isCapturing = true
              
        if diContainer.usageManager.canPerformScan(isProActive: diContainer.revenueCatManager.isProActive) {
            // Instant tactile UI response mirroring the Apple Camera app
            AppDIContainer.shared.hapticManager.triggerMediumPulse()
            
            triggerFlash()
            
            Task {
                do {
                    let instantLocation = diContainer.environmentContextManager.cachedLocation
                    let captureData = try await diContainer.cameraManager.captureImage()
                    
                    // Actively push the original 12MP buffer down natively into the user's Camera Roll securely without blocking UI sweeps natively
                    Task.detached(priority: .utility) {
                        await AppDIContainer.shared.photoLibraryManager.saveImageToLibrary(imageData: captureData, location: instantLocation)
                    }
                    
                    let flashFired = diContainer.cameraManager.isFlashEnabled
                    let capturedDistance = diContainer.cameraManager.subjectDistanceInMeters
                    
                    let detachedDownsample = await Task.detached(priority: .userInitiated) {
                        ImageDownsampler.downsample(data: captureData, maxSize: 4000)
                    }.value
                    
                    if let cgImage = detachedDownsample {
                        let rawImage = UIImage(cgImage: cgImage)
                        
                        Task.detached(priority: .userInitiated) {
                            let prefetched = await AppDIContainer.shared.environmentContextManager.fetchDeferredContext(preLockedLocation: instantLocation)
                            await MainActor.run {
                                self.preFetchedContext = prefetched
                            }
                        }
                        
                        await MainActor.run {
                            self.imageToCrop = IdentifiableImage(
                                image: rawImage,
                                environmentContext: instantLocation != nil ? EnvironmentContext(location: instantLocation) : nil,
                                isFromGallery: false,
                                isFlashFired: flashFired,
                                subjectDistanceInMeters: capturedDistance
                            )
                        }
                    }
                } catch {
                    print("⚠️ Hardware Shutter failure: \(error.localizedDescription)")
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
