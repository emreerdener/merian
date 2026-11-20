import SwiftData
import SwiftUI

/// Centralized Dependency Injection Container for Merian
/// Holds all core services and managers to prevent massive `@StateObject` pollution in App entry.
@MainActor
@Observable final class AppDIContainer {
    static let shared: AppDIContainer = {
        MerianEnvironment.requireHistoryQualificationConfiguration()
        return AppDIContainer(bindGlobalManagers: true)
    }()

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
    let viewfinderHintLaunchState = ViewfinderHintLaunchState()
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
    
    /// App lifetime retains idle fresh-media inputs as well as active presentation work.
    private(set) var preparedReanalysisHostOwner = CaptureAudioReanalysisHostOwner()
    /// Called synchronously under the explicit feature-open account lease.
    func prepareReanalysisHostLifetimeForFeature() throws {
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified else { throw ObservationHistoryError.unavailable }
        try preparedReanalysisHostOwner.armAccountLifetime(manager: supabaseManager)
    }

    /// Reuse construction provenance without adopting the native-media profile.
    func reanalysisStartupForFeature(container: ModelContainer) throws -> NativeReleaseStartupAdmission {
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified,
              let startup = nativeMediaStartup, startup.container === container else { throw ObservationHistoryError.unavailable }
        return startup.admission
    }

    func reanalysisBorrowForFeature(container: ModelContainer) throws -> SharedMediaNativeOriginalDrain.LocalBorrow {
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified,
              let ownerID = supabaseManager.currentUser?.id else { throw ObservationHistoryError.unavailable }
        let manager = supabaseManager
        let account = PhotoOriginalPreparationOwner.AccountAccess(ownerID: ownerID,
            begin: { try manager.beginUnownedAccountBoundWork(expectedUserID: ownerID) },
            isCurrent: { manager.isAccountBoundWorkLeaseCurrent($0) },
            finish: { manager.finishAccountBoundWork($0) })
        let owner = preparedReanalysisHostOwner
        return try admitPreparedInputBorrow(container: container, account: account,
            consumer: owner, install: { try manager.installNativeMediaAccountTransitionDrain($0) },
            close: { await owner.drainAccountLifetimeDisposition(manager: manager).isRuntimeQuiescent })
    }

    private func retainedNativeLifetime(install: (SharedMediaNativeOriginalDrain) throws -> Void) throws -> SharedMediaNativeOriginalDrain {
        if let lifetime = nativeMediaLifetime { return lifetime }
        guard let startup = nativeMediaStartup else { throw SharedMediaStorageFailure.closed }
        let lifetime = SharedMediaNativeOriginalDrain(container: startup.container, admission: startup.admission) { [weak self] completed in
            guard let self, self.nativeMediaLifetime === completed else { return }
            self.nativeMediaOwner = nil
        }
        try install(lifetime)
        nativeMediaLifetime = lifetime
        return lifetime
    }

    private func admitPreparedInputBorrow(container: ModelContainer, account: PhotoOriginalPreparationOwner.AccountAccess,
                                          consumer: AnyObject, install: (SharedMediaNativeOriginalDrain) throws -> Void,
                                          close: @escaping @MainActor () async -> Bool) throws -> SharedMediaNativeOriginalDrain.LocalBorrow {
        let lease = try account.begin()
        defer { account.finish(lease) }
        guard account.isCurrent(lease), lease.session.userID == account.ownerID,
              nativeMediaStartup?.container === container else { throw PhotoPreparationFailure.accountChanged }
        let lifetime = try retainedNativeLifetime(install: install)
        try lifetime.bindPreparedAccount(account)
        return try lifetime.borrowLocalFence(for: consumer, role: .preparedInputs, container: container, close: close)
    }

