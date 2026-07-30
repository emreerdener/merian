import GoogleSignIn
import SwiftData
import SwiftUI

enum StartupStoreState: Equatable {
    case normal
    case recovered
    case safeMode
}

enum MerianOpenURLRoute: Equatable {
    case handledByGoogle
    case merianDeepLink
    case externalImageImport
    case supabaseAuthentication

    static func classify(_ url: URL, googleHandled: Bool) -> MerianOpenURLRoute {
        if googleHandled {
            return .handledByGoogle
        }
        if MerianDeepLinkRoute(url: url) != nil {
            return .merianDeepLink
        }
        if url.isFileURL {
            return .externalImageImport
        }
        return .supabaseAuthentication
    }
}

enum AppLaunchPresentationPolicy {
    static func shouldOpenExplore(
        hasCompletedOnboarding: Bool,
        opensExploreOnLaunch: Bool
    ) -> Bool {
        hasCompletedOnboarding && opensExploreOnLaunch
    }
}

private struct StartupStoreStateKey: EnvironmentKey {
    static let defaultValue: StartupStoreState = .normal
}

extension EnvironmentValues {
    var startupStoreState: StartupStoreState {
        get { self[StartupStoreStateKey.self] }
        set { self[StartupStoreStateKey.self] = newValue }
    }
}

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

enum UITestSeedCoordinator {
    private static let achievementDeletionRefreshArgument = "-seedAchievementDeletionRefreshFlow"
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
        guard arguments.contains("-seedAchievementDetailFlow") ||
                arguments.contains(achievementDeletionRefreshArgument) ||
                arguments.contains(queuedAudioHandoffArgument) else { return }

        let context = container.mainContext

        do {
            try context.delete(model: LocalScanRecord.self)
            try context.delete(model: ScanCollection.self)
            try context.delete(model: OfflineQueuedScan.self)
            try context.delete(model: ActiveOfflineQueuedScanGoalHint.self)
            try context.delete(model: PendingCloudDeletionTask.self)

            if arguments.contains("-seedAchievementDetailFlow") {
                for record in achievementDetailFlowRecords() {
                    context.insert(record)
                }
                OfflineQueueManager.shared.unsyncedItemsCount = 0
                MerianLog.general.debug("UITestSeedCoordinator seeded achievement detail flow records.")
            } else if arguments.contains(achievementDeletionRefreshArgument) {
                context.insert(achievementDeletionRefreshRecord())
                OfflineQueueManager.shared.unsyncedItemsCount = 0
                MerianLog.general.debug("UITestSeedCoordinator seeded achievement deletion refresh record.")
            } else if arguments.contains(queuedAudioHandoffArgument) {
                try prepareQueuedAudioHandoffMedia()
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

    private static func achievementDeletionRefreshRecord() -> LocalScanRecord {
        let calendar = Calendar(identifier: .gregorian)
        let dogDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 11, minute: 20)) ?? Date()

        return LocalScanRecord(
            id: "achievement_domestic_dog_refresh",
            speciesId: "dog_canis_lupus_familiaris",
            scientificName: "Canis lupus familiaris",
            commonName: "Domestic Dog",
            timestamp: dogDate,
            hazardType: "none",
            isInvasive: false,
            ecologyType: "domesticated",
            confidenceScore: 0.995,
            isLocallyArchived: true,
            taxonomyKingdom: "Animalia",
            locationName: "Home",
            confirmedSpeciesId: "dog_canis_lupus_familiaris_confirmed"
        )
    }

