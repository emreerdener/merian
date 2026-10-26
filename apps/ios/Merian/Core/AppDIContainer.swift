import SwiftData
import SwiftUI

/// Centralized Dependency Injection Container for Merian
/// Holds all core services and managers to prevent massive `@StateObject` pollution in App entry.
@MainActor
@Observable final class AppDIContainer {
    static let shared = AppDIContainer(bindGlobalManagers: true)

    // MARK: - Dependencies (Environment & Hardware)
    var hardwareOrchestrator = HardwareOrchestrator.shared
    var cameraManager = CameraManager.shared
    var hapticManager = HapticManager.shared
    var pushNotificationManager = PushNotificationManager.shared

    // MARK: - Dependencies (AI & Intelligence)
    @ObservationIgnored
    let visionSubjectClassifier: any VisionSubjectClassifying
    @ObservationIgnored
    let localVisualTraitExtractor: any LocalVisualTraitExtracting
    @ObservationIgnored
    let foundationVisualCueProvider: any FoundationVisualCueProviding
    @ObservationIgnored
    let foundationVisualCueEligibilityChecker: any FoundationVisualCueEligibilityChecking
    @ObservationIgnored
    let liveInferenceRequestService: InferenceLiveRequestService
    @ObservationIgnored
    let liveInferenceResultService: InferenceLiveResultService
    @ObservationIgnored
    let liveInferenceQueueService: InferenceLiveQueueService
    @ObservationIgnored
    let liveInferenceCompletionDependencies:
        InferenceLiveCompletionCoordinator.Dependencies
    @ObservationIgnored
    let liveInferenceFailureDependencies:
        InferenceLiveFailureCoordinator.Dependencies
    @ObservationIgnored
    let liveInferencePipelineDependencies:
        InferenceLivePipelineCoordinator.Dependencies
    @ObservationIgnored
    let liveInferenceSpeciesReferenceService:
        SpeciesReferenceHydrationService
    @ObservationIgnored
    let liveInferenceSpeciesEnrichmentService:
        InferenceSpeciesEnrichmentService
    @ObservationIgnored
    let liveInferenceHydrationPersistenceService:
        InferenceHydrationPersistenceService
    @ObservationIgnored
    let liveInferenceSpeciesHydrationDependencies:
        InferenceSpeciesHydrationCoordinator.Dependencies
    @ObservationIgnored
    let liveInferenceLookalikeCacheResetService:
        InferenceLookalikeCacheResetService
    @ObservationIgnored
    let liveInferenceIdentificationReviewService:
        InferenceIdentificationReviewService
    @ObservationIgnored
    let liveInferenceReviewSnapshotService:
        InferenceReviewSnapshotService
    @ObservationIgnored
    let liveInferenceIdentificationReviewDependencies:
        InferenceIdentificationReviewCoordinator.Dependencies
    var inferenceEngine: InferenceEngine
    var viewfinderIntelligence = ViewfinderIntelligence.shared
    var speechManager = SpeechManager()
    var audioCaptureManager = AudioCaptureManager(
        maxDurationFeedback: {
            HapticManager.shared.triggerHeavyImpact()
        }
    )
    
    // MARK: - Dependencies (Core Services)
    @ObservationIgnored
    var environmentContextManager = EnvironmentContextManager.shared
    let exploreContentVisibility = ExploreContentVisibilityStore()
    let appEventPublisher: AppEventPublisher
    let appUpdateCoordinator: AppUpdateCoordinator
    let appRouteCoordinator = AppRouteCoordinator()
    let milestoneToastClock: any MilestoneToastClock
    let milestoneToastPresenter: MilestoneToastPresenter
    let milestoneToastHostRegistry: MilestoneToastHostRegistry
    let scanMilestoneCoordinator: ScanMilestoneCoordinator
    var appSettings = AppSettings.shared

    // MARK: - Dependencies (Data & Sync)
    var scanRepository = ScanRepository.shared
    var offlineQueueManager = OfflineQueueManager.shared
    var syncStateManager = SyncStateManager.shared
    var archiveManager = ArchiveManager.shared
    var photoLibraryManager = PhotoLibraryManager.shared
    var externalImageImportStore = ExternalImageImportStore.shared
    let privateScanMapStore = PrivateScanMapStore()
    let mapPlaceSearchConfiguration: MapPlaceSearchConfiguration = {
        #if DEBUG
        if let fixture = UITestSeedCoordinator.mapPlaceSearchConfiguration() { return fixture }
        #endif
        return MapPlaceSearchConfiguration(dependencies: .live, history: RecentPlaceStore())
    }()
    var activeCaptureGoalStore = ActiveCaptureGoalStore(
        provider: FieldTripCaptureGoalProvider()
    )

