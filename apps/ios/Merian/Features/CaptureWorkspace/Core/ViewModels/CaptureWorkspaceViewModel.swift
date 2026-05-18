import Combine
import CoreLocation
import Observation
import Photos
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct HistoricalEnvironmentContextSnapshot: Sendable, Equatable {
    let latitude: CLLocationDegrees?
    let longitude: CLLocationDegrees?
    let locationName: String?
    let weatherCondition: String?
    let weatherTemperature: Double?
    let captureDate: Date?

    init(context: EnvironmentContext) {
        latitude = context.location?.coordinate.latitude
        longitude = context.location?.coordinate.longitude
        locationName = context.locationName
        weatherCondition = context.weatherCondition
        weatherTemperature = context.weatherTemperature
        captureDate = context.captureDate
    }

    init(captureDate: Date) {
        latitude = nil
        longitude = nil
        locationName = nil
        weatherCondition = nil
        weatherTemperature = nil
        self.captureDate = captureDate
    }

    func makeEnvironmentContext() -> EnvironmentContext {
        let location: CLLocation?
        if let latitude, let longitude {
            location = CLLocation(latitude: latitude, longitude: longitude)
        } else {
            location = nil
        }

        return EnvironmentContext(
            location: location,
            locationName: locationName,
            weatherCondition: weatherCondition,
            weatherTemperature: weatherTemperature,
            captureDate: captureDate
        )
    }
}

enum PreparedDisplayDataStrategy: Sendable, Equatable {
    case reencodeDisplaySized
    case memoryMapOriginalFile
}

struct SendableCGImage: @unchecked Sendable {
    let image: CGImage
}

struct PreparedStagedImage: Sendable {
    let compressedData: Data
    let displayData: Data
    let historicalContext: HistoricalEnvironmentContextSnapshot?
    let previewCGImage: SendableCGImage
}

struct PreparedStagedImageRequest: Sendable, Equatable {
    let fileURL: URL
    let isPro: Bool
    let historicalContext: HistoricalEnvironmentContextSnapshot?
    let displayDataStrategy: PreparedDisplayDataStrategy
}

typealias PreparedStagedImageLoader = @Sendable (PreparedStagedImageRequest) throws -> PreparedStagedImage?

@Observable
@MainActor
final class CaptureWorkspaceViewModel {
    
    // MARK: - Types
    enum ActiveSheet: String, Identifiable {
        case insight, paywall, scans, profile, explore
        var id: String { rawValue }
    }

    private struct GalleryImportBudget: Sendable {
        let availableSlots: Int
        let canPerformScan: Bool
    }
    
    // MARK: - Dependencies
    @ObservationIgnored let diContainer: AppDIContainer
    @ObservationIgnored private let preparedImageLoader: PreparedStagedImageLoader
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var externalRouteSessionResetSuppressionDeadline: Date?
    
    // MARK: - UI & Navigation State
    var activeSheet: ActiveSheet?
    var pendingExplorePostId: String?
    var explorePresentationIdentity = UUID()
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
    var refinementInitialDescriptionDraft: String?
    var refinementSubjectId: String?
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

    var stagedCaptureLimit: Int {
        (diContainer.appSettings.isMultiCaptureEnabled || baseRefinementRecord != nil) ? stagedCaptureCapacity : 1
    }

    var availableStagedCaptureSlots: Int {
        stagedCapture.availableSlots(limit: stagedCaptureLimit)
    }

    var hasAvailableStagedCaptureSlot: Bool {
        !stagedCapture.isAtCapacity(limit: stagedCaptureLimit)
    }

    var shouldShowMediaModeToggle: Bool {
        hasAvailableStagedCaptureSlot || baseRefinementRecord != nil
    }

    var describePromptFlow: DescribePromptFlow {
        if baseRefinementRecord != nil {
            return .reanalysis(subjectId: refinementSubjectId)
        }
        return .standard
    }

    var describePromptMediaContext: DescribePromptMediaContext {
        let activeMediaKinds = [
            !stagedCapture.images.isEmpty,
            !stagedCapture.audios.isEmpty,
            !stagedCapture.observationContexts.isEmpty
        ].filter { $0 }.count

        guard activeMediaKinds == 1 else {
            return activeMediaKinds == 0 ? .none : .mixed
        }
        if !stagedCapture.images.isEmpty { return .photo }
        if !stagedCapture.audios.isEmpty { return .audio }
        return .description
    }
    
    // MARK: - Lifecycle
    convenience init() {
        self.init(
            diContainer: AppDIContainer.shared,
            preparedImageLoader: CaptureWorkspaceViewModel.livePreparedImageLoader,
            prewarmHeadersOnInit: true
        )
    }

