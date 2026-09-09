import Foundation
import Testing

@Suite("Background Database Actor Inference Persistence Architecture")
struct InferencePersistenceArchitectureTests {
    @Test func inferenceDeclarationsHaveFocusedOwners() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian"
        )

        for method in Self.ownedMethods {
            let owners = sources.compactMap { source -> String? in
                source.contents.contains(method.signature)
                    ? source.relativePath
                    : nil
            }.sorted()
            #expect(
                owners == [method.owner],
                "\(method.name) must have one focused persistence owner"
            )
        }

        for helper in Self.privateHelpers {
            let owners = sources.compactMap { source -> String? in
                source.contents.contains(helper.signature)
                    ? source.relativePath
                    : nil
            }.sorted()
            #expect(
                owners == [helper.owner],
                "\(helper.signature) must remain file-private"
            )
        }
    }

    @Test func focusedOwnersStayBoundedAndPersistenceOnly() throws {
        let lifecycle = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.lifecycleSourcePath
        )
        let retry = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.retrySourcePath
        )
        let aggregate = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.aggregateSourcePath
        )

        #expect(lifecycle.contains("extension BackgroundDatabaseActor"))
        #expect(retry.contains("extension BackgroundDatabaseActor"))
        #expect(
            DatabaseActorTestSupport.lineCount(of: lifecycle) <= 600,
            "Inference lifecycle persistence exceeds its 600-line ceiling"
        )
        #expect(
            DatabaseActorTestSupport.lineCount(of: retry) <= 400,
            "Inference retry persistence exceeds its 400-line ceiling"
        )
        #expect(
            DatabaseActorTestSupport.lineCount(of: aggregate) <= 1_000,
            "The residual BackgroundDatabaseActor aggregate must not regrow"
        )

        for source in [lifecycle, retry] {
            let imports = Set(
                source.split(separator: "\n").compactMap { line in
                    line.hasPrefix("import ") ? String(line) : nil
                }
            )
            #expect(
                imports == ["import Foundation", "import SwiftData"]
            )
            #expect(!source.contains("try? modelContext.fetch"))
            for forbidden in Self.forbiddenDependencies {
                #expect(
                    !source.contains(forbidden),
                    "Inference persistence must not own \(forbidden)"
                )
            }
        }

        #expect(
            lifecycle.components(
                separatedBy: "try modelContext.fetchOfflineJob("
            ).count == 6,
            "Every lifecycle job decision must distinguish failure from absence"
        )
        #expect(
            retry.components(
                separatedBy: "try modelContext.fetchOfflineJob("
            ).count == 2,
            "Both retry paths must share one throwing job lookup"
        )
        #expect(
            lifecycle.contains(
                "let jobsByScanId = inferenceJobsForOrphanReconciliation("
            ),
            "Orphan recovery must load every job before mutating its batch"
        )
        #expect(!aggregate.contains("private func fetchOfflineJob("))
    }

    @Test func serializedMutationsKeepBalancedPersistenceFences() throws {
        let lifecycle = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.lifecycleSourcePath
        )
        let retry = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.retrySourcePath
        )

        #expect(
            occurrenceCount(
                of: "ScanInferencePersistenceCoordinator.shared.acquire(",
                in: lifecycle
            ) == 3
        )
        #expect(
            occurrenceCount(
                of: "ScanInferencePersistenceCoordinator.shared.release(",
                in: lifecycle
            ) == 6,
            "Lifecycle cancellation and normal exits must release every fence"
        )
        #expect(
            occurrenceCount(
                of: "guard !Task.isCancelled else {",
                in: lifecycle
            ) == 3,
            "Every lifecycle mutation must check cancellation after acquire"
        )
        #expect(
            lifecycle.contains(
                "let readContext = ModelContext(modelContext.container)"
            ),
            "Orphan recovery must revalidate durable eligibility in a fresh context"
        )

        #expect(
            occurrenceCount(
                of: "ScanInferencePersistenceCoordinator.shared.acquire(",
                in: retry
            ) == 2
        )
        #expect(
            occurrenceCount(
                of: "ScanInferencePersistenceCoordinator.shared.release(",
                in: retry
            ) == 4,
            "Retry cancellation and normal exits must release every fence"
        )
        #expect(
            occurrenceCount(
                of: "guard !Task.isCancelled else {",
                in: retry
            ) == 2,
            "Every retry mutation must check cancellation after acquire"
        )
    }

    @Test func consumersStayAtOfflineSyncBoundaries() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian"
        )

        for entry in Self.consumerAllowlist {
            let consumers = sources.compactMap { source -> String? in
                guard source.relativePath != entry.owner,
                      source.contents.contains(entry.call) else {
                    return nil
                }
                return source.relativePath
            }.sorted()
            #expect(
                consumers == entry.expected.sorted(),
                "\(entry.call) must remain in its reviewed orchestration owners"
            )
        }
    }

    @Test func focusedTestsMirrorExtractedBehavior() throws {
        let lifecycleTests = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.lifecycleTestsPath
        )
        let retryTests = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.retryTestsPath
        )
        let testSources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/MerianTests"
        )

        #expect(
            lifecycleTests.contains("struct InferenceLifecyclePersistenceTests")
        )
        #expect(retryTests.contains("struct InferenceRetryPersistenceTests"))
        for test in Self.lifecycleBehaviorTests {
            assertTestOwnership(
                test,
                expectedOwner: Self.lifecycleTestRelativePath,
                sources: testSources
            )
        }
        for test in Self.retryBehaviorTests {
            assertTestOwnership(
                test,
                expectedOwner: Self.retryTestRelativePath,
                sources: testSources
            )
        }
        #expect(
            DatabaseActorTestSupport.lineCount(of: lifecycleTests) <= 600,
            "InferenceLifecyclePersistenceTests.swift exceeds 600 lines"
        )
        #expect(
            DatabaseActorTestSupport.lineCount(of: retryTests) <= 600,
            "InferenceRetryPersistenceTests.swift exceeds 600 lines"
        )
    }

    private func assertTestOwnership(
        _ test: String,
        expectedOwner: String,
        sources: [DatabaseActorTestSupport.RepositorySourceFile]
    ) {
        let owners = sources.compactMap { source -> String? in
            source.contents.contains("func \(test)(")
                ? source.relativePath
                : nil
        }.sorted()
        #expect(
            owners == [expectedOwner],
            "\(test) must have one focused test owner"
        )
    }

    private func occurrenceCount(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    private static let aggregateSourcePath =
        "apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor.swift"

    private static let lifecycleSourcePath =
        "apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor+InferenceLifecycle.swift"

    private static let lifecycleRelativePath =
        "Core/Data/Database/BackgroundDatabaseActor+InferenceLifecycle.swift"

    private static let retrySourcePath =
        "apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor+InferenceRetry.swift"

    private static let retryRelativePath =
        "Core/Data/Database/BackgroundDatabaseActor+InferenceRetry.swift"

    private static let lifecycleTestsPath =
        "apps/ios/MerianTests/Core/Data/Database/InferenceLifecyclePersistenceTests.swift"

    private static let lifecycleTestRelativePath =
        "Core/Data/Database/InferenceLifecyclePersistenceTests.swift"

    private static let retryTestsPath =
        "apps/ios/MerianTests/Core/Data/Database/InferenceRetryPersistenceTests.swift"

    private static let retryTestRelativePath =
        "Core/Data/Database/InferenceRetryPersistenceTests.swift"

    private struct OwnedMethod {
        let name: String
        let signature: String
        let owner: String
    }

    private struct ConsumerRule {
        let call: String
        let owner: String
        let expected: [String]

        init(_ call: String, _ owner: String, _ expected: [String]) {
            self.call = call
            self.owner = owner
            self.expected = expected
        }
    }

    private static let ownedMethods: [OwnedMethod] = [
        .init(
            name: "fetchServerOwnedInferencingScanIds",
            signature: "func fetchServerOwnedInferencingScanIds(",
            owner: lifecycleRelativePath
        ),
        .init(
            name: "tryClaimForInference",
            signature: "func tryClaimForInference(",
            owner: lifecycleRelativePath
        ),
        .init(
            name: "transitionScanToStaged",
            signature: "func transitionScanToStaged(",
            owner: lifecycleRelativePath
        ),
        .init(
            name: "inferenceGenerationIsCurrentAssumingPersistenceLock",
            signature: "func inferenceGenerationIsCurrentAssumingPersistenceLock(",
            owner: lifecycleRelativePath
        ),
        .init(
            name: "liveInferenceGenerationIsCurrentAssumingPersistenceLock",
            signature: "func liveInferenceGenerationIsCurrentAssumingPersistenceLock(",
            owner: lifecycleRelativePath
        ),
        .init(
            name: "reconcileOrphanedInferencingScans",
            signature: "func reconcileOrphanedInferencingScans(",
            owner: lifecycleRelativePath
        ),
        .init(
            name: "updateScanTelemetry",
            signature: "func updateScanTelemetry(",
            owner: lifecycleRelativePath
        ),
        .init(
            name: "scheduleInferenceRetry",
            signature: "func scheduleInferenceRetry(",
            owner: retryRelativePath
        ),
        .init(
            name: "scheduleServerResultRecoveryRetry",
            signature: "func scheduleServerResultRecoveryRetry(",
            owner: retryRelativePath
        )
    ]

    private static let privateHelpers: [(
        signature: String,
        owner: String
    )] = [
        ("private func tryClaimForInferenceLocked(", lifecycleRelativePath),
        ("private func transitionScanToStagedLocked(", lifecycleRelativePath),
        (
            "private func reconcileOrphanedInferencingScansLocked(",
            lifecycleRelativePath
        ),
        (
            "private func orphanedInferenceCandidateIds(",
            lifecycleRelativePath
        ),
        (
            "private func inferenceJobsForOrphanReconciliation(",
            lifecycleRelativePath
        ),
        ("private func scheduleInferenceRetryLocked(", retryRelativePath),
        (
            "private func scheduleServerResultRecoveryRetryLocked(",
            retryRelativePath
        ),
        ("private func inferenceRetryRecords(", retryRelativePath)
    ]

    private static let consumerAllowlist: [ConsumerRule] = [
        .init(
            ".fetchServerOwnedInferencingScanIds(",
            lifecycleRelativePath,
            [
                "Core/Data/OfflineSync/Services/BackgroundInference/OfflineQueueManager+InferenceReconciliation.swift"
            ]
        ),
        .init(
            ".tryClaimForInference(",
            lifecycleRelativePath,
            [
                "Core/Data/OfflineSync/Services/InferenceReplay/OfflineQueueManager+InferenceReplay.swift",
                "Core/Data/OfflineSync/Services/MediaUpload/OfflineQueueManager+UploadCompletion.swift"
            ]
        ),
        .init(".transitionScanToStaged(", lifecycleRelativePath, []),
        .init(
            ".inferenceGenerationIsCurrentAssumingPersistenceLock(",
            lifecycleRelativePath,
            [
                "Core/Data/OfflineSync/Services/QueueMaintenance/OfflineQueueManager+QueueDeletion.swift"
            ]
        ),
        .init(
            "liveInferenceGenerationIsCurrentAssumingPersistenceLock(",
            lifecycleRelativePath,
            [
                "Core/Data/Database/BackgroundDatabaseActor+LiveScanPersistence.swift",
                "Core/Data/OfflineSync/Services/QueueMaintenance/OfflineQueueManager+QueueDeletion.swift"
            ]
        ),
        .init(
            ".reconcileOrphanedInferencingScans(",
            lifecycleRelativePath,
            [
                "Core/Data/OfflineSync/Services/InferenceReplay/OfflineQueueManager+InferenceReplay.swift"
            ]
        ),
        .init(".updateScanTelemetry(", lifecycleRelativePath, []),
        .init(
            ".scheduleInferenceRetry(",
            retryRelativePath,
            [
                "Core/Data/OfflineSync/Services/BackgroundInference/OfflineQueueManager+InferenceRecovery.swift",
                "Core/Data/OfflineSync/Services/BackgroundInference/OfflineQueueManager+InferenceRetry.swift"
            ]
        ),
        .init(
            ".scheduleServerResultRecoveryRetry(",
            retryRelativePath,
            [
                "Core/Data/OfflineSync/Services/BackgroundInference/OfflineQueueManager+InferenceRecovery.swift"
            ]
        )
    ]

    private static let lifecycleBehaviorTests = [
        "testTryClaimForInferenceSucceedsOnStagedScan",
        "testTryClaimForInferenceFailsWhenAlreadyInferencing",
        "testTryClaimForInferenceFailsWhenPending",
        "testTryClaimForInferenceRejectsUnsupportedQueuedAudio",
        "testTryClaimForInferenceDoesNotResurrectTombstone",
        "testTryClaimForInferenceSecondCallReturnsFalse",
        "testTryClaimForInferenceCreatesMissingLegacyJob",
        "cancelledClaimReleasesPersistenceFence",
        "testTransitionScanToStagedSucceedsFromInferencing",
        "testTransitionScanToStagedRejectsOlderPersistedGeneration",
        "absentQueueRequiresExactCompletedGenerationForInferenceDeletion",
        "testTransitionScanToStagedDoesNotResurrectTombstone",
        "testTransitionScanToStagedIsNoOpFromPending",
        "testReconcileOrphanedInferencingScansResetsAllToStaged",
        "testInferenceReconciliationDoesNotResetWorkNewerThanSnapshot",
        "reconciliationRevalidatesAfterPersistenceFenceWait"
    ]

    private static let retryBehaviorTests = [
        "testScheduleInferenceRetryRejectsOlderPersistedGeneration",
        "testPersistenceRetryRestagesLocalMediaInsteadOfDeadObjectKeys",
        "testScheduleInferenceRetryUsesMonotonicMirroredAttempt",
        "testInferenceRetryCannotOverrideCompletedCloudOwnership",
        "testServerResultRecoveryRetryPreservesCloudOwnershipEvidence",
        "testScheduleInferenceRetryCreatesMissingLegacyJob",
        "testServerResultRecoveryRetryCreatesMissingLegacyJob",
        "cancelledRetryReleasesPersistenceFence"
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
