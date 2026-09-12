import Foundation
import Testing

@Suite("Core Domain Policy Ownership Architecture")
struct CorePolicyOwnershipArchitectureTests {
    @Test func formerGlobalConfigurationHasFocusedDomainOwners() throws {
        #expect(containsDeclaration(
            "enum ExamplePolicy",
            in: "private enum ExamplePolicy {}"
        ))
        #expect(!containsDeclaration(
            "enum ExamplePolicy",
            in: "enum ExamplePolicyLegacy {}"
        ))

        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian"
        )

        for owner in Self.policyOwners {
            let owners = sources.compactMap { source -> String? in
                containsDeclaration(owner.declaration, in: source.contents)
                    ? source.relativePath
                    : nil
            }
            #expect(
                owners == [owner.path],
                "\(owner.declaration) changed ownership"
            )
        }

        let staleReferences = sources.compactMap { source in
            source.contents.contains("MerianConfig")
                ? source.relativePath
                : nil
        }
        #expect(staleReferences.isEmpty)
    }

    @Test func focusedPolicyFilesStaySmallAndEffectFree() throws {
        for owner in Self.purePolicyOwners {
            let source = try DatabaseActorTestSupport.loadRepositorySource(
                at: "apps/ios/Merian/\(owner.path)"
            )
            #expect(
                DatabaseActorTestSupport.lineCount(of: source) <= 200,
                "\(owner.path) exceeds the 200-line policy ceiling"
            )
            #expect(
                imports(in: source) == owner.imports,
                "\(owner.path) has an unexpected framework dependency"
            )
            for token in Self.forbiddenPolicyEffects {
                #expect(
                    !source.contains(token),
                    "\(owner.path) resolves \(token)"
                )
            }
        }
    }

    @Test func behaviorTestsMirrorOwnersAndRetiredAggregatesStayAbsent() throws {
        let repository = try DatabaseActorTestSupport.repositoryRoot()
        for path in Self.expectedTestPaths {
            #expect(FileManager.default.fileExists(
                atPath: repository.appendingPathComponent(path).path
            ))
        }
        for path in Self.retiredPaths {
            #expect(!FileManager.default.fileExists(
                atPath: repository.appendingPathComponent(path).path
            ))
        }
    }

    @Test func imagePreparationConsumersRetainFocusedPolicyLinks() throws {
        for consumer in Self.imagePreparationConsumers {
            let source = try DatabaseActorTestSupport.loadRepositorySource(
                at: "apps/ios/Merian/\(consumer.path)"
            )
            for reference in consumer.references {
                #expect(
                    source.contains(reference),
                    "\(consumer.path) no longer references \(reference)"
                )
            }
        }
    }

    private struct PolicyOwner: Sendable {
        let declaration: String
        let path: String
        let imports: Set<String>

        init(
            _ declaration: String,
            path: String,
            imports: Set<String> = []
        ) {
            self.declaration = declaration
            self.path = path
            self.imports = imports
        }
    }

    private func containsDeclaration(
        _ declaration: String,
        in source: String
    ) -> Bool {
        let escapedDeclaration = NSRegularExpression.escapedPattern(
            for: declaration
        )
        let modifiers = [
            "private", "fileprivate", "internal", "package", "public", "open",
            "indirect", "nonisolated"
        ].joined(separator: "|")
        let pattern = #"(?m)^\s*(?:@[_A-Za-z][_A-Za-z0-9]*(?:\([^\n]*\))?\s+)*"#
            + "(?:(?:\(modifiers))\\s+)*"
            + escapedDeclaration
            + #"(?=\s|:|\{|$)"#
        return source.range(of: pattern, options: .regularExpression) != nil
    }

    private func imports(in source: String) -> Set<String> {
        Set(source.split(separator: "\n").compactMap { line in
            line.hasPrefix("import ") ? String(line) : nil
        })
    }

    private static let policyOwners = [
        PolicyOwner(
            "enum InferenceLookalikeCachePolicy",
            path: "Core/AI/Inference/Recovery/InferenceLookalikeCachePolicy.swift"
        ),
        PolicyOwner(
            "enum InferenceConfidencePolicy",
            path: "Core/AI/Inference/Result/InferenceConfidencePolicy.swift"
        ),
        PolicyOwner(
            "enum ScanningPhrasePolicy",
            path: "Core/AI/Inference/LocalAnalysis/ScanningPhrasePolicy.swift"
        ),
        PolicyOwner(
            "enum HistoricalSyncPolicy",
            path: "Core/Data/Database/HistoricalSync/HistoricalSyncPolicy.swift"
        ),
        PolicyOwner(
            "enum NonBiologicalRetentionPolicy",
            path: "Core/Data/Database/NonBiologicalRetentionPolicy.swift"
        ),
        PolicyOwner(
            "enum ImagePreparationPolicy",
            path: "Core/Data/Images/Policies/ImagePreparationPolicy.swift",
            imports: ["import CoreGraphics"]
        ),
        PolicyOwner(
            "enum OfflineQueueBatchPolicy",
            path: "Core/Data/OfflineSync/Policies/OfflineQueueBatchPolicy.swift"
        ),
        PolicyOwner(
            "enum MediaStagingContract",
            path: "Core/Data/OfflineSync/Policies/MediaStagingContract.swift",
            imports: ["import Foundation"]
        ),
        PolicyOwner(
            "enum OfflineQueueStoragePolicy",
            path: "Core/Data/OfflineSync/Policies/OfflineQueueStoragePolicy.swift",
            imports: ["import Foundation"]
        ),
        PolicyOwner(
            "enum ScanMediaPayloadPolicy",
            path: "Core/Media/ScanMediaPayloadPolicy.swift"
        )
    ]

    private static let purePolicyOwners = policyOwners.filter {
        $0.declaration != "enum MediaStagingContract"
            && $0.declaration != "enum OfflineQueueStoragePolicy"
    }

    private static let expectedTestPaths = [
        "apps/ios/MerianTests/Configuration/MerianEnvironmentTests.swift",
        "apps/ios/MerianTests/Core/AI/Inference/InferenceConfidencePolicyTests.swift",
        "apps/ios/MerianTests/Core/AI/Inference/InferenceLookalikeCachePolicyTests.swift",
        "apps/ios/MerianTests/Core/AI/Inference/ScanningPhrasePolicyTests.swift",
        "apps/ios/MerianTests/Core/Data/Database/NonBiologicalRetentionPolicyTests.swift",
        "apps/ios/MerianTests/Core/Data/HistoricalSync/HistoricalSyncPolicyTests.swift",
        "apps/ios/MerianTests/Core/Data/Images/ImagePreparationPolicyTests.swift",
        "apps/ios/MerianTests/Core/Data/OfflineSync/MediaStagingContractTests.swift",
        "apps/ios/MerianTests/Core/Data/OfflineSync/OfflineQueuePolicyTests.swift",
        "apps/ios/MerianTests/Core/Media/ScanMediaPayloadPolicyTests.swift"
    ]

    private static let imagePreparationConsumers: [(
        path: String,
        references: [String]
    )] = [
        (
            "Core/Media/ImageCropProcessor.swift",
            [
                "ImagePreparationPolicy.compressionQuality",
                "ImagePreparationPolicy.maximumInferenceDimension"
            ]
        ),
        (
            "Core/UI/Components/MediaCarousel/Gallery/FullscreenMediaLiveImageView.swift",
            ["ImagePreparationPolicy.displayMaxDimension"]
        ),
        (
            "Features/Capture/Staging/Views/CropSheetModifier.swift",
            ["ImagePreparationPolicy.displayMaxDimension"]
        ),
        (
            "Features/Insights/Media/Carousel/Pages/LiveCapturePageView.swift",
            ["ImagePreparationPolicy.displayMaxDimension"]
        )
    ]

    private static let retiredPaths = [
        "apps/ios/Merian/Core/Utilities/MerianConfig.swift",
        "apps/ios/MerianTests/Core/Utilities/MerianConfigTests.swift"
    ]

    private static let forbiddenPolicyEffects = [
        "@Observable",
        "AppDIContainer",
        "MerianNetworkClient",
        "ModelContext",
        "SupabaseManager",
        "Task {",
        "UIApplication",
        "URLSession",
        "UserDefaults",
        ".shared"
    ]
}