    init(
        diContainer: AppDIContainer,
        preparedImageLoader: @escaping PreparedStagedImageLoader,
        prewarmHeadersOnInit: Bool = true
    ) {
        self.diContainer = diContainer
        self.preparedImageLoader = preparedImageLoader

        // Pre-warm the HTTPS connection to Supabase and refresh the auth token while the
        // user composes their shot. Eliminates TCP/TLS handshake (~200–400ms) and token
        // refresh latency from the scan critical path on cold app launch.
        if prewarmHeadersOnInit {
            Task {
                _ = try? await diContainer.supabaseManager.getValidAuthHeaders()
            }
        }

        // Centralized System Event Routing (AppEventPublisher)
        diContainer.appEventPublisher.publisher
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                switch event {
                case .appDidResumeAfterTimeout:
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        self?.handleSessionTimeoutReset()
                    }
                case .triggerPaywall:
                    self?.activeSheet = .paywall
                case .appDidEnterActivePhaseWithScan(let scanId):
                    self?.handleDeepLinkRoute(scanId: scanId)
                case .appDidEnterActivePhaseWithExplorePost(let postId):
                    self?.handleExploreDeepLinkRoute(postId: postId)
                case .triggerRefinement(let record, let initialDescription):
                    self?.startRefinementScan(from: record, initialDescription: initialDescription)
                case .requestOpenNonBiologicalScansIntent:
                    self?.activeSheet = .scans
                case .requestOpenScansLibraryIntent:
                    self?.activeSheet = .scans
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    nonisolated private static let livePreparedImageLoader: PreparedStagedImageLoader = { request in
        // Inference payload: tier-conditional longest edge — 768 px for Flash (free),
        // 1024 px for Pro. Matches the camera shutter path for consistent token costs per tier.
        guard let inferenceCGImage = ImageDownsampler.downsample(
            url: request.fileURL,
            maxSize: MerianConfig.inferenceImageMaxSize(isProActive: request.isPro)
        ) else { return nil }

        let compressedData = ImageCropProcessor.encode(inferenceCGImage) ?? Data()
        guard !compressedData.isEmpty else { return nil }

        let displayData: Data
        switch request.displayDataStrategy {
        case .reencodeDisplaySized:
            displayData = autoreleasepool {
                guard let displayCGImage = ImageDownsampler.downsample(
                    url: request.fileURL,
                    maxSize: MerianConfig.displayImageMaxSize
                ) else {
                    return compressedData
                }
                return ImageCropProcessor.encode(displayCGImage) ?? compressedData
            }
        case .memoryMapOriginalFile:
            displayData = try Data(contentsOf: request.fileURL, options: [.mappedIfSafe])
        }

        guard !displayData.isEmpty else { return nil }
        return PreparedStagedImage(
            compressedData: compressedData,
            displayData: displayData,
            historicalContext: request.historicalContext,
            previewCGImage: SendableCGImage(image: inferenceCGImage)
        )
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

    private func protectExternalRouteFromImmediateSessionTimeoutReset() {
        externalRouteSessionResetSuppressionDeadline = Date().addingTimeInterval(5)
    }

    private func handleSessionTimeoutReset(now: Date = Date()) {
        if let deadline = externalRouteSessionResetSuppressionDeadline,
           now <= deadline {
            externalRouteSessionResetSuppressionDeadline = nil
            MerianLog.general.debug("Skipped session timeout reset because an external route was just opened.")
            return
        }

        externalRouteSessionResetSuppressionDeadline = nil
        resetModalsForSessionTimeout()
    }

    private func resetModalsForSessionTimeout() {
        // Clear all sheets and UI modals instantly when the session times out
        activeSheet = nil
        pendingExplorePostId = nil
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
                protectExternalRouteFromImmediateSessionTimeoutReset()
                self.activeSheet = .insight
            }
        } catch {
            MerianLog.general.error("Failed to route to scanId \(scanId, privacy: .private): \(error, privacy: .private)")
        }
    }

    private func handleExploreDeepLinkRoute(postId: String) {
        protectExternalRouteFromImmediateSessionTimeoutReset()
        pendingExplorePostId = postId
        explorePresentationIdentity = UUID()
        activeSheet = .explore
    }
    
    // MARK: - User Intents
    
