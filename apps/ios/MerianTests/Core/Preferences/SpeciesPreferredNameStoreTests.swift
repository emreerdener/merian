import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("Species Preferred Name Store")
struct SpeciesPreferredNameStoreTests {
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

    @Test func testSpeciesPreferredNameStoreScopesPendingCloudDeletes() {
        let suiteName = "merian.tests.species-preferred-name-pending-deletes.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstDate = Date(timeIntervalSince1970: 1_000)
        let secondDate = Date(timeIntervalSince1970: 2_000)
        SpeciesPreferredNameStore.markPendingCloudDelete(
            for: " Quercus alba ",
            at: firstDate,
            userDefaults: defaults
        )
        SpeciesPreferredNameStore.markPendingCloudDelete(
            for: "Quercus rubra",
            at: secondDate,
            userDefaults: defaults
        )

        #expect(
            SpeciesPreferredNameStore.pendingDeleteDates(userDefaults: defaults) == [
                "Quercus alba": firstDate,
                "Quercus rubra": secondDate
            ]
        )

        SpeciesPreferredNameStore.clearPendingCloudDelete(
            for: " Quercus alba ",
            userDefaults: defaults
        )
        #expect(
            SpeciesPreferredNameStore.pendingDeleteDates(userDefaults: defaults) == [
                "Quercus rubra": secondDate
            ]
        )

        SpeciesPreferredNameStore.clearPendingCloudDelete(
            for: "Quercus rubra",
            userDefaults: defaults
        )
        #expect(defaults.object(forKey: UserDefaultsKeys.pendingSpeciesPreferredNameDeletes) == nil)
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
}
