import SwiftUI
import SwiftData

// Mock InferenceEngine resolving architecture boundaries
class InferenceEngine: ObservableObject {
    @Published var isProcessing: Bool = false
    @Published var activePayload: Data? = nil
    
    func cancelActiveRequest() {
        print("Cancelled active inference request to prevent watchdog termination.")
        isProcessing = false
    }
}

@main
struct MerianApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject private var hardwareOrchestrator = HardwareOrchestrator.shared
    @StateObject private var cameraManager = CameraManager.shared
    @StateObject private var offlineQueueManager = OfflineQueueManager.shared
    @StateObject private var inferenceEngine = InferenceEngine()
    @StateObject private var syncStateManager = SyncStateManager.shared
    @StateObject private var supabaseManager = SupabaseManager.shared
    @StateObject private var revenueCatManager = RevenueCatManager.shared
    @StateObject private var usageManager = UsageManager.shared

    let container: ModelContainer
    
    init() {
        // Initialize Zero-PII Crash & Anonymous Usage Metrics natively
        AppTelemetry.initialize()
        PostHogManager.shared.configure()
        
        let schema = Schema([LocalScanRecord.self, OfflineQueuedScan.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            OfflineQueueManager.shared.modelContext = container.mainContext
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            CameraRootView()
                .environmentObject(hardwareOrchestrator)
                .environmentObject(cameraManager)
                .environmentObject(offlineQueueManager)
                .environmentObject(inferenceEngine)
                .environmentObject(syncStateManager)
                .environmentObject(supabaseManager)
                .environmentObject(revenueCatManager)
                .environmentObject(usageManager)
                .modelContainer(container)
                .onAppear {
                    revenueCatManager.configure()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // Safely intercept mid-flight networks limits rescuing images asynchronously before standard app suspension
                if inferenceEngine.isProcessing, let payload = inferenceEngine.activePayload {
                    offlineQueueManager.enqueueCapture(imageData: payload)
                    inferenceEngine.cancelActiveRequest()
                }
            case .inactive:
                // Kill camera hardware to drastically preserve total battery draw in states like App Switcher or Notification Center Pulls
                cameraManager.stopSession()
            case .active:
                // Restore thermal feeds dynamically safely
                cameraManager.startSession()
                
                // Initialize the anonymous session natively if they haven't authenticated
                // Then check edge databases implicitly for ghost uploads
                Task {
                    await supabaseManager.initializeGhostSession()
                    offlineQueueManager.syncPendingScans()
                }
            @unknown default:
                break
            }
        }
    }
}
