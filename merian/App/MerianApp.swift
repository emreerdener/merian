import SwiftUI
import SwiftData

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        OfflineQueueManager.shared.backgroundCompletionHandler = completionHandler
    }
}

@main
struct MerianApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    let diContainer = AppDIContainer.shared

    let container: ModelContainer
    
    init() {
        // Initialize Zero-PII Crash & Anonymous Usage Metrics safely on the main thread after the camera UI loads
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            AppTelemetry.initialize()
            Task {
                await PostHogManager.shared.configure()
            }
        }
        
        let schema = Schema(versionedSchema: MerianSchemaV5.self)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, migrationPlan: MerianMigrationPlan.self, configurations: [modelConfiguration])
            
            // CRITICAL FIX: Access the singleton directly via .shared to prevent SwiftUI from 
            // prematurely evaluating the @StateObject property wrapper and throwing memory warnings.
            AppDIContainer.shared.scanRepository.configure(with: container.mainContext)
        } catch {
            // Fatal error protects against wiping data when encountering production schema migrations
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            CameraRootView()
                .injectAppDependencies(container: diContainer)
                .modelContainer(container)
                .onAppear {
                    diContainer.revenueCatManager.configure()
                }
                .onOpenURL { url in
                    Task {
                        do {
                            try await diContainer.supabaseManager.client.auth.session(from: url)
                        } catch {
                            print("Supabase auth session URL handler failed: \(error)")
                        }
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                diContainer.handleBackgroundPhase()
            case .inactive:
                diContainer.handleInactivePhase()
            case .active:
                diContainer.handleActivePhase()
            @unknown default:
                break
            }
        }
    }
}
