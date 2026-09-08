import Foundation
import Testing

@Suite("Background Database Actor Non-Biological Retention Architecture")
struct NonBiologicalRetentionArchitectureTests {
    @Test func retentionDeclarationsHaveOneFocusedOwner() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian"
        )

        for method in Self.retentionMethods {
            let owners = sources.compactMap { source -> String? in
                source.contents.contains(method.signature)
                    ? source.relativePath
                    : nil
            }.sorted()
            #expect(
                owners == [Self.productionRelativePath],
                "\(method.name) must have one focused persistence owner"
            )
        }

        for type in Self.retentionTypes {
            let owners = sources.compactMap { source -> String? in
                source.contents.contains("struct \(type)")
                    ? source.relativePath
                    : nil
            }.sorted()
            #expect(
                owners == [Self.productionRelativePath],
                "\(type) must have one focused persistence owner"
            )
        }
    }

    @Test func focusedOwnerKeepsNarrowDependencies() throws {
        let source = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.productionSourcePath
        )

        #expect(source.contains("extension BackgroundDatabaseActor"))
        #expect(
            source.contains(
                "try modelContext.ensurePendingCloudDeletionTask("
            )
        )
        #expect(source.contains("let mediaPaths: [String]"))
        #expect(!source.contains("let imagePaths: [String]"))
        #expect(source.contains("let committedErasureCount: Int"))
        #expect(
            source.contains(
                "committedErasureCount: commit.committedErasureCount"
            ),
            "Purge results must report accepted erasure work"
        )
        #expect(
            source.contains(
                "deletedRecordCount: commit.deletedRecordCount"
            ),
            "Purge results must report only rows deleted by the commit"
        )
        #expect(
            !source.contains(
                "deletedRecordCount: expiredRecords.count"
            ),
            "A stale purge snapshot must not over-report deletions"
        )
        #expect(
            DatabaseActorTestSupport.lineCount(of: source) <= 600,
            "Non-biological retention persistence exceeds the 600-line ceiling"
        )

        let imports = Set(source.split(separator: "\n").compactMap { line in
            line.hasPrefix("import ") ? String(line) : nil
        })
        #expect(imports == ["import Foundation", "import SwiftData"])

        for forbidden in Self.forbiddenDependencies {
            #expect(
                !source.contains(forbidden),
                "Non-biological retention must not own \(forbidden)"
            )
        }
    }

    @Test func focusedTestsMirrorTheExtractedOwner() throws {
        let focusedTests = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.behaviorTestsPath
        )
        let testSources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/MerianTests"
        )

        #expect(
            focusedTests.contains(
                "struct NonBiologicalRetentionPersistenceTests"
            )
        )
        #expect(
            focusedTests.contains(
                "\"Non-Biological Retention Persistence\""
            )
        )
        for test in Self.behaviorTests {
            let owners = testSources.compactMap { source -> String? in
                source.contents.contains("func \(test)(")
                    ? source.relativePath
                    : nil
            }.sorted()
            #expect(
                owners == [Self.behaviorTestRelativePath],
                "\(test) must have one focused test owner"
            )
        }
        #expect(
            DatabaseActorTestSupport.lineCount(of: focusedTests) <= 600,
            "NonBiologicalRetentionPersistenceTests.swift exceeds the 600-line ceiling"
        )
    }

    @Test func repositoryRoutesOnlyCommittedPurgeEffects() throws {
        let source = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.repositorySourcePath
        )

        #expect(
            source.contains(
                "guard result.committedErasureCount > 0 else { return }"
            ),
            "Cloud cleanup must be driven by accepted erasure work"
        )
        #expect(
            !source.contains(
                "guard result.deletedRecordCount > 0 else { return }"
            ),
            "A missing row must not suppress committed cleanup work"
        )
        #expect(
            source.contains(
                "if result.deletedRecordCount > 0 {"
            ),
            "Library changes must be published only for deleted rows"
        )
    }

    private static let productionSourcePath =
        "apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor+NonBiologicalRetention.swift"

    private static let productionRelativePath =
        "Core/Data/Database/BackgroundDatabaseActor+NonBiologicalRetention.swift"

    private static let behaviorTestsPath =
        "apps/ios/MerianTests/Core/Data/Database/NonBiologicalRetentionPersistenceTests.swift"

    private static let behaviorTestRelativePath =
        "Core/Data/Database/NonBiologicalRetentionPersistenceTests.swift"

    private static let repositorySourcePath =
        "apps/ios/Merian/Core/Data/Database/ScanRepository.swift"

    private static let retentionMethods: [(name: String, signature: String)] = [
        (
            "bulkDeleteNonBiologicalScans",
            "func bulkDeleteNonBiologicalScans(\n        payloads:"
        ),
        (
            "purgeExpiredNonBiologicalScans",
            "func purgeExpiredNonBiologicalScans(\n        cutoffDate:"
        )
    ]

    private static let retentionTypes = [
        "ScanErasurePayload",
        "ExpiredNonBiologicalPurgeResult"
    ]

    private static let behaviorTests = [
        "testBulkDeleteNonBiologicalScansCommitsBeforeReturningPaths",
        "testBulkDeleteNonBiologicalScansReusesExistingPendingCloudDeletionTask",
        "testBulkDeleteNonBiologicalScansKeepsMissingRecordCleanupIdempotent",
        "testBulkDeleteNonBiologicalScansRevalidatesEligibilityBeforeCommit",
        "testPurgeExpiredNonBiologicalScansDeletesOnlyExpiredNonBioRecords",
        "testPurgeExpiredNonBiologicalScansHonorsOldestFirstBatchLimit"
    ]

    private static let forbiddenDependencies = [
        "FileIOActor",
        "FileManager",
        "MerianNetworkClient",
        "OfflineQueueManager",
        "SupabaseManager",
        "URLSession",
        "import Supabase",
        "import UIKit"
    ]
}
