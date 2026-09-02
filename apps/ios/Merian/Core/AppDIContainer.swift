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
    let appEventPublisher: AppEventPublisher
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
    var activeCaptureGoalStore = ActiveCaptureGoalStore(
        provider: FieldTripCaptureGoalProvider()
    )

    // MARK: - Dependencies (Network & Backend)
    var supabaseManager = SupabaseManager.shared
    
    // MARK: - Dependencies (Analytics & Security)
    var consentManager = ConsentManager.shared
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
        let foundationVisualCueProvider = UnavailableFoundationVisualCueProvider()
        let foundationVisualCueEligibilityChecker =
            SystemFoundationCueEligibility()
        let appEventPublisher = AppEventPublisher()
        let milestoneToastClock = ContinuousMilestoneToastClock()
        let milestoneToastPresenter = MilestoneToastPresenter()
        self.visionSubjectClassifier = visionSubjectClassifier
        self.localVisualTraitExtractor = localVisualTraitExtractor
        self.foundationVisualCueProvider = foundationVisualCueProvider
        self.foundationVisualCueEligibilityChecker =
            foundationVisualCueEligibilityChecker
        self.appEventPublisher = appEventPublisher
        self.inferenceEngine = InferenceEngine(
            visionSubjectClassifier: visionSubjectClassifier,
            localVisualTraitExtractor: localVisualTraitExtractor,
            foundationVisualCueProvider: foundationVisualCueProvider,
            foundationVisualCueEligibilityChecker:
                foundationVisualCueEligibilityChecker,
            localAnalysisStartFeedback: {
                HapticManager.shared.triggerLightImpact(intensity: 0.3)
            }
        )
        self.milestoneToastClock = milestoneToastClock
        self.milestoneToastPresenter = milestoneToastPresenter
        self.milestoneToastHostRegistry = MilestoneToastHostRegistry()
        self.scanMilestoneCoordinator = ScanMilestoneCoordinator(
            eventSender: appEventPublisher,
            presenter: milestoneToastPresenter
        )

        if bindGlobalManagers {
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
            .environment(container.appRouteCoordinator)
            .environment(container.milestoneToastPresenter)
            .environment(container.milestoneToastHostRegistry)
            .environment(\.milestoneToastClock, container.milestoneToastClock)
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

enum DetachedWorkCategory: String {
    case thirdPartyBootstrap
    case imagePreparation
    case audioPreparation
    case fileSystemCleanup
    case backgroundDatabaseMutation
}

enum DetachedWork {
    @discardableResult
    static func fireAndForget(
        priority: TaskPriority = .userInitiated,
        category _: DetachedWorkCategory,
        operation: @Sendable @escaping () async -> Void
    ) -> Task<Void, Never> {
        Task.detached(priority: priority) {
            await operation()
        }
    }

    static func value<Success: Sendable>(
        priority: TaskPriority = .userInitiated,
        category _: DetachedWorkCategory,
        operation: @Sendable @escaping () async throws -> Success
    ) async throws -> Success {
        let task = Task.detached(priority: priority) {
            try await operation()
        }

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let value = try await task.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            task.cancel()
        }
    }
}
