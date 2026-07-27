import Foundation
@testable import Merian
import SwiftData
import SwiftUI
import Testing

@MainActor
struct AppDIContainerTests {
    private func makeSpeciesPreferenceContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: UserSpeciesPreference.self, configurations: configuration)
        return ModelContext(container)
    }

    private func fetchSpeciesPreference(
        for scientificName: String,
        modelContext: ModelContext
    ) throws -> UserSpeciesPreference? {
        let targetScientificName = scientificName
        var descriptor = FetchDescriptor<UserSpeciesPreference>(
            predicate: #Predicate<UserSpeciesPreference> { $0.scientificName == targetScientificName }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    @Test func testSharedInstanceUnification() {
        let sharedContainerA = AppDIContainer.shared
        let sharedContainerB = AppDIContainer.shared
        
        // Because these contain critical heavy references (InferenceEngine, HardwareOrchestrator)
        // fetching shared across the app must mathematically return the exact same memory pointer structure.
        let isIdentical = sharedContainerA === sharedContainerB
        #expect(isIdentical == true, "AppDIContainer broke singleton rules. Multiple instantiations found.")
    }
    
    @Test func testMockPreviewInitialization() {
        let previewA = AppDIContainer.preview
        let previewB = AppDIContainer.preview
        
        // Mock init creates independent containers manually each time to prevent preview artifacts from permanently locking memory
        let isIdentical = previewA === previewB
        #expect(isIdentical == false, "AppDIContainer.preview shouldn't leak singletons to parallel SwiftUI macro previews")
        
        // Assert it constructs valid structural bindings
        #expect(previewA.hardwareOrchestrator === HardwareOrchestrator.shared)
    }

    @Test func testAppSettingsOwnsTransientUIFlags() {
        let suiteName = "merian.tests.app-settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults, observeExternalChanges: false)
        #expect(settings.hasUnseenScan == false)
        #expect(settings.hasPromptedForNotificationsPostIdent == false)
        #expect(settings.hasSeenExploreOnboarding == false)
        #expect(settings.hasUnseenExplorePost == false)
        #expect(settings.lastSeenExplorePostSharedAt.isEmpty)
        #expect(settings.suppressInferenceBanners == false)

        settings.hasUnseenScan = true
        settings.hasPromptedForNotificationsPostIdent = true
        settings.hasSeenExploreOnboarding = true
        settings.hasUnseenExplorePost = true
        settings.lastSeenExplorePostSharedAt = "2026-05-09T12:34:56Z"
        settings.suppressInferenceBanners = true

        #expect(defaults.bool(forKey: UserDefaultsKeys.hasUnseenScan))
        #expect(defaults.bool(forKey: UserDefaultsKeys.hasPromptedForNotificationsPostIdent))
        #expect(defaults.bool(forKey: UserDefaultsKeys.hasSeenExploreOnboarding))
        #expect(defaults.bool(forKey: UserDefaultsKeys.hasUnseenExplorePost))
        #expect(defaults.string(forKey: UserDefaultsKeys.lastSeenExplorePostSharedAt) == "2026-05-09T12:34:56Z")
        #expect(defaults.bool(forKey: UserDefaultsKeys.suppressInferenceBanners))

        defaults.set(false, forKey: UserDefaultsKeys.hasUnseenScan)
        defaults.set(false, forKey: UserDefaultsKeys.suppressInferenceBanners)
        settings.refreshFromDefaults()

        #expect(settings.hasUnseenScan == false)
        #expect(settings.suppressInferenceBanners == false)
    }

    @Test func testAchievementNotificationsDefaultOnAndRespectExplicitOff() {
        let suiteName = "merian.tests.achievement-notification-defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults, observeExternalChanges: false)
        #expect(settings.isAchievementNotificationsEnabled == true)

        defaults.set(false, forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)
        settings.refreshFromDefaults()

        #expect(settings.isAchievementNotificationsEnabled == false)
    }

    @Test func testOpenExploreOnLaunchDefaultsOffPersistsAndReloads() {
        let suiteName = "merian.tests.open-explore-on-launch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults, observeExternalChanges: false)
        #expect(settings.opensExploreOnLaunch == false)

        settings.opensExploreOnLaunch = true
        #expect(defaults.bool(forKey: UserDefaultsKeys.opensExploreOnLaunch))

        let restored = AppSettings(userDefaults: defaults, observeExternalChanges: false)
        #expect(restored.opensExploreOnLaunch)

        defaults.set(false, forKey: UserDefaultsKeys.opensExploreOnLaunch)
        restored.refreshFromDefaults()
        #expect(restored.opensExploreOnLaunch == false)
    }

    @Test func testExploreLaunchPresentationRequiresOnboardingAndOptIn() {
        #expect(!AppLaunchPresentationPolicy.shouldOpenExplore(
            hasCompletedOnboarding: false,
            opensExploreOnLaunch: true
        ))
        #expect(!AppLaunchPresentationPolicy.shouldOpenExplore(
            hasCompletedOnboarding: true,
            opensExploreOnLaunch: false
        ))
        #expect(AppLaunchPresentationPolicy.shouldOpenExplore(
            hasCompletedOnboarding: true,
            opensExploreOnLaunch: true
        ))
    }

    @Test func testCaptureGoalProgressDefaultsOnAndPersistsExplicitOff() {
        let suiteName = "merian.tests.capture-goal-progress.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults, observeExternalChanges: false)
        #expect(settings.showsCaptureGoalProgress)

        settings.showsCaptureGoalProgress = false
        #expect(!defaults.bool(forKey: UserDefaultsKeys.showsCaptureGoalProgress))

        let restored = AppSettings(userDefaults: defaults, observeExternalChanges: false)
        #expect(!restored.showsCaptureGoalProgress)
    }

    @Test func testExploreNotificationDefaultsStartOn() {
        let suiteName = "merian.tests.explore-notification-defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults, observeExternalChanges: false)

        #expect(settings.isExploreNotificationsEnabled == true)
        #expect(settings.isExploreCommentMentionNotificationsEnabled == true)
    }

    @Test func testSpeciesPreferredNameStoreKeepsPreferenceScopedBySpecies() {
        let suiteName = "merian.tests.species-preferred-name.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SpeciesPreferredNameStore.setPreferredName(
            "Post Oak",
            for: "Quercus stellata",
            userDefaults: defaults
        )

        #expect(
            SpeciesPreferredNameStore.preferredName(
                for: "Quercus stellata",
                userDefaults: defaults
            ) == "Post Oak"
        )
        #expect(
            SpeciesPreferredNameStore.preferredName(
                for: "Quercus alba",
                userDefaults: defaults
            ) == nil
        )

        SpeciesPreferredNameStore.setPreferredName(
            "   ",
            for: "Quercus stellata",
            userDefaults: defaults
        )
        #expect(
            SpeciesPreferredNameStore.preferredName(
                for: "Quercus stellata",
                userDefaults: defaults
            ) == nil
        )
    }

    @Test func testSpeciesPreferredNameStoreClearAllDoesNotTouchOtherDefaults() {
        let suiteName = "merian.tests.species-preferred-name-clear.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SpeciesPreferredNameStore.setPreferredName("Bur Oak", for: "Quercus macrocarpa", userDefaults: defaults)
        defaults.set("keep-me", forKey: UserDefaultsKeys.sharedExplorePostIdPrefix + "scan-id")

        SpeciesPreferredNameStore.clearAll(userDefaults: defaults)

        #expect(SpeciesPreferredNameStore.preferredName(for: "Quercus macrocarpa", userDefaults: defaults) == nil)
        #expect(defaults.string(forKey: UserDefaultsKeys.sharedExplorePostIdPrefix + "scan-id") == "keep-me")
    }

    @Test func testSpeciesPreferredNameRepositoryPersistsToSwiftDataAndClearsLegacyStore() throws {
        let context = try makeSpeciesPreferenceContext()
        let suiteName = "merian.tests.species-preferred-name-repository.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let didSave = SpeciesPreferredNameRepository.setPreferredName(
            "Bur Oak",
            for: "Quercus macrocarpa",
            modelContext: context,
            legacyDefaults: defaults
        )

        #expect(didSave)
        #expect(try fetchSpeciesPreference(for: "Quercus macrocarpa", modelContext: context)?.preferredCommonName == "Bur Oak")
        #expect(SpeciesPreferredNameStore.preferredName(for: "Quercus macrocarpa", userDefaults: defaults) == nil)

        let didClear = SpeciesPreferredNameRepository.clearPreferredName(
            for: "Quercus macrocarpa",
            modelContext: context,
            legacyDefaults: defaults
        )

        #expect(didClear)
        #expect(try fetchSpeciesPreference(for: "Quercus macrocarpa", modelContext: context) == nil)
        #expect(SpeciesPreferredNameStore.preferredName(for: "Quercus macrocarpa", userDefaults: defaults) == nil)
    }

    @Test func testSpeciesPreferredNameRepositoryQueuesCloudDeleteUntilSynced() throws {
        let context = try makeSpeciesPreferenceContext()
        let suiteName = "merian.tests.species-preferred-name-delete-queue.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SpeciesPreferredNameStore.markPendingCloudDelete(for: "Quercus macrocarpa", userDefaults: defaults)
        #expect(SpeciesPreferredNameStore.pendingDeleteDates(userDefaults: defaults)["Quercus macrocarpa"] != nil)

        #expect(
            SpeciesPreferredNameRepository.setPreferredName(
                "Bur Oak",
                for: "Quercus macrocarpa",
                modelContext: context,
                legacyDefaults: defaults
            )
        )
        #expect(SpeciesPreferredNameStore.pendingDeleteDates(userDefaults: defaults)["Quercus macrocarpa"] == nil)

        #expect(
            SpeciesPreferredNameRepository.clearPreferredName(
                for: "Quercus macrocarpa",
                modelContext: context,
                legacyDefaults: defaults
            )
        )
        #expect(try fetchSpeciesPreference(for: "Quercus macrocarpa", modelContext: context) == nil)
        #expect(SpeciesPreferredNameStore.pendingDeleteDates(userDefaults: defaults)["Quercus macrocarpa"] != nil)

        SpeciesPreferredNameStore.clearPendingCloudDelete(for: "Quercus macrocarpa", userDefaults: defaults)
        #expect(SpeciesPreferredNameStore.pendingDeleteDates(userDefaults: defaults).isEmpty)
    }

    @Test func testSpeciesPreferredNameCloudSyncTreatsMatchingValuesAsConverged() {
        let localUpdatedAt = Date(timeIntervalSince1970: 2_000)
        let matchingRemote = SpeciesPreferenceCloudRow(
            scientific_name: "Quercus macrocarpa",
            preferred_common_name: "  Bur Oak  ",
            updated_at: "1970-01-01T00:16:40.000Z",
            deleted_at: nil
        )
        let newerConflictingRemote = SpeciesPreferenceCloudRow(
            scientific_name: "Quercus macrocarpa",
            preferred_common_name: "Mossycup Oak",
            updated_at: "1970-01-01T00:50:00.000Z",
            deleted_at: nil
        )
        let olderConflictingRemote = SpeciesPreferenceCloudRow(
            scientific_name: "Quercus macrocarpa",
            preferred_common_name: "Mossycup Oak",
            updated_at: "1970-01-01T00:16:40.000Z",
            deleted_at: nil
        )

        #expect(!SpeciesPreferredNameRepository.needsActiveCloudUpsert(
            preferredName: "Bur Oak",
            updatedAt: localUpdatedAt,
            remote: matchingRemote
        ))
        #expect(!SpeciesPreferredNameRepository.needsActiveCloudUpsert(
            preferredName: "Bur Oak",
            updatedAt: localUpdatedAt,
            remote: newerConflictingRemote
        ))
        #expect(SpeciesPreferredNameRepository.needsActiveCloudUpsert(
            preferredName: "Bur Oak",
            updatedAt: localUpdatedAt,
            remote: olderConflictingRemote
        ))
        #expect(SpeciesPreferredNameRepository.needsActiveCloudUpsert(
            preferredName: "Bur Oak",
            updatedAt: localUpdatedAt,
            remote: nil
        ))
    }

    @Test func testSpeciesPreferredNameCloudDeleteDoesNotRewriteExistingTombstone() {
        let localDeletedAt = Date(timeIntervalSince1970: 2_000)
        let deletedRemote = SpeciesPreferenceCloudRow(
            scientific_name: "Quercus macrocarpa",
            preferred_common_name: nil,
            updated_at: "1970-01-01T00:16:40.000Z",
            deleted_at: "1970-01-01T00:16:40.000Z"
        )
        let newerActiveRemote = SpeciesPreferenceCloudRow(
            scientific_name: "Quercus macrocarpa",
            preferred_common_name: "Bur Oak",
            updated_at: "1970-01-01T00:50:00.000Z",
            deleted_at: nil
        )

        #expect(!SpeciesPreferredNameRepository.needsPendingDeleteCloudUpsert(
            deletedAt: localDeletedAt,
            remote: deletedRemote
        ))
        #expect(!SpeciesPreferredNameRepository.needsPendingDeleteCloudUpsert(
            deletedAt: localDeletedAt,
            remote: newerActiveRemote
        ))
        #expect(SpeciesPreferredNameRepository.needsPendingDeleteCloudUpsert(
            deletedAt: localDeletedAt,
            remote: nil
        ))
    }

    @Test func testSpeciesPreferredNameStoreTracksCloudSyncDiagnostics() {
        let suiteName = "merian.tests.species-preferred-name-sync-diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(SpeciesPreferredNameStore.syncDiagnostics(userDefaults: defaults).status == nil)

        let attemptDate = Date(timeIntervalSince1970: 1_000)
        SpeciesPreferredNameStore.recordSyncAttempt(at: attemptDate, userDefaults: defaults)

        var diagnostics = SpeciesPreferredNameStore.syncDiagnostics(userDefaults: defaults)
        #expect(diagnostics.lastAttemptAt == attemptDate)
        #expect(diagnostics.status == .running)
        #expect(diagnostics.message == nil)

        let failureDate = Date(timeIntervalSince1970: 2_000)
        SpeciesPreferredNameStore.recordSyncFailure(
            "Network unavailable",
            at: failureDate,
            userDefaults: defaults
        )

        diagnostics = SpeciesPreferredNameStore.syncDiagnostics(userDefaults: defaults)
        #expect(diagnostics.lastAttemptAt == failureDate)
        #expect(diagnostics.status == .failure)
        #expect(diagnostics.message == "Network unavailable")

        let skipDate = Date(timeIntervalSince1970: 3_000)
        SpeciesPreferredNameStore.recordSyncSkip(
            "No authenticated Supabase user.",
            at: skipDate,
            userDefaults: defaults
        )

        diagnostics = SpeciesPreferredNameStore.syncDiagnostics(userDefaults: defaults)
        #expect(diagnostics.lastAttemptAt == skipDate)
        #expect(diagnostics.status == .skipped)
        #expect(diagnostics.message == "No authenticated Supabase user.")

        let successDate = Date(timeIntervalSince1970: 4_000)
        SpeciesPreferredNameStore.recordSyncSuccess(
            at: successDate,
            pushedCount: 2,
            pulledCount: 3,
            userDefaults: defaults
        )

        diagnostics = SpeciesPreferredNameStore.syncDiagnostics(userDefaults: defaults)
        #expect(diagnostics.lastSuccessAt == successDate)
        #expect(diagnostics.status == .success)
        #expect(diagnostics.message == nil)
        #expect(diagnostics.lastPushedCount == 2)
        #expect(diagnostics.lastPulledCount == 3)

        SpeciesPreferredNameStore.clearSyncDiagnostics(userDefaults: defaults)
        diagnostics = SpeciesPreferredNameStore.syncDiagnostics(userDefaults: defaults)
        #expect(diagnostics.lastAttemptAt == nil)
        #expect(diagnostics.lastSuccessAt == nil)
        #expect(diagnostics.status == nil)
        #expect(diagnostics.lastPushedCount == 0)
        #expect(diagnostics.lastPulledCount == 0)
    }

    @Test func testSpeciesPreferredNameRepositoryPromotesLegacyFallbackToSwiftData() throws {
        let context = try makeSpeciesPreferenceContext()
        let suiteName = "merian.tests.species-preferred-name-promotion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SpeciesPreferredNameStore.setPreferredName(
            "Post Oak",
            for: "Quercus stellata",
            userDefaults: defaults
        )

        let preferred = SpeciesPreferredNameRepository.preferredName(
            for: "Quercus stellata",
            modelContext: context,
            legacyDefaults: defaults
        )

        #expect(preferred == "Post Oak")
        #expect(try fetchSpeciesPreference(for: "Quercus stellata", modelContext: context)?.preferredCommonName == "Post Oak")
        #expect(SpeciesPreferredNameStore.preferredName(for: "Quercus stellata", userDefaults: defaults) == nil)

        let persistedPreferred = SpeciesPreferredNameRepository.preferredName(
            for: "Quercus stellata",
            modelContext: context,
            legacyDefaults: defaults
        )

        #expect(persistedPreferred == "Post Oak")
        #expect(SpeciesPreferredNameStore.preferredName(for: "Quercus stellata", userDefaults: defaults) == nil)
    }

    @Test func testSpeciesPreferredNameRepositoryBuildsBoundedDisplayMap() throws {
        let context = try makeSpeciesPreferenceContext()
        let suiteName = "merian.tests.species-preferred-name-map.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(
            SpeciesPreferredNameRepository.setPreferredName(
                "Bur Oak",
                for: "Quercus macrocarpa",
                modelContext: context,
                legacyDefaults: defaults
            )
        )
        SpeciesPreferredNameStore.setPreferredName(
            "Post Oak",
            for: "Quercus stellata",
            userDefaults: defaults
        )

        let preferredNames = SpeciesPreferredNameRepository.preferredNames(
            for: [
                "Quercus macrocarpa",
                "Quercus stellata",
                "Quercus alba",
                "Quercus macrocarpa",
                "   "
            ],
            modelContext: context,
            legacyDefaults: defaults
        )

        #expect(preferredNames["Quercus macrocarpa"] == "Bur Oak")
        #expect(preferredNames["Quercus stellata"] == "Post Oak")
        #expect(preferredNames["Quercus alba"] == nil)
        #expect(try fetchSpeciesPreference(for: "Quercus stellata", modelContext: context)?.preferredCommonName == "Post Oak")
        #expect(SpeciesPreferredNameStore.preferredName(for: "Quercus stellata", userDefaults: defaults) == nil)
    }

    @Test func testSpeciesPreferredNameRepositoryMigratesLegacyPreferencesAtStartup() throws {
        let context = try makeSpeciesPreferenceContext()
        let suiteName = "merian.tests.species-preferred-name-startup-migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(
            SpeciesPreferredNameRepository.setPreferredName(
                "Bur Oak",
                for: "Quercus macrocarpa",
                modelContext: context,
                legacyDefaults: defaults
            )
        )
        SpeciesPreferredNameStore.setPreferredName("Legacy Bur Oak", for: "Quercus macrocarpa", userDefaults: defaults)
        SpeciesPreferredNameStore.setPreferredName("Post Oak", for: "Quercus stellata", userDefaults: defaults)
        defaults.set("keep-me", forKey: UserDefaultsKeys.sharedExplorePostIdPrefix + "scan-id")

        let result = SpeciesPreferredNameRepository.migrateLegacyPreferences(
            modelContext: context,
            legacyDefaults: defaults
        )

        #expect(result.scannedCount == 2)
        #expect(result.promotedCount == 1)
        #expect(result.preservedExistingCount == 1)
        #expect(result.removedLegacyCount == 2)
        #expect(result.failedCount == 0)
        #expect(try fetchSpeciesPreference(for: "Quercus macrocarpa", modelContext: context)?.preferredCommonName == "Bur Oak")
        #expect(try fetchSpeciesPreference(for: "Quercus stellata", modelContext: context)?.preferredCommonName == "Post Oak")
        #expect(SpeciesPreferredNameStore.preferredName(for: "Quercus macrocarpa", userDefaults: defaults) == nil)
        #expect(SpeciesPreferredNameStore.preferredName(for: "Quercus stellata", userDefaults: defaults) == nil)
        #expect(defaults.string(forKey: UserDefaultsKeys.sharedExplorePostIdPrefix + "scan-id") == "keep-me")
    }
}
