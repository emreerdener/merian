import Combine
import Observation
import Photos
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
    var activeSheet: ActiveSheet?
    var imageToCrop: IdentifiableImage?
    var editingCropIndex: Int?
    var activeScannedDatas: [Data] = []
    var activeScanImages: [UIImage] = []
    var activeOriginals: [IdentifiableImage] = []
    var selectedPhotoItems: [PhotosPickerItem] = []
    var isTooltipVisible: Bool = false
    /// Display-quality (2048 px) versions of the staged captures, written to disk after
    /// inference so the insight sheet and scan library render without JPEG blocking artifacts.
    /// Kept separate from `activeScannedDatas` so the AI inference path never sees the
    /// larger payload — only `activeScannedDatas` (1024 px) is base64-encoded for Gemini.
    var activeDisplayDatas: [Data] = []
    
    // MARK: - Composing Zone
    /// Vertical center of the on-screen composing zone as a fraction of screen height (0–1).
    /// Set by CameraRootView once layout is measured. The capture pipeline uses this to
    /// center the auto-crop on the region the user actually frames their subject in,
    /// rather than the geometric center of the full sensor image.
    var composingZoneVerticalCenter: CGFloat = 0.5
    // MARK: - Camera & Scanning State
    var isCapturing: Bool = false
    var flashOpacity: Double = 0.0
    
    // MARK: - Asynchronous Jobs
    @ObservationIgnored var preFetchTask: Task<EnvironmentContext, Never>?
    @ObservationIgnored private var focusTask: Task<Void, Never>?
    
    // MARK: - Lifecycle
    init() {
        // Pre-warm the HTTPS connection to Supabase and refresh the auth token while the
        // user composes their shot. Eliminates TCP/TLS handshake (~200–400ms) and token
        // refresh latency from the scan critical path on cold app launch.
        Task {
            _ = try? await SupabaseManager.shared.getValidAuthHeaders()
        }

        // Centralized System Event Routing (AppEventPublisher)
        diContainer.appEventPublisher.publisher
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                switch event {
                case .appDidEnterInactivePhase:
                    self?.resetModalsForBackground()
                case .triggerPaywall:
                    self?.activeSheet = .paywall
                case .appDidEnterActivePhaseWithScan(let scanId):
                    self?.handleDeepLinkRoute(scanId: scanId)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Background Reset Policy

    /// Controls whether the staging state is preserved when the app enters the background.
    ///
    /// Return `true` to keep staged images and the active scan toolbar intact on foreground return.
    /// Return `false` to wipe staging and return to the default camera view.
    ///
    /// Add cases here as new interrupt-sensitive states are introduced.
    private var shouldPreserveStagingOnBackground: Bool {
        // User has images staged for submission — a brief background trip should not discard their work.
        !activeScanImages.isEmpty
    }

    private func resetModalsForBackground() {
        // Sheets and crop state always close — they hold UI locks and must not reopen stale.
        activeSheet = nil
        imageToCrop = nil
        editingCropIndex = nil

        // Only wipe staged images if no active workflow should survive the background transition.
        if !shouldPreserveStagingOnBackground {
            activeScannedDatas.removeAll()
            activeScanImages.removeAll()
            activeOriginals.removeAll()
            activeDisplayDatas.removeAll()
            selectedPhotoItems.removeAll()
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
            MerianLog.general.error("Failed to route to scanId \(scanId, privacy: .private): \(error, privacy: .private)")
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
                    var historicalContext: EnvironmentContext?
                    if let localId = newItem.itemIdentifier {
                        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil)
                        if let asset = fetchResult.firstObject {
                            if let location = asset.location, let creationDate = asset.creationDate {
                                historicalContext = await self.diContainer.environmentContextManager.fetchHistoricalContext(location: location, date: creationDate)
                            } else if let creationDate = asset.creationDate {
                                historicalContext = EnvironmentContext(location: nil, captureDate: creationDate)
                            }
                        }
                    }
                    
                    if self.diContainer.usageManager.canPerformScan(isProActive: self.diContainer.revenueCatManager.isProActive) {
                        // Inference payload: tier-conditional longest edge — 768 px for Flash (free),
                        // 1024 px for Pro. Matches the camera shutter path for consistent token costs per tier.
                        let inferenceCGImage = ImageDownsampler.shared.downsample(url: validUrl, maxSize: MerianConfig.inferenceImageMaxSize(isProActive: self.diContainer.revenueCatManager.isProActive))

                        if let cgImage = inferenceCGImage {
                            let rawImage = UIImage(cgImage: cgImage)
                            let finalSafeData: Data = autoreleasepool {
                                let renderData = NSMutableData()
                                guard let destination =
                                    CGImageDestinationCreateWithData(renderData as CFMutableData, UTType.webP.identifier as CFString, 1, nil) ??
                                    CGImageDestinationCreateWithData(renderData as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
                                else { return Data() }
                                let options: [CFString: Any] = [
                                    kCGImageDestinationLossyCompressionQuality: MerianConfig.imageCompressionQuality
                                ]
                                CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
                                guard CGImageDestinationFinalize(destination) else { return Data() }
                                return Data(renderData)
                            }

                            // Display payload: 2048 px — written to disk so the insight sheet and
                            // scan library render crisp.
                            let displaySafeData: Data = autoreleasepool {
                                guard let displayCGImage = ImageDownsampler.shared.downsample(url: validUrl, maxSize: MerianConfig.displayImageMaxSize) else {
                                    return finalSafeData
                                }
                                let renderData = NSMutableData()
                                guard let destination =
                                    CGImageDestinationCreateWithData(renderData as CFMutableData, UTType.webP.identifier as CFString, 1, nil) ??
                                    CGImageDestinationCreateWithData(renderData as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
                                else { return finalSafeData }
                                let options: [CFString: Any] = [
                                    kCGImageDestinationLossyCompressionQuality: MerianConfig.imageCompressionQuality
                                ]
                                CGImageDestinationAddImage(destination, displayCGImage, options as CFDictionary)
                                guard CGImageDestinationFinalize(destination) else { return finalSafeData }
                                return Data(renderData)
                            }

                            guard !finalSafeData.isEmpty else { continue }
                            await MainActor.run {
                                let identifiable = IdentifiableImage(image: rawImage, environmentContext: historicalContext, isFromGallery: true)
                                self.activeOriginals.append(identifiable)
                                self.activeScannedDatas.append(finalSafeData)
                                self.activeDisplayDatas.append(displaySafeData)
                                self.activeScanImages.append(rawImage)
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
    private var tooltipTask: Task<Void, Never>?
    
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
    
    // MARK: - Notification Suppression Context
    
    /// Updates the global notification suppression flag used by PushNotificationManager.
    /// Informs the OS whether the user is actively engaged with the live scan UI.
    func updateNotificationSuppression() {
        // Suppress if the user is looking at the final insight sheet.
        let isActivelyWatchingScan = activeSheet == .insight
        UserDefaults.standard.set(isActivelyWatchingScan, forKey: "suppressInferenceBanners")
    }
}
