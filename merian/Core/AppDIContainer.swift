import SwiftUI
import SwiftData

/// Centralized Dependency Injection Container for Merian
/// Holds all core services and managers to prevent massive `@StateObject` pollution in App entry.
@MainActor
final class AppDIContainer: ObservableObject {
    static let shared = AppDIContainer()

    // Environment & Hardware
    let hardwareOrchestrator = HardwareOrchestrator.shared
    let cameraManager = CameraManager.shared
    let hapticManager = HapticManager() // or shared if applicable

    // AI & Intelligence
    let inferenceEngine = InferenceEngine()
    let vui = ViewfinderIntelligence.shared

    // Data & Sync
    let scanRepository = ScanRepository.shared
    let offlineQueueManager = OfflineQueueManager.shared
    let syncStateManager = SyncStateManager.shared
    let archiveManager = ArchiveManager.shared
    let photoLibraryManager = PhotoLibraryManager.shared

    // Network & Backend
    let supabaseManager = SupabaseManager.shared
    
    // Analytics & Security
    let revenueCatManager = RevenueCatManager.shared
    let usageManager = UsageManager.shared
    let gamificationManager = GamificationManager.shared
    let circuitBreakerManager = CircuitBreakerManager.shared

    private init() {
        // Private initialization for singleton
    }
    
    /// Handles application transition to background gracefully
    func handleBackgroundPhase() {
        // Safely intercept mid-flight networks limits rescuing images asynchronously before standard app suspension
        if inferenceEngine.isProcessing, let payload = inferenceEngine.activeCompressedPayload ?? inferenceEngine.activePayload {
            offlineQueueManager.enqueueCapture(
                imageData: payload,
                gpsLatitude: inferenceEngine.activeLatitude,
                gpsLongitude: inferenceEngine.activeLongitude,
                weatherCondition: inferenceEngine.activeWeatherCondition
            )
            inferenceEngine.cancelActiveRequest()
        }
    }
    
    /// Handles application transition to inactive (like app switcher)
    func handleInactivePhase() {
        cameraManager.stopSession()
    }
    
    /// Handles application transition to active foreground
    func handleActivePhase() {
        cameraManager.startSession()
        
        Task {
            await supabaseManager.initializeGhostSession()
            offlineQueueManager.syncPendingScans()
        }
    }
}

/// View modifier to easily inject all dependent EnvironmentObjects
struct DIContainerModifier: ViewModifier {
    @ObservedObject var container: AppDIContainer
    
    func body(content: Content) -> some View {
        content
            .environmentObject(container.hardwareOrchestrator)
            .environmentObject(container.cameraManager)
            .environmentObject(container.inferenceEngine)
            .environmentObject(container.vui)
            .environmentObject(container.offlineQueueManager)
            .environmentObject(container.syncStateManager)
            .environmentObject(container.archiveManager)
            .environmentObject(container.photoLibraryManager)
            .environmentObject(container.supabaseManager)
            .environmentObject(container.revenueCatManager)
            .environmentObject(container.usageManager)
            .environmentObject(container.gamificationManager)
            .environmentObject(container.circuitBreakerManager)
    }
}

extension View {
    func injectAppDependencies(container: AppDIContainer) -> some View {
        modifier(DIContainerModifier(container: container))
    }
}
