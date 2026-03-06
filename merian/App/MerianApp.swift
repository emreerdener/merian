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

    let container: ModelContainer
    
    init() {
        let schema = Schema([LocalScanRecord.self, OfflineQueuedScan.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
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
                .modelContainer(container)
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
                
                // Check edge databases implicitly for ghost uploads
                Task {
                    offlineQueueManager.syncPendingScans()
                }
            @unknown default:
                break
            }
        }
    }
}