    /// Called by this exact manager after Auth closes admission. An unarmed lifetime is inert.
    func awaitPreparedReanalysisHostDrain(for manager: SupabaseManager,
                                          recoveryAuthority: AuthRecoveryAuthority? = nil) async -> Bool {
        guard manager === supabaseManager, recoveryAuthority?.isCurrent ?? true else { return false }
        let result = await preparedReanalysisHostOwner.drainAccountLifetimeDisposition(manager: manager)
        guard recoveryAuthority?.isCurrent ?? true else { return false }
        return result == .cleaned || (recoveryAuthority != nil && result.isRuntimeQuiescent)
    }

    func accountDeletionLibraryContext(for manager: SupabaseManager) -> @MainActor (AnyObject?) -> Bool {
        guard manager === supabaseManager, let container = offlineQueueManager.modelContext?.container else { return { _ in false } }
        return { [weak self, weak manager] supplied in
            guard let self, let manager, manager === self.supabaseManager,
                  self.offlineQueueManager.modelContext?.container === container,
                  self.preparedReanalysisHostOwner.recognizesLibraryContainer(container) else { return false }
            return supplied == nil || supplied === container
        }
    }

    func acknowledgeDeletionPurge(for manager: SupabaseManager, scope: AccountDeletionLocalCleanupStore.RecoveryScope) -> Bool {
        guard manager === supabaseManager, let container = offlineQueueManager.modelContext?.container,
              scope.permitsLibraryPurge(in: container) else { return false }
        return preparedReanalysisHostOwner.acknowledgeLibraryPurge(container: container, manager: manager)
    }

    func librarySignOutScope(manager: SupabaseManager, transition: AuthTransitionToken,
                             journal: LibrarySignOutJournal) -> LibrarySignOutJournalStore.RecoveryScope? {
        guard manager === supabaseManager, let container = offlineQueueManager.modelContext?.container else { return nil }
        return LibrarySignOutJournalStore.live.recoveryScope(expected: journal) { [weak self, weak manager] in
            guard let self, let manager, self.supabaseManager === manager, manager.ownsAuthTransition(transition),
                  transition.kind == .recovery, self.offlineQueueManager.modelContext?.container === container,
                  self.preparedReanalysisHostOwner.recognizesLibraryContainer(container),
                  manager.activeAuthTransition?.sourceSession.map({ $0.userID == journal.sourceUserID }) != false,
                  manager.activeAuthTransition?.expectedSession.map({ $0.userID == journal.sourceUserID }) != false,
                  manager.currentUser.map({ $0.id == journal.sourceUserID }) != false else { return false }
            let sdkOwner = manager.client.auth.currentSession?.user.id
            return journal.phase == .sourceCleared ? sdkOwner == nil : (sdkOwner == nil || sdkOwner == journal.sourceUserID)
        }
    }

    func purgeLibraryForSignOut(manager: SupabaseManager, transition: AuthTransitionToken,
                                journal: LibrarySignOutJournal,
                                drain: (LibrarySignOutJournalStore.RecoveryScope) async -> Bool) async -> Bool {
        guard let scope = librarySignOutScope(manager: manager, transition: transition, journal: journal),
              scope.allowsLibraryPurge, let context = offlineQueueManager.modelContext,
              await drain(scope), scope.allowsLibraryPurge else { return false }
        guard await scanRepository.purgeAllData(modelContext: context,
            resetDerivedState: privateScanMapStore.resetSensitiveState,
            validateAuthorization: { scope.allowsLibraryPurge }), scope.allowsLibraryPurge else { return false }
        guard preparedReanalysisHostOwner.acknowledgeLibraryPurge(container: context.container, manager: manager) else { return false }
        do { try LibraryAccountOwnerStore.clear(); return true } catch { return false }
    }

    @ObservationIgnored private(set) var nativeMediaLifetime: SharedMediaNativeOriginalDrain?
    @ObservationIgnored private(set) var nativeMediaOwner: SharedMediaNativeOriginalOwner?
    @ObservationIgnored private var nativeMediaStartup: (container: ModelContainer, admission: NativeReleaseStartupAdmission)?
    @ObservationIgnored private var nativeMediaOpening: Task<SharedMediaNativeOriginalOwner, Error>?
    @ObservationIgnored private var nativeMediaAccountID: UUID?

