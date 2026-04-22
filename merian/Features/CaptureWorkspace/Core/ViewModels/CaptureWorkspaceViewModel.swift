import Combine
import Observation
import Photos
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@Observable
@MainActor
final class CaptureWorkspaceViewModel {
    
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
    var offlineToastMessage: String?
    var imageToCrop: IdentifiableImage?
    var editingCropIndex: Int?
    /// All content staged for the next combined submission — images, optional audio (reserved),
    /// and optional describe description. Replaces the previous four parallel image arrays.
    var stagedCapture = StagedCapture()
    var selectedPhotoItems: [PhotosPickerItem] = []
    var isTooltipVisible: Bool = false
    
    // MARK: - Refinement Flow
    /// The historical scan actively chosen by the user to be appended with new photographic context.
    /// Drives the multi-image composition path in `submitActiveScan`.
    var baseRefinementRecord: LocalScanRecord?
    var isStagingRefinement: Bool = false
    @ObservationIgnored private var refinementStagingTask: Task<Void, Never>?
    /// Set to `.describe` when reanalysis is triggered so `CaptureWorkspaceView` navigates to the
    /// Describe page immediately after the insight sheet dismisses. Consumed and cleared by
    /// `CaptureWorkspaceView.onChange(of: viewModel.requestedCaptureMode)`.
    var requestedCaptureMode: CaptureMode?
    
    // MARK: - Composing Zone
    /// Vertical center of the on-screen composing zone as a fraction of screen height (0–1).
    /// Set by CaptureWorkspaceView once layout is measured. The capture pipeline uses this to
    /// center the auto-crop on the region the user actually frames their subject in,
    /// rather than the geometric center of the full sensor image.
    var composingZoneVerticalCenter: CGFloat = 0.5
    // MARK: - Camera & Scanning State
    var isCapturing: Bool = false
    var flashOpacity: Double = 0.0
    
    // MARK: - Asynchronous Jobs
    @ObservationIgnored var preFetchTask: Task<EnvironmentContext, Never>?
    @ObservationIgnored private var focusTask: Task<Void, Never>?
    /// Tracks the scanId of the most recently submitted scan. Used by the async telemetry
    /// Task in `submitActiveScan` to detect when a newer scan has superseded this one and
    /// skip calling `analyze()` — prevents a stale Task from re-triggering live inference
    /// after the engine has already moved on to a subsequent capture.
    @ObservationIgnored var pendingAnalyzeScanId: String?
    
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
                case .appDidEnterBackgroundPhase:
                    self?.resetModalsForBackground()
                case .triggerPaywall:
                    self?.activeSheet = .paywall
                case .appDidEnterActivePhaseWithScan(let scanId):
                    self?.handleDeepLinkRoute(scanId: scanId)
                case .triggerRefinement(let record):
                    self?.startRefinementScan(from: record)
                default:
                    break
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
        // Any staged content should survive a brief background trip.
        !stagedCapture.isEmpty
    }

    private func resetModalsForBackground() {
        // Sheets and crop state always close — they hold UI locks and must not reopen stale.
        activeSheet = nil
        imageToCrop = nil
        editingCropIndex = nil

        // Only wipe staged content if no active workflow should survive the background transition.
        if !shouldPreserveStagingOnBackground {
            stagedCapture.clearAll()
            selectedPhotoItems.removeAll()
            cancelRefinementStaging()
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
                // Fast-fail check to protect strictly against exceeding the image cap natively
                if await MainActor.run(resultType: Bool.self, body: { self.stagedCapture.images.count >= stagedImageCapacity }) {
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
                        let inferenceCGImage = ImageDownsampler.downsample(url: validUrl, maxSize: MerianConfig.inferenceImageMaxSize(isProActive: self.diContainer.revenueCatManager.isProActive))

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
                                guard let displayCGImage = ImageDownsampler.downsample(url: validUrl, maxSize: MerianConfig.displayImageMaxSize) else {
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
                                self.stagedCapture.images.append(StagedImage(
                                    compressedData: finalSafeData,
                                    displayData: displaySafeData,
                                    uiImage: rawImage,
                                    original: identifiable
                                ))
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
        guard index < stagedCapture.images.count else { return }
        self.editingCropIndex = index
        self.imageToCrop = stagedCapture.images[index].original
    }
    
    func startRefinementScan(from record: LocalScanRecord) {
        self.baseRefinementRecord = record
        self.activeSheet = nil
        self.requestedCaptureMode = .describe
        
        guard let localPath = record.coverImagePath,
              !localPath.starts(with: "http") else { return }

        self.isStagingRefinement = true
        self.refinementStagingTask?.cancel()

        self.refinementStagingTask = Task { [weak self] in
            guard let self = self else { return }
            // localImagePath stores a bare filename relative to the documents directory
            // (written by FileIOActor.writeTemporaryImages). Reconstruct the full URL
            // the same way every other consumer does — see FileIOActor.validPaths and deleteImages.
            let fileURL = URL.documentsDirectory.appendingPathComponent(localPath)
            
            do {
                let rawData = try Data(contentsOf: fileURL)
                let isPro = self.diContainer.revenueCatManager.isProActive
                let inferenceSize = MerianConfig.inferenceImageMaxSize(isProActive: isPro)
                
                var inferenceData: Data?
                var rawImage: UIImage?
                
                if let cgInference = ImageDownsampler.downsample(url: fileURL, maxSize: inferenceSize) {
                    rawImage = UIImage(cgImage: cgInference)
                    inferenceData = autoreleasepool {
                        let renderData = NSMutableData()
                        guard let dest = CGImageDestinationCreateWithData(renderData as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
                        CGImageDestinationAddImage(dest, cgInference, [kCGImageDestinationLossyCompressionQuality: MerianConfig.imageCompressionQuality] as CFDictionary)
                        guard CGImageDestinationFinalize(dest) else { return nil }
                        return Data(renderData)
                    }
                }
                
                let finalSafeData = inferenceData ?? rawData
                guard let finalImage = rawImage ?? UIImage(data: rawData) else {
                    await MainActor.run { self.isStagingRefinement = false }
                    return
                }
                
                try Task.checkCancellation()
                
                await MainActor.run {
                    let identifiable = IdentifiableImage(image: finalImage, environmentContext: nil, isFromGallery: true)
                    self.stagedCapture.images.append(StagedImage(
                        compressedData: finalSafeData,
                        displayData: rawData,
                        uiImage: finalImage,
                        original: identifiable
                    ))
                    self.isStagingRefinement = false
                }
            } catch {
                MerianLog.general.error("Failed to load historical refinement image for UI staging: \(error.localizedDescription, privacy: .private)")
                await MainActor.run { self.isStagingRefinement = false }
            }
        }
    }
    
    func cancelRefinementStaging() {
        refinementStagingTask?.cancel()
        isStagingRefinement = false
        baseRefinementRecord = nil
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
