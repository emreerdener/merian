import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("Species Preferred Name Store")
struct SpeciesPreferredNameStoreTests {
    @Test func pendingDeletesArePartitionedByAccount() {
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstUserID = UUID()
        let secondUserID = UUID()
        let firstDate = Date(timeIntervalSince1970: 1_000)
        let secondDate = Date(timeIntervalSince1970: 2_000)

        SpeciesPreferredNameStore.markPendingCloudDelete(
            for: "Quercus alba",
            ownerUserID: firstUserID,
            at: firstDate,
            userDefaults: defaults
        )
        SpeciesPreferredNameStore.markPendingCloudDelete(
            for: "Quercus rubra",
            ownerUserID: secondUserID,
            at: secondDate,
            userDefaults: defaults
        )

        #expect(SpeciesPreferredNameStore.pendingDeleteDates(
            ownerUserID: firstUserID,
            userDefaults: defaults
        ) == ["Quercus alba": firstDate])
        #expect(SpeciesPreferredNameStore.pendingDeleteDates(
            ownerUserID: secondUserID,
            userDefaults: defaults
        ) == ["Quercus rubra": secondDate])

        SpeciesPreferredNameStore.clearPendingCloudDelete(
            for: "Quercus alba",
            ownerUserID: firstUserID,
            userDefaults: defaults
        )
        #expect(SpeciesPreferredNameStore.pendingDeleteDates(
            ownerUserID: firstUserID,
            userDefaults: defaults
        ).isEmpty)
        #expect(!SpeciesPreferredNameStore.pendingDeleteDates(
            ownerUserID: secondUserID,
            userDefaults: defaults
        ).isEmpty)
    }

    @Test func pendingDeleteTimestampNeverRegresses() throws {
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ownerUserID = try #require(
            UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        )
        let scientificName = "Quercus macrocarpa"
        let newerDate = Date(timeIntervalSince1970: 3_000)

        SpeciesPreferredNameStore.markPendingCloudDelete(
            for: scientificName,
            ownerUserID: ownerUserID,
            at: newerDate,
            userDefaults: defaults
        )
        SpeciesPreferredNameStore.markPendingCloudDelete(
            for: scientificName,
            ownerUserID: ownerUserID,
            at: Date(timeIntervalSince1970: 2_000),
            userDefaults: defaults
        )

        #expect(
            SpeciesPreferredNameStore.pendingDeleteDates(
                ownerUserID: ownerUserID,
                userDefaults: defaults
            )[scientificName] == newerDate
        )
    }

    @Test func syncDiagnosticsArePartitionedByAccount() {
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstUserID = UUID()
        let secondUserID = UUID()

        SpeciesPreferredNameStore.recordSyncSuccess(
            ownerUserID: firstUserID,
            at: Date(timeIntervalSince1970: 4_000),
            pushedCount: 2,
            pulledCount: 3,
            userDefaults: defaults
        )
        SpeciesPreferredNameStore.recordSyncFailure(
            "Network unavailable",
            ownerUserID: secondUserID,
            at: Date(timeIntervalSince1970: 5_000),
            userDefaults: defaults
        )

        let first = SpeciesPreferredNameStore.syncDiagnostics(
            ownerUserID: firstUserID,
            userDefaults: defaults
        )
        let second = SpeciesPreferredNameStore.syncDiagnostics(
            ownerUserID: secondUserID,
            userDefaults: defaults
        )
        #expect(first.status == .success)
        #expect(first.lastPushedCount == 2)
        #expect(first.lastPulledCount == 3)
        #expect(second.status == .failure)
        #expect(second.message == "Network unavailable")

        SpeciesPreferredNameStore.clearSyncDiagnostics(
            ownerUserID: firstUserID,
            userDefaults: defaults
        )
        #expect(SpeciesPreferredNameStore.syncDiagnostics(
            ownerUserID: firstUserID,
            userDefaults: defaults
        ).status == nil)
        #expect(SpeciesPreferredNameStore.syncDiagnostics(
            ownerUserID: secondUserID,
            userDefaults: defaults
        ).status == .failure)
    }

    @Test func legacyCleanupDoesNotTouchUnrelatedDefaults() {
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        SpeciesPreferredNameStore.setLegacyPreferredName(
            "Bur Oak",
            for: "Quercus macrocarpa",
            userDefaults: defaults
        )
        defaults.set(
            "failure",
            forKey: UserDefaultsKeys.speciesPreferredNameSyncStatus
        )
        defaults.set("keep-me", forKey: "unrelated")

        SpeciesPreferredNameStore.discardLegacyUnscopedData(
            userDefaults: defaults
        )

        #expect(SpeciesPreferredNameStore.legacyPreferences(
            userDefaults: defaults
        ).isEmpty)
        #expect(defaults.object(
            forKey: UserDefaultsKeys.speciesPreferredNameSyncStatus
        ) == nil)
        #expect(defaults.string(forKey: "unrelated") == "keep-me")
    }

    @Test func clearAllAccountDataRemovesEveryAccountPartition() {
        let (defaults, suiteName) = makeSpeciesPreferenceDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstUserID = UUID()
        let secondUserID = UUID()
        SpeciesPreferredNameStore.markPendingCloudDelete(
            for: "Quercus alba",
            ownerUserID: firstUserID,
            userDefaults: defaults
        )
        SpeciesPreferredNameStore.recordSyncAttempt(
            ownerUserID: secondUserID,
            userDefaults: defaults
        )
        #expect(SpeciesPreferredNameStore.hasStoredAccountData(
            userDefaults: defaults
        ))

        SpeciesPreferredNameStore.clearAllAccountData(
            userDefaults: defaults
        )

        #expect(!SpeciesPreferredNameStore.hasStoredAccountData(
            userDefaults: defaults
        ))
    }
}
