import Foundation
import Testing

@testable import Merian

@Suite("Inference Live Completion Architecture")
struct InferenceLiveCompletionArchitectureTests {
    @Test func coordinatorOwnsSharedCompletionWithoutLiveDependencies() throws {
        let root = try repositoryRoot()
        let coordinator = try contents(
            of: root.appendingPathComponent(
                "apps/ios/Merian/Core/AI/Inference/Completion/InferenceLiveCompletionCoordinator.swift"
            )
        )
        let liveAdapter = try contents(
            of: root.appendingPathComponent(
                "apps/ios/Merian/Core/AI/Inference/Completion/InferenceLiveCompletionCoordinator+Live.swift"
            )
        )
        let engine = try contents(
            of: root.appendingPathComponent(
                "apps/ios/Merian/Core/AI/InferenceEngine.swift"
            )
        )
        let appDI = try contents(
            of: root.appendingPathComponent(
                "apps/ios/Merian/Core/AppDIContainer.swift"
            )
        )

        for token in [
            "struct PreparedCompletion",
            "struct FollowUpPermit",
            "fileprivate init(\n            speciesData: SpeciesData,",
            "func prepare(",
            "func publishForegroundCompletionEventIfNeeded(",
            "func authorizeQueueLessFollowUps(",
            "guard scanId == nil else { return nil }",
            "func finalizeQueueAndAuthorizeFollowUps(",
            "func sendNotificationIfEnabled(",
            "func scheduleMilestones("
        ] {
            #expect(coordinator.contains(token))
        }
        for token in [
            ".shared", "Task {", "Task.detached",
            "GamificationManager", "ScanRepository", "RevenueCatManager",
            "PushNotificationManager", "AppSettings", "AppTelemetry"
        ] {
            #expect(
                !coordinator.contains(token),
                "Completion coordinator must not own live dependency \(token)"
            )
        }

        for token in [
            "GamificationManager.shared",
            "ScanRepository.shared",
            "CircuitBreakerManager.shared",
            "RevenueCatManager.shared",
            "AppSettings.shared",
            "PushNotificationManager.shared",
            "AppDIContainer.shared.appEventPublisher",
            "AppDIContainer.shared.scanMilestoneCoordinator",
            "InferenceScanReplacement.transferMetadata(",
            "AppTelemetry.trackScan(",
            "Task { @MainActor in"
        ] {
            #expect(liveAdapter.contains(token))
        }

        for token in [
            "private let liveCompletionCoordinator:",
            "liveCompletionCoordinator.prepare(",
            ".finalizeQueueAndAuthorizeFollowUps(",
            ".authorizeQueueLessFollowUps(",
            ".sendNotificationIfEnabled(",
            ".scheduleMilestones("
        ] {
            #expect(engine.contains(token))
        }
        for retiredToken in [
            "GamificationManager.shared",
            "ScanRepository.shared",
            "CircuitBreakerManager.shared.recordSuccess()",
            "RevenueCatManager.shared",
            "AppSettings.shared",
            "PushNotificationManager.shared",
            "AppTelemetry.trackScan(",
            "AppDIContainer.shared.scanMilestoneCoordinator.processCompletedScan(",
            ".foregroundBiologicalScanCompleted(scanId:"
        ] {
            #expect(
                !engine.contains(retiredToken),
                "InferenceEngine reclaimed completion effect \(retiredToken)"
            )
        }

        for token in [
            "liveInferenceCompletionDependencies",
            "InferenceLiveCompletionCoordinator.Dependencies.composed(",
            "liveCompletionDependencies:"
        ] {
            #expect(appDI.contains(token))
        }
    }

    @Test func visualAndNonvisualCallSitesPreserveReviewedEffectOrder() throws {
        let engine = try contents(
            of: repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AI/InferenceEngine.swift"
            )
        )
        let visualStart = try #require(
            engine.range(of: "// MARK: - Live Inference Pipeline")
        )
        let nonvisualStart = try #require(
            engine.range(
                of: "// MARK: - Describe Inference Pipeline",
                range: visualStart.upperBound..<engine.endIndex
            )
        )
        let failureStart = try #require(
            engine.range(
                of: "// MARK: - Live Failure Recovery",
                range: nonvisualStart.upperBound..<engine.endIndex
            )
        )
        let visual = engine[
            visualStart.lowerBound..<nonvisualStart.lowerBound
        ]
        let nonvisual = engine[
            nonvisualStart.lowerBound..<failureStart.lowerBound
        ]

        let visualPrepare = try #require(
            visual.range(of: "liveCompletionCoordinator.prepare(")
        )
        let visualCommit = try #require(
            visual.range(of: "let didCommitResult = self.commitSuccessfulResult(")
        )
        let visualFinalize = try #require(
            visual.range(of: ".finalizeQueueAndAuthorizeFollowUps(")
        )
        let visualNotification = try #require(
            visual.range(of: ".sendNotificationIfEnabled(")
        )
        let visualPostFlight = try #require(
            visual.range(of: "[⏱ BENCH] Post-flight")
        )
        let visualHydration = try #require(
            visual.range(of: "schedulePostInferenceHydrationIfNeeded(")
        )
        let visualMilestone = try #require(
            visual.range(of: ".scheduleMilestones(")
        )
        #expect(visualPrepare.lowerBound < visualCommit.lowerBound)
        #expect(visualCommit.lowerBound < visualFinalize.lowerBound)
        #expect(visualFinalize.lowerBound < visualNotification.lowerBound)
        #expect(visualNotification.lowerBound < visualPostFlight.lowerBound)
        #expect(visualPostFlight.lowerBound < visualHydration.lowerBound)
        #expect(visualHydration.lowerBound < visualMilestone.lowerBound)

        let nonvisualPrepare = try #require(
            nonvisual.range(of: "liveCompletionCoordinator.prepare(")
        )
        let nonvisualCommit = try #require(
            nonvisual.range(
                of: "let didCommitResult = self.commitSuccessfulResult("
            )
        )
        let nonvisualPostFlight = try #require(
            nonvisual.range(of: "[⏱ BENCH] Post-flight")
        )
        let nonvisualFinalize = try #require(
            nonvisual.range(of: ".finalizeQueueAndAuthorizeFollowUps(")
        )
        let nonvisualQueueLess = try #require(
            nonvisual.range(of: ".authorizeQueueLessFollowUps(")
        )
        let nonvisualMilestone = try #require(
            nonvisual.range(of: ".scheduleMilestones(")
        )
        let nonvisualNotification = try #require(
            nonvisual.range(of: ".sendNotificationIfEnabled(")
        )
        let nonvisualHydration = try #require(
            nonvisual.range(of: "schedulePostInferenceHydrationIfNeeded(")
        )
        #expect(nonvisualPrepare.lowerBound < nonvisualCommit.lowerBound)
        #expect(nonvisualCommit.lowerBound < nonvisualPostFlight.lowerBound)
        #expect(nonvisualPostFlight.lowerBound < nonvisualFinalize.lowerBound)
        #expect(nonvisualFinalize.lowerBound < nonvisualQueueLess.lowerBound)
        #expect(nonvisualQueueLess.lowerBound < nonvisualMilestone.lowerBound)
        #expect(nonvisualMilestone.lowerBound < nonvisualNotification.lowerBound)
        #expect(nonvisualNotification.lowerBound < nonvisualHydration.lowerBound)
    }

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
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
