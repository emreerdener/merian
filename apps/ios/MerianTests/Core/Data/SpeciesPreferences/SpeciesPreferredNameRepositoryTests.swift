import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Species Preferred Name Repository")
struct SpeciesPreferredNameRepositoryTests {
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

    @Test func clearWithoutLocalRowStillQueuesCloudDelete() throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(SpeciesPreferredNameRepository.clearPreferredName(
            for: " Quercus alba ",
            modelContext: context,
            legacyDefaults: defaults
        ))

        #expect(try fetchSpeciesPreference(
            for: "Quercus alba",
            modelContext: context
        ) == nil)
        #expect(
            SpeciesPreferredNameStore.pendingDeleteDates(
                userDefaults: defaults
            )["Quercus alba"] != nil
        )
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