    private static func queuedAudioHandoffCapturedMediaJSON() -> String? {
        let items: [SerializedMediaItem] = [
            .audio(.documents(queuedAudioHandoffAudioFilename)),
            .image(.documents(queuedAudioHandoffImageFilename))
        ]
        guard let data = try? JSONEncoder().encode(items) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func prepareQueuedAudioHandoffMedia() throws {
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let audioURL = documentsURL.appendingPathComponent(
            queuedAudioHandoffAudioFilename,
            isDirectory: false
        )
        try queuedAudioHandoffWAVData().write(to: audioURL, options: .atomic)
    }

    private static func queuedAudioHandoffWAVData() -> Data {
        let sampleRate: UInt32 = 8_000
        let sampleCount = Int(sampleRate)
        let bytesPerSample: UInt16 = 2
        let audioByteCount = UInt32(sampleCount) * UInt32(bytesPerSample)

        var data = Data()
        func appendASCII(_ value: String) {
            data.append(contentsOf: value.utf8)
        }
        func appendUInt16LE(_ value: UInt16) {
            data.append(UInt8(truncatingIfNeeded: value))
            data.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func appendUInt32LE(_ value: UInt32) {
            data.append(UInt8(truncatingIfNeeded: value))
            data.append(UInt8(truncatingIfNeeded: value >> 8))
            data.append(UInt8(truncatingIfNeeded: value >> 16))
            data.append(UInt8(truncatingIfNeeded: value >> 24))
        }

        appendASCII("RIFF")
        appendUInt32LE(36 + audioByteCount)
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32LE(16)
        appendUInt16LE(1)
        appendUInt16LE(1)
        appendUInt32LE(sampleRate)
        appendUInt32LE(sampleRate * UInt32(bytesPerSample))
        appendUInt16LE(bytesPerSample)
        appendUInt16LE(16)
        appendASCII("data")
        appendUInt32LE(audioByteCount)

        for sampleIndex in 0..<sampleCount {
            let sample: Int16 = (sampleIndex / 10).isMultiple(of: 2) ? 4_000 : -4_000
            appendUInt16LE(UInt16(bitPattern: sample))
        }

        return data
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
    let diagnosticText: String?

    init(title: String, message: String, diagnosticText: String? = nil) {
        self.title = title
        self.message = message
        self.diagnosticText = diagnosticText
    }
}

struct StartupRecoveryTelemetryEvent {
    let outcome: String
    let reason: String
    let properties: [String: String]

    init(outcome: String, reason: String, properties: [String: String] = [:]) {
        self.outcome = outcome
        self.reason = reason
        self.properties = properties
    }
}

struct ModelContainerBootstrapOutcome {
    let container: ModelContainer?
    let startupStoreState: StartupStoreState
    let startupNotice: StartupRecoveryNotice?
    let telemetryEvent: StartupRecoveryTelemetryEvent?
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
            if let diagnosticText = notice.diagnosticText,
               Self.shouldShowDiagnostics {
                ShareLink(item: diagnosticText) {
                    Label("Share Diagnostics", systemImage: "square.and.arrow.up")
                        .font(.footnote.weight(.semibold))
                }
                .padding(.top, 4)
            }
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

    private static var shouldShowDiagnostics: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
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
    let startupStoreState: StartupStoreState
    let startupRecoveryNotice: StartupRecoveryNotice?
    let shouldOpenExploreOnFreshLaunch: Bool
    
    // MARK: - Lifecycle Bootstrapping
    @MainActor
    init() {
        let appSettings = AppDIContainer.shared.appSettings
        shouldOpenExploreOnFreshLaunch = AppLaunchPresentationPolicy.shouldOpenExplore(
            hasCompletedOnboarding: appSettings.hasCompletedOnboarding,
            opensExploreOnLaunch: appSettings.opensExploreOnLaunch
        )

        // Migrate old multiImageScanMode to the new isMultiCaptureEnabled key
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.legacyMultiImageScanMode) != nil {
            let oldVal = UserDefaults.standard.bool(forKey: UserDefaultsKeys.legacyMultiImageScanMode)
            UserDefaults.standard.set(oldVal, forKey: UserDefaultsKeys.isMultiCaptureEnabled)
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.legacyMultiImageScanMode)
        }

        let bootstrapOutcome = Self.bootstrapModelContainer()
        container = bootstrapOutcome.container
        startupStoreState = bootstrapOutcome.startupStoreState
        startupRecoveryNotice = Self.combinedStartupNotice(storeNotice: bootstrapOutcome.startupNotice)
        if let container {
            let mainContext = container.mainContext
            AppDIContainer.shared.scanRepository.configure(with: mainContext)
            SpeciesPreferredNameRepository.migrateLegacyPreferences(modelContext: mainContext)

            UITestSeedCoordinator.prepareIfNeeded(container: container)

            if LocalScanMediaRecoveryResolver.hasLegacyRecoveryIndex {
                let descriptor = FetchDescriptor<LocalScanRecord>()
                let records = (try? mainContext.fetch(descriptor)) ?? []
                let recoveryCount = LocalScanMediaRecoveryResolver
                    .registerRecoveryMappings(for: records)
                MerianLog.data.info(
                    "Startup media recovery registered \(recoveryCount, privacy: .public) legacy scan image mapping(s)."
                )
            }
        }
        
        // Keep app-hosted test sessions hermetic: no analytics startup, no disk-backed
        // production store, and no background sync noise racing the test containers.
        if !TestExecutionCoordinator.isRunningTests {
            FieldTripEventsAvailability.logRolloutState()

            // Initialize the app analytics facade after PostHog has been configured
            // by SupabaseManager, before startup recovery can emit its event.
            AppTelemetry.initialize()
            if let telemetryEvent = bootstrapOutcome.telemetryEvent {
                AppTelemetry.trackStartupStoreRecovery(
                    outcome: telemetryEvent.outcome,
                    reason: telemetryEvent.reason,
                    properties: telemetryEvent.properties
                )
            }
        }
    }

    private static func makePersistentContainerUnchecked<MigrationPlan: SchemaMigrationPlan>(
        migrationPlan: MigrationPlan.Type
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: TestExecutionCoordinator.isRunningTests
        )
        return try ModelContainer(for: schema, migrationPlan: migrationPlan, configurations: [config])
    }

