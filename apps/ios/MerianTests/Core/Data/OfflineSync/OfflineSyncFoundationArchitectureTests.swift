import Foundation
import Testing

@Suite("Offline Sync Foundation Architecture")
struct OfflineSyncFoundationArchitectureTests {
    @Test func declarationsHaveFocusedOwners() throws {
        let root = try offlineSyncRoot()
        let sources = try swiftFiles(below: root)

        for (declaration, expectedPath) in Self.declarationOwners {
            let owners = try sources.compactMap { file -> String? in
                let source = try contents(of: file)
                guard containsDeclaration(declaration, in: source) else {
                    return nil
                }
                return relativePath(of: file, below: root)
            }
            #expect(owners == [expectedPath])
        }

        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent("OfflineSyncTypes.swift").path
            )
        )
    }

    @Test func extractedOwnersStayBoundedAndDependencyFocused() throws {
        let root = try offlineSyncRoot()

        for path in Self.extractedOwnerPaths {
            let file = root.appendingPathComponent(path)
            let source = try contents(of: file)
            #expect(
                lineCount(of: source) <= 600,
                "\(path) exceeds the 600-line review ceiling"
            )
            #expect(
                imports(in: source) == Self.expectedImportsByPath[path],
                "\(path) has an unexpected framework dependency"
            )
        }

        let focusedOwnerPaths = try swiftFiles(below: root).compactMap { file -> String? in
            let path = relativePath(of: file, below: root)
            let components = path.split(separator: "/")
            guard components.count == 2,
                  let directory = components.first,
                  Self.focusedOwnerDirectories.contains(String(directory))
            else {
                return nil
            }
            return path
        }
        #expect(
            Set(focusedOwnerPaths)
                == Self.extractedOwnerPaths.subtracting([
                    "OfflineQueueDurability.swift"
                ]),
            "A focused owner was added or removed without updating its architecture guard"
        )
        #expect(
            Set(Self.expectedImportsByPath.keys) == Self.extractedOwnerPaths,
            "Every bounded owner must declare its exact framework imports"
        )

        for path in Self.modelAndPolicyPaths {
            let source = try contents(of: root.appendingPathComponent(path))
            #expect(!source.contains("SupabaseManager.shared"))
            #expect(!source.contains("AppDIContainer.shared"))
            #expect(!source.contains("RevenueCatManager.shared"))
            #expect(!source.contains("MerianNetworkClient"))
            #expect(!source.contains("URLSession.shared"))
            #expect(!source.contains("@Observable"))
            #expect(!source.contains("Task.detached"))
        }
    }

    @Test func mutableTaskAndPrivateDiagnosticsRemainContained() throws {
        let root = try offlineSyncRoot()
        let registry = try contents(
            of: root.appendingPathComponent(
                "Coordinators/GenerationTaskRegistry.swift"
            )
        )
        let diagnostics = try contents(
            of: root.appendingPathComponent(
                "Services/OfflineQueueManager+Diagnostics.swift"
            )
        )
        let durability = try contents(
            of: root.appendingPathComponent("OfflineQueueDurability.swift")
        )

        #expect(registry.contains("@MainActor"))
        #expect(registry.contains("private struct Entry"))
        #expect(registry.contains("private var entries"))
        #expect(diagnostics.contains("private struct OfflineQueueDiagnosticsExport"))
        #expect(diagnostics.contains("private enum OfflineQueueDiagnosticsExportPolicy"))
        #expect(diagnostics.contains("private func pruneOfflineQueueEvents"))
        #expect(!durability.contains("enum OfflineQueueRetryPolicy"))
        #expect(!durability.contains("enum OfflineQueueStoragePolicy"))
        #expect(!durability.contains("struct OfflineQueueDiagnosticsExport"))
        #expect(
            durability.contains(
                "guard scan.queueState != .externalImport else { return false }"
            )
        )
    }

    @Test func queuedScanExtractionTestsMirrorOwner() throws {
        let repository = try repositoryRoot()
        let focusedTests = try contents(
            of: repository.appendingPathComponent(
                "apps/ios/MerianTests/Core/Data/OfflineSync/QueuedScanExtractionTests.swift"
            )
        )
        let legacyAggregate = try contents(
            of: repository.appendingPathComponent(
                "apps/ios/MerianTests/Core/Data/OfflineQueueManagerTests.swift"
            )
        )

        #expect(focusedTests.contains("struct QueuedScanExtractionTests"))
        #expect(focusedTests.contains("\"Queued Scan Extraction\""))
        #expect(!focusedTests.contains(".sharedProcessState"))
        for declaration in Self.queuedScanExtractionTestDeclarations {
            #expect(focusedTests.contains(declaration))
            #expect(!legacyAggregate.contains(declaration))
        }
        #expect(
            lineCount(of: focusedTests) <= 600,
            "QueuedScanExtractionTests.swift exceeds the 600-line review ceiling"
        )
    }

    @Test func queuedScanExtractionDependenciesRemainExplicit() throws {
        let root = try offlineSyncRoot()
        let extraction = try contents(
            of: root.appendingPathComponent(
                "Persistence/OfflineQueueManager+QueuedScanExtraction.swift"
            )
        )
        let sources = try swiftFiles(below: root)

        #expect(!extraction.contains("OfflineQueueManager.shared"))
        #expect(!extraction.contains("AppDIContainer.shared"))
        #expect(!extraction.contains("MerianNetworkClient"))
        #expect(!extraction.contains("URLSession"))

        let preferredGoalConsumers = try sources.compactMap { file -> String? in
            let source = try contents(of: file)
            guard source.contains("preferredGoalHint") else { return nil }
            return relativePath(of: file, below: root)
        }
        #expect(Set(preferredGoalConsumers) == Self.preferredGoalHintConsumers)

        let extractionConsumers = try sources.compactMap { file -> String? in
            let source = try contents(of: file)
            guard source.contains("buildExtractedScanData") else { return nil }
            return relativePath(of: file, below: root)
        }
        #expect(Set(extractionConsumers) == Self.queuedScanExtractionConsumers)
    }

    private static let declarationOwners: [String: String] = [
        "struct CollectionSyncSnapshot":
            "Models/CollectionSyncSnapshot.swift",
        "struct PendingScanPayload": "Models/OfflineScanPayloads.swift",
        "enum StagedMediaKind": "Models/MediaStagingModels.swift",
        "enum StagingUploadPurpose": "Models/MediaStagingModels.swift",
        "struct StagedMediaObjectKeys": "Models/MediaStagingModels.swift",
        "struct MediaStagingUploadTaskIdentity":
            "Models/MediaStagingModels.swift",
        "struct MediaStagingUploadCompletionState":
            "Models/MediaStagingModels.swift",
        "struct StagingUploadFile": "Models/MediaStagingModels.swift",
        "struct ScanUploadItem": "Models/MediaStagingModels.swift",
        "struct MediaStagingPreparation": "Models/MediaStagingModels.swift",
        "struct InferenceURLSessionTaskIdentity":
            "Models/InferenceOwnershipModels.swift",
        "struct InferenceGenerationExpectation":
            "Models/InferenceOwnershipModels.swift",
        "struct ForegroundInferenceGenerationExpectation":
            "Models/InferenceOwnershipModels.swift",
        "struct LiveInferencePersistenceFence":
            "Models/InferenceOwnershipModels.swift",
        "struct LiveInferencePersistenceResult":
            "Models/InferenceOwnershipModels.swift",
        "enum ScanFundingSource": "Models/InferenceOwnershipModels.swift",
        "struct ScanFundingReservation":
            "Models/InferenceOwnershipModels.swift",
        "enum BackgroundAccountWorkPhase":
            "Models/InferenceOwnershipModels.swift",
        "struct BackgroundAccountWorkOwnership":
            "Models/InferenceOwnershipModels.swift",
        "struct BackgroundAccountWorkCandidate":
            "Models/InferenceOwnershipModels.swift",
        "struct ExtractedScanData": "Models/ExtractedScanData.swift",
        "struct OfflineScanProcessingResult": "Models/ExtractedScanData.swift",
        "enum InferenceGenerationMetadataContract":
            "Policies/OfflineScanJobMetadataContract.swift",
        "enum OfflineScanJobMetadataContract":
            "Policies/OfflineScanJobMetadataContract.swift",
        "enum InferenceURLSessionTaskContract":
            "Policies/InferenceURLSessionTaskContract.swift",
        "enum MediaStagingContract": "Policies/MediaStagingContract.swift",
        "enum QueuedInferenceMediaPolicy":
            "Policies/QueuedInferenceMediaPolicy.swift",
        "enum OfflineQueueRetryDisposition":
            "Policies/OfflineQueueRetryPolicy.swift",
        "enum OfflineQueueRetryPolicy":
            "Policies/OfflineQueueRetryPolicy.swift",
        "enum OfflineQueueStoragePolicy":
            "Policies/OfflineQueueStoragePolicy.swift",
        "final class GenerationTaskRegistry":
            "Coordinators/GenerationTaskRegistry.swift",
        "func deletePreferredGoalHint":
            "Persistence/ModelContext+FieldTripGoalHints.swift",
        "func preferredGoalHint":
            "Persistence/ModelContext+FieldTripGoalHints.swift",
        "func fetchOfflineJob":
            "Persistence/ModelContext+OfflineJobs.swift",
        "func ensureOfflineJobRecord":
            "Persistence/ModelContext+OfflineJobs.swift",
        "func buildExtractedScanData":
            "Persistence/OfflineQueueManager+QueuedScanExtraction.swift",
        "enum OfflineQueueDiagnosticsExportError":
            "Services/OfflineQueueManager+Diagnostics.swift",
        "struct OfflineQueueDiagnosticsExport":
            "Services/OfflineQueueManager+Diagnostics.swift",
        "struct OfflineQueueDiagnosticsApp":
            "Services/OfflineQueueManager+Diagnostics.swift",
        "struct OfflineQueueDiagnosticsJob":
            "Services/OfflineQueueManager+Diagnostics.swift",
        "struct OfflineQueueDiagnosticsScan":
            "Services/OfflineQueueManager+Diagnostics.swift",
        "struct OfflineQueueDiagnosticsEvent":
            "Services/OfflineQueueManager+Diagnostics.swift",
        "enum OfflineQueueDiagnosticsExportPolicy":
            "Services/OfflineQueueManager+Diagnostics.swift",
        "func recordQueueEvent":
            "Services/OfflineQueueManager+Diagnostics.swift",
        "func writeQueueDiagnosticsExport":
            "Services/OfflineQueueManager+Diagnostics.swift",
        "func pruneOfflineQueueEvents":
            "Services/OfflineQueueManager+Diagnostics.swift"
    ]

    private static let focusedOwnerDirectories: Set<String> = [
        "Coordinators",
        "Models",
        "Persistence",
        "Policies",
        "Services"
    ]

    private static let extractedOwnerPaths: Set<String> = [
        "Coordinators/GenerationTaskRegistry.swift",
        "Models/CollectionSyncSnapshot.swift",
        "Models/ExtractedScanData.swift",
        "Models/InferenceOwnershipModels.swift",
        "Models/MediaStagingModels.swift",
        "Models/OfflineScanPayloads.swift",
        "OfflineQueueDurability.swift",
        "Persistence/ModelContext+FieldTripGoalHints.swift",
        "Persistence/ModelContext+OfflineJobs.swift",
        "Persistence/OfflineQueueManager+QueuedScanExtraction.swift",
        "Policies/InferenceURLSessionTaskContract.swift",
        "Policies/BackgroundInferencePolicy.swift",
        "Policies/MediaStagingContract.swift",
        "Policies/QueuedInferenceMediaPolicy.swift",
        "Policies/OfflineQueueRetryPolicy.swift",
        "Policies/OfflineQueueStoragePolicy.swift",
        "Policies/OfflineScanJobMetadataContract.swift",
        "Services/OfflineQueueManager+Diagnostics.swift"
    ]

    private static let modelAndPolicyPaths: Set<String> = [
        "Models/CollectionSyncSnapshot.swift",
        "Models/ExtractedScanData.swift",
        "Models/InferenceOwnershipModels.swift",
        "Models/MediaStagingModels.swift",
        "Models/OfflineScanPayloads.swift",
        "Policies/BackgroundInferencePolicy.swift",
        "Policies/InferenceURLSessionTaskContract.swift",
        "Policies/MediaStagingContract.swift",
        "Policies/QueuedInferenceMediaPolicy.swift",
        "Policies/OfflineQueueRetryPolicy.swift",
        "Policies/OfflineQueueStoragePolicy.swift",
        "Policies/OfflineScanJobMetadataContract.swift"
    ]

    private static let expectedImportsByPath: [String: Set<String>] = [
        "Coordinators/GenerationTaskRegistry.swift": ["import Foundation"],
        "Models/CollectionSyncSnapshot.swift": ["import Foundation"],
        "Models/ExtractedScanData.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "Models/InferenceOwnershipModels.swift": ["import Foundation"],
        "Models/MediaStagingModels.swift": ["import Foundation"],
        "Models/OfflineScanPayloads.swift": [],
        "OfflineQueueDurability.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "Persistence/ModelContext+FieldTripGoalHints.swift": [
            "import SwiftData"
        ],
        "Persistence/ModelContext+OfflineJobs.swift": [
            "import Foundation",
            "import SwiftData"
        ],
        "Persistence/OfflineQueueManager+QueuedScanExtraction.swift": [
            "import CoreGraphics",
            "import Foundation",
            "import SwiftData"
        ],
        "Policies/BackgroundInferencePolicy.swift": ["import Foundation"],
        "Policies/InferenceURLSessionTaskContract.swift": ["import Foundation"],
        "Policies/MediaStagingContract.swift": ["import Foundation"],
        "Policies/QueuedInferenceMediaPolicy.swift": ["import Foundation"],
        "Policies/OfflineQueueRetryPolicy.swift": ["import Foundation"],
        "Policies/OfflineQueueStoragePolicy.swift": ["import Foundation"],
        "Policies/OfflineScanJobMetadataContract.swift": ["import Foundation"],
        "Services/OfflineQueueManager+Diagnostics.swift": [
            "import Foundation",
            "import SwiftData"
        ]
    ]

    private static let queuedScanExtractionTestDeclarations = [
        "func galleryQueueReplayOmitsBookkeepingTimestampWhenPhotoHasNoEmbeddedDate()",
        "func queueReplayReusesPersistedStandaloneAudioIdentity()",
        "func legacyQueueReplayDoesNotRenumberSparseAudioIdentity()",
        "func legacyVisualQueueWithoutDescriptorsUsesConservativeReplay()",
        "func queueReplayKeepsAudioPathsAlignedWithDescriptorsAcrossMixedTimeline()",
        "func galleryQueueReplayUsesEmbeddedCaptureDateWhenPresent()"
    ]

    private static let preferredGoalHintConsumers: Set<String> = [
        "Persistence/ModelContext+FieldTripGoalHints.swift",
        "Persistence/OfflineQueueManager+QueuedScanExtraction.swift",
        "Services/BackgroundInference/OfflineQueueManager+InferenceRecovery.swift"
    ]

    private static let queuedScanExtractionConsumers: Set<String> = [
        "Persistence/OfflineQueueManager+QueuedScanExtraction.swift",
        "Services/BackgroundInference/OfflineQueueManager+InferenceCompletion.swift",
        "Services/InferenceReplay/OfflineQueueManager+InferenceReplay.swift",
        "Services/MediaUpload/OfflineQueueManager+UploadCompletion.swift"
    ]

    private func offlineSyncRoot() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/Data/OfflineSync"
        )
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        while candidate.path != "/" {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    private func imports(in source: String) -> Set<String> {
        Set(
            source.split(separator: "\n")
                .map(String.init)
                .filter { $0.hasPrefix("import ") }
        )
    }

    private func lineCount(of source: String) -> Int {
        source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
    }

    private func relativePath(of file: URL, below root: URL) -> String {
        file.path.replacingOccurrences(of: root.path + "/", with: "")
    }

    private func swiftFiles(below root: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys)
        ) else {
            return []
        }
        return try enumerator.compactMap { element in
            guard let file = element as? URL,
                  file.pathExtension == "swift",
                  try file.resourceValues(forKeys: keys).isRegularFile == true
            else {
                return nil
            }
            return file
        }
    }

    private func containsDeclaration(
        _ declaration: String,
        in source: String
    ) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: declaration)
        let pattern =
            #"(?m)^\s*(?:(?:private|fileprivate|internal|package|public|final)\s+)*"#
            + escaped
            + #"(?:\s*[:(<{=])"#
        return source.range(of: pattern, options: .regularExpression) != nil
    }
}