    // MARK: - Dependencies (Network & Backend)
    var supabaseManager = SupabaseManager.shared
    
    @ObservationIgnored private(set) var nativeMediaLifetime: SharedMediaNativeOriginalDrain?
    @ObservationIgnored private(set) var nativeMediaOwner: SharedMediaNativeOriginalOwner?
    @ObservationIgnored private var nativeMediaStartup: (container: ModelContainer, admission: NativeReleaseStartupAdmission)?
    @ObservationIgnored private var nativeMediaOpening: Task<SharedMediaNativeOriginalOwner, Error>?
    @ObservationIgnored private var nativeMediaAccountID: UUID?

    /// Inert in ordinary builds. No account or filesystem work occurs at setup.
    func configureNativeMediaLifetime(container: ModelContainer?, admission: NativeReleaseStartupAdmission?) throws {
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified else { return }
        guard nativeMediaStartup == nil, nativeMediaLifetime == nil else { throw SharedMediaStorageFailure.closed }
        guard let container, let admission else { return }
        nativeMediaStartup = (container, admission)
    }

    /// Explicit feature admission only. Initial Auth transitions occur before
    /// any lifetime/hook is installed; refusal here does not consume startup.
    func nativeMediaOwnerForFeature() async throws -> SharedMediaNativeOriginalOwner {
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified,
              let ownerID = supabaseManager.currentUser?.id else { throw SharedMediaStorageFailure.closed }
        let manager = supabaseManager
        let account = PhotoOriginalPreparationOwner.AccountAccess(ownerID: ownerID,
            begin: { try manager.beginUnownedAccountBoundWork(expectedUserID: ownerID) },
            isCurrent: { manager.isAccountBoundWorkLeaseCurrent($0) },
            finish: { manager.finishAccountBoundWork($0) })
        let task = try admitNativeMedia(account: account,
            install: { try manager.installNativeMediaAccountTransitionDrain($0) },
            discover: { try $0.discover(account: account) })
        let owner = try await task.value
        try Task.checkCancellation()
        guard owner === nativeMediaOwner, owner.isReadyForAppDispatch else { throw SharedMediaStorageFailure.closed }
        return owner
    }

    /// Account admission, hook installation, discovery and task retention are a
    /// single MainActor turn. The preliminary lease is always finished here.
    private func admitNativeMedia(account: PhotoOriginalPreparationOwner.AccountAccess,
        install: (SharedMediaNativeOriginalDrain) throws -> Void,
        discover: (SharedMediaNativeOriginalDrain) throws -> SharedMediaNativeBootstrapDiscovery,
        configure: (SharedMediaNativeOriginalOwner) throws -> Void = { _ in }) throws -> Task<SharedMediaNativeOriginalOwner, Error> {
        try Task.checkCancellation()
        let lease = try account.begin()
        defer { account.finish(lease) }
        guard lease.session.userID == account.ownerID, account.isCurrent(lease) else { throw PhotoPreparationFailure.accountChanged }
        if let lifetime = nativeMediaLifetime {
            guard nativeMediaAccountID == account.ownerID, lifetime.recognizes(account: account) else { throw PhotoPreparationFailure.accountChanged }
            if let opening = nativeMediaOpening { return opening }
            guard let owner = nativeMediaOwner, owner.isReadyForAppDispatch else { throw SharedMediaStorageFailure.closed }
            // Keep the installed terminal lifetime; it is never replaced.
            return Task { @MainActor in owner }
        }
        guard let startup = nativeMediaStartup else { throw SharedMediaStorageFailure.closed }
        let lifetime = SharedMediaNativeOriginalDrain(container: startup.container, admission: startup.admission) { [weak self] completed in
            guard let self, self.nativeMediaLifetime === completed else { return }
            self.nativeMediaOwner = nil; self.nativeMediaStartup = nil
        }
        try install(lifetime)
        nativeMediaLifetime = lifetime; nativeMediaAccountID = account.ownerID
        do {
            let discovery = try discover(lifetime)
            let owner = try SharedMediaNativeOriginalOwner.app(account: account, drain: lifetime, discovery: discovery)
            nativeMediaOwner = owner
            try configure(owner)
            let task = Task { @MainActor [self] in
                defer { nativeMediaOpening = nil }
                do {
                    _ = try await owner.openApp(container: startup.container, discovery: discovery)
                    guard nativeMediaLifetime === lifetime, nativeMediaOwner === owner,
                          nativeMediaStartup?.container === startup.container, owner.isReadyForAppDispatch else {
                        throw PhotoPreparationFailure.accountChanged
                    }
                    return owner
                } catch {
                    _ = await lifetime.shutdown()
                    throw error
                }
            }
            nativeMediaOpening = task
            return task
        } catch {
            // Own cleanup even if the feature caller immediately disappears.
            let task = Task<SharedMediaNativeOriginalOwner, Error> { @MainActor [self] in
                defer { nativeMediaOpening = nil }
                _ = await lifetime.shutdown()
                throw error
            }
            nativeMediaOpening = task
            return task
        }
    }

