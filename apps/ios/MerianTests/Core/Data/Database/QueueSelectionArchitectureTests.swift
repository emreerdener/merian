import Foundation
import Testing

@Suite("Background Database Actor Queue Selection Architecture")
struct QueueSelectionArchitectureTests {
    @Test func queueSelectionDeclarationsHaveOneFocusedOwner() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian"
        )

        for method in Self.queueSelectionMethods {
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

        let priorityTypeOwners = sources.compactMap { source -> String? in
            source.contents.contains(
                "private struct FundingPrioritizedPendingScan"
            ) ? source.relativePath : nil
        }.sorted()
        #expect(priorityTypeOwners == [Self.productionRelativePath])
    }

    @Test func focusedOwnerKeepsSelectionAndQuarantinePrivateDetails() throws {
        let source = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.productionSourcePath
        )

        #expect(source.contains("extension BackgroundDatabaseActor"))
        #expect(source.contains("private struct FundingPrioritizedPendingScan"))
        #expect(source.contains("fundingJobs = try modelContext.fetch("))
        #expect(source.contains("job = try modelContext.fetchOfflineJob("))
        #expect(!source.contains("try? modelContext.fetch(jobDescriptor)"))
        #expect(!source.contains("try? modelContext.fetchOfflineJob("))
        #expect(!source.contains("private func fetchQueueSelectionJob("))
        #expect(source.contains("guard fundingSource != .deferredFlash"))
        #expect(source.contains("}.prefix(limit).map(\\.payload)"))
        #expect(source.contains("return selectedMedia + emptyCandidates"))
        #expect(source.contains("scan.queueNeedsAttention = true"))
        #expect(source.contains("job.status = .needsAttention"))
        #expect(source.contains("errorCode: \"queued_media_missing\""))
        #expect(
            DatabaseActorTestSupport.lineCount(of: source) <= 600,
            "Queue selection persistence exceeds the 600-line ceiling"
        )

        let imports = Set(source.split(separator: "\n").compactMap { line in
            line.hasPrefix("import ") ? String(line) : nil
        })
        #expect(imports == ["import Foundation", "import SwiftData"])

        for forbidden in Self.forbiddenDependencies {
            #expect(
                !source.contains(forbidden),
                "Queue selection persistence must not own \(forbidden)"
            )
        }
    }

    @Test func productionConsumersStayAtTheUploadOrchestrationBoundary() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian"
        )

        for call in Self.queueSelectionCalls {
            let consumers = sources.compactMap { source -> String? in
                guard source.relativePath != Self.productionRelativePath,
                      source.contents.contains(call) else {
                    return nil
                }
                return source.relativePath
            }.sorted()
            #expect(
                consumers == [Self.uploadSyncRelativePath],
                "\(call) must remain upload-orchestration owned"
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

        #expect(focusedTests.contains("struct QueueSelectionPersistenceTests"))
        #expect(focusedTests.contains("\"Queue Selection Persistence\""))
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
            "QueueSelectionPersistenceTests.swift exceeds the 600-line ceiling"
        )
    }

    private static let productionSourcePath =
        "apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor+QueueSelection.swift"

    private static let productionRelativePath =
        "Core/Data/Database/BackgroundDatabaseActor+QueueSelection.swift"

    private static let behaviorTestsPath =
        "apps/ios/MerianTests/Core/Data/Database/QueueSelectionPersistenceTests.swift"

    private static let behaviorTestRelativePath =
        "Core/Data/Database/QueueSelectionPersistenceTests.swift"

    private static let uploadSyncRelativePath =
        "Core/Data/OfflineSync/Services/MediaUpload/OfflineQueueManager+UploadSync.swift"

    private static let queueSelectionMethods: [(
        name: String,
        signature: String
    )] = [
        (
            "fetchPendingScans",
            "func fetchPendingScans(\n"
        ),
        (
            "quarantineEmptyPendingScans",
            "func quarantineEmptyPendingScans(\n"
        )
    ]

    private static let queueSelectionCalls = [
        ".fetchPendingScans(",
        ".quarantineEmptyPendingScans("
    ]

    private static let behaviorTests = [
        "testBackgroundActorIsolatesSendablePayloadsDynamically",
        "testFetchPendingScansExcludesNonPendingScans",
        "pendingFetchPagesPastDelayedAndLocallyBlockedRowsWithoutStarvingRunnableWork",
        "pendingFetchPrioritizesFundingAndPreservesTierOrder",
        "emptyPendingQuarantineIsAtomicAndStateBound"
    ]

    private static let forbiddenDependencies = [
        "AuthenticationManager",
        "FileIOActor",
        "FileManager",
        "MerianNetworkClient",
        "OfflineQueueManager.shared",
        "RevenueCat",
        "SupabaseManager",
        "URLSession",
        "import SwiftUI",
        "import UIKit"
    ]
}
