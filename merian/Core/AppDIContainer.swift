import SwiftUI
import SwiftData

/// Centralized Dependency Injection Container for Merian
/// Holds all core services and managers to prevent massive `@StateObject` pollution in App entry.
@MainActor
final class AppDIContainer: ObservableObject {
    static let shared = AppDIContainer()

    // Environment & Hardware
    lazy var hardwareOrchestrator = HardwareOrchestrator.shared
    lazy var cameraManager = CameraManager.shared
    lazy var hapticManager = HapticManager.shared

    // AI & Intelligence
    lazy var inferenceEngine = InferenceEngine()
    lazy var vui = ViewfinderIntelligence.shared
    
    // Core Services
    lazy var environmentContextManager = EnvironmentContextManager.shared

    // Data & Sync
    lazy var scanRepository = ScanRepository.shared
    lazy var offlineQueueManager = OfflineQueueManager.shared
    lazy var syncStateManager = SyncStateManager.shared
    lazy var archiveManager = ArchiveManager.shared
    lazy var photoLibraryManager = PhotoLibraryManager.shared

    // Network & Backend
    lazy var supabaseManager = SupabaseManager.shared
    
    // Analytics & Security
    lazy var revenueCatManager = RevenueCatManager.shared
    lazy var usageManager = UsageManager.shared
    lazy var gamificationManager = GamificationManager.shared
    lazy var circuitBreakerManager = CircuitBreakerManager.shared

    private init() {
        // Private initialization for singleton
    }
    
    /// Handles application transition to background gracefully
    func handleBackgroundPhase() {
        // Safely intercept mid-flight networks limits rescuing images asynchronously before standard app suspension
        if inferenceEngine.isProcessing, let payload = inferenceEngine.activeCompressedImageData ?? inferenceEngine.activeImageData {
            if revenueCatManager.isProActive {
                offlineQueueManager.enqueueCapture(
                    imageData: payload,
                    telemetry: CaptureTelemetry(
                        subjectDistanceInMeters: inferenceEngine.activeDistanceInMeters,
                        gpsLatitude: inferenceEngine.activeLatitude,
                        gpsLongitude: inferenceEngine.activeLongitude,
                        gpsElevation: inferenceEngine.activeElevation,
                        locationName: inferenceEngine.activeLocationName,
                        weatherCondition: inferenceEngine.activeWeatherCondition,
                        weatherTemperatureF: inferenceEngine.activeTemperatureF,
                        cameraPitchDegrees: inferenceEngine.activePitchDegrees,
                        compassHeading: inferenceEngine.activeCompassHeading,
                        relativeHumidity: inferenceEngine.activeRelativeHumidity,
                        uvIndex: inferenceEngine.activeUvIndex,
                        isFlashFired: inferenceEngine.activeFlashFired
                    ),
                    blurScore: nil
                )
            }
            inferenceEngine.cancelActiveRequest()
        }
    }
    
    /// Handles application transition to inactive (like app switcher)
    func handleInactivePhase() {
        cameraManager.stopSession()
        
        // Ensure the UI gracefully defaults back to the ready-to-scan state
        // if the user drops out of the app while viewing a sheet natively.
        // It's imperative that this is dispatched globally because we do not want
        // to directly couple `AppDIContainer` tightly to `CameraViewModel`.
        NotificationCenter.default.post(name: NSNotification.Name("AppDidEnterInactivePhase"), object: nil)
    }
    
    /// Handles application transition to active foreground
    func handleActivePhase() {
        cameraManager.startSession()
        usageManager.evaluateDailyRefresh()
        
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
            .environmentObject(container.environmentContextManager)
    }
}

extension View {
    func injectAppDependencies(container: AppDIContainer) -> some View {
        modifier(DIContainerModifier(container: container))
    }
}
