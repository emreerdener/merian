import Foundation
import Testing

@Suite("Models Integration Architecture")
struct ModelsIntegrationArchitectureTests {
    @Test func historyStorageHasFencedAdmissionOwnersAndNoOrdinaryScheduling() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(below: "apps/ios/Merian")
        for source in sources {
            let code = codeLines(in: source.contents)
            let admissionOwner = source.relativePath == "Core/Data/AnalysisHistory/ObservationHistorySyncService.swift"
            let stateOwner = source.relativePath == "Core/Data/AnalysisHistory/ObservationHistoryStateSyncService.swift"
            let enrollmentOwner = source.relativePath == "Core/Data/AnalysisHistory/ObservationHistoryEnrollmentService.swift"
            let stateModel = source.relativePath == "Models/ActiveSchema/LocalAnalysisStateRecord.swift"
            let cacheOwner = source.relativePath == "Core/Data/AnalysisHistory/ObservationHistoryStateCache.swift"
            if !cacheOwner {
                #expect(code.range(of: #"LocalAnalysisStateRecord\s*(?:\(|\.init\b)"#, options: .regularExpression) == nil,
                        "Only fenced cache admission may create analysis state: \(source.relativePath)")
            }
            if !admissionOwner {
                #expect(code.range(of: #"LocalAnalysisRecord\s*(?:\(|\.init\b)"#, options: .regularExpression) == nil, "Only enrolled account-bound admission may write history: \(source.relativePath)")
            }
            let historyAdapter = source.relativePath == "Features/Insights/History/Services/IdentificationHistoryDependencies.swift"
            let listingOwner = source.relativePath == "Core/Data/AnalysisHistory/ObservationHistoryListingService.swift"
            if !listingOwner {
                #expect(code.range(of: #"ObservationHistorySyncService\s*\("#, options: .regularExpression) == nil,
                    "Normal history scheduling remains behind the activation hold: \(source.relativePath)")
            }
            if !historyAdapter {
                #expect(code.range(of: #"ObservationHistoryStateSyncService\s*\("#, options: .regularExpression) == nil,
                    "Normal state scheduling remains behind the activation hold: \(source.relativePath)")
            #expect(code.range(of: #"ObservationHistoryPreviewService\s*\("#, options: .regularExpression) == nil,
                    "Normal preview presentation remains behind the activation hold: \(source.relativePath)")
            }
            #expect(code.range(of: #"ObservationHistoryEnrollmentService\s*\("#, options: .regularExpression) == nil,
                    "Normal enrollment remains behind the activation hold: \(source.relativePath)")
            if !historyAdapter {
                #expect(code.range(of: #"ObservationHistorySelectionService\s*\("#, options: .regularExpression) == nil,
                    "Normal Restore/Undo remains behind the activation hold: \(source.relativePath)")
            }
            for field in ["analysisRecords", "selectedAnalysisID", "analysisOwnerAccountID",
                          "observationStateRevision", "analysisSelectionInitialized"] {
                if admissionOwner && field == "analysisRecords" { continue }
                if enrollmentOwner && ["selectedAnalysisID", "analysisOwnerAccountID", "observationStateRevision"].contains(field) { continue }
                if (stateOwner || stateModel) && field == "observationStateRevision" { continue }
                if stateOwner && field == "selectedAnalysisID" { continue }
                #expect(code.range(of: "\\.\(field)\\s*=(?!=)", options: .regularExpression) == nil, "History selection/enrollment is still disabled: \(source.relativePath)")
            }
        }
    }

    @Test func rootValuesRemainFocusedAndEffectFree() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian/Models"
        )
        let rootSources = sources.filter { !$0.relativePath.contains("/") }

        #expect(rootSources.map(\.relativePath) == Self.rootSourcePaths)

        for path in Self.rootValuePaths {
            let source = try source(at: "apps/ios/Merian/Models/\(path)")
            let code = codeLines(in: source)
            #expect(imports(in: source) == ["import Foundation"])
            for token in Self.forbiddenRootValueEffects {
                #expect(
                    !code.contains(token),
                    "Models/\(path) must not resolve \(token)"
                )
            }
        }
    }

    @Test func activeSchemaOwnsModelsWithoutPersistenceWorkflows() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian/Models/ActiveSchema"
        )

        #expect(sources.map(\.relativePath) == Self.activeSchemaPaths)
        for source in sources {
            let code = codeLines(in: source.contents)
            #expect(
                imports(in: source.contents) == [
                    "import Foundation",
                    "import SwiftData"
                ],
                "Unexpected imports in ActiveSchema/\(source.relativePath)"
            )
            #expect(
                DatabaseActorTestSupport.lineCount(of: source.contents) <= 600,
                "ActiveSchema/\(source.relativePath) exceeds the review ceiling"
            )
            for token in Self.forbiddenActiveSchemaEffects {
                #expect(
                    !code.contains(token),
                    "ActiveSchema/\(source.relativePath) must not own \(token)"
                )
            }
        }
    }

    @Test func crossLayerAdaptersHaveSingleOwners() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian"
        )

        for expectation in Self.declarationOwners {
            let owners = sources.compactMap { source in
                source.contents.contains(expectation.token)
                    ? source.relativePath
                    : nil
            }
            #expect(
                owners == [expectation.path],
                "\(expectation.token) owners: \(owners)"
            )
        }

        let queuedContext = try source(
            at: "apps/ios/Merian/Models/QueuedScanContext.swift"
        )
        let queuedContextCode = codeLines(in: queuedContext)
        #expect(queuedContextCode.contains("approximateQueuedBytes: Int64"))
        #expect(!queuedContextCode.contains("ActiveScanMedia"))
        #expect(!queuedContextCode.contains("IdentifyVisualMediaItem"))
        #expect(!queuedContextCode.contains("FileManager"))
        #expect(!queuedContextCode.contains("OfflineQueuedScan"))

        let queuedProjection = try source(
            at: "apps/ios/Merian/Core/Data/OfflineSync/Persistence/" +
                "OfflineQueueManager+QueuedScanExtraction.swift"
        )
        #expect(
            queuedProjection.contains(
                "@MainActor\n    func queuedScanContext()"
            )
        )
    }

    @Test func nonhistoricalModelsStayBoundedWithExplicitRegistryException() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian/Models"
        )
        let boundedSources = sources.filter {
            !$0.relativePath.hasPrefix("Schema/")
                && $0.relativePath != "SchemaVersions.swift"
        }

        for source in boundedSources {
            #expect(
                DatabaseActorTestSupport.lineCount(of: source.contents) <= 600,
                "Models/\(source.relativePath) exceeds the review ceiling"
            )
        }

        let registry = try source(
            at: "apps/ios/Merian/Models/SchemaVersions.swift"
        )
        #expect(registry.contains("enum MerianMigrationPlan"))
        #expect(registry.contains("enum MerianSchemaV51"))
        let currentSchema = try source(at: "apps/ios/Merian/Models/Schema/SchemaV57.swift")
        #expect(currentSchema.contains("enum MerianSchemaV57"))
        #expect(registry.contains("migrateV56toV57"))
    }

    @Test func historyPresentationRemainsAnExplicitClosedConsumer() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(below: "apps/ios/Merian")
        for entry in sources {
            #expect(!codeLines(in: entry.contents).contains("IdentificationHistoryAccess.prepared"))
        }
        let shell = try source(at: "apps/ios/Merian/Features/Insights/Shell/Services/InsightShellDependencies.swift")
        #expect(shell.contains("var historyAccess: IdentificationHistoryAccess? = nil"))
        #expect(shell.contains("#if DEBUG\n        result.historyAccess = UITestSeedCoordinator.identificationHistoryAccess\n        #endif"))
        let fixture = try source(at: "apps/ios/Merian/App/UITesting/UITestSeedCoordinator+IdentificationHistory.swift")
        #expect(fixture.contains("#if DEBUG"))
        #expect(fixture.contains("-seedIdentificationHistory"))
        #expect(fixture.contains("guard isEnabled"))
    }

    private func source(at relativePath: String) throws -> String {
        try DatabaseActorTestSupport.loadRepositorySource(at: relativePath)
    }

    private func imports(in source: String) -> [String] {
        source.split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("import ") }
    }

    /// Removes full-line comments before effect-token checks so ownership
    /// documentation may name the source model without becoming executable
    /// coupling. The guarded model files use line comments for documentation.
    private func codeLines(in source: String) -> String {
        source.split(separator: "\n")
            .map(String.init)
            .filter {
                !$0.trimmingCharacters(in: .whitespaces)
                    .hasPrefix("//")
            }
            .joined(separator: "\n")
    }

    private static let rootSourcePaths = [
        "Aliases.swift",
        "QueuedScanContext.swift",
        "ScanQueueState.swift",
        "SchemaVersions.swift",
        "UserReviewState.swift"
    ]

    private static let rootValuePaths = [
        "QueuedScanContext.swift",
        "ScanQueueState.swift",
        "UserReviewState.swift"
    ]

    private static let activeSchemaPaths = [
        "CapturedMediaEntry.swift",
        "LocalAnalysisRecord.swift",
        "LocalAnalysisStateRecord.swift",
        "LocalScanRecord.swift",
        "OfflineJobRecord.swift",
        "OfflineQueueEvent.swift",
        "OfflineQueuedScan.swift",
        "PendingCloudDeletionTask.swift",
        "ScanCollection.swift",
        "UserSpeciesPreference.swift"
    ]

    private static let forbiddenRootValueEffects = [
        "ActiveScanMedia",
        "AppDIContainer.",
        "FileManager.",
        "IdentifyVisualMediaItem",
        "MerianNetworkClient.",
        "ModelContext(",
        "OfflineQueuedScan",
        "SupabaseManager.",
        "= Task {",
        "URLSession."
    ]

    private static let forbiddenActiveSchemaEffects = [
        "AppDIContainer.",
        "extension ModelContext",
        "FetchDescriptor<",
        "FileManager.",
        "MerianNetworkClient.",
        "SupabaseManager.",
        "= Task {",
        "URLSession."
    ]

    private static let declarationOwners: [(token: String, path: String)] = [
        (
            "struct QueuedScanContext: Identifiable, Equatable, Sendable",
            "Models/QueuedScanContext.swift"
        ),
        (
            "public enum ScanQueueState: Int, Sendable",
            "Models/ScanQueueState.swift"
        ),
        (
            "public enum UserReviewState: String, Codable, Sendable",
            "Models/UserReviewState.swift"
        ),
        (
            "extension QueuedScanContext {\n    var activeScanMedia",
            "Features/Insights/Shell/ViewModels/" +
                "InsightSheetViewModel+MediaPresentation.swift"
        ),
        (
            "static func queuedMediaBytes(",
            "Core/Data/OfflineSync/Policies/OfflineQueueStoragePolicy.swift"
        ),
        (
            "func queuedScanContext() -> QueuedScanContext",
            "Core/Data/OfflineSync/Persistence/" +
                "OfflineQueueManager+QueuedScanExtraction.swift"
        ),
        (
            "func ensurePendingCloudDeletionTask(",
            "Core/Data/OfflineSync/Persistence/ModelContext+OfflineJobs.swift"
        )
    ]
}
