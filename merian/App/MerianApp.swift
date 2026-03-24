import SwiftUI
import SwiftData
import GoogleSignIn

// MARK: - Core Application Delegation
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        OfflineQueueManager.shared.backgroundCompletionHandler = completionHandler
    }
}

// MARK: - Main Execution Point
@main
struct MerianApp: App {
    // MARK: - Lifecycle Hooks
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - App Dependencies
    let diContainer = AppDIContainer.shared
    let lifecycleManager = AppLifecycleManager(container: AppDIContainer.shared)
    
    // MARK: - SwiftData Container
    let container: ModelContainer
    
    // MARK: - Lifecycle Bootstrapping
    init() {
        do {
            let schema = Schema(versionedSchema: MerianSchemaV12.self)
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

    // MARK: - State Management
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("themeMode") private var themeMode: ThemeMode = .system

    // MARK: - Scene Hierarchy
    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    CameraRootView()
                } else {
                    OnboardingView()
                }
            }
            .preferredColorScheme(themeMode.colorScheme)
            .modelContainer(container)
            .injectAppDependencies(container: diContainer)
            .onAppear {
                diContainer.revenueCatManager.configure()
                applyTheme(themeMode) // Apply strictly on initial application foregrounding
            }
            .onChange(of: themeMode) { _, newTheme in
                applyTheme(newTheme) // Force dynamic UIWindow overrides across all views cleanly synchronously
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
        // MARK: - Scene Phases
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                lifecycleManager.handleBackgroundPhase()
            case .inactive:
                lifecycleManager.handleInactivePhase()
            case .active:
                lifecycleManager.handleActivePhase()
            @unknown default:
                break
            }
        }
    }
    
    // MARK: - Application Theming
    private func applyTheme(_ theme: ThemeMode) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        
        let style: UIUserInterfaceStyle
        switch theme {
        case .system: style = .unspecified
        case .light: style = .light
        case .dark: style = .dark
        }
        
        for window in windowScene.windows {
            window.overrideUserInterfaceStyle = style
        }
    }
}
