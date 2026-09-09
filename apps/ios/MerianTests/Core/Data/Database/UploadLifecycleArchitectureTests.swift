import Foundation
import Testing

@Suite("Background Database Actor Upload Lifecycle Architecture")
struct UploadLifecycleArchitectureTests {
    @Test func uploadLifecycleDeclarationsHaveOneFocusedOwner() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian"
        )

        for method in Self.uploadLifecycleMethods {
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

        let outcomeOwners = sources.compactMap { source -> String? in
            source.contents.contains("enum ScanStagingTransitionOutcome")
                ? source.relativePath
                : nil
        }.sorted()
        #expect(outcomeOwners == [Self.productionRelativePath])

        let supportOwners = sources.compactMap { source -> String? in
            source.contents.contains(
                "func reconcileMirroredInferenceState("
            ) ? source.relativePath : nil
        }.sorted()
        #expect(supportOwners == [Self.supportRelativePath])
    }

    @Test func focusedOwnersStayBoundedAndPersistenceOnly() throws {
        let source = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.productionSourcePath
        )
        let support = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.supportSourcePath
        )
        let aggregate = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.aggregateSourcePath
        )

        #expect(source.contains("extension BackgroundDatabaseActor"))
        #expect(source.contains("enum ScanStagingTransitionOutcome"))
        #expect(source.contains("case staged"))
        #expect(source.contains("case alreadyAdvanced"))
        #expect(source.contains("case retryRequired"))
        #expect(source.contains("case discarded"))
        #expect(
            DatabaseActorTestSupport.lineCount(of: source) <= 600,
            "Upload lifecycle persistence exceeds the 600-line ceiling"
        )
        #expect(
            DatabaseActorTestSupport.lineCount(of: support) <= 100,
            "Queue transition persistence support must stay narrowly scoped"
        )
        #expect(
            DatabaseActorTestSupport.lineCount(of: aggregate) <= 1_900,
            "The residual BackgroundDatabaseActor aggregate must not regrow"
        )

        let imports = Set(source.split(separator: "\n").compactMap { line in
            line.hasPrefix("import ") ? String(line) : nil
        })
        #expect(imports == ["import Foundation", "import SwiftData"])
        #expect(!support.contains("import "))
        #expect(support.contains("extension BackgroundDatabaseActor"))
        #expect(!support.contains("static "))
        #expect(!support.contains("nonisolated"))
        #expect(!support.contains("enum "))
        #expect(!support.contains("class "))
        #expect(
            source.components(
                separatedBy: "job = try modelContext.fetchOfflineJob("
            ).count == 4,
            "Every upload lifecycle transition must use the throwing job lookup"
        )
        #expect(!source.contains("try? modelContext.fetchOfflineJob("))

        for forbidden in Self.forbiddenDependencies {
            #expect(
                !source.contains(forbidden),
                "Upload lifecycle persistence must not own \(forbidden)"
            )
            #expect(
                !support.contains(forbidden),
                "Queue transition support must not own \(forbidden)"
            )
        }
    }

    @Test func uploadLifecycleConsumersStayAtOfflineSyncBoundaries() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian"
        )

        for entry in Self.consumerAllowlist {
            let consumers = sources.compactMap { source -> String? in
                guard source.relativePath != Self.productionRelativePath,
                      source.contents.contains(entry.call) else {
                    return nil
                }
                return source.relativePath
            }.sorted()
            #expect(
                consumers == entry.expected.sorted(),
                "\(entry.call) must remain Offline Sync orchestration owned"
            )
        }

        let supportConsumers = sources.compactMap { source -> String? in
            guard source.relativePath != Self.supportRelativePath,
                  source.contents.contains(
                    "reconcileMirroredInferenceState("
                  ) else {
                return nil
            }
            return source.relativePath
        }.sorted()
        #expect(
            supportConsumers == [
                Self.inferenceLifecycleRelativePath,
                Self.inferenceRetryRelativePath,
                Self.productionRelativePath
            ].sorted()
        )
    }

    @Test func focusedTestsMirrorTheExtractedOwner() throws {
        let focusedTests = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.behaviorTestsPath
        )
        let testSources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/MerianTests"
        )

        #expect(
            focusedTests.contains("struct UploadLifecyclePersistenceTests")
        )
        #expect(focusedTests.contains("\"Upload Lifecycle Persistence\""))
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
            "UploadLifecyclePersistenceTests.swift exceeds the 600-line ceiling"
        )
    }

    private static let aggregateSourcePath =
        "apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor.swift"

    private static let inferenceLifecycleRelativePath =
        "Core/Data/Database/BackgroundDatabaseActor+InferenceLifecycle.swift"

    private static let inferenceRetryRelativePath =
        "Core/Data/Database/BackgroundDatabaseActor+InferenceRetry.swift"

    private static let productionSourcePath =
        "apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor+UploadLifecycle.swift"

    private static let productionRelativePath =
        "Core/Data/Database/BackgroundDatabaseActor+UploadLifecycle.swift"

    private static let supportSourcePath =
        "apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor+RetryMirror.swift"

    private static let supportRelativePath =
        "Core/Data/Database/BackgroundDatabaseActor+RetryMirror.swift"

    private static let behaviorTestsPath =
        "apps/ios/MerianTests/Core/Data/Database/UploadLifecyclePersistenceTests.swift"

    private static let behaviorTestRelativePath =
        "Core/Data/Database/UploadLifecyclePersistenceTests.swift"

    private static let uploadLifecycleMethods: [(
        name: String,
        signature: String
    )] = [
        (
            "markScansAsUploading",
            "func markScansAsUploading(scanIds:"
        ),
        (
            "markScanAsStaged",
            "func markScanAsStaged(\n"
        ),
        (
            "reconcileOrphanedUploadingScans",
            "func reconcileOrphanedUploadingScans(\n"
        )
    ]

    private static let consumerAllowlist: [(
        call: String,
        expected: [String]
    )] = [
        (
            ".markScansAsUploading(",
            [
                "Core/Data/OfflineSync/Services/MediaUpload/OfflineQueueManager+UploadSync.swift"
            ]
        ),
        (
            ".markScanAsStaged(",
            [
                "Core/Data/OfflineSync/Services/MediaUpload/OfflineQueueManager+UploadCompletion.swift"
            ]
        ),
        (
            ".reconcileOrphanedUploadingScans(",
            [
                "Core/Data/OfflineSync/Services/InferenceReplay/OfflineQueueManager+InferenceReplay.swift",
                "Core/Data/OfflineSync/Services/MediaUpload/OfflineQueueManager+UploadDispatch.swift",
                "Core/Data/OfflineSync/Services/MediaUpload/OfflineQueueManager+UploadSync.swift"
            ]
        )
    ]

    private static let behaviorTests = [
        "testMarkScanAsStagedPersistsR2Keys",
        "testMarkScanAsStagedPreservesScheduledServerFailureRetry",
        "testMarkScanAsStagedDoesNotResurrectTombstone",
        "testMarkScanAsStagedIsNoOpFromPending",
        "testMarkScanAsStagedReportsSerializedAdvance",
        "testMarkScanAsStagedRejectsMismatchedAdvancedManifest",
        "testMarkScansAsUploadingOnlyTransitionsPendingScans",
        "testReconcileOrphanedUploadingScansResetsOrphansKeepsActive",
        "testReconcileOrphanedUploadingScansWithEmptyActiveSet",
        "testUploadReconciliationDoesNotResetWorkNewerThanSnapshot"
    ]

    private static let forbiddenDependencies = [
        "AuthenticationManager",
        "FileIOActor",
        "FileManager",
        "MerianNetworkClient",
        "OfflineQueueManager.shared",
        "RevenueCat",
        "SupabaseManager",
        "URLRequest",
        "URLSession.shared",
        "import SwiftUI",
        "import UIKit"
    ]
}
