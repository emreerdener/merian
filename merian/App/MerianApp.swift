import CoreData
import GoogleSignIn
import SwiftData
import SwiftUI

// MARK: - Core Application Delegation
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        OfflineQueueManager.shared.backgroundCompletionHandler = completionHandler
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PushNotificationManager.shared.handleRemoteDeviceToken(deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            PushNotificationManager.shared.handleRemoteRegistrationFailure(error)
        }
    }
}

// MARK: - Store Recovery

enum ModelStoreRecoveryCoordinator {
    private static let sqliteCorruptionCodes: Set<Int> = [11, 26] // SQLITE_CORRUPT, SQLITE_NOTADB
    private static let corruptionPhrases = [
        "database disk image is malformed",
        "file is not a database",
        "file is encrypted or is not a database",
        "sqlite_corrupt",
        "sqlite_notadb",
        "malformed database schema",
        "corrupt"
    ]

    static func defaultStoreURL() -> URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    static func shouldAttemptRecovery(for error: Error) -> Bool {
        errorChain(from: error).contains { candidate in
            let nsError = candidate as NSError
            if nsError.domain == NSSQLiteErrorDomain, sqliteCorruptionCodes.contains(nsError.code) {
                return true
            }
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadCorruptFileError {
                return true
            }

            let normalizedText = [
                nsError.localizedDescription,
                nsError.userInfo[NSDebugDescriptionErrorKey] as? String,
                nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: "\n")

            return corruptionPhrases.contains { normalizedText.contains($0) }
        }
    }

    @discardableResult
    static func quarantineStoreArtifacts(at storeURL: URL, fileManager: FileManager = .default) throws -> URL {
        let artifacts = storeArtifacts(for: storeURL, fileManager: fileManager)
        guard !artifacts.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }

        let quarantineRoot = storeURL.deletingLastPathComponent().appending(path: "store-quarantine", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: quarantineRoot, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let quarantineDirectory = quarantineRoot.appending(path: "\(timestamp)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: quarantineDirectory, withIntermediateDirectories: false)

        for artifact in artifacts {
            let destination = quarantineDirectory.appending(path: artifact.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: artifact, to: destination)
        }

        return quarantineDirectory
    }

    private static func storeArtifacts(for storeURL: URL, fileManager: FileManager) -> [URL] {
        let candidates = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private static func errorChain(from rootError: Error) -> [Error] {
        var collected: [Error] = []
        var stack: [Error] = [rootError]

        while let next = stack.popLast() {
            collected.append(next)
            let nsError = next as NSError

            if let nestedError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                stack.append(nestedError)
            }
            if let nestedErrors = nsError.userInfo[NSDetailedErrorsKey] as? [NSError] {
                stack.append(contentsOf: nestedErrors)
            }
        }

        return collected
    }
}

private enum UITestSeedCoordinator {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["UITesting"] == "true"
    }

