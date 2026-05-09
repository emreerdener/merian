import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Merian

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
        #expect(settings.hasSeenExploreNewChip == false)
        #expect(settings.hasUnseenExplorePost == false)
        #expect(settings.lastSeenExplorePostSharedAt.isEmpty)
        #expect(settings.suppressInferenceBanners == false)

        settings.hasUnseenScan = true
        settings.hasPromptedForNotificationsPostIdent = true
        settings.hasSeenExploreOnboarding = true
        settings.hasSeenExploreNewChip = true
        settings.hasUnseenExplorePost = true
        settings.lastSeenExplorePostSharedAt = "2026-05-09T12:34:56Z"
        settings.suppressInferenceBanners = true

        #expect(defaults.bool(forKey: UserDefaultsKeys.hasUnseenScan))
        #expect(defaults.bool(forKey: UserDefaultsKeys.hasPromptedForNotificationsPostIdent))
        #expect(defaults.bool(forKey: UserDefaultsKeys.hasSeenExploreOnboarding))
        #expect(defaults.bool(forKey: UserDefaultsKeys.hasSeenExploreNewChip))
        #expect(defaults.bool(forKey: UserDefaultsKeys.hasUnseenExplorePost))
        #expect(defaults.string(forKey: UserDefaultsKeys.lastSeenExplorePostSharedAt) == "2026-05-09T12:34:56Z")
        #expect(defaults.bool(forKey: UserDefaultsKeys.suppressInferenceBanners))

        defaults.set(false, forKey: UserDefaultsKeys.hasUnseenScan)
        defaults.set(false, forKey: UserDefaultsKeys.suppressInferenceBanners)
        settings.refreshFromDefaults()

        #expect(settings.hasUnseenScan == false)
        #expect(settings.suppressInferenceBanners == false)
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