    #if DEBUG
    func configureNativeMediaForTesting(container: ModelContainer, admission: NativeReleaseStartupAdmission) throws {
        guard TestExecutionCoordinator.isRunningTests, nativeMediaStartup == nil, nativeMediaLifetime == nil else { throw SharedMediaStorageFailure.closed }
        nativeMediaStartup = (container, admission)
    }
    func nativeMediaOwnerForTesting(account: PhotoOriginalPreparationOwner.AccountAccess, support: URL,
        install: (SharedMediaNativeOriginalDrain) throws -> Void,
        configure: (SharedMediaNativeOriginalOwner) throws -> Void = { _ in }) async throws -> SharedMediaNativeOriginalOwner {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        let task = try admitNativeMedia(account: account, install: install,
            discover: { try $0.qualificationDiscover(account: account, support: support) }, configure: configure)
        let owner = try await task.value
        try Task.checkCancellation()
        guard owner === nativeMediaOwner, owner.isReadyForAppDispatch else { throw SharedMediaStorageFailure.closed }
        return owner
    }
    #endif

    // MARK: - Dependencies (Analytics & Security)
    var consentManager: ConsentManager = {
        #if DEBUG
        if let fixture = UITestSeedCoordinator.openAIPermissionConsentManager() { return fixture }
        #endif
        return ConsentManager.shared
    }()
    var revenueCatManager = RevenueCatManager.shared
    var entitlementManager = EntitlementManager.shared
    var scanAdmissionManager = ScanAdmissionManager.shared
    var usageManager = UsageManager.shared
    var gamificationManager = GamificationManager.shared
    var circuitBreakerManager = CircuitBreakerManager.shared
    
    // MARK: - Dependencies (ViewModels)
    var profileViewModel = ProfileViewModel()

