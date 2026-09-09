import Foundation
import Testing

@Suite("Background Database Actor Scan Finalization Architecture")
struct ScanFinalizationArchitectureTests {
    @Test func declarationsHaveFocusedOwners() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian"
        )

        for declaration in Self.declarationOwners {
            let owners = sources.compactMap { source -> String? in
                source.contents.contains(declaration.signature)
                    ? source.relativePath
                    : nil
            }.sorted()
            #expect(
                owners == [declaration.owner],
                "\(declaration.name) must have one focused owner"
            )
        }
    }

    @Test func focusedOwnersStayBoundedAndDependencyFocused() throws {
        for owner in Self.focusedOwners {
            let source = try DatabaseActorTestSupport.loadRepositorySource(
                at: owner.path
            )
            #expect(
                DatabaseActorTestSupport.lineCount(of: source)
                    <= owner.lineCeiling,
                "\(owner.path) exceeds its \(owner.lineCeiling)-line ceiling"
            )
        }

        let aggregate = try source(Self.aggregatePath)
        #expect(aggregate.contains("actor BackgroundDatabaseActor {}"))
        #expect(!aggregate.contains("func "))
        #expect(!aggregate.contains("extension BackgroundDatabaseActor"))

        for path in Self.persistencePaths {
            let persistence = try source(path)
            #expect(persistence.contains("BackgroundDatabaseActor"))
            for forbidden in Self.persistenceForbiddenDependencies {
                #expect(
                    !persistence.contains(forbidden),
                    "\(path) must not own \(forbidden)"
                )
            }
        }

        let media = try source(Self.mediaServicePath)
        #expect(media.contains("struct CapturedMediaPersistenceService"))
        #expect(media.contains("struct Dependencies: Sendable"))
        #expect(media.contains("FileIOActor.shared.persistAudioFile"))
        #expect(media.contains("FileIOActor.shared.persistVideoFile"))
        #expect(!media.contains("ModelContext"))
        #expect(!media.contains("BackgroundDatabaseActor"))

        let factory = try source(Self.recordFactoryPath)
        #expect(factory.contains("enum LocalScanRecordFactory"))
        #expect(factory.contains("static func makeRecord("))
        #expect(!factory.contains("modelContext"))
        #expect(!factory.contains(".shared"))

        let support = try source(Self.supportPath)
        #expect(support.contains(
            "func scanRecordSpeciesIdentity(\n        for scientificName: String\n    ) throws"
        ))
        #expect(support.contains(
            "func localScanRecord(id recordId: String) throws"
        ))
        #expect(support.contains(
            "func preservedScanRecordFieldNotes(scanId: String) throws"
        ))
        #expect(support.contains(
            "func insertOfflineScanRecordIfMissing("
        ))
        #expect(support.contains(") async throws"))
        #expect(!support.contains("existingRecords = []"))
        #expect(!support.contains("return nil\n        } catch"))

        let finalization = try source(Self.finalizationServicePath)
        #expect(finalization.contains(
            "struct BackgroundInferenceFinalizationService: Sendable"
        ))
        #expect(finalization.contains(
            "InferenceResponsePreparationService.live.prepare("
        ))
        #expect(finalization.contains(
            ".persistOfflineScanResultAssumingPersistenceLock("
        ))
        for forbidden in [
            "import SwiftData",
            "JSONDecoder",
            "EntitlementManager",
            "UsageManager",
            "ModelContext",
            "FileIOActor"
        ] {
            #expect(!finalization.contains(forbidden))
        }
    }

    @Test func coordinationStateAndReleaseBoundaryStayContained() throws {
        let coordinators = try source(Self.coordinatorsPath)
        #expect(coordinators.contains("actor ScanFinalizationCoordinator"))
        #expect(coordinators.contains(
            "actor ScanInferencePersistenceCoordinator"
        ))
        #expect(
            coordinators.components(
                separatedBy: "private var activeScanIds"
            ).count == 3
        )
        #expect(
            coordinators.components(
                separatedBy: "private var waitersByScanId"
            ).count == 3
        )

        let finalization = try source(Self.finalizationServicePath)
        let acquire = try #require(finalization.range(
            of: "ScanInferencePersistenceCoordinator.shared.acquire("
        ))
        let work = try #require(finalization.range(
            of: "let result = await processAssumingPersistenceLock("
        ))
        let release = try #require(finalization.range(
            of: "ScanInferencePersistenceCoordinator.shared.release("
        ))
        #expect(acquire.lowerBound < work.lowerBound)
        #expect(work.lowerBound < release.lowerBound)
        #expect(
            finalization.components(
                separatedBy: "ScanInferencePersistenceCoordinator.shared.acquire("
            ).count == 2
        )
        #expect(
            finalization.components(
                separatedBy: "ScanInferencePersistenceCoordinator.shared.release("
            ).count == 2
        )

        let offlinePersistence = try source(Self.offlinePersistencePath)
        let finalizationAcquire = try #require(offlinePersistence.range(
            of: "await acquireScanFinalizationLock("
        ))
        let cancellationFence = try #require(offlinePersistence.range(
            of: "guard !Task.isCancelled else { return .notProcessed }",
            range: finalizationAcquire.upperBound..<offlinePersistence.endIndex
        ))
        let recordLookup = try #require(offlinePersistence.range(
            of: "try localScanRecord(id: recordId)",
            range: cancellationFence.upperBound..<offlinePersistence.endIndex
        ))
        #expect(finalizationAcquire.lowerBound < cancellationFence.lowerBound)
        #expect(cancellationFence.lowerBound < recordLookup.lowerBound)

    }

    @Test func foregroundAndBackgroundShareResponsePreparation() throws {
        let inference = try source(Self.inferenceProcessingPath)
        let preparation = try source(Self.responsePreparationPath)
        let finalization = try source(Self.finalizationServicePath)
        let resultModels = try source(Self.resultModelsPath)

        #expect(inference.contains(
            "InferenceResponsePreparationService.live"
        ))
        #expect(inference.contains("struct ParseAndSaveResult: Sendable"))
        #expect(preparation.contains("func prepare("))
        #expect(preparation.contains("await reconcileEntitlement("))
        #expect(preparation.contains(
            "struct InferenceResponsePreparationService: Sendable"
        ))
        #expect(preparation.contains("struct PreparedResponse: Sendable"))
        #expect(!preparation.contains("@unchecked Sendable"))
        #expect(!preparation.contains("actor InferenceResponsePreparationService"))
        #expect(!finalization.contains("InferenceProcessingActor.shared"))
        #expect(
            preparation.components(
                separatedBy: "JSONDecoder().decode("
            ).count == 2
        )
        #expect(
            preparation.components(
                separatedBy: "SpeciesData(\n            fromEdgeResponse:"
            ).count == 2
        )
        #expect(finalization.contains("dependencies.decodeResponse("))
        #expect(!finalization.contains("SpeciesData("))
        #expect(resultModels.contains(
            "struct OfflineScanProcessingResult: Sendable"
        ))
    }

    @Test func existingBehavioralCoverageExercisesEverySeam() throws {
        let tests = try source(Self.integrationTestsPath)
        for testName in Self.requiredBehaviorTests {
            #expect(
                tests.contains("func \(testName)("),
                "Missing scan-finalization coverage for \(testName)"
            )
        }
        #expect(tests.contains("BackgroundInferenceFinalizationService"))
        #expect(tests.contains("saveLiveScanRecord("))
        #expect(tests.contains("saveNonVisualRecord("))
    }

    private func source(_ path: String) throws -> String {
        try DatabaseActorTestSupport.loadRepositorySource(at: path)
    }

    private static let aggregatePath =
        "apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor.swift"
    private static let livePersistencePath =
        "apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor+LiveScanPersistence.swift"
    private static let offlinePersistencePath =
        "apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor+OfflineFinalization.swift"
    private static let supportPath =
        "apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor+ScanRecordSupport.swift"
    private static let recordFactoryPath =
        "apps/ios/Merian/Core/Data/Database/LocalScanRecordFactory.swift"
    private static let coordinatorsPath =
        "apps/ios/Merian/Core/Data/Database/ScanPersistenceCoordinators.swift"
    private static let mediaServicePath =
        "apps/ios/Merian/Core/Data/CapturedMediaPersistenceService.swift"
    private static let finalizationServicePath =
        "apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundInference/BackgroundInferenceFinalizationService.swift"
    private static let inferenceProcessingPath =
        "apps/ios/Merian/Core/AI/InferenceProcessingActor.swift"
    private static let responsePreparationPath =
        "apps/ios/Merian/Core/AI/Inference/Services/InferenceResponsePreparationService.swift"
    private static let resultModelsPath =
        "apps/ios/Merian/Core/Data/OfflineSync/Models/ExtractedScanData.swift"
    private static let integrationTestsPath =
        "apps/ios/MerianTests/Core/Data/BackgroundDatabaseActorTests.swift"

    private static let persistencePaths = [
        livePersistencePath,
        offlinePersistencePath,
        supportPath
    ]

    private static let focusedOwners: [(path: String, lineCeiling: Int)] = [
        (aggregatePath, 20),
        (livePersistencePath, 350),
        (offlinePersistencePath, 250),
        (supportPath, 220),
        (recordFactoryPath, 150),
        (coordinatorsPath, 120),
        (mediaServicePath, 200),
        (finalizationServicePath, 200),
        (inferenceProcessingPath, 180),
        (responsePreparationPath, 150)
    ]

    private static let persistenceForbiddenDependencies = [
        "EdgeResponseWrapper",
        "EntitlementManager",
        "FileIOActor",
        "JSONDecoder",
        "UsageManager",
        "URLRequest",
        "URLSession",
        "import SwiftUI",
        "import UIKit"
    ]

    private struct DeclarationOwner {
        let name: String
        let signature: String
        let owner: String
    }

    private static let declarationOwners: [DeclarationOwner] = [
        .init(
            name: "BackgroundDatabaseActor",
            signature: "actor BackgroundDatabaseActor {}",
            owner: "Core/Data/Database/BackgroundDatabaseActor.swift"
        ),
        .init(
            name: "saveLiveScanRecord",
            signature: "func saveLiveScanRecord(",
            owner: "Core/Data/Database/BackgroundDatabaseActor+LiveScanPersistence.swift"
        ),
        .init(
            name: "saveNonVisualRecord",
            signature: "func saveNonVisualRecord(",
            owner: "Core/Data/Database/BackgroundDatabaseActor+LiveScanPersistence.swift"
        ),
        .init(
            name: "persistOfflineScanResultAssumingPersistenceLock",
            signature: "func persistOfflineScanResultAssumingPersistenceLock(",
            owner: "Core/Data/Database/BackgroundDatabaseActor+OfflineFinalization.swift"
        ),
        .init(
            name: "validateOrAdoptInferenceGenerationAssumingPersistenceLock",
            signature: "func validateOrAdoptInferenceGenerationAssumingPersistenceLock(",
            owner: "Core/Data/Database/BackgroundDatabaseActor+OfflineFinalization.swift"
        ),
        .init(
            name: "CapturedMediaPersistenceService",
            signature: "struct CapturedMediaPersistenceService: Sendable",
            owner: "Core/Data/CapturedMediaPersistenceService.swift"
        ),
        .init(
            name: "LocalScanRecordFactory",
            signature: "enum LocalScanRecordFactory",
            owner: "Core/Data/Database/LocalScanRecordFactory.swift"
        ),
        .init(
            name: "ScanFinalizationCoordinator",
            signature: "actor ScanFinalizationCoordinator",
            owner: "Core/Data/Database/ScanPersistenceCoordinators.swift"
        ),
        .init(
            name: "ScanInferencePersistenceCoordinator",
            signature: "actor ScanInferencePersistenceCoordinator",
            owner: "Core/Data/Database/ScanPersistenceCoordinators.swift"
        ),
        .init(
            name: "BackgroundInferenceFinalizationService",
            signature: "struct BackgroundInferenceFinalizationService: Sendable",
            owner: "Core/Data/OfflineSync/Services/BackgroundInference/BackgroundInferenceFinalizationService.swift"
        ),
        .init(
            name: "InferenceResponsePreparationService",
            signature: "struct InferenceResponsePreparationService: Sendable",
            owner: "Core/AI/Inference/Services/InferenceResponsePreparationService.swift"
        )
    ]

    private static let requiredBehaviorTests = [
        "staleLiveGenerationCannotPersistOverReplacementAttempt",
        "testProcessAndCleanupOfflineScanPreservesOriginalTimestamp",
        "testOfflineFinalizationRechecksExistingRecordAfterWaitingForSameScanLock",
        "cancelledOfflineFinalizationDoesNotPersistAfterWaitingForSameScanLock",
        "generatedBackgroundResultRejectsWrongScanId",
        "generatedBackgroundResultRejectsMalformedSuccessBody",
        "generatedConfidenceZeroBackgroundResultIsTerminal",
        "testSaveLiveScanRecordReplacesCollisionPreservingFieldNotesAndSpeciesId",
        "testSaveLiveScanRecordPreservesAudioBeforeImageTimeline",
        "testSaveNonVisualRecordSupportsAllowedCombinationMatrix",
        "testSaveLiveScanRecordSupportsAllowedVisualCombinationMatrix",
        "testOfflineFinalizationRejectsOlderPersistedGeneration"
    ]
}
