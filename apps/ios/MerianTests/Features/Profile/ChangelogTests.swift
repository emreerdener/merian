import Foundation
import Testing
@testable import Merian

struct ChangelogTests {
    @Test func decodesChangelogCatalog() throws {
        let catalog = try ChangelogCatalog.decode(from: samplePayload)

        #expect(catalog.schemaVersion == 1)
        #expect(catalog.entries.count == 2)
        #expect(catalog.entries[0].sections[0].items.count == 2)
    }

    @Test func sortsEntriesNewestFirst() throws {
        let catalog = try ChangelogCatalog.decode(from: samplePayload)
        let sorted = catalog.newestEntriesFirst

        #expect(sorted.map(\.id) == ["newer-entry", "older-entry"])
    }

    @Test func supportsMissingAndInvalidImageNames() throws {
        let catalog = try ChangelogCatalog.decode(from: samplePayload)
        let sorted = catalog.newestEntriesFirst

        #expect(sorted[0].imageAssetName == "missing_changelog_asset")
        #expect(sorted[1].imageAssetName == nil)
    }

    @Test func supportsEntriesWithoutVersionLabels() throws {
        let catalog = try ChangelogCatalog.decode(from: samplePayload)

        #expect(catalog.entries[0].version == nil)
        #expect(catalog.entries[0].build == nil)
    }

    private var samplePayload: Data {
        Data(
            """
            {
              "schemaVersion": 1,
              "entries": [
                {
                  "id": "older-entry",
                  "date": "2026-05-01",
                  "title": "Older entry",
                  "sections": [
                    {
                      "title": "Added",
                      "items": [
                        "First note.",
                        "Second note."
                      ]
                    }
                  ]
                },
                {
                  "id": "newer-entry",
                  "date": "2026-06-04",
                  "title": "Newer entry",
                  "imageAssetName": "missing_changelog_asset",
                  "sections": [
                    {
                      "title": "Added",
                      "items": [
                        "A future-facing note."
                      ]
                    }
                  ]
                }
              ]
            }
            """.utf8
        )
    }
}
