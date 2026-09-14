import Foundation
import Testing

@testable import Merian

@Suite("Inference Live Pipeline Architecture")
struct InferenceLivePipelineArchitectureTests {
    @Test func coreCoordinatorOwnsPipelineWithoutResolvingLiveManagers() throws {
        let root = try repositoryRoot()
        let coordinator = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/Inference/Pipeline/InferenceLivePipelineCoordinator.swift"
        ))
        let models = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/Inference/Pipeline/InferenceLivePipelineModels.swift"
        ))
        let live = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/Inference/Pipeline/InferenceLivePipelineCoordinator+Live.swift"
        ))
        let presentation = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/Inference/Pipeline/InferenceLivePresentationCoordinator.swift"
        ))
        let submission = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/Inference/Pipeline/InferenceLiveSubmissionCoordinator.swift"
        ))
        let engine = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/InferenceEngine.swift"
        ))
        let appDI = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AppDIContainer.swift"
        ))
        let inferenceRoot = root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/Inference"
        )
        let presentationURL = inferenceRoot.appendingPathComponent(
            "Pipeline/InferenceLivePresentationCoordinator.swift"
        )
        let callbackOwners = try swiftFiles(in: inferenceRoot).filter { file in
            let source = try contents(of: file)
            return source.contains(
                "InferenceLivePipelineCoordinator.Callbacks("
            ) || source.contains(
                "InferenceLivePipelineCoordinator.VisualCallbacks("
            )
        }

        #expect(callbackOwners == [presentationURL])

        for token in [
            "final class InferenceLivePipelineCoordinator",
            "func admit(",
            "func activate(",
            "func executeVisual(",
            "func executeNonVisual(",
            "private func processResult(",
            "else if session.durableQueueOwnsRecovery",
            "followUpPermit = await completionCoordinator",
            "followUpPermit = completionCoordinator",
            ".authorizeQueueLessFollowUps(",
            "clearActiveAttemptIfCurrent(",
            "failureCoordinator.handle("
        ] {
            #expect(coordinator.contains(token))
        }
        for token in [
            "MerianLog", "UsageManager",
            "CircuitBreakerManager", "InferenceEngine", "Task.detached"
        ] {
            #expect(!coordinator.contains(token))
            #expect(!models.contains(token))
        }
        let core = coordinator + models
        #expect(
            core.range(
                of: #"[A-Z][A-Za-z0-9_]*\.shared\b"#,
                options: .regularExpression
            ) == nil
        )
        for token in [
            "CircuitBreakerManager.shared",
            "UsageManager.shared",
            "refundScan(scanId:",
            "MerianLog.general.debug(",
            "MerianLog.general.error("
        ] {
            #expect(live.contains(token))
        }

        for token in [
            "private let liveSubmissionCoordinator:",
            "private let livePipelinePresentationCoordinator:",
            "liveSubmissionCoordinator.startVisual(",
            "liveSubmissionCoordinator.startNonVisual("
        ] {
            #expect(engine.contains(token))
        }
        for token in [
            "private let livePipelineCoordinator:",
            "private let liveMediaProjector:",
            "livePipelineCoordinator.admit(",
            "livePipelineCoordinator.activate(",
            "livePipelineCoordinator.executeVisual(",
            "livePipelineCoordinator.executeNonVisual(",
            "liveMediaProjector.projectVisual(",
            "liveMediaProjector.projectNonVisual("
        ] {
            #expect(!engine.contains(token))
        }
        for token in [
            "final class InferenceLiveSubmissionCoordinator",
            "struct VisualSubmission {",
            "struct NonVisualSubmission {",
            "private let attemptCoordinator:",
            "private let writeCoordinator:",
            "private let sessionLifecycleCoordinator:",
            "private let presentationCoordinator:",
            "private let presentationState:",
            "private let localAnalysisCoordinator:",
            "private let mediaProjector:",
            "private let pipelineCoordinator:",
            "private let pipelinePresentationCoordinator:",
            "func startVisual(",
            "func startNonVisual(",
            "func recordFirstRenderedFrame(",
            "presentationCoordinator\n            .consumeFirstRenderStart(",
            "pipelineCoordinator.recordBenchmark(",
            ".tapToFirstRenderedFrame(",
            "private func startLocalClassification(",
            "private func isLocalAnalysisCurrent(",
            "func debugStartLocalClassification(",
            "func debugIsLocalAnalysisCurrent("
        ] {
            #expect(submission.contains(token))
        }
        for token in [
            "MerianNetworkClient", "BackgroundDatabaseActor",
            "AppDIContainer", "FileManager", "URLSession", "MerianLog",
            "Task.detached", "@Observable", "private var", ".shared"
        ] {
            #expect(
                !submission.contains(token),
                "The submission coordinator must not own \(token)"
            )
        }
        #expect(
            submission.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).count <= 600
        )
        #expect(
            engine.contains(
                "liveSubmissionCoordinator.recordFirstRenderedFrame("
            )
        )
        #expect(!engine.contains("consumeFirstRenderStart("))

        let visualExecution = try section(
            in: coordinator,
            from: "func executeVisual(",
            until: "func executeNonVisual("
        )
        #expect(visualExecution.contains(
            "clientScanId: session.resolvedClientScanId"
        ))
        #expect(visualExecution.contains(
            "expectedScanId: session.resolvedClientScanId"
        ))
        let nonvisualExecution = try section(
            in: coordinator,
            from: "func executeNonVisual(",
            until: "private func check("
        )
        #expect(nonvisualExecution.contains("clientScanId: session.scanId"))
        #expect(nonvisualExecution.contains("expectedScanId: session.scanId"))

        let debugAdapters = try section(
            in: submission,
            from: "#if DEBUG",
            until: "#endif"
        )
        for token in [
            "func debugStartLocalClassification(",
            "func debugIsLocalAnalysisCurrent("
        ] {
            #expect(debugAdapters.contains(token))
        }

        let visual = try section(
            in: submission,
            from: "func startVisual(",
            until: "func startNonVisual("
        )
        try expectOrder([
            "guard !writeCoordinator.isAuthTransitionFenceActive",
            "guard !submission.imageDatas.isEmpty",
            "pipelineCoordinator.admit(",
            "sessionLifecycleCoordinator.prepareForVisualAnalysis()",
            "mediaProjector.projectVisual(",
            "presentationState.stageVisualMedia(",
            "pipelineCoordinator.activate(session)",
            "presentationCoordinator.activate(",
            "presentationState.applyVisualTelemetry(",
            "startLocalClassification(",
            "presentationCoordinator.beginFirstRenderMetric(",
            "InferenceLivePipelineCoordinator.VisualRequest(",
            "attemptCoordinator.replaceTask(Task",
            "pipelineCoordinator.executeVisual(",
            "pipelinePresentationCoordinator",
            ".makeVisualCallbacks("
        ], in: visual)

        let nonVisual = try section(
            in: submission,
            from: "func startNonVisual(",
            until: "private func startLocalClassification("
        )
        try expectOrder([
            "guard !writeCoordinator.isAuthTransitionFenceActive",
            "mediaProjector.projectNonVisual(",
            "guard !mediaProjection.media.mediaTimeline.isEmpty",
            "pipelineCoordinator.admit(",
            "sessionLifecycleCoordinator.prepareForNonVisualAnalysis(",
            "presentationState.setScanningPhaseText(",
            "pipelineCoordinator.activate(session)",
            "presentationCoordinator.activate(",
            "presentationState.applyNonVisualTelemetry(",
            "presentationState.replaceActiveMedia(",
            "presentationCoordinator.beginFirstRenderMetric(",
            "InferenceLivePipelineCoordinator.NonVisualRequest(",
            "attemptCoordinator.replaceTask(Task",
            "pipelineCoordinator.executeNonVisual(",
            "pipelinePresentationCoordinator",
            ".makeCallbacks("
        ], in: nonVisual)
        for token in [
            "final class InferenceLivePresentationCoordinator",
            "func makeCallbacks(",
            "func makeVisualCallbacks(",
            "func commitSuccessfulResult(",
            "private func applyFailurePresentation(",
            "resetPhraseCoordinator: false",
            "InferenceLocalAnalysisCoordinator.Session(",
            "scanId: session.scanId",
            "attemptGeneration: session.attemptGeneration",
            "foregroundGeneration: session.foregroundGeneration",
            "firstRenderMetricScanId: session.resolvedClientScanId",
            "sessionLifecycleCoordinator.rebindFirstRenderMetric(",
            "modelContainer: modelContainer",
            "referencePolicy: referencePolicy",
            "resolvePersistedMediaItems: {"
        ] {
            #expect(presentation.contains(token))
        }
        let lazyCommitStart = try #require(
            presentation.range(of: "private func commitSuccessfulResult(")
        )
        let failureMappingStart = try #require(
            presentation.range(
                of: "private func applyFailurePresentation(",
                range: lazyCommitStart.upperBound..<presentation.endIndex
            )
        )
        let lazyCommit = presentation[
            lazyCommitStart.lowerBound..<failureMappingStart.lowerBound
        ]
        let exactAttemptFence = try #require(
            lazyCommit.range(
                of: "guard attemptCoordinator.isAttemptCurrent("
            )
        )
        let renderMetricTransfer = try #require(
            lazyCommit.range(
                of: "sessionLifecycleCoordinator.rebindFirstRenderMetric("
            )
        )
        let mediaProjection = try #require(
            lazyCommit.range(of: "resolvePersistedMediaItems()")
        )
        #expect(exactAttemptFence.lowerBound < renderMetricTransfer.lowerBound)
        #expect(renderMetricTransfer.lowerBound < mediaProjection.lowerBound)
        #expect(exactAttemptFence.lowerBound < mediaProjection.lowerBound)
        for token in [
            "InferenceLivePipelineCoordinator.Callbacks(",
            "InferenceLivePipelineCoordinator.VisualCallbacks(",
            "private func livePipelineCallbacks(",
            "private func applyLiveFailurePresentation(",
            "private func finishLivePipelinePresentation("
        ] {
            #expect(!engine.contains(token))
        }
        for token in [
            ".shared", "Task {", "Task.detached", "await ",
            "AppDIContainer", "InferenceEngine", "MerianLog",
            "URLSession", "ModelContext"
        ] {
            #expect(
                !presentation.contains(token),
                "The presentation bridge must not own \(token)"
            )
        }
        for token in [
            "private let liveRequestService:",
            "private let liveResultService:",
            "private let liveFailureCoordinator:",
            "CircuitBreakerManager.shared",
            "UsageManager.shared",
            "liveRequestService.dispatch",
            "liveResultService.process("
        ] {
            #expect(!engine.contains(token))
        }
        for token in [
            "liveInferencePipelineDependencies",
            "InferenceLivePipelineCoordinator.Dependencies.composed(",
            "livePipelineDependencies:"
        ] {
            #expect(appDI.contains(token))
        }
    }

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
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
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func expectOrder(
        _ tokens: [String],
        in source: String
    ) throws {
        var remainder = source
        for token in tokens {
            let range = try #require(remainder.range(of: token))
            remainder = String(remainder[range.upperBound...])
        }
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
}