    // MARK: - Initialization Engine
    private init(bindGlobalManagers: Bool) {
        let visionSubjectClassifier = AppleVisionSubjectClassifier()
        let localVisualTraitExtractor = AppleImageVisualTraitExtractor()
        let foundationVisualCueProvider = AppleFoundationVisualCueProvider()
        let foundationVisualCueEligibilityChecker =
            SystemFoundationCueEligibility()
        let liveInferenceRequestService = InferenceLiveRequestService.live
        let liveInferenceResultService = InferenceLiveResultService.live
        let liveInferenceQueueService = InferenceLiveQueueService.live
        let liveInferenceSpeciesReferenceService =
            SpeciesReferenceHydrationService.live
        let liveInferenceSpeciesEnrichmentService =
            InferenceSpeciesEnrichmentService.live
        let liveInferenceHydrationPersistenceService =
            InferenceHydrationPersistenceService.live
        let liveInferenceSpeciesHydrationDependencies =
            InferenceSpeciesHydrationCoordinator.Dependencies.live
        let liveInferenceLookalikeCacheResetService =
            InferenceLookalikeCacheResetService.live
        let liveInferenceIdentificationReviewService =
            InferenceIdentificationReviewService.live
        let liveInferenceReviewSnapshotService =
            InferenceReviewSnapshotService.live
        let appEventPublisher = AppEventPublisher()
        let appUpdateCoordinator = AppUpdateCoordinator {
            SupabaseManager.shared.currentUser?.id
        }
        let milestoneToastClock = ContinuousMilestoneToastClock()
        let milestoneToastPresenter = MilestoneToastPresenter()
        let milestoneToastHostRegistry = MilestoneToastHostRegistry()
        let scanMilestoneCoordinator = ScanMilestoneCoordinator(
            eventSender: appEventPublisher,
            presenter: milestoneToastPresenter,
            dependencies: .live
        )
        let liveInferenceCompletionDependencies =
            InferenceLiveCompletionCoordinator.Dependencies.composed(
                gamificationManager: GamificationManager.shared,
                scanRepository: ScanRepository.shared,
                circuitBreakerManager: CircuitBreakerManager.shared,
                revenueCatManager: RevenueCatManager.shared,
                appSettings: AppSettings.shared,
                pushNotificationManager: PushNotificationManager.shared,
                offlineQueueManager: OfflineQueueManager.shared,
                eventSender: appEventPublisher,
                milestoneCoordinator: scanMilestoneCoordinator
            )
        let liveInferenceFailureDependencies =
            InferenceLiveFailureCoordinator.Dependencies.composed(
                circuitBreakerManager: CircuitBreakerManager.shared,
                hapticManager: HapticManager.shared,
                usageManager: UsageManager.shared,
                requestAppUpdate: { appUpdateCoordinator.record(.identification) }
            )
        let liveInferencePipelineDependencies =
            InferenceLivePipelineCoordinator.Dependencies.composed(
                circuitBreakerManager: CircuitBreakerManager.shared,
                usageManager: UsageManager.shared
            )
        let liveInferenceIdentificationReviewDependencies =
            InferenceIdentificationReviewCoordinator.Dependencies.composed(
                eventSender: appEventPublisher,
                milestoneCoordinator: scanMilestoneCoordinator
            )
        self.visionSubjectClassifier = visionSubjectClassifier
        self.localVisualTraitExtractor = localVisualTraitExtractor
        self.foundationVisualCueProvider = foundationVisualCueProvider
        self.foundationVisualCueEligibilityChecker =
            foundationVisualCueEligibilityChecker
        self.liveInferenceRequestService = liveInferenceRequestService
        self.liveInferenceResultService = liveInferenceResultService
        self.liveInferenceQueueService = liveInferenceQueueService
        self.liveInferenceCompletionDependencies =
            liveInferenceCompletionDependencies
        self.liveInferenceFailureDependencies =
            liveInferenceFailureDependencies
        self.liveInferencePipelineDependencies =
            liveInferencePipelineDependencies
        self.liveInferenceSpeciesReferenceService =
            liveInferenceSpeciesReferenceService
        self.liveInferenceSpeciesEnrichmentService =
            liveInferenceSpeciesEnrichmentService
        self.liveInferenceHydrationPersistenceService =
            liveInferenceHydrationPersistenceService
        self.liveInferenceSpeciesHydrationDependencies =
            liveInferenceSpeciesHydrationDependencies
        self.liveInferenceLookalikeCacheResetService =
            liveInferenceLookalikeCacheResetService
        self.liveInferenceIdentificationReviewService =
            liveInferenceIdentificationReviewService
        self.liveInferenceReviewSnapshotService =
            liveInferenceReviewSnapshotService
        self.liveInferenceIdentificationReviewDependencies =
            liveInferenceIdentificationReviewDependencies
        self.appEventPublisher = appEventPublisher
        self.appUpdateCoordinator = appUpdateCoordinator
        self.milestoneToastClock = milestoneToastClock
        self.milestoneToastPresenter = milestoneToastPresenter
        self.milestoneToastHostRegistry = milestoneToastHostRegistry
        self.scanMilestoneCoordinator = scanMilestoneCoordinator
        self.inferenceEngine = InferenceEngine(
            visionSubjectClassifier: visionSubjectClassifier,
            localVisualTraitExtractor: localVisualTraitExtractor,
            foundationVisualCueProvider: foundationVisualCueProvider,
            foundationVisualCueEligibilityChecker:
                foundationVisualCueEligibilityChecker,
            localAnalysisStartFeedback: {
                HapticManager.shared.triggerLightImpact(intensity: 0.3)
            },
            liveRequestService: liveInferenceRequestService,
            liveResultService: liveInferenceResultService,
            liveQueueService: liveInferenceQueueService,
            liveCompletionDependencies:
                liveInferenceCompletionDependencies,
            speciesReferenceService:
                liveInferenceSpeciesReferenceService,
            speciesEnrichmentService:
                liveInferenceSpeciesEnrichmentService,
            hydrationPersistenceService:
                liveInferenceHydrationPersistenceService,
            identificationReviewService:
                liveInferenceIdentificationReviewService,
            identificationReviewSnapshotService:
                liveInferenceReviewSnapshotService,
            identificationReviewDependencies:
                liveInferenceIdentificationReviewDependencies,
            liveFailureDependencies:
                liveInferenceFailureDependencies,
            livePipelineDependencies:
                liveInferencePipelineDependencies,
            speciesHydrationDependencies:
                liveInferenceSpeciesHydrationDependencies,
            lookalikeCacheResetService:
                liveInferenceLookalikeCacheResetService
        )

        if bindGlobalManagers {
            exploreContentVisibility.didInvalidate = { [weak exploreContentVisibility] in
                guard let visibility = exploreContentVisibility else { return }
                MerianNetworkClient.shared.invalidateSpeciesDictionaryVisibility()
                AppIconBadgeCoordinator.clearExploreUnreadNotificationCount()
                ExploreWidgetSnapshotWriter.invalidate(visibility: visibility)
            }
            scanRepository.appUpdateCoordinator = appUpdateCoordinator
            offlineQueueManager.appUpdateCoordinator = appUpdateCoordinator
            supabaseManager.bindAppRouteSessionController(appRouteCoordinator)
            supabaseManager.bindMilestoneToastSessionController(scanMilestoneCoordinator)
        }
    }
    
#if DEBUG
    // MARK: - Mock Initialization (Previews)
    /// A safe mock container for SwiftUI `#Preview` execution that guarantees live production databases or hardware components are not mutated.
    static var preview: AppDIContainer {
        let container = AppDIContainer(bindGlobalManagers: false)
        container.appSettings = .preview
        // Inject mock instances or disable background observers here as needed.
        return container
    }
#endif
    
}