    private static func makePersistentContainerUnchecked() throws -> ModelContainer {
        try makePersistentContainerUnchecked(migrationPlan: MerianMigrationPlan.self)
    }

    private static func makePersistentContainerUncheckedWithoutMigrationPlan() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: TestExecutionCoordinator.isRunningTests
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func makeInMemoryContainerUnchecked() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, migrationPlan: MerianMigrationPlan.self, configurations: [config])
    }

    static func makeContainerCatchingObjectiveCExceptions(
        _ buildContainer: @escaping () throws -> ModelContainer
    ) throws -> ModelContainer {
        var container: ModelContainer?
        var swiftError: Error?
        var exceptionError: NSError?

        _ = MerianCatchObjCException({
            do {
                container = try buildContainer()
            } catch {
                swiftError = error
            }
        }, &exceptionError)

        if let swiftError {
            throw swiftError
        }
        if let exceptionError {
            throw exceptionError
        }
        guard let container else {
            throw NSError(
                domain: "app.merian.model-container",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "ModelContainer creation returned no container."]
            )
        }
        return container
    }

    private static func makePersistentContainer<MigrationPlan: SchemaMigrationPlan>(
        migrationPlan: MigrationPlan.Type
    ) throws -> ModelContainer {
        try makeContainerCatchingObjectiveCExceptions {
            try makePersistentContainerUnchecked(migrationPlan: migrationPlan)
        }
    }

    private static func makePersistentContainer() throws -> ModelContainer {
        try makePersistentContainer(migrationPlan: MerianMigrationPlan.self)
    }

    private static func makePersistentContainerWithoutMigrationPlan() throws -> ModelContainer {
        try makeContainerCatchingObjectiveCExceptions {
            try makePersistentContainerUncheckedWithoutMigrationPlan()
        }
    }

    private static func recordPersistentContainerAttempt(
        named name: String,
        diagnostic: inout StartupStoreDiagnostic,
        _ buildContainer: () throws -> ModelContainer
    ) throws -> ModelContainer {
        do {
            let container = try buildContainer()
            diagnostic.recordAttempt(name: name, outcome: "success")
            return container
        } catch {
            diagnostic.recordAttempt(name: name, outcome: "failure", error: error)
            throw error
        }
    }

    private static func makePersistentContainer<MigrationPlan: SchemaMigrationPlan>(
        migrationPlan: MigrationPlan.Type,
        named name: String,
        diagnostic: inout StartupStoreDiagnostic
    ) throws -> ModelContainer {
        try recordPersistentContainerAttempt(named: name, diagnostic: &diagnostic) {
            try makePersistentContainer(migrationPlan: migrationPlan)
        }
    }

    private static func makePersistentContainerWithoutMigrationPlan(
        named name: String,
        diagnostic: inout StartupStoreDiagnostic
    ) throws -> ModelContainer {
        try recordPersistentContainerAttempt(named: name, diagnostic: &diagnostic) {
            try makePersistentContainerWithoutMigrationPlan()
        }
    }

    private static func makePersistentContainerRetryingChecksumRepresentative(
        after error: Error,
        diagnostic: inout StartupStoreDiagnostic
    ) throws -> ModelContainer {
        guard ModelStoreRecoveryCoordinator.isDuplicateVersionChecksumFailure(error) else {
            throw error
        }

        MerianLog.general.error(
            "ModelContainer migration plan hit duplicate version checksums; retrying with recent checksum-safe migration plans."
        )

        do {
            let recovered = try makePersistentContainerWithoutMigrationPlan(
                named: "checksum-current-store",
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened without a migration plan; store was already current."
            )
            return recovered
        } catch let currentStoreError {
            MerianLog.general.error(
                "ModelContainer current-store retry failed: \(currentStoreError.localizedDescription, privacy: .private)"
            )
        }

        do {
            let recovered = try makePersistentContainerForV48Source(diagnostic: &diagnostic)
            MerianLog.general.error(
                "ModelContainer opened with a recent V48 startup recovery plan."
            )
            return recovered
        } catch let recentV48Error {
            MerianLog.general.error(
                "ModelContainer recent V48 startup recovery retry failed: \(recentV48Error.localizedDescription, privacy: .private)"
            )
        }

        do {
            let recovered = try makePersistentContainer(
                migrationPlan: MerianRecentV47MigrationPlan.self,
                named: "checksum-recent-v47",
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened with the recent V47 checksum-safe migration plan."
            )
            return recovered
        } catch let recentV47Error {
            MerianLog.general.error(
                "ModelContainer recent V47 checksum-safe retry failed: \(recentV47Error.localizedDescription, privacy: .private)"
            )
        }

        do {
            let recovered = try makePersistentContainer(
                migrationPlan: MerianRecentV46MigrationPlan.self,
                named: "checksum-recent-v46",
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened with the recent V46 checksum-safe migration plan."
            )
            return recovered
        } catch let recentV46Error {
            MerianLog.general.error(
                "ModelContainer recent V46 checksum-safe retry failed: \(recentV46Error.localizedDescription, privacy: .private)"
            )
        }

        do {
            let recovered = try makePersistentContainer(
                migrationPlan: MerianRecentV45MigrationPlan.self,
                named: "checksum-recent-v45",
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened with the recent V45 checksum-safe migration plan."
            )
            return recovered
        } catch let recentV45Error {
            MerianLog.general.error(
                "ModelContainer recent V45 checksum-safe retry failed: \(recentV45Error.localizedDescription, privacy: .private)"
            )
        }

        do {
            let recovered = try makePersistentContainer(
                migrationPlan: MerianRecentV44MigrationPlan.self,
                named: "checksum-recent-v44",
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened with the recent V44 checksum-safe migration plan."
            )
            return recovered
        } catch let recentV44Error {
            MerianLog.general.error(
                "ModelContainer recent V44 checksum-safe retry failed: \(recentV44Error.localizedDescription, privacy: .private)"
            )
        }

        do {
            let recovered = try makePersistentContainer(
                migrationPlan: MerianRecentV43MigrationPlan.self,
                named: "checksum-recent-v43",
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened with the recent V43 checksum-safe migration plan."
            )
            return recovered
        } catch let recentV43Error {
            MerianLog.general.error(
                "ModelContainer recent V43 checksum-safe retry failed: \(recentV43Error.localizedDescription, privacy: .private)"
            )
        }

        do {
            let recovered = try makePersistentContainer(
                migrationPlan: MerianRecentV42MigrationPlan.self,
                named: "checksum-recent-v42",
                diagnostic: &diagnostic
            )
            MerianLog.general.error(
                "ModelContainer opened with the recent V42 checksum-safe migration plan."
            )
            return recovered
        } catch let recentV42Error {
            MerianLog.general.error(
                "ModelContainer recent V42 checksum-safe retry failed. Primary error: \(error.localizedDescription, privacy: .private) | Retry error: \(recentV42Error.localizedDescription, privacy: .private)"
            )
            throw error
        }
    }

    private static func makePersistentContainerForV48Source(
        diagnostic: inout StartupStoreDiagnostic
    ) throws -> ModelContainer {
        do {
            return try makePersistentContainer(
                migrationPlan: MerianRecentV48MigrationPlan.self,
                named: "recent-v48-known-good",
                diagnostic: &diagnostic
            )
        } catch let knownGoodV48Error {
            MerianLog.general.error(
                "ModelContainer known-good V48 startup recovery failed: \(knownGoodV48Error.localizedDescription, privacy: .private)"
            )
        }

        return try makePersistentContainer(
            migrationPlan: MerianOptionalQueueV48RecoveryPlan.self,
            named: "recent-v48-optional-queue",
            diagnostic: &diagnostic
        )
    }

    private static func makePersistentContainer(
        forStoreMigrationHint hint: ModelStoreRecoveryCoordinator.StoreMigrationHint,
        diagnostic: inout StartupStoreDiagnostic
    ) throws -> ModelContainer {
        switch hint {
        case .currentStore:
            return try makePersistentContainerWithoutMigrationPlan(
                named: "current-store",
                diagnostic: &diagnostic
            )
        case .recentSource(48):
            return try makePersistentContainerForV48Source(diagnostic: &diagnostic)
        case .recentSource(47):
            return try makePersistentContainer(
                migrationPlan: MerianRecentV47MigrationPlan.self,
                named: "recent-v47",
                diagnostic: &diagnostic
            )
        case .recentSource(46):
            return try makePersistentContainer(
                migrationPlan: MerianRecentV46MigrationPlan.self,
                named: "recent-v46",
                diagnostic: &diagnostic
            )
        case .recentSource(45):
            return try makePersistentContainer(
                migrationPlan: MerianRecentV45MigrationPlan.self,
                named: "recent-v45",
                diagnostic: &diagnostic
            )
        case .recentSource(44):
            return try makePersistentContainer(
                migrationPlan: MerianRecentV44MigrationPlan.self,
                named: "recent-v44",
                diagnostic: &diagnostic
            )
        case .recentSource(43):
            return try makePersistentContainer(
                migrationPlan: MerianRecentV43MigrationPlan.self,
                named: "recent-v43",
                diagnostic: &diagnostic
            )
        case .recentSource(42):
            return try makePersistentContainer(
                migrationPlan: MerianRecentV42MigrationPlan.self,
                named: "recent-v42",
                diagnostic: &diagnostic
            )
        case .recentSource:
            return try makePersistentContainer(
                migrationPlan: MerianMigrationPlan.self,
                named: "recent-fallback-full",
                diagnostic: &diagnostic
            )
        case .fullHistorical:
            return try makePersistentContainer(
                migrationPlan: MerianMigrationPlan.self,
                named: "full-historical",
                diagnostic: &diagnostic
            )
        }
    }

    private static func makePersistentContainerUsingStoreAwarePlan(
        decision: ModelStoreRecoveryCoordinator.StoreMigrationDecision,
        diagnostic: inout StartupStoreDiagnostic
    ) throws -> ModelContainer {
        let detectedSchema = decision.storedSchemaMajorVersion.map { "V\($0)" } ?? "unavailable"

        MerianLog.general.notice(
            "ModelContainer store-aware migration selection: hasStoreArtifacts=\(decision.hasStoreArtifacts, privacy: .public) storedSchema=\(detectedSchema, privacy: .public) strategy=\(decision.hint.description, privacy: .public)"
        )

        do {
            return try makePersistentContainer(forStoreMigrationHint: decision.hint, diagnostic: &diagnostic)
        } catch {
            return try makePersistentContainerRetryingChecksumRepresentative(after: error, diagnostic: &diagnostic)
        }
    }

    private static func makeInMemoryContainer() throws -> ModelContainer {
        try makeContainerCatchingObjectiveCExceptions {
            try makeInMemoryContainerUnchecked()
        }
    }

    private static func migrationSchemaVersionSummary() -> String {
        MerianMigrationPlan.schemas
            .map { "\($0.versionIdentifier.major)" }
            .joined(separator: ",")
    }

    private static func migrationStageVersionSummary() -> String {
        MerianMigrationPlan.stages
            .map { stage -> String in
                switch stage {
                case let .lightweight(fromVersion, toVersion):
                    return "\(fromVersion.versionIdentifier.major)>\(toVersion.versionIdentifier.major):L"
                case let .custom(fromVersion, toVersion, _, _):
                    return "\(fromVersion.versionIdentifier.major)>\(toVersion.versionIdentifier.major):C"
                @unknown default:
                    return "unknown"
                }
            }
            .joined(separator: ",")
    }

    private static func logModelContainerBootstrapDiagnostics() {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let sourceRevision = Bundle.main.object(forInfoDictionaryKey: "MERIAN_SOURCE_REVISION") as? String ?? "unavailable"
        let sourceFingerprint = Bundle.main.object(forInfoDictionaryKey: "MERIAN_SOURCE_FINGERPRINT") as? String ?? "unavailable"
        let sourceState = Bundle.main.object(forInfoDictionaryKey: "MERIAN_SOURCE_STATE") as? String ?? "unavailable"
        let currentSchema = CurrentSchema.versionIdentifier.major
        let schemas = migrationSchemaVersionSummary()
        let stages = migrationStageVersionSummary()

        MerianLog.general.notice(
            "ModelContainer bootstrap diagnostics: app=\(appVersion, privacy: .public)(\(buildNumber, privacy: .public)) source=\(sourceRevision, privacy: .public) sourceFingerprint=\(sourceFingerprint, privacy: .public) sourceState=\(sourceState, privacy: .public) currentSchema=V\(currentSchema, privacy: .public) migrationSchemas=[\(schemas, privacy: .public)] migrationStages=[\(stages, privacy: .public)]"
        )
    }

    private static func bootstrapModelContainer() -> ModelContainerBootstrapOutcome {
        logModelContainerBootstrapDiagnostics()
        let storeURL = ModelStoreRecoveryCoordinator.defaultStoreURL()
        let decision = ModelStoreRecoveryCoordinator.migrationDecision(
            at: storeURL,
            currentSchemaMajor: CurrentSchema.versionIdentifier.major
        )
        var diagnostic = ModelStoreRecoveryCoordinator.makeStartupDiagnostic(
            storeURL: storeURL,
            currentSchemaMajor: CurrentSchema.versionIdentifier.major,
            migrationSchemas: migrationSchemaVersionSummary(),
            migrationStages: migrationStageVersionSummary(),
            decision: decision
        )

        do {
            let container = try makePersistentContainerUsingStoreAwarePlan(
                decision: decision,
                diagnostic: &diagnostic
            )
            diagnostic.recordFinalOutcome("normal", reason: nil)
            ModelStoreRecoveryCoordinator.recordLatestStartupDiagnostic(diagnostic)
            return ModelContainerBootstrapOutcome(
                container: container,
                startupStoreState: .normal,
                startupNotice: nil,
                telemetryEvent: nil
            )
        } catch {
            MerianLog.general.error("CRITICAL: Failed to initialize ModelContainer. Error: \(error.localizedDescription)")

            if ModelStoreRecoveryCoordinator.shouldQuarantineStore(for: error, storeURL: storeURL) {
                do {
                    let quarantineDirectory = try ModelStoreRecoveryCoordinator.quarantineStoreArtifacts(
                        at: storeURL,
                        for: error
                    )
                    let recoveredContainer = try makePersistentContainerWithoutMigrationPlan(
                        named: "post-quarantine-current-store",
                        diagnostic: &diagnostic
                    )
                    diagnostic.recordFinalOutcome(
                        "recovered",
                        reason: "corruption_quarantined",
                        quarantineAttempted: true,
                        quarantinePerformed: true
                    )
                    ModelStoreRecoveryCoordinator.recordLatestStartupDiagnostic(diagnostic)
                    MerianLog.general.error(
                        "RECOVERY: Quarantined suspected-corrupt store artifacts to \(quarantineDirectory.lastPathComponent, privacy: .public) and recreated a fresh ModelContainer."
                    )
                    return ModelContainerBootstrapOutcome(
                        container: recoveredContainer,
                        startupStoreState: .recovered,
                        startupNotice: StartupRecoveryNotice(
                            title: "Library Repaired",
                            message: "Naturebook recovered from a corrupted local store and rebuilt the library safely.",
                            diagnosticText: ModelStoreRecoveryCoordinator.startupDiagnosticText(diagnostic)
                        ),
                        telemetryEvent: StartupRecoveryTelemetryEvent(
                            outcome: "recovered",
                            reason: "corruption_quarantined",
                            properties: diagnostic.telemetryProperties
                        )
                    )
                } catch let recoveryError {
                    MerianLog.general.fault(
                        "ModelContainer recovery failed after quarantine. Initial error: \(error.localizedDescription, privacy: .private) | Recovery error: \(recoveryError.localizedDescription, privacy: .private)"
                    )
                    diagnostic.recordAttempt(name: "post-quarantine-recovery", outcome: "failure", error: recoveryError)
                    return fallbackInMemoryBootstrap(
                        reason: "Naturebook started in safe mode because the local library could not be recovered. New work in this session is temporary until the app restarts with a healthy store.",
                        telemetryReason: "persistent_store_recovery_failed",
                        startupDiagnostic: diagnostic
                    )
                }
            }

            if ModelStoreRecoveryCoordinator.shouldRescueStoreAfterMigrationFailure(
                for: error,
                decision: decision,
                storeURL: storeURL
            ) {
                var rescuePerformed = false
                do {
                    let rescueDirectory = try ModelStoreRecoveryCoordinator.rescueStoreArtifactsAfterMigrationFailure(
                        at: storeURL,
                        for: error
                    )
                    rescuePerformed = true
                    let recoveredContainer = try makePersistentContainerWithoutMigrationPlan(
                        named: "post-migration-rescue-current-store",
                        diagnostic: &diagnostic
                    )
                    diagnostic.recordFinalOutcome(
                        "recovered",
                        reason: "legacy_store_rescued",
                        rescueAttempted: true,
                        rescuePerformed: true
                    )
                    ModelStoreRecoveryCoordinator.recordLatestStartupDiagnostic(diagnostic)
                    MerianLog.general.error(
                        "RECOVERY: Archived a legacy store that could not migrate to \(rescueDirectory.lastPathComponent, privacy: .public) and recreated a fresh ModelContainer."
                    )
                    return ModelContainerBootstrapOutcome(
                        container: recoveredContainer,
                        startupStoreState: .recovered,
                        startupNotice: StartupRecoveryNotice(
                            title: "Library Rebuilt",
                            message: "Naturebook archived an older local library that could not be upgraded and started with a fresh library. Cloud sync can restore saved scans where available.",
                            diagnosticText: ModelStoreRecoveryCoordinator.startupDiagnosticText(diagnostic)
                        ),
                        telemetryEvent: StartupRecoveryTelemetryEvent(
                            outcome: "recovered",
                            reason: "legacy_store_rescued",
                            properties: diagnostic.telemetryProperties
                        )
                    )
                } catch let rescueError {
                    MerianLog.general.fault(
                        "ModelContainer recovery failed after legacy migration rescue. Initial error: \(error.localizedDescription, privacy: .private) | Rescue error: \(rescueError.localizedDescription, privacy: .private)"
                    )
                    if !rescuePerformed {
                        diagnostic.recordAttempt(name: "migration-rescue-archive", outcome: "failure", error: rescueError)
                    }
                    diagnostic.recordFinalOutcome(
                        "safe_mode",
                        reason: "persistent_store_rescue_failed",
                        rescueAttempted: true,
                        rescuePerformed: rescuePerformed
                    )
                    return fallbackInMemoryBootstrap(
                        reason: "Naturebook started in safe mode because an older local library could not be archived and rebuilt. New work in this session is temporary until the app restarts with a healthy store.",
                        telemetryReason: "persistent_store_rescue_failed",
                        startupDiagnostic: diagnostic
                    )
                }
            }

            MerianLog.general.error("ModelContainer recovery skipped because the failure did not match a verified corruption signature.")
            let safeModeFallback = ModelStoreRecoveryCoordinator.safeModeFallback(for: error)
            return fallbackInMemoryBootstrap(
                reason: safeModeFallback.message,
                telemetryReason: safeModeFallback.telemetryReason,
                startupDiagnostic: diagnostic
            )
        }
    }

    static func fallbackInMemoryBootstrap(
        reason: String,
        telemetryReason: String = "persistent_store_unavailable",
        startupDiagnostic: StartupStoreDiagnostic? = nil,
        makeInMemoryContainer: () throws -> ModelContainer = makeInMemoryContainer
    ) -> ModelContainerBootstrapOutcome {
        var diagnostic = startupDiagnostic
        do {
            let container = try makeInMemoryContainer()
            diagnostic?.recordAttempt(name: "safe-mode-in-memory", outcome: "success")
            diagnostic?.recordFinalOutcome("safe_mode", reason: telemetryReason)
            if let diagnostic {
                ModelStoreRecoveryCoordinator.recordLatestStartupDiagnostic(diagnostic)
            }
            return ModelContainerBootstrapOutcome(
                container: container,
                startupStoreState: .safeMode,
                startupNotice: StartupRecoveryNotice(
                    title: "Safe Mode Enabled",
                    message: reason,
                    diagnosticText: diagnostic.flatMap(ModelStoreRecoveryCoordinator.startupDiagnosticText)
                ),
                telemetryEvent: StartupRecoveryTelemetryEvent(
                    outcome: "safe_mode",
                    reason: telemetryReason,
                    properties: diagnostic?.telemetryProperties ?? [:]
                )
            )
        } catch {
            MerianLog.general.fault("In-memory ModelContainer bootstrap failed: \(error.localizedDescription, privacy: .private)")
            diagnostic?.recordAttempt(name: "safe-mode-in-memory", outcome: "failure", error: error)
            diagnostic?.recordFinalOutcome(
                "blocked",
                reason: "persistent_and_memory_store_unavailable"
            )
            if let diagnostic {
                ModelStoreRecoveryCoordinator.recordLatestStartupDiagnostic(diagnostic)
            }
            return ModelContainerBootstrapOutcome(
                container: nil,
                startupStoreState: .safeMode,
                startupNotice: StartupRecoveryNotice(
                    title: "Startup Blocked",
                    message: "Naturebook could not open either the persistent library or the safe-mode in-memory store. Restart the app after freeing storage or reinstalling if the issue persists.",
                    diagnosticText: diagnostic.flatMap(ModelStoreRecoveryCoordinator.startupDiagnosticText)
                ),
                telemetryEvent: StartupRecoveryTelemetryEvent(
                    outcome: "blocked",
                    reason: "persistent_and_memory_store_unavailable",
                    properties: diagnostic?.telemetryProperties ?? [:]
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
            message: "\(storeNotice.message)\n\n\(configurationMessage)",
            diagnosticText: storeNotice.diagnosticText
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
                            CaptureWorkspaceView(
                                appSettings: appSettings,
                                opensExploreOnFreshLaunch: shouldOpenExploreOnFreshLaunch
                            )
                        } else {
                            OnboardingView()
                        }
                    }
                    .modelContainer(container)
                    .injectAppDependencies(container: diContainer)
                    .environment(\.startupStoreState, startupStoreState)
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
                            message: "Naturebook could not initialize its local library."
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
                switch MerianOpenURLRoute.classify(
                    url,
                    googleHandled: GIDSignIn.sharedInstance.handle(url)
                ) {
                case .handledByGoogle:
                    return
                case .merianDeepLink:
                    _ = handleMerianDeepLink(url)
                case .externalImageImport:
                    handleExternalImageImportURL(url)
                case .supabaseAuthentication:
                    Task {
                        do {
                            try await diContainer.supabaseManager.client.auth.session(from: url)
                        } catch {
                            MerianLog.auth.error("Supabase auth session URL handler failed: \(error, privacy: .private)")
                        }
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

    private func handleExternalImageImportURL(_ url: URL) {
        Task { @MainActor in
            do {
                let pendingImport = try await diContainer.externalImageImportStore.stageIncomingImage(at: url)
                AppTelemetry.trackExternalImageImport(outcome: "received")
                diContainer.appEventPublisher.send(
                    .externalImageImportAvailable(importId: pendingImport.id)
                )
            } catch {
                MerianLog.data.error(
                    "External image import could not be copied into the pending inbox: \(error, privacy: .private)"
                )
                let outcome = (error as? ExternalImageImportError) == .unsupportedURL
                    ? "failed_unsupported_type"
                    : "failed_inbox"
                AppTelemetry.trackExternalImageImport(outcome: outcome)
                await diContainer.externalImageImportStore.recordTerminalFailure()
                HapticManager.shared.triggerErrorThump()
                diContainer.appEventPublisher.send(.externalImageImportFailed)
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
        case .speciesDictionary(let speciesId):
            diContainer.appEventPublisher.send(
                .appDidEnterActivePhaseWithSpeciesDictionary(speciesId: speciesId)
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
