import Foundation
import Testing

@Suite("Background Database Actor Species Metadata Architecture")
struct SpeciesMetadataArchitectureTests {
    @Test func speciesMetadataMethodsHaveOneFocusedOwner() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian"
        )

        for method in Self.speciesMetadataMethods {
            let owners = sources.compactMap { source -> String? in
                source.contents.contains("func \(method)(")
                    ? source.relativePath
                    : nil
            }.sorted()
            #expect(
                owners == [Self.speciesMetadataProductionRelativePath],
                "\(method) must have one focused persistence owner"
            )
        }
    }

    @Test func focusedOwnerKeepsPrivateHelpersAndNarrowDependencies() throws {
        let source = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.speciesMetadataSourcePath
        )

        #expect(source.contains("extension BackgroundDatabaseActor"))
        #expect(source.contains("private func mutateScan("))
        #expect(!source.contains("try? modelContext.fetch"))
        #expect(source.contains("mutateScan: fetch failed"))
        #expect(
            source.contains(
                "private func replaceIdentificationPresentation("
            )
        )
        #expect(
            DatabaseActorTestSupport.lineCount(of: source) <= 600,
            "Species metadata persistence exceeds the 600-line review ceiling"
        )

        let imports = Set(source.split(separator: "\n").compactMap { line in
            line.hasPrefix("import ") ? String(line) : nil
        })
        #expect(imports == ["import Foundation", "import SwiftData"])

        for forbidden in Self.forbiddenDependencies {
            #expect(
                !source.contains(forbidden),
                "Species metadata persistence must not own \(forbidden)"
            )
        }
    }

    @Test func focusedTestsMirrorTheExtractedOwner() throws {
        let focusedTests = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.speciesMetadataTestsPath
        )
        let testSources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/MerianTests"
        )

        #expect(focusedTests.contains("struct SpeciesMetadataPersistenceTests"))
        #expect(focusedTests.contains("\"Species Metadata Persistence\""))
        for test in Self.speciesMetadataTests {
            let owners = testSources.compactMap { source -> String? in
                source.contents.contains("func \(test)(")
                    ? source.relativePath
                    : nil
            }.sorted()
            #expect(
                owners == [Self.speciesMetadataTestRelativePath],
                "\(test) must have one focused test owner"
            )
        }
        #expect(
            DatabaseActorTestSupport.lineCount(of: focusedTests) <= 600,
            "SpeciesMetadataPersistenceTests.swift exceeds the 600-line review ceiling"
        )
    }

    private static let speciesMetadataSourcePath =
        "apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor+SpeciesMetadata.swift"

    private static let speciesMetadataProductionRelativePath =
        "Core/Data/Database/BackgroundDatabaseActor+SpeciesMetadata.swift"

    private static let speciesMetadataTestsPath =
        "apps/ios/MerianTests/Core/Data/Database/SpeciesMetadataPersistenceTests.swift"

    private static let speciesMetadataTestRelativePath =
        "Core/Data/Database/SpeciesMetadataPersistenceTests.swift"

    private static let speciesMetadataMethods = [
        "updateScanWithWikipedia",
        "updateScanWithEnrichment",
        "clearAllLocalLookalikesCache",
        "beginScanIdentificationOverride",
        "updateScanWithOverride",
        "updateScanWithOverrideSpeciesData",
        "updateScanAsUnflagged"
    ]

    private static let speciesMetadataTests = [
        "staleSpeciesMetadataCannotOverwriteReplacementIdentification",
        "enrichmentPersistsEveryProvidedFieldForMatchingIdentification",
        "wikipediaUpdateUsesEffectiveIdentificationAndReportsChanges",
        "testClearAllLocalLookalikesCacheClearsBiologicalRecordsAcrossBatchesOnly",
        "testUpdateScanWithOverrideSetsOverrideString",
        "testUpdateScanWithOverrideClearsWithNil",
        "testBeginOverrideAtomicallyReplacesPriorIdentity",
        "testOverrideSpeciesPlaceholderClearsPriorTaxonFields",
        "testHistoricOverrideRefreshPreservesCurrentTaxonCollections",
        "testUpdateScanWithOverrideSetsConfirmedTrue",
        "testUpdateScanAsUnflaggedRemovesFlag"
    ]

    private static let forbiddenDependencies = [
        "FileManager",
        "MerianNetworkClient",
        "OfflineQueueManager",
        "SupabaseManager",
        "URLSession",
        "import CoreLocation",
        "import Supabase",
        "import UIKit"
    ]

}
