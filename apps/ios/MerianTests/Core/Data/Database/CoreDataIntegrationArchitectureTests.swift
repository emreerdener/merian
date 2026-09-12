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

    @Test func historicalSyncHasBoundedLayeredOwners() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: Self.historicalSyncDirectory
        )

        #expect(
            Set(sources.map(\.relativePath))
                == Set(Self.expectedHistoricalSyncImports.keys),
            "Historical sync ownership changed without an integration review"
        )
        for source in sources {
            #expect(
                DatabaseActorTestSupport.lineCount(of: source.contents) <= 600,
                "\(source.relativePath) exceeds the 600-line review ceiling"
            )
            #expect(
                imports(in: source.contents)
                    == Self.expectedHistoricalSyncImports[source.relativePath],
                "\(source.relativePath) has an unexpected dependency"
            )
        }

        let repository = try source("Database/ScanRepository.swift")
        #expect(DatabaseActorTestSupport.lineCount(of: repository) <= 600)
        #expect(imports(in: repository) == [
            "import Foundation",
            "import os",
            "import SwiftData"
        ])
        #expect(repository.contains(
            "private let historicalCloudClient = HistoricalSyncCloudClient.live"
        ))
        #expect(!repository.contains("SupabaseManager.shared"))
        #expect(!repository.contains(".from(\""))
        #expect(!repository.contains("import Supabase"))

        let models = try source(
            "Database/HistoricalSync/Models/HistoricalSyncModels.swift"
        )
        let decoder = try source(
            "Database/HistoricalSync/Decoding/HistoricalScanPageDecoder.swift"
        )
        let persistence = try source(
            "Database/HistoricalSync/Persistence/HistoricalDatabaseActor.swift"
        )
        let service = try source(
            "Database/HistoricalSync/Services/HistoricalSyncCloudClient.swift"
        )

        for declaration in [
            "struct HistoricalScanPageRequest: Equatable, Sendable",
            "struct HistoricalScanRecordRequest: Equatable, Sendable",
            "struct HistoricalCollectionPageRequest: Equatable, Sendable",
            "struct HistoricalScanResponse: Decodable, Sendable",
            "struct CloudCollectionResponse: Decodable, Sendable"
        ] {
            #expect(models.contains(declaration))
        }
        #expect(decoder.contains("enum HistoricalScanPageDecoder"))
        #expect(persistence.contains("actor HistoricalDatabaseActor"))
        #expect(!persistence.contains("reconcileAllHistoricalData"))
        #expect(!persistence.contains("SupabaseManager"))
        #expect(!persistence.contains("URLSession"))
        #expect(service.contains("struct HistoricalSyncCloudClient"))
        #expect(service.contains("static let live = HistoricalSyncCloudClient("))
        #expect(occurrences(of: ".from(\"scans\")", in: service) == 2)
        #expect(occurrences(of: ".from(\"collections\")", in: service) == 1)
        #expect(service.contains(".eq(\"user_id\", value: request.userID)"))
        #expect(service.contains(".order(\"timestamp\", ascending: false)"))
        #expect(service.contains(
            ".select(\"id, name, created_at, collection_scans(scan_id)\")"
        ))
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

    @Test func historicalSyncTestsMirrorTheLayeredOwners() throws {
        let historicalTests = try DatabaseActorTestSupport.swiftSources(
            below: Self.historicalSyncTestsDirectory
        )
        #expect(
            Set(historicalTests.map(\.relativePath))
                == Self.expectedHistoricalSyncTestFiles,
            "Historical sync tests changed ownership without an integration review"
        )

        for source in historicalTests {
            #expect(
                DatabaseActorTestSupport.lineCount(of: source.contents) <= 600,
                "\(source.relativePath) exceeds the 600-line review ceiling"
            )
        }

        let suiteRoot = try DatabaseActorTestSupport.loadRepositorySource(
            at: "\(Self.coreDataTestsDirectory)/ScanRepositoryTests.swift"
        )
        let deletion = try DatabaseActorTestSupport.loadRepositorySource(
            at: "\(Self.coreDataTestsDirectory)/ScanRepositoryDeletionTests.swift"
        )
        let ingestion = try DatabaseActorTestSupport.loadRepositorySource(
            at: "\(Self.historicalSyncTestsDirectory)/HistoricalScanIngestionTests.swift"
        )
        let persistence = try DatabaseActorTestSupport.loadRepositorySource(
            at: "\(Self.coreDataTestsDirectory)/ScanRepositoryModelPersistenceTests.swift"
        )
        let cloudClient = try DatabaseActorTestSupport.loadRepositorySource(
            at: "\(Self.historicalSyncTestsDirectory)/HistoricalSyncCloudClientTests.swift"
        )

        #expect(suiteRoot.contains("struct ScanRepositoryTests {}"))
        #expect(deletion.contains("extension ScanRepositoryTests"))
        #expect(!deletion.contains("testIngestScansTimestampGuard"))
        #expect(ingestion.contains(
            "testIngestScansTimestampGuardSkipsNilAndUnparseableTimestamps"
        ))
        #expect(ingestion.contains(
            "try await actor.reconcileScanPage("
        ))
        #expect(persistence.contains("extension ScanRepositoryTests"))
        #expect(cloudClient.contains("struct HistoricalSyncCloudClientTests"))
        #expect(cloudClient.contains(
            "forwardsLeaseAndRequestValuesThroughInjectedHandlers"
        ))
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
        let historicalPersistence = try source(
            "Database/HistoricalSync/Persistence/HistoricalDatabaseActor.swift"
        )

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
        #expect(historicalPersistence.contains(
            "func reconcileScanPage(\n        responses: [HistoricalScanResponse]\n    ) throws -> Int"
        ))
        #expect(historicalPersistence.contains(
            "func syncCollectionsDown(\n        remoteCollections: [CloudCollectionResponse]\n    ) throws"
        ))
        #expect(historicalPersistence.contains(
            "private func saveHistoricalContext(_ logContext: String) throws"
        ))
        #expect(!historicalPersistence.contains("_ = saveHistoricalContext"))
        #expect(!historicalPersistence.contains("if Task.isCancelled { break }"))
        #expect(historicalPersistence.contains(
            "try Task.checkCancellation()\n        for (_, obsolete) in existingLookup"
        ))
        #expect(historicalPersistence.contains(
            "try Task.checkCancellation()\n        try saveHistoricalContext(\"syncCollections inbound reconciliation\")"
        ))
    }

    @Test func rescuedMediaRegistrationIsPostStartupBoundedAndThrowing() throws {
        let app = try DatabaseActorTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/App/MerianApp.swift"
        )
        let repository = try source("Database/ScanRepository.swift")
        let registration = try source(
            "Images/Services/ScanMediaRecoveryRegistrationService.swift"
        )

        #expect(!app.contains(
            "LocalScanMediaRecoveryResolver.hasLegacyRecoveryIndex"
        ))
        #expect(!app.contains("(try? mainContext.fetch(descriptor)) ?? []"))
        #expect(repository.contains(
            "scheduleLocalMediaRecoveryRegistration(for: modelContext)"
        ))
        #expect(repository.contains(
            "previousRegistrationTask?.cancel()"
        ))
        #expect(repository.contains(
            "await previousRegistrationTask?.value"
        ))
        #expect(repository.contains(
            ".resetRegisteredRecoveryMappings()"
        ))
        #expect(repository.contains(
            "currentContainer === expectedContainer"
        ))
        #expect(registration.contains(
            "return try context.fetch(descriptor)"
        ))
        #expect(registration.contains(
            "descriptor.fetchLimit = limit"
        ))
        #expect(registration.contains(
            "private static let maximumBatchSize = 200"
        ))
        #expect(registration.contains("ordering: .scanID"))
        #expect(registration.contains("ordering: .timestampThenScanID"))
        #expect(registration.contains("try Task.checkCancellation()"))
        #expect(!registration.contains("try?"))
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
    private static let historicalSyncDirectory =
        "\(databaseDirectory)/HistoricalSync"
    private static let coreDataTestsDirectory =
        "apps/ios/MerianTests/Core/Data"
    private static let historicalSyncTestsDirectory =
        "\(coreDataTestsDirectory)/HistoricalSync"
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

    private static let expectedHistoricalSyncImports: [String: Set<String>] = [
        "HistoricalSyncPolicy.swift": [],
        "Decoding/HistoricalScanPageDecoder.swift": [
            "import Foundation",
            "import Supabase"
        ],
        "Models/HistoricalSyncModels.swift": [
            "import Foundation"
        ],
        "Persistence/HistoricalDatabaseActor.swift": [
            "import Foundation",
            "import os",
            "import SwiftData"
        ],
        "Services/HistoricalSyncCloudClient.swift": [
            "import Foundation",
            "import Supabase"
        ]
    ]

    private static let expectedHistoricalSyncTestFiles: Set<String> = [
        "HistoricalScanDecodingTests.swift",
        "HistoricalScanIngestionTests.swift",
        "HistoricalScanReconciliationTests.swift",
        "HistoricalSyncPolicyTests.swift",
        "HistoricalSyncCloudClientTests.swift"
    ]
}