    /// Stable Auth only. Original bootstrap provenance stays bound to its container;
    /// every retired owner remains terminal, including after a stale completion.
    func renewNativeMediaLifetime(for manager: SupabaseManager, isCurrent: @escaping @MainActor () -> Bool) async -> Bool {
        guard let startup = nativeMediaStartup else { return true }
        let lifetime = nativeMediaLifetime, prepared = preparedReanalysisHostOwner, cleanup = offlineQueueManager.reanalysisErasureOwner
        let current = { [self] in
            !Task.isCancelled && isCurrent() && manager === supabaseManager && !manager.isAuthTransitionInProgress &&
                !manager.librarySignOutRecoveryPending && !AccountDeletionLocalCleanupStore.isPending() &&
                offlineQueueManager.modelContext?.container === startup.container && nativeMediaLifetime === lifetime &&
                preparedReanalysisHostOwner === prepared && offlineQueueManager.reanalysisErasureOwner === cleanup
        }
        guard current(), nativeMediaOpening == nil else { return false }
        guard lifetime?.isClosed == true || prepared.isClosed else { return true }
        guard lifetime == nil || lifetime?.shutdownFinished == true else { return false }
        guard await prepared.retireAccountLifetime(manager: manager), current(), await cleanup.retire(), current() else { return false }
        do {
            try offlineQueueManager.renewReanalysisErasureOwner(cleanup) { successor in
                try configureInputRecovery(owner: successor, manager: manager)
                if let lifetime { try manager.retireNativeMediaAccountTransitionDrain(lifetime) }
            }
            preparedReanalysisHostOwner = CaptureAudioReanalysisHostOwner()
            nativeMediaLifetime = nil; nativeMediaAccountID = nil
            return true
        } catch { return false }
    }

    /// Inert in ordinary builds. No account or filesystem work occurs at setup.
    func configureNativeMediaLifetime(container: ModelContainer?, admission: NativeReleaseStartupAdmission?) throws {
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified else { return }
        guard nativeMediaStartup == nil, nativeMediaLifetime == nil else { throw SharedMediaStorageFailure.closed }
        guard let container, let admission else { return }
        nativeMediaStartup = (container, admission)
        try configureInputRecovery(owner: offlineQueueManager.reanalysisErasureOwner, manager: supabaseManager)
    }

    private func configureInputRecovery(owner: ObservationReanalysisErasureOwner, manager: SupabaseManager) throws {
        try configureInputRecovery(owner: owner, isCurrent: { [weak self] in
            self?.supabaseManager === manager && !manager.isAuthTransitionInProgress &&
                !manager.librarySignOutRecoveryPending && !AccountDeletionLocalCleanupStore.isPending()
        }, install: manager.installNativeMediaAccountTransitionDrain)
    }