    @MainActor
    static func prepareIfNeeded(container: ModelContainer) {
        guard isEnabled else { return }
        guard ProcessInfo.processInfo.arguments.contains("-seedAchievementDetailFlow") else { return }

        let context = container.mainContext

        do {
            try context.delete(model: LocalScanRecord.self)
            try context.delete(model: ScanCollection.self)
            try context.delete(model: OfflineQueuedScan.self)
            try context.delete(model: PendingCloudDeletionTask.self)

            for record in achievementDetailFlowRecords() {
                context.insert(record)
            }

            try context.save()

            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.hasUnseenScan)
            MerianLog.general.debug("UITestSeedCoordinator seeded achievement detail flow records.")
        } catch {
            MerianLog.general.error("UITestSeedCoordinator failed to seed data: \(error.localizedDescription, privacy: .private)")
        }
    }

    private static func achievementDetailFlowRecords() -> [LocalScanRecord] {
        let calendar = Calendar(identifier: .gregorian)

        let latestFungiDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 28, hour: 10, minute: 15)) ?? Date()
        let duplicateFungiDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 27, hour: 8, minute: 5)) ?? latestFungiDate.addingTimeInterval(-86_400)
        let secondFungiDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 26, hour: 9, minute: 45)) ?? latestFungiDate.addingTimeInterval(-172_800)

        return [
            LocalScanRecord(
                id: "achievement_fungi_latest",
                speciesId: "fungi_amanita_ai",
                scientificName: "Amanita muscaria",
                commonName: "Fly Agaric",
                timestamp: latestFungiDate,
                hazardType: "none",
                isInvasive: false,
                ecologyType: "forest",
                confidenceScore: 0.992,
                isLocallyArchived: true,
                taxonomyKingdom: "fungi",
                locationName: "North Woods",
                confirmedSpeciesId: "fungi_amanita_confirmed"
            ),
            LocalScanRecord(
                id: "achievement_fungi_duplicate",
                speciesId: "fungi_amanita_alternate",
                scientificName: "Amanita cf. muscaria",
                commonName: "Fly Agaric",
                timestamp: duplicateFungiDate,
                hazardType: "none",
                isInvasive: false,
                ecologyType: "forest",
                confidenceScore: 0.981,
                isLocallyArchived: true,
                taxonomyKingdom: "fungi",
                locationName: "North Woods",
                userIdentificationOverride: "Amanita muscaria",
                confirmedSpeciesId: "fungi_amanita_confirmed"
            ),
            LocalScanRecord(
                id: "achievement_fungi_second",
                speciesId: "fungi_boletus",
                scientificName: "Boletus edulis",
                commonName: "Porcini",
                timestamp: secondFungiDate,
                hazardType: "none",
                isInvasive: false,
                ecologyType: "forest",
                confidenceScore: 0.989,
                isLocallyArchived: true,
                taxonomyKingdom: "fungi",
                locationName: "Creek Trail",
                confirmedSpeciesId: "fungi_boletus"
            )
        ]
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
    @MainActor
    init() {
        // Migrate old multiImageScanMode to the new isMultiCaptureEnabled key
        if UserDefaults.standard.object(forKey: "multiImageScanMode") != nil {
            let oldVal = UserDefaults.standard.bool(forKey: "multiImageScanMode")
            UserDefaults.standard.set(oldVal, forKey: "isMultiCaptureEnabled")
            UserDefaults.standard.removeObject(forKey: "multiImageScanMode")
        }

        do {
            container = try Self.makePersistentContainer()
            AppDIContainer.shared.scanRepository.configure(with: container.mainContext)
        } catch {
            MerianLog.general.error("CRITICAL: Failed to initialize ModelContainer. Error: \(error.localizedDescription)")

            guard ModelStoreRecoveryCoordinator.shouldAttemptRecovery(for: error) else {
                fatalError("Could not initialize ModelContainer safely. Recovery was skipped because the failure did not match a verified corruption signature. Error: \(error)")
            }

            do {
                let quarantineDirectory = try ModelStoreRecoveryCoordinator.quarantineStoreArtifacts(
                    at: ModelStoreRecoveryCoordinator.defaultStoreURL()
                )
                container = try Self.makePersistentContainer()
                AppDIContainer.shared.scanRepository.configure(with: container.mainContext)
                MerianLog.general.error(
                    "RECOVERY: Quarantined suspected-corrupt store artifacts to \(quarantineDirectory.lastPathComponent, privacy: .public) and recreated a fresh ModelContainer."
                )
            } catch let recoveryError {
                fatalError("Could not recover ModelContainer after quarantining the suspected corrupted store. Initial error: \(error), Recovery error: \(recoveryError)")
            }
        }

        UITestSeedCoordinator.prepareIfNeeded(container: container)
        
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

    private static func makePersistentContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: UITestSeedCoordinator.isEnabled
        )
        return try ModelContainer(for: schema, migrationPlan: MerianMigrationPlan.self, configurations: [config])
    }

    // MARK: - Scene Hierarchy
    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    CaptureWorkspaceView()
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
