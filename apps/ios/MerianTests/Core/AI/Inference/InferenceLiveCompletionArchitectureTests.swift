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
        let presentationBridge = try contents(
            of: root.appendingPathComponent(
                "apps/ios/Merian/Core/AI/Inference/Pipeline/InferenceLivePresentationCoordinator.swift"
            )
        )
        let pipeline = try contents(
            of: root.appendingPathComponent(
                "apps/ios/Merian/Core/AI/Inference/Pipeline/InferenceLivePipelineCoordinator.swift"
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
            "fileprivate let fundingSettlement:",
            "func prepare(",
            "func publishForegroundCompletionEventIfNeeded(",
            "func authorizeQueueLessFollowUps(",
            "guard scanId == nil else { return nil }",
            "func finalizeQueueAndAuthorizeFollowUps(",
            "func commitFundingSettlement(",
            "fundingSettlement.scanId.caseInsensitiveCompare(resultScanId)",
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
            "OfflineQueueManager.shared",
            "AppDIContainer.shared.appEventPublisher",
            "AppDIContainer.shared.scanMilestoneCoordinator",
            "InferenceScanReplacement.transferMetadata(",
            "AppTelemetry.trackScan(",
            "Task { @MainActor in"
        ] {
            #expect(liveAdapter.contains(token))
        }

        #expect(
            presentationBridge.contains(
                "private let completionCoordinator:"
            )
        )
        #expect(
            presentationBridge.contains(
                "publishForegroundCompletionEventIfNeeded(\n            for: speciesData"
            )
        )
        for token in [
            "completionCoordinator.prepare(",
            ".finalizeQueueAndAuthorizeFollowUps(",
            ".authorizeQueueLessFollowUps(",
            ".commitFundingSettlement(",
            ".sendNotificationIfEnabled(",
            ".scheduleMilestones("
        ] {
            #expect(pipeline.contains(token))
            #expect(!engine.contains(token))
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
        let pipeline = try contents(
            of: repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AI/Inference/Pipeline/InferenceLivePipelineCoordinator.swift"
            )
        )
        let visualStart = try #require(
            pipeline.range(of: "func executeVisual(")
        )
        let nonvisualStart = try #require(
            pipeline.range(
                of: "func executeNonVisual(",
                range: visualStart.upperBound..<pipeline.endIndex
            )
        )
        let sharedHelperStart = try #require(
            pipeline.range(
                of: "private func check(",
                range: nonvisualStart.upperBound..<pipeline.endIndex
            )
        )
        let visual = pipeline[
            visualStart.lowerBound..<nonvisualStart.lowerBound
        ]
        let nonvisual = pipeline[
            nonvisualStart.lowerBound..<sharedHelperStart.lowerBound
        ]

        let visualPrepare = try #require(
            visual.range(of: "processResult(")
        )
        let visualCommit = try #require(
            visual.range(of: "let didCommitResult = callbacks.shared.publishCompletion(")
        )
        let visualFinalize = try #require(
            visual.range(of: ".finalizeQueueAndAuthorizeFollowUps(")
        )
        let visualNotification = try #require(
            visual.range(of: ".sendNotificationIfEnabled(")
        )
        let visualFundingSettlement = try #require(
            visual.range(of: ".commitFundingSettlement(")
        )
        let visualPostFlight = try #require(
            visual.range(of: ".postFlight(")
        )
        let visualHydration = try #require(
            visual.range(of: "callbacks.shared.scheduleHydration(")
        )
        let visualMilestone = try #require(
            visual.range(of: ".scheduleMilestones(")
        )
        #expect(visualPrepare.lowerBound < visualCommit.lowerBound)
        #expect(visualCommit.lowerBound < visualFinalize.lowerBound)
        #expect(visualFinalize.lowerBound < visualFundingSettlement.lowerBound)
        #expect(visualFundingSettlement.lowerBound < visualNotification.lowerBound)
        #expect(visualNotification.lowerBound < visualPostFlight.lowerBound)
        #expect(visualPostFlight.lowerBound < visualHydration.lowerBound)
        #expect(visualHydration.lowerBound < visualMilestone.lowerBound)

        let nonvisualPrepare = try #require(
            nonvisual.range(of: "processResult(")
        )
        let nonvisualCommit = try #require(
            nonvisual.range(
                of: "let didCommitResult = callbacks.publishCompletion("
            )
        )
        let nonvisualPostFlight = try #require(
            nonvisual.range(of: ".postFlight(")
        )
        let nonvisualDurableAuthorization = try #require(
            nonvisual.range(of: ".finalizeQueueAndAuthorizeFollowUps(")
        )
        let nonvisualQueueLessAuthorization = try #require(
            nonvisual.range(of: ".authorizeQueueLessFollowUps(")
        )
        let nonvisualMilestone = try #require(
            nonvisual.range(of: ".scheduleMilestones(")
        )
        let nonvisualFundingSettlement = try #require(
            nonvisual.range(of: ".commitFundingSettlement(")
        )
        let nonvisualNotification = try #require(
            nonvisual.range(of: ".sendNotificationIfEnabled(")
        )
        let nonvisualHydration = try #require(
            nonvisual.range(of: "callbacks.scheduleHydration(")
        )
        #expect(nonvisualPrepare.lowerBound < nonvisualCommit.lowerBound)
        #expect(nonvisualCommit.lowerBound < nonvisualPostFlight.lowerBound)
        #expect(
            nonvisualPostFlight.lowerBound
                < nonvisualDurableAuthorization.lowerBound
        )
        #expect(
            nonvisualDurableAuthorization.lowerBound
                < nonvisualQueueLessAuthorization.lowerBound
        )
        #expect(
            nonvisualQueueLessAuthorization.lowerBound
                < nonvisualFundingSettlement.lowerBound
        )
        #expect(nonvisualFundingSettlement.lowerBound < nonvisualMilestone.lowerBound)
        #expect(nonvisualMilestone.lowerBound < nonvisualNotification.lowerBound)
        #expect(nonvisualNotification.lowerBound < nonvisualHydration.lowerBound)

        #expect(
            nonvisual.contains("else if session.durableQueueOwnsRecovery")
        )
        #expect(
            nonvisual.contains("followUpPermit = await completionCoordinator")
        )
        #expect(
            nonvisual.contains(
                "followUpPermit = completionCoordinator\n"
                    + "                    .authorizeQueueLessFollowUps("
            )
        )
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
