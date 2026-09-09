import Foundation
import Testing

@Suite("Core Data Integration Architecture")
struct CoreDataIntegrationArchitectureTests {
    @Test func backgroundActorSurfaceHasExactBoundedOwners() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: Self.databaseDirectory
        ).filter { source in
            source.relativePath.hasPrefix("BackgroundDatabaseActor")
        }

        #expect(
            Set(sources.map(\.relativePath))
                == Set(Self.expectedActorImports.keys),
            "BackgroundDatabaseActor ownership changed without an integration review"
        )

        for source in sources {
            #expect(
                DatabaseActorTestSupport.lineCount(of: source.contents) <= 600,
                "\(source.relativePath) exceeds the 600-line review ceiling"
            )
            #expect(
                imports(in: source.contents)
                    == Self.expectedActorImports[source.relativePath],
                "\(source.relativePath) has an unexpected dependency"
            )
        }

        let aggregate = try source(
            "Database/BackgroundDatabaseActor.swift"
        )
        #expect(aggregate.contains("actor BackgroundDatabaseActor {}"))
        #expect(!aggregate.contains("func "))
        #expect(!aggregate.contains("extension BackgroundDatabaseActor"))
    }

    @Test func swiftDataReadsNeverSilentlyCollapseFailureIntoAbsence() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: Self.coreDataDirectory
        )

        for source in sources {
            #expect(
                source.contents.range(
                    of: Self.silentFetchPattern,
                    options: .regularExpression
                ) == nil,
                "\(source.relativePath) silently discards a SwiftData fetch failure"
            )
        }
    }

    @Test func mirroredQueueAuthorityUsesOneFreshThrowingSnapshot() throws {
        let authority = try source(
            "OfflineSync/Persistence/OfflineQueueDurableAuthorityReader.swift"
        )

        #expect(authority.contains(
            "static func read(\n        scanId: String,\n        from container: ModelContainer\n    ) throws"
        ))
        #expect(
            occurrences(of: "let context = ModelContext(container)", in: authority)
                == 1
        )
        #expect(authority.contains("let scan = try context.fetch("))
        #expect(authority.contains("let job = try context.fetchOfflineJob("))
        #expect(authority.contains(
            "throw OfflineQueueDurableAuthorityReadError.missingModelContainer"
        ))
        #expect(authority.contains("scanAttemptCount: scan?.queueAttemptCount"))
        #expect(authority.contains("jobAttemptCount: job?.attemptCount"))
        #expect(authority.contains("requiredVideoCount:"))
        #expect(!authority.contains("try?"))
    }

    @Test func durableQueueAuthorityConsumersStayBounded() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: Self.coreDataDirectory
        )

        let throwingConsumers = Set(sources.compactMap { source in
            source.contents.contains("durableQueueAuthority(")
                ? source.relativePath
                : nil
        })
        #expect(throwingConsumers == [
            "OfflineSync/OfflineQueueDurability.swift",
            "OfflineSync/Persistence/OfflineQueueDurableAuthorityReader.swift"
        ])

        let loggingConsumers = Set(sources.compactMap { source in
            source.contents.contains("durableQueueAuthorityIfReadable(")
                ? source.relativePath
                : nil
        })
        #expect(loggingConsumers == [
            "OfflineSync/Persistence/OfflineQueueDurableAuthorityReader.swift",
            "OfflineSync/Services/BackgroundInference/OfflineQueueManager+InferenceRecovery.swift"
        ])
    }

    @Test func crossSurfaceMissingAndFailureSemanticsStayDistinct() throws {
        let support = try source(
            "Database/BackgroundDatabaseActor+ScanRecordSupport.swift"
        )
        let goalHints = try source(
            "OfflineSync/Persistence/ModelContext+FieldTripGoalHints.swift"
        )
        let queueState = try source(
            "OfflineSync/Services/QueueMaintenance/OfflineQueueManager+QueueState.swift"
        )
        let queueDeletion = try source(
            "OfflineSync/Services/QueueMaintenance/OfflineQueueManager+QueueDeletion.swift"
        )
        let cloudDeletion = try source(
            "OfflineSync/Services/CloudDeletion/OfflineQueueManager+CloudDeletionSync.swift"
        )
        let repository = try source("Database/ScanRepository.swift")

        #expect(support.contains(
            "func localScanRecord(id recordId: String) throws"
        ))
        #expect(support.contains(
            "func preservedScanRecordFieldNotes(scanId: String) throws"
        ))
        #expect(goalHints.contains(
            "func preferredGoalHint(\n        scanId: String\n    ) throws"
        ))
        #expect(goalHints.contains(
            "func deletePreferredGoalHint(scanId: String) throws"
        ))
        #expect(!queueState.contains("try? context.fetchOfflineJob"))
        #expect(!queueDeletion.contains("try? context.fetchOfflineJob"))
        #expect(!cloudDeletion.contains("try? context.fetchOfflineJob"))
        #expect(!repository.contains("try? modelContext.fetch"))
        #expect(!repository.contains("(try? modelContext.fetch"))
        #expect(repository.contains(
            "func reconcileScanPage(\n        responses: [HistoricalScanResponse]\n    ) throws -> Int"
        ))
        #expect(repository.contains(
            "func syncCollectionsDown(\n        remoteCollections: [CloudCollectionResponse]\n    ) throws"
        ))
        #expect(repository.contains(
            "private func saveHistoricalContext(_ logContext: String) throws"
        ))
        #expect(!repository.contains("_ = saveHistoricalContext"))
        #expect(!repository.contains("if Task.isCancelled { break }"))
        #expect(repository.contains(
            "try Task.checkCancellation()\n        for (_, obsolete) in existingLookup"
        ))
        #expect(repository.contains(
            "try Task.checkCancellation()\n        try saveHistoricalContext(\"syncCollections inbound reconciliation\")"
        ))
    }

    private func source(_ relativePath: String) throws -> String {
        try DatabaseActorTestSupport.loadRepositorySource(
            at: "\(Self.coreDataDirectory)/\(relativePath)"
        )
    }

    private func imports(in source: String) -> Set<String> {
        Set(source.split(separator: "\n").compactMap { line in
            line.hasPrefix("import ") ? String(line) : nil
        })
    }

    private func occurrences(of token: String, in source: String) -> Int {
        source.components(separatedBy: token).count - 1
    }

    private static let coreDataDirectory = "apps/ios/Merian/Core/Data"
    private static let databaseDirectory = "\(coreDataDirectory)/Database"
    private static let silentFetchPattern =
        #"try\?\s*(?:await\s+)?[A-Za-z_][A-Za-z0-9_]*\.(?:fetch|fetchCount)\s*\("#

    private static let expectedActorImports: [String: Set<String>] = [
        "BackgroundDatabaseActor.swift": ["import SwiftData"],
        "BackgroundDatabaseActor+BackgroundAccountWork.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "BackgroundDatabaseActor+CollectionSync.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "BackgroundDatabaseActor+InferenceLifecycle.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "BackgroundDatabaseActor+InferenceRetry.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "BackgroundDatabaseActor+LiveScanPersistence.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "BackgroundDatabaseActor+NonBiologicalRetention.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "BackgroundDatabaseActor+OfflineFinalization.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "BackgroundDatabaseActor+QueueSelection.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "BackgroundDatabaseActor+RetryMirror.swift": [],
        "BackgroundDatabaseActor+ScanRecordSupport.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "BackgroundDatabaseActor+SpeciesMetadata.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "BackgroundDatabaseActor+UploadLifecycle.swift": [
            "import Foundation",
            "import SwiftData"
        ]
    ]
}
