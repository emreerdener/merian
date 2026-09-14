import Foundation
import Testing

@testable import Merian

@Suite("Inference Live Failure Architecture")
struct InferenceLiveFailureArchitectureTests {
    @Test func coordinatorOwnsOneSynchronousExactFailureCommit() throws {
        let root = try repositoryRoot()
        let engine = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/InferenceEngine.swift"
        ))
        let presentationBridge = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/Inference/Pipeline/InferenceLivePresentationCoordinator.swift"
        ))
        let pipeline = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/Inference/Pipeline/InferenceLivePipelineCoordinator.swift"
        ))
        let coordinator = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/Inference/Recovery/InferenceLiveFailureCoordinator.swift"
        ))
        let liveDependencies = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/Inference/Recovery/InferenceLiveFailureCoordinator+Live.swift"
        ))
        let appDI = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AppDIContainer.swift"
        ))

        for token in [
            "final class InferenceLiveFailureCoordinator",
            "private let attemptCoordinator:",
            "private let dependencies:",
            "func handle(",
            "enum PresentationAction",
            "case retainRecoverableScan(String)",
            "case transitionToQueue(scanId: String, attemptGeneration: UUID)",
            "case publishFailure(SpeciesData)"
        ] {
            #expect(coordinator.contains(token))
        }
        for token in [
            ".shared", "Task {", "Task.detached", "await ",
            "InferenceEngine", "AppDIContainer", "AppTelemetry",
            "CircuitBreakerManager", "HapticManager", "UsageManager",
            "MerianLog"
        ] {
            #expect(
                !coordinator.contains(token),
                "The coordinator core must not own \(token)"
            )
        }

        let handleStart = try #require(
            coordinator.range(of: "func handle(")
        )
        let publicationStart = try #require(
            coordinator.range(
                of: "private func publishTerminalFailure(",
                range: handleStart.upperBound..<coordinator.endIndex
            )
        )
        let handler = coordinator[
            handleStart.lowerBound..<publicationStart.lowerBound
        ]
        #expect(!handler.contains("await "))
        #expect(!handler.contains("Task {"))

        let snapshot = try #require(
            handler.range(of: "let stillOwnsAttempt =")
        )
        let interruption = try #require(
            handler.range(of: "InferenceLiveFailurePolicy.interruption(")
        )
        let retiredHandoff = try #require(
            handler.range(of: "publishRetiredOwnershipHandoffIfNeeded(")
        )
        let connectivity = try #require(
            handler.range(
                of: "InferenceLiveFailurePolicy.isConnectivityFailure(error)"
            )
        )
        let ownerGuard = try #require(
            handler.range(of: "guard stillOwnsAttempt else { return }")
        )
        let retirement = try #require(
            handler.range(of: "reason: mode.failureReason")
        )
        let postRetirementGuard = try #require(
            handler.range(
                of: "guard attemptCoordinator.isLocalAttemptCurrent(",
                range: retirement.upperBound..<handler.endIndex
            )
        )
        let recoveryRetention = try #require(
            handler.range(of: ".retainRecoverableScan(")
        )
        let publicationCall = try #require(
            handler.range(of: "publishTerminalFailure(")
        )
        #expect(snapshot.lowerBound < interruption.lowerBound)
        #expect(retiredHandoff.lowerBound < connectivity.lowerBound)
        #expect(connectivity.lowerBound < ownerGuard.lowerBound)
        #expect(ownerGuard.lowerBound < retirement.lowerBound)
        #expect(retirement.lowerBound < postRetirementGuard.lowerBound)
        #expect(postRetirementGuard.lowerBound < recoveryRetention.lowerBound)
        #expect(recoveryRetention.lowerBound < publicationCall.lowerBound)

        let pipelineHandlerStart = try #require(
            pipeline.range(of: "private func handleFailure(")
        )
        let pipelineFinishStart = try #require(
            pipeline.range(
                of: "private func finish(",
                range: pipelineHandlerStart.upperBound..<pipeline.endIndex
            )
        )
        let pipelineHandler = pipeline[
            pipelineHandlerStart.lowerBound..<pipelineFinishStart.lowerBound
        ]
        #expect(pipelineHandler.contains("failureCoordinator.handle("))
        for token in [
            "InferenceLiveFailurePolicy.failure(", "AppTelemetry",
            "recordFailure()", "triggerErrorThump()", "requestPaywall()",
            "rejectQueuedScan(", "MerianLog"
        ] {
            #expect(!pipelineHandler.contains(token))
        }

        let presentationStart = try #require(
            presentationBridge.range(of: "private func applyFailurePresentation(")
        )
        let presentation = presentationBridge[
            presentationStart.lowerBound..<presentationBridge.endIndex
        ]
        for token in [
            "case .retainRecoverableScan", "case .transitionToQueue",
            "case .publishFailure"
        ] {
            #expect(presentation.contains(token))
        }
        for token in [
            "InferenceLiveFailurePolicy", "AppTelemetry", "recordFailure()",
            "triggerErrorThump()", "requestPaywall()", "rejectQueuedScan(",
            "MerianLog"
        ] {
            #expect(!presentation.contains(token))
        }
        #expect(!engine.contains("private func applyLiveFailurePresentation("))

        for token in [
            "AppTelemetry.trackError(",
            "circuitBreakerManager().recordFailure()",
            "hapticManager().triggerErrorThump()",
            "usageManager.showPaywall = true",
            "MerianLog.general.debug("
        ] {
            #expect(liveDependencies.contains(token))
        }
        #expect(appDI.contains("liveInferenceFailureDependencies"))
        #expect(
            appDI.contains(
                "InferenceLiveFailureCoordinator.Dependencies.composed("
            )
        )
        #expect(appDI.contains("liveFailureDependencies:"))
    }

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
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
