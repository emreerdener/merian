import SwiftUI
import SwiftData

/// Centralized Dependency Injection Container for Merian
/// Holds all core services and managers to prevent massive `@StateObject` pollution in App entry.
@MainActor
@Observable final class AppDIContainer {
    static let shared = AppDIContainer()

    // MARK: - Dependencies (Environment & Hardware)
    var hardwareOrchestrator = HardwareOrchestrator.shared
    var cameraManager = CameraManager.shared
    var hapticManager = HapticManager.shared
    var pushNotificationManager = PushNotificationManager.shared

    // MARK: - Dependencies (AI & Intelligence)
    var inferenceEngine = InferenceEngine()
    var vui = ViewfinderIntelligence.shared
    
    // MARK: - Dependencies (Core Services)
    var environmentContextManager = EnvironmentContextManager.shared

    // MARK: - Dependencies (Data & Sync)
    var scanRepository = ScanRepository.shared
    var offlineQueueManager = OfflineQueueManager.shared
    var syncStateManager = SyncStateManager.shared
    var archiveManager = ArchiveManager.shared
    var photoLibraryManager = PhotoLibraryManager.shared

    // MARK: - Dependencies (Network & Backend)
    var supabaseManager = SupabaseManager.shared
    
    // MARK: - Dependencies (Analytics & Security)
    var revenueCatManager = RevenueCatManager.shared
    var usageManager = UsageManager.shared
    var gamificationManager = GamificationManager.shared
    var circuitBreakerManager = CircuitBreakerManager.shared

    // MARK: - Initialization Engine
    private init() {
        // Private initialization for singleton
    }
    
    // MARK: - App Lifecycle: Background Phase
    /// Handles application transition to background gracefully
    func handleBackgroundPhase() {
        // Safely intercept mid-flight networks limits rescuing images asynchronously before standard app suspension
        if inferenceEngine.isProcessing, let payload = inferenceEngine.activeCompressedImageData ?? inferenceEngine.activeImageData {
            if revenueCatManager.isProActive {
                offlineQueueManager.enqueueCapture(
                    imageDatas: [payload],
                    telemetry: CaptureTelemetry(from: inferenceEngine),
                    blurScore: nil
                )
            }
            inferenceEngine.cancelActiveRequest()
        }
    }
    
    // MARK: - App Lifecycle: Inactive Phase
    /// Handles application transition to inactive (like app switcher)
    func handleInactivePhase() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        guard hasCompletedOnboarding else { return }
        
        cameraManager.stopSession()
        
        // Ensure the UI gracefully defaults back to the ready-to-scan state
        // if the user drops out of the app while viewing a sheet natively.
        // It's imperative that this is dispatched globally because we do not want
        // to directly couple `AppDIContainer` tightly to `CameraViewModel`.
        NotificationCenter.default.post(name: NSNotification.Name("AppDidEnterInactivePhase"), object: nil)
    }
    
    // MARK: - App Lifecycle: Active Phase
    /// Handles application transition to active foreground
    func handleActivePhase() {
        // Structurally prevent the OS from booting camera sessions implicitly or hitting API quotas actively natively during the Onboarding flow securely.
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        guard hasCompletedOnboarding else { return }
        
        cameraManager.startSession()
        usageManager.evaluateDailyRefresh()
        pushNotificationManager.setupDelegate()
        pushNotificationManager.syncPermissionState()
        
        Task {
            await supabaseManager.initializeGhostSession()
            offlineQueueManager.syncPendingScans()
            
            if let context = offlineQueueManager.modelContext {
                // Restore account history for re-installs or multi-device login seamlessly
                await scanRepository.syncHistoricalScansDown(modelContext: context)
            }
            
            // Trigger Archive Safety Protocol natively once per 24 hours
            let now = Date()
            let lastRescueDate = UserDefaults.standard.object(forKey: "lastArchiveRescueDate") as? Date ?? Date.distantPast
            if now.timeIntervalSince(lastRescueDate) >= 86400 {
                if let context = offlineQueueManager.modelContext {
                    archiveManager.evaluateAndRescueAgingScans(modelContext: context)
                    UserDefaults.standard.set(now, forKey: "lastArchiveRescueDate")
                }
            }
        }
    }
}

// MARK: - DI Injection Modifiers

/// View modifier to easily inject all dependent EnvironmentObjects
struct DIContainerModifier: ViewModifier {
    var container: AppDIContainer
    
    func body(content: Content) -> some View {
        content
            .environment(container.hardwareOrchestrator)
            .environment(container.cameraManager)
            .environment(container.hapticManager)
            .environment(container.pushNotificationManager)
            .environment(container.inferenceEngine)
            .environment(container.vui)
            .environment(container.offlineQueueManager)
            .environment(container.syncStateManager)
            .environment(container.archiveManager)
            .environment(container.photoLibraryManager)
            .environment(container.supabaseManager)
            .environment(container.revenueCatManager)
            .environment(container.usageManager)
            .environment(container.gamificationManager)
            .environment(container.circuitBreakerManager)
            .environment(container.environmentContextManager)
    }
}

// MARK: - View Environment Extensions

extension View {
    func injectAppDependencies(container: AppDIContainer) -> some View {
        modifier(DIContainerModifier(container: container))
    }
}
