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

    init(
        latitude: CLLocationDegrees?,
        longitude: CLLocationDegrees?,
        captureDate: Date?
    ) {
        self.latitude = latitude
        self.longitude = longitude
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

struct SendableCGImage: @unchecked Sendable {
    let image: CGImage
}

struct PreparedStagedImage: Sendable {
    let compressedData: Data
    let displayData: Data
    let historicalContext: HistoricalEnvironmentContextSnapshot?
    let previewCGImage: SendableCGImage
    let metrics: MediaPreparationMetrics?
    let focusRegion: NormalizedImageFocusRegion?

    init(
        compressedData: Data,
        displayData: Data,
        historicalContext: HistoricalEnvironmentContextSnapshot?,
        previewCGImage: SendableCGImage,
        metrics: MediaPreparationMetrics? = nil,
        focusRegion: NormalizedImageFocusRegion? = nil
    ) {
        self.compressedData = compressedData
        self.displayData = displayData
        self.historicalContext = historicalContext
        self.previewCGImage = previewCGImage
        self.metrics = metrics
        self.focusRegion = focusRegion
    }
}

enum ExternalImageImportAttemptResult: Equatable {
    case staged
    case temporarilyBlocked
    case terminalFailure
    case noPendingImport
}

struct RefinementScanContext: Equatable {
    let scanId: String
    let subjectId: String?
    let capturedMediaSnapshot: CapturedMediaSnapshot
    let coverImagePath: String?
    let entryPoint: RefinementEntryPoint

    init(record: LocalScanRecord, entryPoint: RefinementEntryPoint = .standard) {
        self.scanId = record.id
        self.subjectId = DescribeSubjectResolver.subjectId(for: record)
        self.capturedMediaSnapshot = record.capturedMediaSnapshot
        self.coverImagePath = record.coverImagePath
        self.entryPoint = entryPoint
    }
}

struct PreparedStagedImageRequest: Sendable, Equatable {
    let fileURL: URL
    let isPro: Bool
    let historicalContext: HistoricalEnvironmentContextSnapshot?
}

typealias PreparedStagedImageLoader = @Sendable (PreparedStagedImageRequest) async throws -> PreparedStagedImage?

@Observable
@MainActor
final class CaptureWorkspaceViewModel {
    
    // MARK: - Types
    enum ActiveSheet: String, Identifiable, Sendable {
        case insight, paywall, scans, profile, explore, achievement, notificationPrompt
        var id: String { rawValue }
    }

    enum PresentationStyle: Sendable, Equatable {
        case sheet
    }

    struct PresentedRoute: Identifiable, Equatable {
        let id: UUID
        let destination: ActiveSheet
        let style: PresentationStyle
        let routeRequestID: UUID?
    }

    private struct GalleryImportBudget: Sendable {
        let availableSlots: Int
        let canPerformScan: Bool
    }
    
    // MARK: - Dependencies
    @ObservationIgnored let diContainer: AppDIContainer
    @ObservationIgnored private let preparedImageLoader: PreparedStagedImageLoader
    @ObservationIgnored private let externalImageImportStore: ExternalImageImportStore
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var externalRouteSessionResetSuppressionDeadline: Date?
    @ObservationIgnored private var externalImageImportTask: Task<Void, Never>?
    @ObservationIgnored private var externalImageImportRetryRequested = false
    @ObservationIgnored private var resumesExternalImageImportAfterSheetDismissal = false
    @ObservationIgnored private var slotBlockedExternalImportIds = Set<UUID>()
    @ObservationIgnored private var paywallPresentedExternalImportIds = Set<UUID>()
    @ObservationIgnored private var routeRequestIDBeingApplied: UUID?
    @ObservationIgnored private var dismissingPresentation: PresentedRoute?
    @ObservationIgnored private var deferredRouteRequestID: UUID?
    
    // MARK: - UI & Navigation State
    var activePresentation: PresentedRoute?
    var isRootPresentationDismissing: Bool {
        dismissingPresentation != nil
    }
    var activeSheet: ActiveSheet? {
        get { activePresentation?.destination }
        set {
            guard let newValue else {
                dismissActivePresentation()
                return
            }
            guard activePresentation?.destination != newValue else { return }
            if activePresentation != nil || dismissingPresentation != nil {
                // Local presentation changes are latest-wins, but never mount
                // during the previous sheet's interactive dismissal window.
                pendingLocalSheet = newValue
                dismissActivePresentation()
                return
            }
            activePresentation = PresentedRoute(
                id: UUID(),
                destination: newValue,
                style: .sheet,
                routeRequestID: routeRequestIDBeingApplied
            )
        }
    }
    private var pendingLocalSheet: ActiveSheet?
    var pendingExplorePostId: String?
    var pendingSpeciesDictionaryRoute: SpeciesDictionaryRoute?
    var pendingCommunityIdentificationRequestId: String?
    var pendingExploreTargetCommentId: String?
    var pendingExploreTargetReplyParentCommentId: String?
    var pendingCaptureGoalDestination: CaptureGoalDestination?
    var pendingExploreShowsFieldTrips = false
    var pendingScansRecoveryContext: ExploreMediaRecoveryRouteContext?
    var pendingScansShowsNonBiologicalCollection = false
    var pendingAchievementAward: AwardPayload?
    var explorePresentationIdentity = UUID()
    var offlineToastMessage: String?
    var imageToCrop: IdentifiableImage?
    var editingCropIndex: Int?
    @ObservationIgnored private var requiredGalleryCropImageIds: [UUID] = []
    /// All content staged for the next combined submission — images, optional audio (reserved),
    /// and optional describe description. Replaces the previous four parallel image arrays.
    var stagedCapture = StagedCapture()
    var selectedPhotoItems: [PhotosPickerItem] = []
    var isTooltipVisible: Bool = false
    
    // MARK: - Refinement Flow
    /// The historical scan actively chosen by the user to be appended with new photographic context.
    /// Drives the multi-image composition path in `submitActiveScan`.
    var baseRefinementContext: RefinementScanContext?
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
    var isVideoRecording: Bool = false
    var videoRecordingProgress: Double = 0
    var flashOpacity: Double = 0.0
    
    // MARK: - Asynchronous Jobs
    @ObservationIgnored var preFetchTask: Task<EnvironmentContext, Never>?
    @ObservationIgnored var videoRecordingTask: Task<Void, Never>?
    @ObservationIgnored var videoRecordingProgressTask: Task<Void, Never>?
    @ObservationIgnored private var focusTask: Task<Void, Never>?
    /// Tracks the scanId of the most recently submitted scan. Used by the async telemetry
    /// Task in `submitActiveScan` to detect when a newer scan has superseded this one and
    /// skip calling `analyze()` — prevents a stale Task from re-triggering live inference
    /// after the engine has already moved on to a subsequent capture.
    @ObservationIgnored var pendingAnalyzeScanId: String?

    var isMultiCaptureFunctionallyEnabled: Bool {
        diContainer.appSettings.isMultiCaptureEnabled
            && diContainer.revenueCatManager.canStartProScan
    }

    var stagedCaptureLimit: Int {
        (isMultiCaptureFunctionallyEnabled || baseRefinementContext != nil) ? stagedCaptureCapacity : 1
    }

    var availableStagedCaptureSlots: Int {
        stagedCapture.availableSlots(limit: stagedCaptureLimit)
    }

    var hasAvailableStagedCaptureSlot: Bool {
        !stagedCapture.isAtCapacity(limit: stagedCaptureLimit)
    }

    var shouldShowMediaModeToggle: Bool {
        hasAvailableStagedCaptureSlot || baseRefinementContext != nil
    }

    var shouldShowViewfinderHints: Bool {
        hasAvailableStagedCaptureSlot
    }

    var describePromptFlow: DescribePromptFlow {
        if baseRefinementContext != nil {
            return .reanalysis(subjectId: refinementSubjectId)
        }
        return .standard
    }

    var describePromptMediaContext: DescribePromptMediaContext {
        let activeMediaKinds = [
            stagedCapture.hasVisualMedia,
            !stagedCapture.audios.isEmpty,
            !stagedCapture.observationContexts.isEmpty
        ].filter { $0 }.count

        guard activeMediaKinds == 1 else {
            return activeMediaKinds == 0 ? .none : .mixed
        }
        if stagedCapture.hasVisualMedia { return .photo }
        if !stagedCapture.audios.isEmpty { return .audio }
        return .description
    }
    
    // MARK: - Lifecycle
    convenience init(initialActiveSheet: ActiveSheet? = nil) {
        self.init(
            diContainer: AppDIContainer.shared,
            preparedImageLoader: CaptureWorkspaceViewModel.livePreparedImageLoader,
            prewarmHeadersOnInit: true,
            initialActiveSheet: initialActiveSheet
        )
    }

    init(
        diContainer: AppDIContainer,
        preparedImageLoader: @escaping PreparedStagedImageLoader,
        prewarmHeadersOnInit: Bool = true,
        initialActiveSheet: ActiveSheet? = nil,
        externalImageImportStore: ExternalImageImportStore? = nil
    ) {
        self.diContainer = diContainer
        self.preparedImageLoader = preparedImageLoader
        self.externalImageImportStore = externalImageImportStore ?? diContainer.externalImageImportStore
        self.activePresentation = initialActiveSheet.map {
            PresentedRoute(id: UUID(), destination: $0, style: .sheet, routeRequestID: nil)
        }

        // Pre-warm both connection pools while the user composes their shot: Supabase Auth
        // owns one session, while live inference uses MerianNetworkClient's pinned session.
        if prewarmHeadersOnInit {
            Task {
                async let authWarmup: Void = {
                    _ = try? await diContainer.supabaseManager.getValidAuthHeaders()
                }()
                async let inferenceWarmup: Void = MerianNetworkClient.shared.prewarmInferenceEndpoint()
                _ = await (authWarmup, inferenceWarmup)
            }
        }

        // The app event bus is synchronous and actor-isolated. Framework
        // publishers use a separate asynchronous bridge at their boundaries.
        diContainer.appEventPublisher.publisher
            .sink { [weak self] event in
                guard case .appDidResumeAfterTimeout = event, let self else { return }
                let now = Date()
                self.diContainer.appRouteCoordinator.advanceSession(now: now)
                guard !self.diContainer.appRouteCoordinator.shouldSuppressTimeoutReset(now: now) else {
                    MerianLog.general.debug(
                        "Skipped session timeout reset because an explicit route is pending or was just applied."
                    )
                    return
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    self.handleSessionTimeoutReset(now: now)
                }
            }
            .store(in: &cancellables)
    }

    nonisolated private static let livePreparedImageLoader: PreparedStagedImageLoader = { request in
        let prepared = try await MediaPreparationActor.shared.prepareStillImage(
            fileURL: request.fileURL,
            isPro: request.isPro
        )
        let focusRegion = await ImageFocusRegionDetector.detect(in: prepared.inferenceData)
        return PreparedStagedImage(
            compressedData: prepared.inferenceData,
            displayData: prepared.displayData,
            historicalContext: request.historicalContext,
            previewCGImage: SendableCGImage(image: prepared.previewImage.cgImage),
            metrics: prepared.metrics,
            focusRegion: focusRegion
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
        pendingLocalSheet = nil
        pendingExplorePostId = nil
        pendingSpeciesDictionaryRoute = nil
        pendingCommunityIdentificationRequestId = nil
        pendingExploreTargetCommentId = nil
        pendingExploreTargetReplyParentCommentId = nil
        pendingCaptureGoalDestination = nil
        pendingExploreShowsFieldTrips = false
        pendingScansRecoveryContext = nil
        imageToCrop = nil
        editingCropIndex = nil

        // Only wipe staged content if no active workflow should survive the background transition.
        if !shouldPreserveStagingOnBackground {
            clearStagedCaptureAndCropState(discardStagedMediaFiles: true)
            selectedPhotoItems.removeAll()
            cancelRefinementStaging()
        }
    }

    // MARK: - Delivery-Critical Route Consumption

    func consumeNextAppRoute(
        now: Date = Date(),
        isFeaturePresentationOccupied: Bool = false
    ) {
        let coordinator = diContainer.appRouteCoordinator
        guard let request = coordinator.claimNext(now: now) else { return }

        if activePresentation != nil
            || dismissingPresentation != nil
            || isFeaturePresentationOccupied {
            deferredRouteRequestID = request.id
            coordinator.resolve(
                request.id,
                outcome: .deferred(reason: .presentationOccupied),
                now: now
            )
            dismissActivePresentation()
            return
        }

        routeRequestIDBeingApplied = request.id
        let outcome = apply(request.route)
        routeRequestIDBeingApplied = nil
        coordinator.resolve(request.id, outcome: outcome, now: now)
    }

    private func apply(_ route: AppRoute) -> AppRouteOutcome {
        switch route {
        case .proAccessRequired:
            activeSheet = .paywall
        case .scan(let scanId):
            guard handleDeepLinkRoute(scanId: scanId) else {
                return .rejected(reason: .targetUnavailable)
            }
        case .explorePost(let postId, let targetCommentId, let targetReplyParentCommentId):
            guard !postId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .rejected(reason: .invalidPayload)
            }
            handleExploreDeepLinkRoute(
                postId: postId,
                targetCommentId: targetCommentId,
                targetReplyParentCommentId: targetReplyParentCommentId
            )
        case .speciesDictionary(let speciesId):
            guard handleSpeciesDictionaryDeepLinkRoute(speciesId: speciesId) else {
                return .rejected(reason: .invalidPayload)
            }
        case .communityIdentification(let requestId):
            guard !requestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .rejected(reason: .invalidPayload)
            }
            handleCommunityIdentificationRoute(requestId: requestId)
        case .identifyNature, .openScanner:
            activeSheet = nil
            requestedCaptureMode = .visual
            if FeatureFlags.isEnabled(.fieldTrips) {
                let accountID = diContainer.supabaseManager.currentUser?.id.uuidString.lowercased()
                Task { [activeCaptureGoalStore = diContainer.activeCaptureGoalStore] in
                    await activeCaptureGoalStore.refresh(accountId: accountID, force: true)
                }
            }
        case .achievement(let award):
            pendingAchievementAward = award
            activeSheet = .achievement
        case .captureGoal(let destination):
            openCaptureGoal(destination)
        case .fieldTrips:
            openFieldTrips()
        case .recallLastFind:
            guard diContainer.inferenceEngine.historicHydrationTask != nil
                    || diContainer.inferenceEngine.speciesData != nil else {
                return .rejected(reason: .targetUnavailable)
            }
            activeSheet = .insight
        case .refinement(let scanId, let initialDescription, let entryPoint):
            guard startRefinementScan(
                scanId: scanId,
                initialDescription: initialDescription,
                entryPoint: entryPoint
            ) else {
                return .rejected(reason: .targetUnavailable)
            }
        case .nonBiologicalScans:
            handleScansLibraryRoute(showsNonBiologicalCollection: true)
        case .scansLibrary:
            handleScansLibraryRoute()
        case .scansLibraryRecovery(let context):
            let currentOwner = diContainer.supabaseManager.currentUser?.id.uuidString.lowercased()
            guard currentOwner == context.ownerUserId.lowercased() else {
                return .rejected(reason: .staleAccount)
            }
            handleScansLibraryRoute(recoveryContext: context)
        case .processExternalImageImports:
            protectExternalRouteFromImmediateSessionTimeoutReset()
            importPendingExternalImageIfPossible()
        case .externalImageImportFailed:
            prepareForExternalImageImportPresentation()
            presentExternalImageImportFailure()
        #if DEBUG
        case .debugPreviewAnalyzing:
            activeSheet = .insight
        #endif
        }

        let presentationID = activePresentation?.routeRequestID == routeRequestIDBeingApplied
            ? activePresentation?.id
            : nil
        return .applied(presentationID: presentationID)
    }

    func handleRouteAccountGenerationChanged() {
        deferredRouteRequestID = nil
        pendingLocalSheet = nil
        clearExplorePresentationRoute()
        pendingScansRecoveryContext = nil
        pendingScansShowsNonBiologicalCollection = false
        pendingAchievementAward = nil
        if activePresentation?.routeRequestID != nil {
            dismissActivePresentation()
        }
    }
    
    // MARK: - App Linking
    
    @discardableResult
    private func handleDeepLinkRoute(scanId: String) -> Bool {
        clearExplorePresentationRoute()

        // SwiftData Context Access boundary seamlessly leveraging the shared queue context
        guard let context = diContainer.offlineQueueManager.modelContext else { return false }

        do {
            let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
            if let record = (try context.fetch(descriptor)).first {
                diContainer.inferenceEngine.load(from: record)
                protectExternalRouteFromImmediateSessionTimeoutReset()
                self.activeSheet = .insight
                return true
            }
        } catch {
            MerianLog.general.error("Failed to route to scanId \(scanId, privacy: .private): \(error, privacy: .private)")
        }
        return false
    }

    func fetchLocalScan(scanId: String) -> LocalScanRecord? {
        guard let context = diContainer.offlineQueueManager.modelContext else { return nil }
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func handleExploreDeepLinkRoute(
        postId: String,
        targetCommentId: String?,
        targetReplyParentCommentId: String?
    ) {
        protectExternalRouteFromImmediateSessionTimeoutReset()
        pendingExplorePostId = postId
        pendingSpeciesDictionaryRoute = nil
        pendingCommunityIdentificationRequestId = nil
        pendingExploreTargetCommentId = targetCommentId
        pendingExploreTargetReplyParentCommentId = targetReplyParentCommentId
        pendingCaptureGoalDestination = nil
        pendingExploreShowsFieldTrips = false
        explorePresentationIdentity = UUID()
        activeSheet = .explore
    }

    @discardableResult
    private func handleSpeciesDictionaryDeepLinkRoute(speciesId: String) -> Bool {
        guard let uuid = UUID(
            uuidString: speciesId.trimmingCharacters(in: .whitespacesAndNewlines)
        ) else {
            return false
        }
        let canonicalSpeciesId = uuid.uuidString.lowercased()

        protectExternalRouteFromImmediateSessionTimeoutReset()
        pendingExplorePostId = nil
        pendingSpeciesDictionaryRoute = SpeciesDictionaryRoute(
            scientificName: "",
            speciesId: canonicalSpeciesId,
            entryPoint: .deepLink
        )
        pendingCommunityIdentificationRequestId = nil
        pendingExploreTargetCommentId = nil
        pendingExploreTargetReplyParentCommentId = nil
        pendingCaptureGoalDestination = nil
        pendingExploreShowsFieldTrips = false
        explorePresentationIdentity = UUID()
        activeSheet = .explore
        return true
    }

    private func handleCommunityIdentificationRoute(requestId: String) {
        protectExternalRouteFromImmediateSessionTimeoutReset()
        pendingExplorePostId = nil
        pendingSpeciesDictionaryRoute = nil
        pendingCommunityIdentificationRequestId = requestId
        pendingExploreTargetCommentId = nil
        pendingExploreTargetReplyParentCommentId = nil
        pendingCaptureGoalDestination = nil
        pendingExploreShowsFieldTrips = false
        explorePresentationIdentity = UUID()
        activeSheet = .explore
    }

    private func handleScansLibraryRoute(
        recoveryContext: ExploreMediaRecoveryRouteContext? = nil,
        showsNonBiologicalCollection: Bool = false
    ) {
        protectExternalRouteFromImmediateSessionTimeoutReset()
        clearExplorePresentationRoute()
        pendingScansRecoveryContext = recoveryContext
        pendingScansShowsNonBiologicalCollection = showsNonBiologicalCollection
        activeSheet = .scans
    }

    func openCaptureGoal(_ goal: CaptureGoal) {
        openCaptureGoal(goal.destination)
    }

    func openCaptureGoal(_ destination: CaptureGoalDestination) {
        protectExternalRouteFromImmediateSessionTimeoutReset()
        pendingExplorePostId = nil
        pendingSpeciesDictionaryRoute = nil
        pendingCommunityIdentificationRequestId = nil
        pendingExploreTargetCommentId = nil
        pendingExploreTargetReplyParentCommentId = nil
        pendingCaptureGoalDestination = destination
        pendingExploreShowsFieldTrips = false
        explorePresentationIdentity = UUID()
        activeSheet = .explore
    }

    private func openFieldTrips() {
        protectExternalRouteFromImmediateSessionTimeoutReset()
        clearExplorePresentationRoute()
        pendingExploreShowsFieldTrips = true
        explorePresentationIdentity = UUID()
        activeSheet = .explore
    }
    
    // MARK: - User Intents
    
    func handlePhotoPickerSelection(newItems: [PhotosPickerItem], modelContext _: ModelContext) {
        guard !newItems.isEmpty else { return }

        let isPro = self.diContainer.revenueCatManager.canStartProScan
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
                    guard let preparedImport = try? await self.prepareFileBackedStagedImage(
                        fileURL: validUrl,
                        isPro: isPro,
                        historicalContext: historicalContext
                    ) else { continue }
                    preparedImports.append(preparedImport)
                }
            }

            guard !Task.isCancelled, !preparedImports.isEmpty else { return }
            await self.commitPreparedStagedImages(preparedImports, requiresCrop: true)
        }
    }

    func importPendingExternalImageIfPossible() {
        guard externalImageImportTask == nil else {
            externalImageImportRetryRequested = true
            return
        }

        externalImageImportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.externalImageImportTask = nil }

            repeat {
                self.externalImageImportRetryRequested = false

                let hasTerminalFailure = await self.externalImageImportStore.consumeTerminalFailure()
                let hasPendingImport = !(await self.externalImageImportStore.pendingImports()).isEmpty
                if hasTerminalFailure || hasPendingImport {
                    let didDismissSheet = self.prepareForExternalImageImportPresentation()
                    if hasTerminalFailure {
                        self.offlineToastMessage = "Naturebook couldn’t import that photo."
                    }
                    if hasPendingImport {
                        if didDismissSheet {
                            self.resumesExternalImageImportAfterSheetDismissal = true
                            self.externalImageImportRetryRequested = false
                            break
                        }
                        _ = await self.importNextPendingExternalImage()
                    }
                }
            } while self.externalImageImportRetryRequested && !Task.isCancelled
        }
    }

    func dismissActivePresentation() {
        guard let activePresentation else { return }
        dismissingPresentation = activePresentation
        self.activePresentation = nil
    }

    func queueNotificationPromptAfterInsightDismissal() {
        pendingLocalSheet = .notificationPrompt
    }

    func handleRootSheetDismissed(now: Date = Date()) {
        if let dismissed = dismissingPresentation {
            if dismissed.destination == .achievement {
                pendingAchievementAward = nil
            }
            if let requestID = dismissed.routeRequestID {
                diContainer.appRouteCoordinator.resolve(
                    requestID,
                    outcome: .dismissed(presentationID: dismissed.id),
                    now: now
                )
            }
            dismissingPresentation = nil
        }

        if let deferredRouteRequestID {
            self.deferredRouteRequestID = nil
            diContainer.appRouteCoordinator.resumeDeferredRequest(deferredRouteRequestID)
        }

        if resumesExternalImageImportAfterSheetDismissal {
            resumesExternalImageImportAfterSheetDismissal = false
            importPendingExternalImageIfPossible()
        }

        if diContainer.appRouteCoordinator.nextRequestID == nil,
           activePresentation == nil,
           let pendingLocalSheet {
            self.pendingLocalSheet = nil
            activeSheet = pendingLocalSheet
        }
    }

    /// Called only by a feature-local sheet/cover's exact `onDismiss` callback.
    /// A deferred global route is requeued here, after UIKit has released the
    /// presentation slot, rather than after a guessed teardown delay.
    func handleFeaturePresentationDismissed() {
        guard let deferredRouteRequestID else { return }
        self.deferredRouteRequestID = nil
        diContainer.appRouteCoordinator.resumeDeferredRequest(deferredRouteRequestID)
    }

    @discardableResult
    private func prepareForExternalImageImportPresentation() -> Bool {
        protectExternalRouteFromImmediateSessionTimeoutReset()
        clearExplorePresentationRoute()
        let didDismissSheet = activePresentation != nil || dismissingPresentation != nil
        activeSheet = nil
        return didDismissSheet
    }

    private func clearExplorePresentationRoute() {
        pendingExplorePostId = nil
        pendingSpeciesDictionaryRoute = nil
        pendingCommunityIdentificationRequestId = nil
        pendingExploreTargetCommentId = nil
        pendingExploreTargetReplyParentCommentId = nil
        pendingCaptureGoalDestination = nil
        pendingExploreShowsFieldTrips = false
    }

    private func presentExternalImageImportFailure() {
        offlineToastMessage = "Naturebook couldn’t import that photo."
        Task { [externalImageImportStore] in
            _ = await externalImageImportStore.consumeTerminalFailure()
        }
    }

    func importNextPendingExternalImage() async -> ExternalImageImportAttemptResult {
        guard let pendingImport = await externalImageImportStore.pendingImports().first else {
            return .noPendingImport
        }

        let isPro = diContainer.revenueCatManager.canStartProScan
        let importBudget = prepareGalleryImportBudget(isPro: isPro)
        guard importBudget.availableSlots > 0 else {
            presentExternalImportSlotBlock(for: pendingImport)
            return .temporarilyBlocked
        }
        guard importBudget.canPerformScan else {
            presentExternalImportQuotaBlock(for: pendingImport)
            return .temporarilyBlocked
        }
        guard let fileURL = await externalImageImportStore.fileURL(for: pendingImport) else {
            await failExternalImageImport(pendingImport, outcome: "failed_missing_file")
            return .terminalFailure
        }

        do {
            let metadata = try await DetachedWork.value(
                priority: .userInitiated,
                category: .imagePreparation
            ) {
                ImportedImageMetadataExtractor.extract(from: fileURL)
            }
            let historicalContext = await historicalContextSnapshot(for: metadata)
            guard let preparedImport = try await prepareFileBackedStagedImage(
                fileURL: fileURL,
                isPro: isPro,
                historicalContext: historicalContext
            ) else {
                throw MediaPreparationError.unreadableImage
            }

            let refreshedIsPro = diContainer.revenueCatManager.canStartProScan
            let refreshedBudget = prepareGalleryImportBudget(isPro: refreshedIsPro)
            guard refreshedBudget.availableSlots > 0 else {
                presentExternalImportSlotBlock(for: pendingImport)
                return .temporarilyBlocked
            }
            guard refreshedBudget.canPerformScan else {
                presentExternalImportQuotaBlock(for: pendingImport)
                return .temporarilyBlocked
            }

            let committedCount = commitPreparedStagedImages([preparedImport], requiresCrop: true)
            guard committedCount == 1 else {
                presentExternalImportSlotBlock(for: pendingImport)
                return .temporarilyBlocked
            }

            await externalImageImportStore.remove(pendingImport)
            slotBlockedExternalImportIds.remove(pendingImport.id)
            paywallPresentedExternalImportIds.remove(pendingImport.id)
            AppTelemetry.trackExternalImageImport(outcome: "staged")
            return .staged
        } catch is CancellationError {
            return .temporarilyBlocked
        } catch {
            MerianLog.data.error(
                "External image import preparation failed: \(error, privacy: .private)"
            )
            await failExternalImageImport(pendingImport, outcome: "failed_preparation")
            return .terminalFailure
        }
    }

    private func prepareFileBackedStagedImage(
        fileURL: URL,
        isPro: Bool,
        historicalContext: HistoricalEnvironmentContextSnapshot?
    ) async throws -> PreparedStagedImage? {
        let request = PreparedStagedImageRequest(
            fileURL: fileURL,
            isPro: isPro,
            historicalContext: historicalContext
        )
        return try await preparedImageLoader(request)
    }

    private func presentExternalImportSlotBlock(for pendingImport: PendingExternalImageImport) {
        if slotBlockedExternalImportIds.insert(pendingImport.id).inserted {
            AppTelemetry.trackExternalImageImport(outcome: "blocked_staging_capacity")
            offlineToastMessage = "Finish your current capture to import the shared photo."
        }
    }

    private func presentExternalImportQuotaBlock(for pendingImport: PendingExternalImageImport) {
        guard paywallPresentedExternalImportIds.insert(pendingImport.id).inserted else { return }
        AppTelemetry.trackExternalImageImport(outcome: "blocked_quota")
        AppTelemetry.trackPaywallImpression()
        activeSheet = .paywall
    }

    private func failExternalImageImport(
        _ pendingImport: PendingExternalImageImport,
        outcome: String
    ) async {
        await externalImageImportStore.remove(pendingImport)
        slotBlockedExternalImportIds.remove(pendingImport.id)
        paywallPresentedExternalImportIds.remove(pendingImport.id)
        AppTelemetry.trackExternalImageImport(outcome: outcome)
        HapticManager.shared.triggerErrorThump()
        offlineToastMessage = "Naturebook couldn’t import that photo."
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

    private func historicalContextSnapshot(
        for metadata: ImportedImageMetadata
    ) async -> HistoricalEnvironmentContextSnapshot? {
        if let latitude = metadata.latitude,
           let longitude = metadata.longitude,
           let captureDate = metadata.captureDate {
            let historicalContext = await diContainer.environmentContextManager.fetchHistoricalContext(
                location: CLLocation(latitude: latitude, longitude: longitude),
                date: captureDate
            )
            return HistoricalEnvironmentContextSnapshot(context: historicalContext)
        }

        guard metadata.captureDate != nil || metadata.hasCoordinate else { return nil }
        return HistoricalEnvironmentContextSnapshot(
            latitude: metadata.latitude,
            longitude: metadata.longitude,
            captureDate: metadata.captureDate
        )
    }

    @discardableResult
    func commitPreparedStagedImages(
        _ preparedImports: [PreparedStagedImage],
        requiresCrop: Bool = false
    ) -> Int {
        let availableSlots = availableStagedCaptureSlots
        guard availableSlots > 0 else { return 0 }

        var committedCount = 0

        for preparedImport in preparedImports.prefix(availableSlots) {
            let rawImage = UIImage(cgImage: preparedImport.previewCGImage.image)

            let identifiable = IdentifiableImage(
                image: rawImage,
                environmentContext: preparedImport.historicalContext?.makeEnvironmentContext(),
                isFromGallery: true
            )
            if requiresCrop {
                requiredGalleryCropImageIds.append(identifiable.id)
            }
            stagedCapture.images.append(StagedImage(
                compressedData: preparedImport.compressedData,
                displayData: preparedImport.displayData,
                uiImage: rawImage,
                original: identifiable,
                focusRegion: preparedImport.focusRegion
            ))
            committedCount += 1
        }

        if requiresCrop, committedCount > 0 {
            presentNextRequiredGalleryCrop()
        }
        return committedCount
    }
    
    // MARK: - Manual Crop Routing
    @ObservationIgnored var activeCropTask: Task<Void, Never>?

    var hasPendingRequiredGalleryCrop: Bool {
        requiredGalleryCropImageIds.contains { imageId in
            stagedCapture.images.contains { $0.original.id == imageId }
        }
    }

    var shouldAutoSubmitStagedCapture: Bool {
        guard !diContainer.appSettings.requiresScanConfirmation else { return false }

        let isMultiCapture = isMultiCaptureFunctionallyEnabled || baseRefinementContext != nil
        guard !isMultiCapture else { return false }

        let hasOtherModalities = !stagedCapture.observationContexts.isEmpty || !stagedCapture.audios.isEmpty
        guard !hasOtherModalities else { return false }

        return stagedCapture.images.count + stagedCapture.videos.count == 1 && !hasPendingRequiredGalleryCrop
    }

    func isRequiredGalleryCrop(_ imageID: UUID) -> Bool {
        requiredGalleryCropImageIds.contains(imageID)
    }

    @discardableResult
    func completeRequiredGalleryCrop(for imageID: UUID) -> Bool {
        requiredGalleryCropImageIds.removeAll { $0 == imageID }

        if hasPendingRequiredGalleryCrop {
            presentNextRequiredGalleryCrop()
            return false
        }

        return shouldAutoSubmitStagedCapture
    }

    func cancelRequiredGalleryCrop(for imageID: UUID) {
        activeCropTask?.cancel()
        requiredGalleryCropImageIds.removeAll { $0 == imageID }
        if let editIndex = stagedCapture.images.firstIndex(where: { $0.original.id == imageID }) {
            stagedCapture.images.remove(at: editIndex)
        }
        editingCropIndex = nil
        imageToCrop = nil
        presentNextRequiredGalleryCrop()
    }

    func clearStagedCaptureAndCropState(discardStagedMediaFiles: Bool = false) {
        activeCropTask?.cancel()
        requiredGalleryCropImageIds.removeAll()
        if discardStagedMediaFiles {
            discardLocalMediaFiles(at: stagedCapture.discardableLocalMediaFilePaths)
        }
        stagedCapture.clearAll()
        editingCropIndex = nil
        imageToCrop = nil
    }

    func removeStagedVideo(at index: Int) {
        guard stagedCapture.videos.indices.contains(index) else { return }
        let removedVideo = stagedCapture.videos.remove(at: index)
        discardLocalMediaFiles(
            at: [removedVideo.filePath, removedVideo.audioFilePath].compactMap { $0 }
        )
    }

    func discardLocalMediaFiles(at paths: [String]) {
        let uniquePaths = Array(Set(paths.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
        guard !uniquePaths.isEmpty else { return }
        Task(priority: .utility) {
            await FileIOActor.shared.deleteFiles(at: uniquePaths)
        }
    }

    func presentCrop(for index: Int) {
        guard index < stagedCapture.images.count else { return }
        self.editingCropIndex = index
        self.imageToCrop = stagedCapture.images[index].original
    }

    func presentNextRequiredGalleryCrop() {
        while let nextImageId = requiredGalleryCropImageIds.first {
            if let nextIndex = stagedCapture.images.firstIndex(where: { $0.original.id == nextImageId }) {
                presentCrop(for: nextIndex)
                return
            }
            requiredGalleryCropImageIds.removeFirst()
        }
    }
    
    @discardableResult
    func startRefinementScan(
        from record: LocalScanRecord,
        initialDescription: String? = nil,
        entryPoint: RefinementEntryPoint = .standard
    ) -> Bool {
        guard diContainer.revenueCatManager.canStartProScan else {
            AppTelemetry.trackPaywallImpression()
            activeSheet = .paywall
            return true
        }
        guard canStartRefinement(from: record, entryPoint: entryPoint) else {
            MerianLog.general.debug("Blocked refinement entry point for incompatible scan state.")
            return false
        }

        startRefinementScan(
            with: RefinementScanContext(record: record, entryPoint: entryPoint),
            initialDescription: initialDescription
        )
        return true
    }

    @discardableResult
    func startRefinementScan(
        scanId: String,
        initialDescription: String? = nil,
        entryPoint: RefinementEntryPoint = .standard
    ) -> Bool {
        guard let record = fetchLocalScan(scanId: scanId) else { return false }
        return startRefinementScan(
            from: record,
            initialDescription: initialDescription,
            entryPoint: entryPoint
        )
    }

    private func canStartRefinement(from record: LocalScanRecord, entryPoint: RefinementEntryPoint) -> Bool {
        switch entryPoint {
        case .standard:
            true
        case .nonBiologicalCorrection:
            !record.isBiological
        }
    }

    private func startRefinementScan(with context: RefinementScanContext, initialDescription: String? = nil) {
        self.refinementSubjectId = context.subjectId
        self.baseRefinementContext = context
        let trimmedDescription = initialDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.refinementInitialDescriptionDraft = context.entryPoint == .nonBiologicalCorrection
            ? nil
            : (trimmedDescription?.isEmpty == false ? trimmedDescription : nil)
        self.activeSheet = nil
        self.requestedCaptureMode = .describe

        stageHistoricalMediaForRefinement(from: context)
    }

    private func stageHistoricalMediaForRefinement(from context: RefinementScanContext) {
        for imageReference in context.capturedMediaSnapshot.imageReferences
            where stageHistoricalImageForRefinement(imageReference) {
            return
        }

        if let fallbackImagePath = context.coverImagePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallbackImagePath.isEmpty,
           stageHistoricalImageForRefinement(StoredMediaReference(legacyPath: fallbackImagePath)) {
            return
        }

        for audioReference in context.capturedMediaSnapshot.audioReferences
            where stageHistoricalAudioForRefinement(audioReference) {
            return
        }

        if let descriptionContext = context.capturedMediaSnapshot.observationContexts.first(where: { !$0.isEmpty }),
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

        let isPro = self.diContainer.revenueCatManager.canStartProScan

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
                    historicalContext: nil
                )
                guard let preparedRefinement = try await self.preparedImageLoader(request) else {
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
        guard SecureTransportPolicy.isSecureRemoteURL(remoteURL) else {
            throw URLError(.unsupportedURL)
        }
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
        baseRefinementContext = nil
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
            if captureMode == .visual,
               self.activeSheet == nil,
               self.imageToCrop == nil {
                cameraManager.startSession()
            }
        }
        if newPhase == .inactive && audioCaptureManager.isRecording && !audioCaptureManager.isPaused {
            audioCaptureManager.pauseRecording()
        }
        if newPhase == .background && audioCaptureManager.isRecording && !audioCaptureManager.isPaused {
            audioCaptureManager.pauseRecording()
        }
        if newPhase == .background {
            diContainer.offlineQueueManager.releaseAllDeferredLiveUploads(
                reason: "app_backgrounded"
            )
            diContainer.offlineQueueManager.releaseAllForegroundInferenceClaims(
                reason: "app_backgrounded"
            )
        }
        if newPhase == .inactive || newPhase == .background, isVideoRecording {
            stopVideoCapture()
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
        if newMode != .visual, isVideoRecording {
            stopVideoCapture()
        }

        if newMode == .audio || newMode == .describe {
            cameraManager.stopSession()
        } else if scenePhase == .active,
                  self.activeSheet == nil,
                  self.imageToCrop == nil {
            cameraManager.startSession()
        }
    }
}
