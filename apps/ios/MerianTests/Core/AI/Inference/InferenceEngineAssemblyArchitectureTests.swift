import Foundation
import Testing

@testable import Merian

@Suite("Inference Engine Assembly Architecture")
struct InferenceEngineAssemblyArchitectureTests {
    @Test func assemblyIsTheSoleProductionOwnerGraphConstructor() throws {
        let root = try repositoryRoot()
        let inferenceRoot = root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/Inference"
        )
        let assemblyURL = inferenceRoot.appendingPathComponent(
            "Assembly/InferenceEngineAssembly.swift"
        )
        let engineURL = root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/InferenceEngine.swift"
        )
        let engine = try contents(of: engineURL)
        let constructorTokens = [
            "InferencePresentationCoordinator()",
            "InferencePresentationState()",
            "InferenceWriteCoordinator()",
            "InferenceLocalAnalysisCoordinator(",
            "InferenceLiveAttemptCoordinator(",
            "InferenceLiveCompletionCoordinator(",
            "InferenceLiveFailureCoordinator(",
            "InferenceLivePipelineCoordinator(",
            "InferenceHydrationCoordinator()",
            "InferenceSessionLifecycleCoordinator(",
            "InferenceSpeciesHydrationCoordinator(",
            "InferenceIdentificationReviewCoordinator(",
            "InferenceSpeciesPresentationCoordinator(",
            "InferenceLivePresentationCoordinator(",
            "InferenceLiveSubmissionCoordinator(",
            "InferenceHistoricalHydrationCoordinator(",
            "InferenceReviewWorkflowCoordinator(",
            "InferenceHistoricalLoadCoordinator("
        ]
        let productionSources = try swiftFiles(
            in: root.appendingPathComponent("apps/ios/Merian/Core/AI")
        )
        let assemblyConsumers = try productionSources.filter {
            try contents(of: $0).contains("InferenceEngineAssembly")
        }
        #expect(Set(assemblyConsumers) == Set([assemblyURL, engineURL]))

        for token in constructorTokens {
            let owners = try productionSources.filter {
                try contents(of: $0).contains(token)
            }
            #expect(
                owners == [assemblyURL],
                "\(token) must remain assembly-owned: \(owners)"
            )
            #expect(!engine.contains(token))
        }
    }

    @Test func assemblyPreservesConstructionOrderAndInjectedEdges() throws {
        let assembly = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AI/Inference/Assembly/InferenceEngineAssembly.swift"
            )
        )

        try expectOrder([
            "InferencePresentationCoordinator()",
            "InferencePresentationState()",
            "InferenceWriteCoordinator()",
            "InferenceLocalAnalysisCoordinator(",
            "InferenceLiveAttemptCoordinator(",
            "InferenceLiveCompletionCoordinator(",
            "InferenceLiveFailureCoordinator(",
            "InferenceLivePipelineCoordinator(",
            "InferenceHydrationCoordinator()",
            "InferenceSessionLifecycleCoordinator(",
            "InferenceSpeciesHydrationCoordinator(",
            "InferenceIdentificationReviewCoordinator(",
            "InferenceSpeciesPresentationCoordinator(",
            "InferenceLivePresentationCoordinator(",
            "InferenceLiveSubmissionCoordinator(",
            "InferenceHistoricalHydrationCoordinator(",
            "InferenceReviewWorkflowCoordinator(",
            "InferenceHistoricalLoadCoordinator("
        ], in: assembly)

        for edge in [
            "queueService: dependencies.liveQueueService ?? .live",
            "dependencies: dependencies.liveCompletionDependencies ?? .live",
            "dependencies.liveFailureDependencies",
            ".live(requestPaywall: dependencies.requestPaywall)",
            "requestService: dependencies.liveRequestService",
            "resultService: dependencies.liveResultService",
            "referenceService: dependencies.speciesReferenceService",
            "enrichmentService: dependencies.speciesEnrichmentService",
            "persistenceService: dependencies.hydrationPersistenceService",
            "reviewService: dependencies.identificationReviewService",
            "snapshotService:",
            "dependencies.identificationReviewSnapshotService",
            "mediaProjector: dependencies.liveMediaProjector",
            "lookalikeCacheResetService:",
            "dependencies.lookalikeCacheResetService"
        ] {
            #expect(assembly.contains(edge))
        }

        for dependency in dependencyNames {
            #expect(
                assembly.contains("dependencies.\(dependency)"),
                "Assembly must consume \(dependency)"
            )
        }
    }

    @Test func engineRetainsPrivateOwnersAndStableInitializer() throws {
        let engine = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AI/InferenceEngine.swift"
            )
        )

        #expect(engine.contains("let assembly = InferenceEngineAssembly("))
        let compactEngine = collapsingWhitespace(in: engine)
        for dependency in dependencyNames {
            #expect(
                compactEngine.contains("\(dependency): \(dependency)"),
                "InferenceEngine must forward \(dependency) without renaming"
            )
        }
        #expect(!engine.contains("foundationCueEligibilityChecker:"))
        for owner in [
            "presentationLifecycleCoordinator",
            "presentationState",
            "sessionLifecycleCoordinator",
            "localAnalysisCoordinator",
            "liveAttemptCoordinator",
            "liveSubmissionCoordinator",
            "livePipelinePresentationCoordinator",
            "speciesPresentationCoordinator",
            "historicalLoadCoordinator",
            "identificationReviewWorkflowCoordinator",
            "hydrationCoordinator",
            "writeCoordinator"
        ] {
            #expect(
                engine.contains("private let \(owner):"),
                "InferenceEngine must retain \(owner) privately"
            )
            #expect(
                engine.contains("assembly.\(owner)"),
                "InferenceEngine must install assembled \(owner)"
            )
        }
        #expect(!engine.contains("private let assembly:"))
    }

    @Test func assemblyIsAOneShotEffectFreeValue() throws {
        let source = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AI/Inference/Assembly/InferenceEngineAssembly.swift"
            )
        )
        let lineCount = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .count

        #expect(lineCount <= 600)
        #expect(source.contains("@MainActor\nstruct InferenceEngineAssembly"))
        #expect(source.contains("struct Dependencies"))
        for forbidden in [
            "@Observable", "private var ", "Task {", "Task.detached",
            "URLSession", "ModelContext", "LocalScanRecord", "MerianLog",
            "AppDIContainer", "FileManager", ".shared"
        ] {
            #expect(
                !source.contains(forbidden),
                "Assembly must not acquire runtime effect \(forbidden)"
            )
        }
    }

    private func expectOrder(
        _ tokens: [String],
        in source: String
    ) throws {
        var lowerBound = source.startIndex
        for token in tokens {
            let range = try #require(
                source.range(of: token, range: lowerBound..<source.endIndex),
                "Missing ordered token: \(token)"
            )
            lowerBound = range.upperBound
        }
    }

    private var dependencyNames: [String] {
        [
            "visionSubjectClassifier",
            "localVisualTraitExtractor",
            "foundationVisualCueProvider",
            "foundationVisualCueEligibilityChecker",
            "scanningPhraseSleeper",
            "localAnalysisStartFeedback",
            "liveRequestService",
            "liveResultService",
            "liveQueueService",
            "liveCompletionDependencies",
            "speciesReferenceService",
            "speciesEnrichmentService",
            "hydrationPersistenceService",
            "identificationReviewService",
            "identificationReviewSnapshotService",
            "identificationReviewDependencies",
            "hydrationCoordinator",
            "requestPaywall",
            "liveFailureDependencies",
            "livePipelineDependencies",
            "speciesHydrationDependencies",
            "lookalikeCacheResetService",
            "liveMediaProjector"
        ]
    }

    private func collapsingWhitespace(in source: String) -> String {
        source.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private func swiftFiles(in root: URL) throws -> [URL] {
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        )
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