    func handlePhotoPickerSelection(newItems: [PhotosPickerItem], modelContext _: ModelContext) {
        guard !newItems.isEmpty else { return }

        let isPro = self.diContainer.revenueCatManager.isProActive
        let importBudget = prepareGalleryImportBudget(isPro: isPro)
        self.selectedPhotoItems.removeAll()

        guard importBudget.availableSlots > 0 else { return }

        guard importBudget.canPerformScan else {
            AppTelemetry.trackPaywallImpression()
            self.activeSheet = .paywall
            return
        }

        let itemsToProcess = Array(newItems.prefix(importBudget.availableSlots))

        DetachedWork.fireAndForget(
            priority: .userInitiated,
            category: .imagePreparation
        ) { [weak self, isPro, itemsToProcess] in
            guard let self = self else { return }

            var preparedImports: [PreparedStagedImage] = []
            preparedImports.reserveCapacity(itemsToProcess.count)

            for newItem in itemsToProcess {
                if Task.isCancelled { return }
                guard let wrapper = try? await newItem.loadTransferable(type: ImageFileWrapper.self) else { continue }
                let validUrl = wrapper.url

                // Scope the defer explicitly into an immediate do-block to guarantee memory unlocks natively per-loop
                do {
                    defer { try? FileManager.default.removeItem(at: validUrl) }

                    let historicalContext = await self.historicalContextSnapshot(for: newItem.itemIdentifier)
                    let request = PreparedStagedImageRequest(
                        fileURL: validUrl,
                        isPro: isPro,
                        historicalContext: historicalContext,
                        displayDataStrategy: .reencodeDisplaySized
                    )
                    guard let preparedImport = try? self.preparedImageLoader(request) else { continue }
                    preparedImports.append(preparedImport)
                }
            }

            guard !Task.isCancelled, !preparedImports.isEmpty else { return }
            await self.commitPreparedStagedImages(preparedImports)
        }
    }

    private func prepareGalleryImportBudget(isPro: Bool) -> GalleryImportBudget {
        GalleryImportBudget(
            availableSlots: availableStagedCaptureSlots,
            canPerformScan: diContainer.usageManager.canPerformScan(isProActive: isPro)
        )
    }

    private func historicalContextSnapshot(for localIdentifier: String?) async -> HistoricalEnvironmentContextSnapshot? {
        guard let localIdentifier else { return nil }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }

        if let location = asset.location, let creationDate = asset.creationDate {
            let historicalContext = await diContainer.environmentContextManager.fetchHistoricalContext(
                location: location,
                date: creationDate
            )
            return HistoricalEnvironmentContextSnapshot(context: historicalContext)
        }

        if let creationDate = asset.creationDate {
            return HistoricalEnvironmentContextSnapshot(captureDate: creationDate)
        }

