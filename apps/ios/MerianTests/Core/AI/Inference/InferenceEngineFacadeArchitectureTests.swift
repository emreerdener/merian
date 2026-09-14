import Foundation
import Testing

@testable import Merian

@Suite("Inference Engine Facade Architecture")
struct InferenceEngineFacadeArchitectureTests {
    @Test func productionFacadeRemainsSmallAndRetainsPrivateOwners() throws {
        let engine = try contents(of: engineURL())
        let lineCount = engine
            .split(separator: "\n", omittingEmptySubsequences: false)
            .count

        #expect(lineCount <= 600)
        #expect(!engine.contains("import os"))
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
            #expect(engine.contains("private let \(owner):"))
        }
    }

    @Test func compatibilityFileOwnsOnlyPureFacadeAdapters() throws {
        let engine = try contents(of: engineURL())
        let compatibility = try contents(
            of: inferenceRoot().appendingPathComponent(
                "Facade/InferenceEngineCompatibility.swift"
            )
        )

        for declaration in [
            "enum ScanPresentationModality: Sendable",
            "enum QueuedPresentationSource: Sendable",
            "nonisolated static func plannedEnrichmentScopes(",
            "nonisolated static func normalizedReferenceURLs(",
            "nonisolated static var genericScanningPhasePhrases:"
        ] {
            #expect(compatibility.contains(declaration))
            #expect(!engine.contains(declaration))
        }
        for forbiddenEffect in [
            "@Observable", "private var ", "Task {", "Task.detached",
            "URLSession", "ModelContext", "ModelContainer", "MerianLog",
            "FileManager", ".shared"
        ] {
            #expect(!compatibility.contains(forbiddenEffect))
        }
    }

    @Test func diagnosticsAreCompileTimeGuardedThinAdapters() throws {
        let engine = try contents(of: engineURL())
        let support = try contents(
            of: inferenceRoot().appendingPathComponent(
                "Diagnostics/InferenceEngineDebugSupport.swift"
            )
        )
        let adapter = try contents(
            of: inferenceRoot().appendingPathComponent(
                "Diagnostics/InferenceEngine+Debug.swift"
            )
        )

        for source in [support, adapter] {
            #expect(source.contains("#if DEBUG"))
            #expect(source.contains("#endif"))
            #expect(
                source.split(
                    separator: "\n",
                    omittingEmptySubsequences: false
                ).count <= 600
            )
        }
        #expect(support.contains("struct InferenceEngineDebugSupport"))
        for owner in [
            "presentationLifecycleCoordinator",
            "presentationState",
            "sessionLifecycleCoordinator",
            "localAnalysisCoordinator",
            "liveAttemptCoordinator",
            "liveSubmissionCoordinator",
            "writeCoordinator"
        ] {
            #expect(support.contains("private let \(owner):"))
            #expect(engine.contains("private let \(owner):"))
        }
        for forbiddenEffect in [
            "Task {", "Task.detached", "URLSession", "ModelContext",
            "ModelContainer", "MerianLog", "FileManager", ".shared"
        ] {
            #expect(!support.contains(forbiddenEffect))
            #expect(!adapter.contains(forbiddenEffect))
        }

        let factory = try section(
            in: engine,
            from: "#if DEBUG",
            until: "#endif"
        )
        #expect(factory.contains("func makeDebugSupport()"))
        #expect(factory.contains("InferenceEngineDebugSupport("))
        for signature in [
            "struct DebugBackgroundWriteState",
            "var debugBackgroundWriteTaskCap:",
            "var debugPendingBackgroundWriteTaskCap:",
            "func debugBackgroundWriteState()",
            "func debugEnqueueTrackedBackgroundTask(",
            "func simulateProgressiveAnalyzing(",
            "func debugAdvanceProgressiveAnalyzing()",
            "func simulateAnalyzing()",
            "func debugStartFoundationCueStream(",
            "func debugStartLocalClassification(",
            "func debugTransitionProgressiveAnalyzingToQueue(",
            "func debugStartNonVisualPresentation(",
            "func debugSimulateGeminiResponseArrival()",
            "var debugAcceptedFoundationPhraseCount:",
            "func debugWaitForFoundationVisualCueStream()",
            "func debugWaitForLocalVisualTraits()",
            "var debugLocalVisionCategory:",
            "var debugLocalVisualAnalysisIsRunning:",
            "var debugLocalVisualTraitIsRunning:"
        ] {
            #expect(adapter.contains(signature))
            #expect(!engine.contains(signature))
        }
    }

    @Test func facadeRoutesMetricsAndReviewStateToFocusedOwners() throws {
        let engine = try contents(of: engineURL())
        let submission = try contents(
            of: inferenceRoot().appendingPathComponent(
                "Pipeline/InferenceLiveSubmissionCoordinator.swift"
            )
        )
        let speciesPresentation = try contents(
            of: inferenceRoot().appendingPathComponent(
                "Hydration/InferenceSpeciesPresentationCoordinator.swift"
            )
        )

        #expect(
            engine.contains(
                "liveSubmissionCoordinator.recordFirstRenderedFrame("
            )
        )
        #expect(!engine.contains("consumeFirstRenderStart("))
        #expect(!engine.contains("MerianLog"))
        for token in [
            "func recordFirstRenderedFrame(",
            ".consumeFirstRenderStart(scanId: scanId)",
            "pipelineCoordinator.recordBenchmark(",
            ".tapToFirstRenderedFrame(now - startedAt)"
        ] {
            #expect(submission.contains(token))
        }

        #expect(
            engine.contains(
                "speciesPresentationCoordinator.markAlternativesExhausted("
            )
        )
        for token in [
            "func markAlternativesExhausted(expectedScanId: String?)",
            "expectedScanId?.caseInsensitiveCompare(scanId) == .orderedSame",
            "_ = beginReviewAction(scanId: scanId)",
            "presentationState.markAlternativesExhausted()"
        ] {
            #expect(speciesPresentation.contains(token))
        }
    }

    private func section(
        in source: String,
        from startToken: String,
        until endToken: String
    ) throws -> String {
        let start = try #require(source.range(of: startToken))
        let end = try #require(source.range(
            of: endToken,
            range: start.upperBound..<source.endIndex
        ))
        return String(source[start.lowerBound..<end.upperBound])
    }

    private func engineURL() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/AI/InferenceEngine.swift"
        )
    }

    private func inferenceRoot() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/AI/Inference"
        )
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