// MARK: - DI Injection Modifiers

/// View modifier to easily inject all dependent EnvironmentObjects
struct DIContainerModifier: ViewModifier {
    let container: AppDIContainer
    
    func body(content: Content) -> some View {
        content
            .environment(container.hardwareOrchestrator)
            .environment(container.cameraManager)
            .environment(container.hapticManager)
            .environment(container.pushNotificationManager)
            .environment(container.inferenceEngine)
            .environment(container.viewfinderIntelligence)
            .environment(container.offlineQueueManager)
            .environment(container.syncStateManager)
            .environment(container.archiveManager)
            .environment(container.photoLibraryManager)
            .environment(container.supabaseManager)
            .environment(container.consentManager)
            .environment(container.revenueCatManager)
            .environment(container.entitlementManager)
            .environment(container.usageManager)
            .environment(container.gamificationManager)
            .environment(container.circuitBreakerManager)
            .environment(container.environmentContextManager)
            .environment(container.appSettings)
            .environment(container.profileViewModel)
            .environment(container.speechManager)
            .environment(container.audioCaptureManager)
            .environment(container.activeCaptureGoalStore)
            .environment(container.privateScanMapStore)
            .environment(\.mapPlaceSearchConfiguration, container.mapPlaceSearchConfiguration)
            .environment(container.appRouteCoordinator)
            .environment(container.milestoneToastPresenter)
            .environment(container.milestoneToastHostRegistry)
            .environment(\.milestoneToastClock, container.milestoneToastClock)
            .environment(
                \.milestoneToastFeedback,
                .live(hapticManager: container.hapticManager)
            )
    }
}

private struct MilestoneToastClockEnvironmentKey: EnvironmentKey {
    static let defaultValue: any MilestoneToastClock = ContinuousMilestoneToastClock()
}

extension EnvironmentValues {
    var milestoneToastClock: any MilestoneToastClock {
        get { self[MilestoneToastClockEnvironmentKey.self] }
        set { self[MilestoneToastClockEnvironmentKey.self] = newValue }
    }
}

// MARK: - View Environment Extensions

extension View {
    func injectAppDependencies(container: AppDIContainer) -> some View {
        modifier(DIContainerModifier(container: container))
    }
}
