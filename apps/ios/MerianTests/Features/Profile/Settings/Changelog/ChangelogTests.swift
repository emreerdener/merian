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

    @Test func userFacingCatalogDoesNotExposeInternalAccountTerminology() throws {
        var repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        for _ in 0..<7 {
            repositoryRoot.deleteLastPathComponent()
        }
        let catalogURL = repositoryRoot.appendingPathComponent(
            "apps/ios/Merian/Resources/Changelog/changelog.json"
        )
        let catalog = try ChangelogCatalog.decode(
            from: Data(contentsOf: catalogURL)
        )

        let userFacingCopy = catalog.entries.flatMap { entry in
            [entry.title] + entry.sections.flatMap { section in
                [section.title] + section.items
            }
        }.joined(separator: "\n")

        #expect(!userFacingCopy.localizedCaseInsensitiveContains("ghost"))
        #expect(!userFacingCopy.localizedCaseInsensitiveContains("guest"))
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