        return nil
    }

    private func commitPreparedStagedImages(_ preparedImports: [PreparedStagedImage]) {
        let availableSlots = availableStagedCaptureSlots
        guard availableSlots > 0 else { return }

        for preparedImport in preparedImports.prefix(availableSlots) {
            let rawImage = UIImage(cgImage: preparedImport.previewCGImage.image)

            let identifiable = IdentifiableImage(
                image: rawImage,
                environmentContext: preparedImport.historicalContext?.makeEnvironmentContext(),
                isFromGallery: true
            )
            stagedCapture.images.append(StagedImage(
                compressedData: preparedImport.compressedData,
                displayData: preparedImport.displayData,
                uiImage: rawImage,
                original: identifiable
            ))
        }
    }
    
    // MARK: - Manual Crop Routing
    @ObservationIgnored var activeCropTask: Task<Void, Never>?

    func presentCrop(for index: Int) {
        guard index < stagedCapture.images.count else { return }
        self.editingCropIndex = index
        self.imageToCrop = stagedCapture.images[index].original
    }
    
    func startRefinementScan(from record: LocalScanRecord, initialDescription: String? = nil) {
        self.refinementSubjectId = DescribeSubjectResolver.subjectId(for: record)
        self.baseRefinementRecord = record
        let trimmedDescription = initialDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.refinementInitialDescriptionDraft = trimmedDescription?.isEmpty == false ? trimmedDescription : nil
        self.activeSheet = nil
        self.requestedCaptureMode = .describe

        stageHistoricalMediaForRefinement(from: record)
    }

    private func stageHistoricalMediaForRefinement(from record: LocalScanRecord) {
        let mediaSnapshot = record.capturedMediaSnapshot

        for imageReference in mediaSnapshot.imageReferences
            where stageHistoricalImageForRefinement(imageReference) {
            return
        }

        if let fallbackImagePath = record.coverImagePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallbackImagePath.isEmpty,
           stageHistoricalImageForRefinement(StoredMediaReference(legacyPath: fallbackImagePath)) {
            return
        }

        for audioReference in mediaSnapshot.audioReferences
            where stageHistoricalAudioForRefinement(audioReference) {
            return
        }

        if let descriptionContext = mediaSnapshot.observationContexts.first(where: { !$0.isEmpty }),
           stageHistoricalDescriptionForRefinement(descriptionContext) {
            return
        }
    }

    @discardableResult
    private func stageHistoricalAudioForRefinement(_ audioReference: StoredMediaReference) -> Bool {
        guard stagedCapture.availableSlots(limit: stagedCaptureLimit) > 0 else { return false }
        let audioPath = audioReference.resolvedLocalPath ?? audioReference.serializedPath
        guard !audioPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        stagedCapture.audios.append(StagedAudio(filePath: audioPath))
        return true
    }

    @discardableResult
    private func stageHistoricalDescriptionForRefinement(_ descriptionContext: ObservationContext) -> Bool {
        guard stagedCapture.availableSlots(limit: stagedCaptureLimit) > 0 else { return false }
        stagedCapture.observationContexts.append(StagedObservationContext(context: descriptionContext))
        return true
    }

    @discardableResult
    private func stageHistoricalImageForRefinement(_ imageReference: StoredMediaReference) -> Bool {
        guard stagedCapture.availableSlots(limit: stagedCaptureLimit) > 0 else { return false }
        guard let sourceURL = imageReference.resolvedURL else { return false }

        self.isStagingRefinement = true
        self.refinementStagingTask?.cancel()

        let isPro = self.diContainer.revenueCatManager.isProActive

        self.refinementStagingTask = DetachedWork.fireAndForget(
            priority: .userInitiated,
            category: .imagePreparation
        ) { [weak self, isPro] in
            guard let self = self else { return }
            var temporaryDownloadURL: URL?
            let fileURL: URL

            do {
                if imageReference.isRemote {
                    guard let downloadedURL = try await Self.downloadRefinementImage(from: sourceURL) else {
                        await MainActor.run { self.isStagingRefinement = false }
                        return
                    }
                    temporaryDownloadURL = downloadedURL
                    fileURL = downloadedURL
                } else if FileManager.default.fileExists(atPath: sourceURL.path) {
                    fileURL = sourceURL
                } else {
                    await MainActor.run { self.isStagingRefinement = false }
                    return
                }

                defer {
                    if let temporaryDownloadURL {
                        try? FileManager.default.removeItem(at: temporaryDownloadURL)
                    }
                }

                let request = PreparedStagedImageRequest(
                    fileURL: fileURL,
                    isPro: isPro,
                    historicalContext: nil,
                    displayDataStrategy: .memoryMapOriginalFile
                )
                guard let preparedRefinement = try self.preparedImageLoader(request) else {
                    await MainActor.run { self.isStagingRefinement = false }
                    return
                }
                
                try Task.checkCancellation()
                
                await MainActor.run {
                    self.commitPreparedStagedImages([preparedRefinement])
                    self.isStagingRefinement = false
                }
            } catch {
                MerianLog.general.error("Failed to load historical refinement image for UI staging: \(error.localizedDescription, privacy: .private)")
                await MainActor.run { self.isStagingRefinement = false }
            }
        }
        return true
    }

    private nonisolated static func downloadRefinementImage(from remoteURL: URL) async throws -> URL? {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil

        let session = URLSession(configuration: config)
        let (downloadURL, response) = try await session.download(from: remoteURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }

        let extensionHint = remoteURL.pathExtension.isEmpty ? "jpg" : remoteURL.pathExtension
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(extensionHint)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: downloadURL, to: destinationURL)
        return destinationURL
    }
    
    func cancelRefinementStaging() {
        refinementStagingTask?.cancel()
        isStagingRefinement = false
        baseRefinementRecord = nil
        refinementInitialDescriptionDraft = nil
        refinementSubjectId = nil
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
        diContainer.appSettings.suppressInferenceBanners = isActivelyWatchingScan
    }

    // MARK: - Workspace State Coordination

    func handleScenePhaseChange(
        _ newPhase: ScenePhase,
        captureMode: CaptureMode,
        cameraManager: CameraManager,
        audioCaptureManager: AudioCaptureManager
    ) {
        if newPhase == .active {
            if captureMode == .visual && self.activeSheet == nil {
                cameraManager.startSession()
            }
        }
        if newPhase == .inactive && audioCaptureManager.isRecording && !audioCaptureManager.isPaused {
            audioCaptureManager.pauseRecording()
        }
        if newPhase == .background && audioCaptureManager.isRecording && !audioCaptureManager.isPaused {
            audioCaptureManager.pauseRecording()
        }
    }

    func handleCaptureModeChange(
        _ newMode: CaptureMode,
        scenePhase: ScenePhase,
        cameraManager: CameraManager,
        audioCaptureManager: AudioCaptureManager
    ) {
        HapticManager.shared.triggerSheetSpring()

        if newMode != .audio && audioCaptureManager.isRecording && !audioCaptureManager.isPaused {
            audioCaptureManager.pauseRecording()
        }

        if newMode == .audio || newMode == .describe {
            cameraManager.stopSession()
        } else if scenePhase == .active && self.activeSheet == nil {
            cameraManager.startSession()
        }
    }
}
