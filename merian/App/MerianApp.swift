import GoogleSignIn
import SwiftData
import SwiftUI

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
        // Migrate old multiImageScanMode to the new isMultiCaptureEnabled key
        if UserDefaults.standard.object(forKey: "multiImageScanMode") != nil {
            let oldVal = UserDefaults.standard.bool(forKey: "multiImageScanMode")
            UserDefaults.standard.set(oldVal, forKey: "isMultiCaptureEnabled")
            UserDefaults.standard.removeObject(forKey: "multiImageScanMode")
        }

        do {
            let schema = Schema(versionedSchema: CurrentSchema.self)
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, migrationPlan: MerianMigrationPlan.self, configurations: [config])
            AppDIContainer.shared.scanRepository.configure(with: container.mainContext)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        
        // Initialize telemetry synchronously — just stores config, safe on main thread.
        // PostHog is deferred via Task.detached to avoid blocking init(). Since PostHogManager
        // is not @MainActor, configure() runs on the background thread pool as intended.
        AppTelemetry.initialize()
        Task.detached(priority: .background) {
            PostHogManager.shared.configure()
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
            .modelContainer(container)
            .injectAppDependencies(container: diContainer)
            .onAppear {
                // Bypass SwiftUI .preferredColorScheme(nil) modal inheritance bugs by pushing to UIWindow
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    for window in windowScene.windows {
                        window.overrideUserInterfaceStyle = themeMode.userInterfaceStyle
                    }
                }
            }
            .onChange(of: themeMode) { _, newTheme in
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    for window in windowScene.windows {
                        window.overrideUserInterfaceStyle = newTheme.userInterfaceStyle
                    }
                }
            }
            .onOpenURL { url in
                if GIDSignIn.sharedInstance.handle(url) {
                    return
                }
                Task {
                    do {
                        try await diContainer.supabaseManager.client.auth.session(from: url)
                    } catch {
                        MerianLog.auth.error("Supabase auth session URL handler failed: \(error, privacy: .private)")
                    }
                }
            }
        }
        // MARK: - Scene Phases
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                lifecycleManager.handleBackgroundPhase()
            case .inactive:
                // Only dismiss modals and pause hardware when transitioning out of the foreground.
                // Prevents wiping deep-link state (like open push notifications) when returning from the background.
                if oldPhase == .active {
                    lifecycleManager.handleInactivePhase()
                }
            case .active:
                lifecycleManager.handleActivePhase()
            @unknown default:
                break
            }
        }
    }
    
}
