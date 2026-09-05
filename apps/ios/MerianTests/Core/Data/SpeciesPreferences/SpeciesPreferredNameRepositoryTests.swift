import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Species Preferred Name Repository")
struct SpeciesPreferredNameRepositoryTests {
    @Test func persistsAndClearsOnlyTheRequestedAccount() throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secondUserID = UUID()

        #expect(SpeciesPreferredNameRepository.setPreferredName(
            "Bur Oak",
            for: "Quercus macrocarpa",
            ownerUserID: speciesPreferenceTestUserID,
            modelContext: context,
            legacyDefaults: defaults
        ))
        #expect(SpeciesPreferredNameRepository.setPreferredName(
            "Mossycup Oak",
            for: "Quercus macrocarpa",
            ownerUserID: secondUserID,
            modelContext: context,
            legacyDefaults: defaults
        ))

        #expect(SpeciesPreferredNameRepository.preferredName(
            for: "Quercus macrocarpa",
            ownerUserID: speciesPreferenceTestUserID,
            modelContext: context
        ) == "Bur Oak")
        #expect(SpeciesPreferredNameRepository.preferredName(
            for: "Quercus macrocarpa",
            ownerUserID: secondUserID,
            modelContext: context
        ) == "Mossycup Oak")

        #expect(SpeciesPreferredNameRepository.clearPreferredName(
            for: "Quercus macrocarpa",
            ownerUserID: speciesPreferenceTestUserID,
            modelContext: context,
            legacyDefaults: defaults
        ))
        #expect(try fetchSpeciesPreference(
            for: "Quercus macrocarpa",
            modelContext: context
        ) == nil)
        #expect(try fetchSpeciesPreference(
            for: "Quercus macrocarpa",
            ownerUserID: secondUserID,
            modelContext: context
        )?.preferredCommonName == "Mossycup Oak")
        #expect(SpeciesPreferredNameStore.pendingDeleteDates(
            ownerUserID: speciesPreferenceTestUserID,
            userDefaults: defaults
        )["Quercus macrocarpa"] != nil)
        #expect(SpeciesPreferredNameStore.pendingDeleteDates(
            ownerUserID: secondUserID,
            userDefaults: defaults
        ).isEmpty)
    }

    @Test func batchReadReturnsOnlyTheRequestedAccount() throws {
        let context = try makeSpeciesPreferenceContext()
        let secondUserID = UUID()
        context.insert(UserSpeciesPreference(
            ownerUserID: speciesPreferenceTestUserID,
            scientificName: "Quercus alba",
            preferredCommonName: "White Oak"
        ))
        context.insert(UserSpeciesPreference(
            ownerUserID: secondUserID,
            scientificName: "Quercus alba",
            preferredCommonName: "Second Account Oak"
        ))
        context.insert(UserSpeciesPreference(
            ownerUserID: speciesPreferenceTestUserID,
            scientificName: "Quercus stellata",
            preferredCommonName: "Post Oak"
        ))
        try context.save()

        #expect(SpeciesPreferredNameRepository.preferredNames(
            for: ["Quercus alba", "Quercus stellata", "Quercus alba"],
            ownerUserID: speciesPreferenceTestUserID,
            modelContext: context
        ) == [
            "Quercus alba": "White Oak",
            "Quercus stellata": "Post Oak"
        ])
    }

    @Test func legacyDeviceGlobalValuesAreDiscardedRatherThanAdopted() throws {
        let context = try makeSpeciesPreferenceContext()
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        SpeciesPreferredNameStore.setLegacyPreferredName(
            "Legacy Bur Oak",
            for: "Quercus macrocarpa",
            userDefaults: defaults
        )
        defaults.set(
            ["Quercus alba": 1_000.0],
            forKey: UserDefaultsKeys.pendingSpeciesPreferredNameDeletes
        )
        defaults.set(
            "keep-me",
            forKey: UserDefaultsKeys.sharedExplorePostIdPrefix + "scan-id"
        )

        let result = SpeciesPreferredNameRepository
            .discardLegacyUnscopedPreferences(
                modelContext: context,
                legacyDefaults: defaults
            )

        #expect(result.promotedCount == 0)
        #expect(result.removedLegacyCount == 1)
        #expect(SpeciesPreferredNameStore.legacyPreferences(
            userDefaults: defaults
        ).isEmpty)
        #expect(defaults.object(
            forKey: UserDefaultsKeys.pendingSpeciesPreferredNameDeletes
        ) == nil)
        #expect(defaults.string(
            forKey: UserDefaultsKeys.sharedExplorePostIdPrefix + "scan-id"
        ) == "keep-me")
        #expect(SpeciesPreferredNameRepository.preferredName(
            for: "Quercus macrocarpa",
            ownerUserID: speciesPreferenceTestUserID,
            modelContext: context
        ) == nil)
    }

    @Test func enforcesPreferredNameLengthBeforePersistence() throws {
        let context = try makeSpeciesPreferenceContext()
        let validName = String(repeating: "a", count: 200)
        let invalidName = String(repeating: "b", count: 201)
        let validCombiningName = String(repeating: "e\u{301}", count: 100)
        let invalidCombiningName = String(repeating: "e\u{301}", count: 101)

        #expect(SpeciesPreferredNameRepository.setPreferredName(
            validName,
            for: "Quercus alba",
            ownerUserID: speciesPreferenceTestUserID,
            modelContext: context
        ))
        #expect(!SpeciesPreferredNameRepository.setPreferredName(
            invalidName,
            for: "Quercus rubra",
            ownerUserID: speciesPreferenceTestUserID,
            modelContext: context
        ))
        #expect(SpeciesPreferredNameRepository.setPreferredName(
            validCombiningName,
            for: "Quercus velutina",
            ownerUserID: speciesPreferenceTestUserID,
            modelContext: context
        ))
        #expect(!SpeciesPreferredNameRepository.setPreferredName(
            invalidCombiningName,
            for: "Quercus stellata",
            ownerUserID: speciesPreferenceTestUserID,
            modelContext: context
        ))
        #expect(try fetchSpeciesPreference(
            for: "Quercus rubra",
            modelContext: context
        ) == nil)
        #expect(try fetchSpeciesPreference(
            for: "Quercus stellata",
            modelContext: context
        ) == nil)
    }

    @Test func matchingCloudValuesAndTombstonesConverge() {
        let localUpdatedAt = Date(timeIntervalSince1970: 2_000)
        let matchingRemote = SpeciesPreferenceCloudRow(
            scientific_name: "Quercus macrocarpa",
            preferred_common_name: "  Bur Oak  ",
            updated_at: "1970-01-01T00:16:40.000Z",
            deleted_at: nil
        )
        let deletedRemote = SpeciesPreferenceCloudRow(
            scientific_name: "Quercus macrocarpa",
            preferred_common_name: nil,
            updated_at: "1970-01-01T00:16:40.000Z",
            deleted_at: "1970-01-01T00:16:40.000Z"
        )

        #expect(!SpeciesPreferredNameRepository.needsActiveCloudUpsert(
            preferredName: "Bur Oak",
            updatedAt: localUpdatedAt,
            remote: matchingRemote
        ))
        #expect(!SpeciesPreferredNameRepository
            .needsPendingDeleteCloudUpsert(
                deletedAt: localUpdatedAt,
                remote: deletedRemote
            ))
    }
}
