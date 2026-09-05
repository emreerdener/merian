import Foundation
@testable import Merian
import Testing

@Suite("Keyed Preference Stores")
struct KeyedPreferenceStoreTests {
    @Test func exploreShareStateNormalizesAndClearsValues() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        ExploreShareStateStore.setSharedPostId(
            "  explore-post-id  ",
            for: "scan-id",
            userDefaults: defaults
        )

        #expect(
            ExploreShareStateStore.sharedPostId(
                for: "scan-id",
                userDefaults: defaults
            ) == "explore-post-id"
        )

        ExploreShareStateStore.setSharedPostId(
            "   ",
            for: "scan-id",
            userDefaults: defaults
        )
        #expect(
            ExploreShareStateStore.sharedPostId(
                for: "scan-id",
                userDefaults: defaults
            ) == nil
        )
    }

    @Test func exploreShareClearAllRemainsPrefixScoped() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        ExploreShareStateStore.setSharedPostId(
            "first-post",
            for: "first-scan",
            userDefaults: defaults
        )
        ExploreShareStateStore.setSharedPostId(
            "second-post",
            for: "second-scan",
            userDefaults: defaults
        )
        FieldNotesStore.setFieldNotes(
            "Keep this private note",
            for: "first-scan",
            userDefaults: defaults
        )

        ExploreShareStateStore.clearAll(userDefaults: defaults)

        #expect(
            ExploreShareStateStore.sharedPostId(
                for: "first-scan",
                userDefaults: defaults
            ) == nil
        )
        #expect(
            ExploreShareStateStore.sharedPostId(
                for: "second-scan",
                userDefaults: defaults
            ) == nil
        )
        #expect(
            FieldNotesStore.fieldNotes(
                for: "first-scan",
                userDefaults: defaults
            ) == "Keep this private note"
        )
    }

    @Test func exploreShareReconciliationUpdatesOnlyTheSuppliedScanSet() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        ExploreShareStateStore.setSharedPostId(
            "old-active-post",
            for: "active-scan",
            userDefaults: defaults
        )
        ExploreShareStateStore.setSharedPostId(
            "stale-unshared-post",
            for: "unshared-scan",
            userDefaults: defaults
        )
        ExploreShareStateStore.setSharedPostId(
            "unrelated-post",
            for: "unrelated-scan",
            userDefaults: defaults
        )
        let reconciliationSnapshot = ExploreShareStateStore
            .makeReconciliationSnapshot(userDefaults: defaults)

        let changedScanIds = ExploreShareStateStore.reconcileSharedPostIds(
            ["active-scan": "  current-active-post  "],
            forScanIds: ["active-scan", "unshared-scan", "active-scan"],
            ifUnchangedSince: reconciliationSnapshot,
            userDefaults: defaults
        )

        #expect(changedScanIds == ["active-scan", "unshared-scan"])
        #expect(
            ExploreShareStateStore.sharedPostId(
                for: "active-scan",
                userDefaults: defaults
            ) == "current-active-post"
        )
        #expect(
            ExploreShareStateStore.sharedPostId(
                for: "unshared-scan",
                userDefaults: defaults
            ) == nil
        )
        #expect(
            ExploreShareStateStore.sharedPostId(
                for: "unrelated-scan",
                userDefaults: defaults
            ) == "unrelated-post"
        )
        #expect(
            ExploreShareStateStore.reconcileSharedPostIds(
                ["active-scan": "current-active-post"],
                forScanIds: ["active-scan", "unshared-scan"],
                ifUnchangedSince: ExploreShareStateStore
                    .makeReconciliationSnapshot(userDefaults: defaults),
                userDefaults: defaults
            ).isEmpty
        )
    }

    @Test func exploreShareReconciliationCannotOverwriteNewerLocalMutation() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let staleSnapshot = ExploreShareStateStore
            .makeReconciliationSnapshot(userDefaults: defaults)
        ExploreShareStateStore.setSharedPostId(
            nil,
            for: "scan-id",
            userDefaults: defaults
        )

        let changedScanIds = ExploreShareStateStore.reconcileSharedPostIds(
            ["scan-id": "stale-active-post"],
            forScanIds: ["scan-id"],
            ifUnchangedSince: staleSnapshot,
            userDefaults: defaults
        )

        #expect(changedScanIds.isEmpty)
        #expect(
            ExploreShareStateStore.sharedPostId(
                for: "scan-id",
                userDefaults: defaults
            ) == nil
        )
    }

    @Test func exploreShareReconciliationRejectsOutOfOrderResponses() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let olderSnapshot = ExploreShareStateStore
            .makeReconciliationSnapshot(userDefaults: defaults)
        let newerSnapshot = ExploreShareStateStore
            .makeReconciliationSnapshot(userDefaults: defaults)

        #expect(
            ExploreShareStateStore.reconcileSharedPostIds(
                ["scan-id": "newest-post"],
                forScanIds: ["scan-id"],
                ifUnchangedSince: newerSnapshot,
                userDefaults: defaults
            ) == ["scan-id"]
        )
        #expect(
            ExploreShareStateStore.reconcileSharedPostIds(
                ["scan-id": "stale-post"],
                forScanIds: ["scan-id"],
                ifUnchangedSince: olderSnapshot,
                userDefaults: defaults
            ).isEmpty
        )
        #expect(
            ExploreShareStateStore.sharedPostId(
                for: "scan-id",
                userDefaults: defaults
            ) == "newest-post"
        )
    }

    @Test func exploreShareClearAllInvalidatesInFlightReconciliation() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        ExploreShareStateStore.setSharedPostId(
            "existing-post",
            for: "scan-id",
            userDefaults: defaults
        )
        let staleSnapshot = ExploreShareStateStore
            .makeReconciliationSnapshot(userDefaults: defaults)

        ExploreShareStateStore.clearAll(userDefaults: defaults)
        let changedScanIds = ExploreShareStateStore.reconcileSharedPostIds(
            ["scan-id": "stale-post"],
            forScanIds: ["scan-id"],
            ifUnchangedSince: staleSnapshot,
            userDefaults: defaults
        )

        #expect(changedScanIds.isEmpty)
        #expect(
            ExploreShareStateStore.sharedPostId(
                for: "scan-id",
                userDefaults: defaults
            ) == nil
        )
    }

    @Test func fieldNotesNormalizeReadsAndRejectWhitespaceOnlyValues() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        FieldNotesStore.setFieldNotes(
            "  Woodland edge observation  ",
            for: "scan-id",
            userDefaults: defaults
        )
        #expect(
            FieldNotesStore.fieldNotes(
                for: "scan-id",
                userDefaults: defaults
            ) == "Woodland edge observation"
        )

        FieldNotesStore.setFieldNotes(
            "\n\t ",
            for: "scan-id",
            userDefaults: defaults
        )
        #expect(
            FieldNotesStore.fieldNotes(
                for: "scan-id",
                userDefaults: defaults
            ) == nil
        )
    }

    @Test func fieldNotesClearAllRemainsPrefixScoped() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        FieldNotesStore.setFieldNotes(
            "First note",
            for: "first-scan",
            userDefaults: defaults
        )
        FieldNotesStore.setFieldNotes(
            "Second note",
            for: "second-scan",
            userDefaults: defaults
        )
        ExploreShareStateStore.setSharedPostId(
            "keep-this-post",
            for: "first-scan",
            userDefaults: defaults
        )

        FieldNotesStore.clearAll(userDefaults: defaults)

        #expect(
            FieldNotesStore.fieldNotes(
                for: "first-scan",
                userDefaults: defaults
            ) == nil
        )
        #expect(
            FieldNotesStore.fieldNotes(
                for: "second-scan",
                userDefaults: defaults
            ) == nil
        )
        #expect(
            ExploreShareStateStore.sharedPostId(
                for: "first-scan",
                userDefaults: defaults
            ) == "keep-this-post"
        )
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "merian.tests.keyed-preference-store.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
