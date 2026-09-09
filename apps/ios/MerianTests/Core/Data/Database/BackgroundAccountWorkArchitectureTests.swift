import Foundation
import Testing

@Suite("Background Database Actor Background Account Work Architecture")
struct BackgroundAccountWorkArchitectureTests {
    @Test func backgroundAccountWorkDeclarationsHaveOneFocusedOwner() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian"
        )

        for method in Self.backgroundAccountWorkMethods {
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

        for helper in Self.privateHelpers {
            let owners = sources.compactMap { source -> String? in
                source.contents.contains(helper)
                    ? source.relativePath
                    : nil
            }.sorted()
            #expect(
                owners == [Self.productionRelativePath],
                "\(helper) must remain private to background-account persistence"
            )
        }
    }

    @Test func focusedOwnerStaysBoundedAndPersistenceOnly() throws {
        let source = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.productionSourcePath
        )
        let aggregate = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.aggregateSourcePath
        )

        #expect(source.contains("extension BackgroundDatabaseActor"))
        #expect(
            DatabaseActorTestSupport.lineCount(of: source) <= 400,
            "Background-account persistence exceeds the 400-line ceiling"
        )
        #expect(
            DatabaseActorTestSupport.lineCount(of: aggregate) <= 1_600,
            "The residual BackgroundDatabaseActor aggregate must not regrow"
        )

        let imports = Set(source.split(separator: "\n").compactMap { line in
            line.hasPrefix("import ") ? String(line) : nil
        })
        #expect(imports == ["import Foundation", "import SwiftData"])
        #expect(!source.contains("try? modelContext.fetch"))
        #expect(
            source.components(
                separatedBy: "try modelContext.fetchOfflineJob("
            ).count == 4,
            "Each account-work decision must distinguish lookup failure from absence"
        )

        for forbidden in Self.forbiddenDependencies {
            #expect(
                !source.contains(forbidden),
                "Background-account persistence must not own \(forbidden)"
            )
        }
    }

    @Test func serializedActivationAndRetirementKeepBalancedFences() throws {
        let source = try DatabaseActorTestSupport.loadRepositorySource(
            at: Self.productionSourcePath
        )

        #expect(
            source.components(
                separatedBy: "ScanInferencePersistenceCoordinator.shared.acquire("
            ).count == 3,
            "Activation and retirement must both acquire the per-scan fence"
        )
        #expect(
            source.components(
                separatedBy: "ScanInferencePersistenceCoordinator.shared.release("
            ).count == 4,
            "Every activation exit and retirement must release the per-scan fence"
        )
        #expect(
            source.contains(
                "guard !Task.isCancelled else {\n" +
                    "            await ScanInferencePersistenceCoordinator.shared.release("
            ),
            "Cancelled activation must release its acquired persistence fence"
        )
    }

    @Test func consumersStayAtOfflineSyncBoundaries() throws {
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
                "struct BackgroundAccountWorkPersistenceTests"
            )
        )
        #expect(
            focusedTests.contains("\"Background Account Work Persistence\"")
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
            DatabaseActorTestSupport.lineCount(of: focusedTests) <= 400,
            "BackgroundAccountWorkPersistenceTests.swift exceeds the 400-line ceiling"
        )
    }

    private static let aggregateSourcePath =
        "apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor.swift"

    private static let productionSourcePath =
        "apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor+BackgroundAccountWork.swift"

    private static let productionRelativePath =
        "Core/Data/Database/BackgroundDatabaseActor+BackgroundAccountWork.swift"

    private static let behaviorTestsPath =
        "apps/ios/MerianTests/Core/Data/Database/BackgroundAccountWorkPersistenceTests.swift"

    private static let behaviorTestRelativePath =
        "Core/Data/Database/BackgroundAccountWorkPersistenceTests.swift"

    private static let backgroundAccountWorkMethods: [(
        name: String,
        signature: String
    )] = [
        (
            "activateBackgroundAccountWork",
            "func activateBackgroundAccountWork("
        ),
        (
            "backgroundAccountWorkIsCurrent",
            "func backgroundAccountWorkIsCurrent("
        ),
        (
            "backgroundAccountWorkCandidates",
            "func backgroundAccountWorkCandidates("
        ),
        (
            "retireBackgroundAccountWork",
            "func retireBackgroundAccountWork("
        )
    ]

    private static let privateHelpers = [
        "private func activateBackgroundAccountWorkLocked(",
        "private func retireBackgroundAccountWorkLocked(",
        "private func clearBackgroundAccountWorkMetadataIfNeeded("
    ]

    private static let consumerAllowlist: [(
        call: String,
        expected: [String]
    )] = [
        (
            ".activateBackgroundAccountWork(",
            [
                "Core/Data/OfflineSync/Services/BackgroundInference/OfflineQueueManager+InferenceDispatch.swift",
                "Core/Data/OfflineSync/Services/BackgroundTransfer/OfflineQueueManager+BackgroundTerminalRouting.swift",
                "Core/Data/OfflineSync/Services/MediaUpload/OfflineQueueManager+UploadDispatch.swift"
            ]
        ),
        (
            ".backgroundAccountWorkIsCurrent(",
            [
                "Core/Data/OfflineSync/Services/BackgroundTransfer/OfflineQueueManager+BackgroundTerminalRouting.swift"
            ]
        ),
        (
            ".backgroundAccountWorkCandidates(",
            [
                "Core/Data/OfflineSync/Services/BackgroundTransfer/OfflineQueueManager+BackgroundAccountWork.swift"
            ]
        ),
        (
            ".retireBackgroundAccountWork(",
            [
                "Core/Data/OfflineSync/Services/BackgroundTransfer/OfflineQueueManager+BackgroundAccountWork.swift",
                "Core/Data/OfflineSync/Services/MediaUpload/OfflineQueueManager+UploadDispatch.swift"
            ]
        )
    ]

    private static let behaviorTests = [
        "accountBoundBackgroundWorkRetiresBeforeTransportCancellation",
        "rejectedInferenceDispatchDurablyRequeuesBeforeCancellation",
        "exactUploadOwnerRetiresStagedCallbackRace",
        "activationCreatesAJobForALegacyScanWithoutOne"
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
