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
