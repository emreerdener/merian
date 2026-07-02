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
    private static let unknownModelVersionErrorCode = 134504
    private static let corruptionPhrases = [
        "database disk image is malformed",
        "file is not a database",
        "file is encrypted or is not a database",
        "sqlite_corrupt",
        "sqlite_notadb",
        "malformed database schema",
        "corrupt",
        "cannot use staged migration with an unknown model version",
        "unknown model version"
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
            if nsError.domain == NSCocoaErrorDomain, nsError.code == unknownModelVersionErrorCode {
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

    static func hasStoreArtifacts(at storeURL: URL, fileManager: FileManager = .default) -> Bool {
        !storeArtifacts(for: storeURL, fileManager: fileManager).isEmpty
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

enum UITestSeedCoordinator {
    private static let queuedAudioHandoffArgument = "-seedQueuedAudioHandoffFlow"
    private static let queuedAudioHandoffScanId = "ui_test_queued_audio_handoff"
    private static let queuedAudioHandoffAudioFilename = "ui_test_queued_audio_handoff.wav"
    private static let queuedAudioHandoffImageFilename = "ui_test_queued_audio_handoff.webp"
    @MainActor private static var triggeredQueuedAudioHandoffs: Set<String> = []

    static var isEnabled: Bool {
        TestExecutionCoordinator.isRunningUITests
    }

    @MainActor
    static func prepareIfNeeded(container: ModelContainer) {
        guard isEnabled else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-seedAchievementDetailFlow") || arguments.contains(queuedAudioHandoffArgument) else { return }

        let context = container.mainContext

        do {
            try context.delete(model: LocalScanRecord.self)
            try context.delete(model: ScanCollection.self)
            try context.delete(model: OfflineQueuedScan.self)
            try context.delete(model: PendingCloudDeletionTask.self)

            if arguments.contains("-seedAchievementDetailFlow") {
                for record in achievementDetailFlowRecords() {
                    context.insert(record)
                }
                OfflineQueueManager.shared.unsyncedItemsCount = 0
                MerianLog.general.debug("UITestSeedCoordinator seeded achievement detail flow records.")
            } else if arguments.contains(queuedAudioHandoffArgument) {
                context.insert(queuedAudioHandoffScan())
                OfflineQueueManager.shared.unsyncedItemsCount = 1
                triggeredQueuedAudioHandoffs.removeAll(keepingCapacity: false)
                MerianLog.general.debug("UITestSeedCoordinator seeded queued audio handoff flow.")
            }

            try context.save()

            AppSettings.shared.hasUnseenScan = false
        } catch {
            MerianLog.general.error("UITestSeedCoordinator failed to seed data: \(error.localizedDescription, privacy: .private)")
        }
    }

    @MainActor
    static func triggerQueuedAudioHandoffIfNeeded(scanId: String, container: ModelContainer) {
        let arguments = ProcessInfo.processInfo.arguments
        guard isEnabled,
              arguments.contains(queuedAudioHandoffArgument),
              scanId == queuedAudioHandoffScanId,
              !triggeredQueuedAudioHandoffs.contains(scanId) else { return }

        triggeredQueuedAudioHandoffs.insert(scanId)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)

            let context = container.mainContext
            var descriptor = FetchDescriptor<OfflineQueuedScan>(
                predicate: #Predicate { $0.id == scanId }
            )
            descriptor.fetchLimit = 1

            guard let queuedScan = try? context.fetch(descriptor).first else { return }

            context.insert(queuedAudioHandoffCompletedRecord())
            context.delete(queuedScan)

            do {
                try context.save()
                OfflineQueueManager.shared.unsyncedItemsCount = 0
                ScanLibraryEvents.postLibraryDidUpdate()
                MerianLog.general.debug("UITestSeedCoordinator completed queued audio handoff flow.")
            } catch {
                MerianLog.general.error("UITestSeedCoordinator failed completing queued audio handoff flow: \(error.localizedDescription, privacy: .private)")
            }
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

    private static func queuedAudioHandoffCapturedMediaJSON() -> String? {
        let items: [SerializedMediaItem] = [
            .audio(.documents(queuedAudioHandoffAudioFilename)),
            .image(.documents(queuedAudioHandoffImageFilename))
        ]
        guard let data = try? JSONEncoder().encode(items) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func queuedAudioHandoffScan() -> OfflineQueuedScan {
        OfflineQueuedScan(
            id: queuedAudioHandoffScanId,
            timestamp: Date(timeIntervalSince1970: 1_777_376_400),
            capturedMediaJSON: queuedAudioHandoffCapturedMediaJSON(),
            coverImagePath: queuedAudioHandoffImageFilename,
            weatherCondition: "overcast",
            weatherTemperatureF: 68,
            locationName: "UITest Queue",
            scanState: .pending
        )
    }

    private static func queuedAudioHandoffCompletedRecord() -> LocalScanRecord {
        LocalScanRecord(
            id: queuedAudioHandoffScanId,
            speciesId: "ui_test_cardinal",
            scientificName: "Cardinalis cardinalis",
            commonName: "Northern Cardinal",
            timestamp: Date(timeIntervalSince1970: 1_777_376_400),
            capturedMediaJSON: queuedAudioHandoffCapturedMediaJSON(),
            coverImagePath: queuedAudioHandoffImageFilename,
            hazardType: "none",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "woodland",
            wikipediaUrl: "https://example.com/cardinal",
            wikipediaOverview: "Seeded UI test overview.",
            referenceImageUrl: "https://example.com/cardinal.jpg",
            confidenceScore: 0.97,
            locationName: "UITest Queue",
            weatherCondition: "overcast",
            weatherTemperatureF: 68,
            aiReasoning: "Seeded UI test reasoning.",
            habitatDescription: "Seeded UI test habitat.",
            gbifTaxonKey: 2492488,
            hasBeenViewed: true
        )
    }
}

enum TestExecutionCoordinator {
    static var isRunningUITests: Bool {
        ProcessInfo.processInfo.environment["UITesting"] == "true"
    }

    static var isRunningTests: Bool {
        if isRunningUITests {
            return true
        }

        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }

        return NSClassFromString("XCTestCase") != nil
    }
}

struct StartupRecoveryNotice {
    let title: String
    let message: String
}

struct ModelContainerBootstrapOutcome {
    let container: ModelContainer?
    let startupNotice: StartupRecoveryNotice?
}

struct StartupRecoveryNoticeView: View {
    let notice: StartupRecoveryNotice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(notice.title)
                .font(.subheadline.weight(.semibold))
            Text(notice.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

// MARK: - Main Execution Point
@main
struct MerianApp: App {
    // MARK: - Lifecycle Hooks
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var didRunInitialActivePhase = false
    
    // MARK: - App Dependencies
    let diContainer = AppDIContainer.shared
    let lifecycleManager = AppLifecycleManager(container: AppDIContainer.shared)
    
    // MARK: - SwiftData Container
    let container: ModelContainer?
    let startupRecoveryNotice: StartupRecoveryNotice?
    
    // MARK: - Lifecycle Bootstrapping
    @MainActor
    init() {
        // Migrate old multiImageScanMode to the new isMultiCaptureEnabled key
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.legacyMultiImageScanMode) != nil {
            let oldVal = UserDefaults.standard.bool(forKey: UserDefaultsKeys.legacyMultiImageScanMode)
            UserDefaults.standard.set(oldVal, forKey: UserDefaultsKeys.isMultiCaptureEnabled)
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.legacyMultiImageScanMode)
        }

        let bootstrapOutcome = Self.bootstrapModelContainer()
        container = bootstrapOutcome.container
        startupRecoveryNotice = Self.combinedStartupNotice(storeNotice: bootstrapOutcome.startupNotice)
        if let container {
            let mainContext = container.mainContext
            AppDIContainer.shared.scanRepository.configure(with: mainContext)
            SpeciesPreferredNameRepository.migrateLegacyPreferences(modelContext: mainContext)

            UITestSeedCoordinator.prepareIfNeeded(container: container)
        }
        
        // Keep app-hosted test sessions hermetic: no analytics startup, no disk-backed
        // production store, and no background sync noise racing the test containers.
        if !TestExecutionCoordinator.isRunningTests {
            // Initialize TelemetryDeck synchronously — this just stores config and is safe
            // on the main thread. PostHog is configured by SupabaseManager before auth
            // events can identify the restored session.
            AppTelemetry.initialize()
        }
    }

    private static func makePersistentContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: TestExecutionCoordinator.isRunningTests
        )
        return try ModelContainer(for: schema, migrationPlan: MerianMigrationPlan.self, configurations: [config])
    }

    private static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, migrationPlan: MerianMigrationPlan.self, configurations: [config])
    }

    private static func bootstrapModelContainer() -> ModelContainerBootstrapOutcome {
        do {
            return ModelContainerBootstrapOutcome(
                container: try makePersistentContainer(),
                startupNotice: nil
            )
        } catch {
            MerianLog.general.error("CRITICAL: Failed to initialize ModelContainer. Error: \(error.localizedDescription)")

            let storeURL = ModelStoreRecoveryCoordinator.defaultStoreURL()
            let shouldAttemptRecovery = ModelStoreRecoveryCoordinator.shouldAttemptRecovery(for: error)
                || ModelStoreRecoveryCoordinator.hasStoreArtifacts(at: storeURL)

            if shouldAttemptRecovery {
                do {
                    let quarantineDirectory = try ModelStoreRecoveryCoordinator.quarantineStoreArtifacts(
                        at: storeURL
                    )
                    let recoveredContainer = try makePersistentContainer()
                    MerianLog.general.error(
                        "RECOVERY: Quarantined suspected-corrupt store artifacts to \(quarantineDirectory.lastPathComponent, privacy: .public) and recreated a fresh ModelContainer."
                    )
                    return ModelContainerBootstrapOutcome(
                        container: recoveredContainer,
                        startupNotice: StartupRecoveryNotice(
                            title: "Library Repaired",
                            message: "Merian recovered from a corrupted local store and rebuilt the library safely."
                        )
                    )
                } catch let recoveryError {
                    MerianLog.general.fault(
                        "ModelContainer recovery failed after quarantine. Initial error: \(error.localizedDescription, privacy: .private) | Recovery error: \(recoveryError.localizedDescription, privacy: .private)"
                    )
                    return fallbackInMemoryBootstrap(
                        reason: "Merian started in safe mode because the local library could not be recovered. New work in this session is temporary until the app restarts with a healthy store."
                    )
                }
            }

            MerianLog.general.error("ModelContainer recovery skipped because the failure did not match a verified corruption signature.")
            return fallbackInMemoryBootstrap(
                reason: "Merian started in safe mode after the persistent store failed to open. The app remains usable, but local changes in this session are temporary."
            )
        }
    }

    private static func fallbackInMemoryBootstrap(reason: String) -> ModelContainerBootstrapOutcome {
        do {
            return ModelContainerBootstrapOutcome(
                container: try makeInMemoryContainer(),
                startupNotice: StartupRecoveryNotice(
                    title: "Safe Mode Enabled",
                    message: reason
                )
            )
        } catch {
            MerianLog.general.fault("In-memory ModelContainer bootstrap failed: \(error.localizedDescription, privacy: .private)")
            return ModelContainerBootstrapOutcome(
                container: nil,
                startupNotice: StartupRecoveryNotice(
                    title: "Startup Blocked",
                    message: "Merian could not open either the persistent library or the safe-mode in-memory store. Restart the app after freeing storage or reinstalling if the issue persists."
                )
            )
        }
    }

    private static func combinedStartupNotice(storeNotice: StartupRecoveryNotice?) -> StartupRecoveryNotice? {
        let configurationIssues = MerianEnvironment.configurationIssues
        guard !configurationIssues.isEmpty else { return storeNotice }

        let configurationMessage = "Configuration warnings: " + configurationIssues.map(\.description).joined(separator: " ")
        guard let storeNotice else {
            return StartupRecoveryNotice(
                title: "Configuration Warning",
                message: configurationMessage
            )
        }

        return StartupRecoveryNotice(
            title: storeNotice.title,
            message: "\(storeNotice.message)\n\n\(configurationMessage)"
        )
    }

    // MARK: - Scene Hierarchy
    var body: some Scene {
        WindowGroup {
            let appSettings = diContainer.appSettings
            Group {
                if let container {
                    Group {
                        if appSettings.hasCompletedOnboarding {
                            CaptureWorkspaceView(appSettings: appSettings)
                        } else {
                            OnboardingView()
                        }
                    }
                    .modelContainer(container)
                    .injectAppDependencies(container: diContainer)
                    .overlay(alignment: .top) {
                        if let startupRecoveryNotice {
                            StartupRecoveryNoticeView(notice: startupRecoveryNotice)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                        }
                    }
                } else {
                    StartupRecoveryNoticeView(
                        notice: startupRecoveryNotice ?? StartupRecoveryNotice(
                            title: "Startup Blocked",
                            message: "Merian could not initialize its local library."
                        )
                    )
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Color(.systemBackground))
                }
            }
            .onAppear {
                applyTheme(appSettings.themeMode)
                guard !TestExecutionCoordinator.isRunningTests,
                      !didRunInitialActivePhase else {
                    return
                }
                didRunInitialActivePhase = true
                lifecycleManager.handleActivePhase()
            }
            .onChange(of: appSettings.themeMode) { _, newTheme in
                applyTheme(newTheme)
            }
            .onOpenURL { url in
                if GIDSignIn.sharedInstance.handle(url) {
                    return
                }
                if handleMerianDeepLink(url) {
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
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                _ = handleMerianDeepLink(url)
            }
        }
        // MARK: - Scene Phases
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard !TestExecutionCoordinator.isRunningTests else { return }

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

    private func applyTheme(_ themeMode: ThemeMode) {
        // Bypass SwiftUI .preferredColorScheme(nil) modal inheritance bugs by pushing to UIWindow.
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = themeMode.userInterfaceStyle
            }
        }
    }

    private func handleMerianDeepLink(_ url: URL) -> Bool {
        guard let route = MerianDeepLinkRoute(url: url) else {
            return false
        }

        switch route {
        case .explorePost(let postId):
            diContainer.appEventPublisher.send(
                .appDidEnterActivePhaseWithExplorePost(
                    postId: postId,
                    targetCommentId: nil,
                    targetReplyParentCommentId: nil
                )
            )
        case .scan(let scanId):
            diContainer.appEventPublisher.send(
                .appDidEnterActivePhaseWithScan(scanId: scanId)
            )
        case .scansLibrary:
            diContainer.appEventPublisher.send(.requestOpenScansLibraryIntent)
        }
        return true
    }
}
