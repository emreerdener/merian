import SwiftUI
import SwiftData
import GoogleSignIn

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
        do {
            let schema = Schema(versionedSchema: MerianSchemaV10.self)
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, migrationPlan: MerianMigrationPlan.self, configurations: [config])
            AppDIContainer.shared.scanRepository.configure(with: container.mainContext)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        
        // Initialize Zero-PII Crash & Anonymous Usage Metrics off the main thread
        Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            AppTelemetry.initialize()
            await PostHogManager.shared.configure()
        }
    }

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    CameraRootView()
                } else {
                    OnboardingView()
                }
            }
            .modelContainer(container)
            .injectAppDependencies(container: diContainer)
            .onAppear {
                diContainer.revenueCatManager.configure()
            }
            .onOpenURL { url in
                if GIDSignIn.sharedInstance.handle(url) {
                    return
                }
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