    private func configureInputRecovery(owner: ObservationReanalysisErasureOwner,
                                        isCurrent: @escaping @MainActor () -> Bool,
                                        install: @escaping (SharedMediaNativeOriginalDrain) throws -> Void) throws {
        try owner.configureInputRecovery(admission: { [weak self, weak owner] container in
            guard let self, let owner, isCurrent(), self.nativeMediaStartup?.container === container else {
                throw SharedMediaStorageFailure.closed
            }
            let lifetime = try self.retainedNativeLifetime(install: install)
            return try lifetime.borrowLocalFence(for: owner, role: .inputRecovery, container: container,
                close: { await owner.closeInputRecovery() })
        }, isCurrent: isCurrent)
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
        if let lifetime = nativeMediaLifetime, !lifetime.permitsNativeDiscovery {
            guard nativeMediaAccountID == account.ownerID, lifetime.recognizes(account: account) else { throw PhotoPreparationFailure.accountChanged }
            if let opening = nativeMediaOpening { return opening }
            guard let owner = nativeMediaOwner, owner.isReadyForAppDispatch else { throw SharedMediaStorageFailure.closed }
            // Keep the installed terminal lifetime; it is never replaced.
            return Task { @MainActor in owner }
        }
        guard let startup = nativeMediaStartup else { throw SharedMediaStorageFailure.closed }
        let lifetime = try retainedNativeLifetime(install: install)
        try lifetime.requirePreparedAccount(account)
        nativeMediaAccountID = account.ownerID
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
    func preparedInputBorrowForTesting(container: ModelContainer, account: PhotoOriginalPreparationOwner.AccountAccess,
                                       consumer: AnyObject, install: (SharedMediaNativeOriginalDrain) throws -> Void,
                                       close: @escaping @MainActor () async -> Bool) throws -> SharedMediaNativeOriginalDrain.LocalBorrow {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        return try admitPreparedInputBorrow(container: container, account: account, consumer: consumer, install: install, close: close)
    }
    func configureInputRecoveryForTesting(owner: ObservationReanalysisErasureOwner) throws {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        try configureInputRecovery(owner: owner, manager: supabaseManager)
    }
    func configureInputRecoveryForTesting(owner: ObservationReanalysisErasureOwner,
                                          isCurrent: @escaping @MainActor () -> Bool,
                                          install: @escaping (SharedMediaNativeOriginalDrain) throws -> Void) throws {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        try configureInputRecovery(owner: owner, isCurrent: isCurrent, install: install)
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
        let liveInferenceSpeciesHydrationDependencies =
            InferenceSpeciesHydrationCoordinator.Dependencies.live
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
        self.liveInferenceRequestService = InferenceLiveRequestService.live
        self.liveInferenceResultService = InferenceLiveResultService.live
        self.liveInferenceQueueService = InferenceLiveQueueService.live
        self.liveInferenceCompletionDependencies =
            liveInferenceCompletionDependencies
        self.liveInferenceFailureDependencies =
            liveInferenceFailureDependencies
        self.liveInferencePipelineDependencies =
            liveInferencePipelineDependencies
        self.liveInferenceSpeciesReferenceService = SpeciesReferenceHydrationService.live
        self.liveInferenceSpeciesEnrichmentService = InferenceSpeciesEnrichmentService.live
        self.liveInferenceHydrationPersistenceService = InferenceHydrationPersistenceService.live
        self.liveInferenceSpeciesHydrationDependencies =
            liveInferenceSpeciesHydrationDependencies
        self.liveInferenceLookalikeCacheResetService = InferenceLookalikeCacheResetService.live
        self.liveInferenceIdentificationReviewService = InferenceIdentificationReviewService.live
        self.liveInferenceReviewSnapshotService = InferenceReviewSnapshotService.live
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
            liveRequestService: self.liveInferenceRequestService,
            liveResultService: self.liveInferenceResultService,
            liveQueueService: self.liveInferenceQueueService,
            liveCompletionDependencies:
                liveInferenceCompletionDependencies,
            speciesReferenceService: self.liveInferenceSpeciesReferenceService,
            speciesEnrichmentService: self.liveInferenceSpeciesEnrichmentService,
            hydrationPersistenceService: self.liveInferenceHydrationPersistenceService,
            identificationReviewService: self.liveInferenceIdentificationReviewService,
            identificationReviewSnapshotService: self.liveInferenceReviewSnapshotService,
            identificationReviewDependencies:
                liveInferenceIdentificationReviewDependencies,
            liveFailureDependencies:
                liveInferenceFailureDependencies,
            livePipelineDependencies:
                liveInferencePipelineDependencies,
            speciesHydrationDependencies:
                liveInferenceSpeciesHydrationDependencies,
            lookalikeCacheResetService: self.liveInferenceLookalikeCacheResetService
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
            .environment(container)
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
