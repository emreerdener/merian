import Foundation
import Testing

@testable import Merian

@Suite("Inference Session Lifecycle Architecture")
struct InferenceLifecycleArchitectureTests {
    @Test func lifecycleOwnerContainsTransitionsAndEngineOnlyDelegates() throws {
        let root = try repositoryRoot()
        let lifecycle = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/Inference/Lifecycle/InferenceSessionLifecycleCoordinator.swift"
        ))
        let attempt = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/Inference/State/InferenceLiveAttemptCoordinator.swift"
        ))
        let engine = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/InferenceEngine.swift"
        ))
        let pipelinePresentation = try contents(
            of: root.appendingPathComponent(
                "apps/ios/Merian/Core/AI/Inference/Pipeline/InferenceLivePresentationCoordinator.swift"
            )
        )
        let submission = try contents(
            of: root.appendingPathComponent(
                "apps/ios/Merian/Core/AI/Inference/Pipeline/InferenceLiveSubmissionCoordinator.swift"
            )
        )
        let historicalLoad = try contents(
            of: root.appendingPathComponent(
                "apps/ios/Merian/Core/AI/Inference/Hydration/InferenceHistoricalLoadCoordinator.swift"
            )
        )
        let backgroundCompletion = try contents(
            of: root.appendingPathComponent(
                "apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundInference/OfflineQueueManager+InferenceCompletion.swift"
            )
        )

        for token in [
            "final class InferenceSessionLifecycleCoordinator",
            "private let attemptCoordinator:",
            "private let hydrationCoordinator:",
            "private let writeCoordinator:",
            "private let localAnalysisCoordinator:",
            "private let presentationCoordinator:",
            "private let presentationState:",
            "func beginAuthTransition()",
            "func awaitAuthTransitionQuiescence() async",
            "func prepareForNewScan(",
            "func prepareForVisualAnalysis()",
            "func prepareForNonVisualAnalysis(",
            "func publishSuccessfulResult(",
            "func commitRecoveredBackgroundResult(",
            "func commitRecoveredQueuedResult(",
            "func commitRecoveredQueuedRecord(",
            "func finishLivePipelinePresentation(",
            "func rebindFirstRenderMetric(",
            "func transitionToQueue(",
            "func dismissAnalyzingPresentation()",
            "func cancelActiveRequest(",
            "func beginHistoricalLoad() -> Bool",
            "func handleApplicationActiveStateChange("
        ] {
            #expect(lifecycle.contains(token))
        }
        for token in [
            "URLSession", "ModelContext", "LocalScanRecord", "MerianLog",
            "FileManager", ".shared", "private var ", "Task<", "Task {",
            "Task.detached",
            "SupabaseManager", "OfflineQueueManager"
        ] {
            #expect(!lifecycle.contains(token))
        }

        for token in [
            "@ObservationIgnored private let sessionLifecycleCoordinator:",
            "sessionLifecycleCoordinator.beginAuthTransition()",
            "sessionLifecycleCoordinator.awaitAuthTransitionQuiescence()",
            "sessionLifecycleCoordinator.finishAuthTransition()",
            "sessionLifecycleCoordinator.prepareForNewScan(",
            "sessionLifecycleCoordinator.commitRecoveredBackgroundResult(",
            "sessionLifecycleCoordinator.commitRecoveredQueuedResult(",
            "sessionLifecycleCoordinator.commitRecoveredQueuedRecord(",
            "sessionLifecycleCoordinator.transitionToQueue(",
            "sessionLifecycleCoordinator.dismissAnalyzingPresentation()",
            "sessionLifecycleCoordinator.cancelActiveRequest(",
            "sessionLifecycleCoordinator.handleApplicationActiveStateChange("
        ] {
            #expect(engine.contains(token))
        }
        #expect(
            engine.contains(
                "historicalLoadCoordinator.load(from: record)"
            )
        )
        #expect(
            historicalLoad.contains(
                "sessionLifecycleCoordinator.beginHistoricalLoad()"
            )
        )
        #expect(
            !engine.contains(
                "sessionLifecycleCoordinator.beginHistoricalLoad()"
            )
        )
        for token in [
            "sessionLifecycleCoordinator.prepareForVisualAnalysis()",
            "sessionLifecycleCoordinator.prepareForNonVisualAnalysis("
        ] {
            #expect(submission.contains(token))
            #expect(!engine.contains(token))
        }

        let visualReplacement = try section(
            lifecycle,
            from: "func prepareForVisualAnalysis()",
            until: "func prepareForNonVisualAnalysis("
        )
        #expect(visualReplacement.contains("presentationCoordinator.reset()"))

        let recoveredBackgroundFacade = try section(
            engine,
            from: "func commitRecoveredBackgroundResult(",
            until: "func commitRecoveredQueuedResult("
        )
        let recoveredQueuedFacade = try section(
            engine,
            from: "func commitRecoveredQueuedResult(",
            until: "func commitRecoveredQueuedRecord("
        )
        let recoveredRecordFacade = try section(
            engine,
            from: "func commitRecoveredQueuedRecord(",
            until: "func analyze("
        )
        #expect(
            recoveredBackgroundFacade.contains(
                "sessionLifecycleCoordinator.commitRecoveredBackgroundResult("
            )
        )
        #expect(
            recoveredQueuedFacade.contains(
                "sessionLifecycleCoordinator.commitRecoveredQueuedResult("
            )
        )
        #expect(
            recoveredRecordFacade.contains(
                "sessionLifecycleCoordinator.commitRecoveredQueuedRecord("
            )
        )
        for facade in [
            recoveredBackgroundFacade,
            recoveredQueuedFacade,
            recoveredRecordFacade
        ] {
            for ownershipToken in [
                "guard ",
                "caseInsensitiveCompare",
                "clearActiveAttempt()",
                "setRecoverablePresentationScanId(",
                "cancelLocalVisualAnalysis()",
                "publishSuccessfulResult("
            ] {
                #expect(!facade.contains(ownershipToken))
            }
        }
        #expect(
            pipelinePresentation.contains(
                ".finishLivePipelinePresentation("
            )
        )
        #expect(
            pipelinePresentation.contains(
                "sessionLifecycleCoordinator.publishSuccessfulResult("
            )
        )
        #expect(
            pipelinePresentation.contains(
                "sessionLifecycleCoordinator.rebindFirstRenderMetric("
            )
        )
        for retiredToken in [
            "writeCoordinator.beginAuthTransitionFence()",
            "hydrationCoordinator.beginAuthTransitionFence()",
            "presentationState.clearForAuthTransition(",
            "live_scan_replaced_by_analyze",
            "presentationLifecycleCoordinator.transitionToQueue(",
            "presentationState.beginCancellation()",
            "presentationState.finishCancellation(",
            "persisted_scan_loaded",
            "presentationState.beginHistoricalLoad()",
            "localAnalysisCoordinator.pauseForInactivity(",
            "localAnalysisCoordinator.resumeAfterInactivity(",
            "liveAttemptCoordinator.canCommitRecoveredBackgroundResult(",
            "speciesData.scanId?.caseInsensitiveCompare(scanId)",
            "recoverablePresentationScanId == scanId",
            "record.id == scanId",
            "liveAttemptCoordinator.clearActiveAttempt()"
        ] {
            #expect(!engine.contains(retiredToken))
        }

        for token in [
            "func cancelCurrentTask()",
            "func cancelAllTasks()",
            "func awaitQuiescence() async",
            "func clearCurrentTask()",
            "func cancelAndClearActiveAttempt()"
        ] {
            #expect(attempt.contains(token))
        }
        #expect(
            backgroundCompletion.contains(
                "engine.commitRecoveredBackgroundResult("
            )
        )
        #expect(
            backgroundCompletion.contains(
                "engine.commitRecoveredQueuedResult("
            )
        )
        #expect(
            !backgroundCompletion.contains("engine.inferenceTask?.cancel()")
        )
        #expect(lineCount(lifecycle) <= 600)
    }

    @Test func criticalLifecycleTransitionsKeepTheirReviewedOrder() throws {
        let lifecycle = try contents(of: try repositoryRoot()
            .appendingPathComponent(
                "apps/ios/Merian/Core/AI/Inference/Lifecycle/InferenceSessionLifecycleCoordinator.swift"
            ))

        let auth = try section(
            lifecycle,
            from: "func beginAuthTransition()",
            until: "func awaitAuthTransitionQuiescence() async"
        )
        try expectOrder(
            in: auth,
            tokens: [
                "writeCoordinator.beginAuthTransitionFence()",
                "hydrationCoordinator.beginAuthTransitionFence()",
                "attemptCoordinator.invalidateFollowUpAuthorization()",
                "attemptCoordinator.cancelAllTasks()",
                "localAnalysisCoordinator.cancel()",
                "presentationCoordinator.clearForAuthTransitionAdmission()",
                "attemptCoordinator.setRecoverablePresentationScanId(nil)",
                "presentationState.clearForAuthTransition(",
                "writeCoordinator.resetPresentationWrites()"
            ]
        )

        let cancellation = try section(
            lifecycle,
            from: "func cancelActiveRequest(isUserInitiated: Bool)",
            until: "func beginHistoricalLoad() -> Bool"
        )
        try expectOrder(
            in: cancellation,
            tokens: [
                "attemptCoordinator.invalidateActiveAttempt(",
                "presentationState.beginCancellation()",
                "hydrationCoordinator.cancelAllTasks()",
                "localAnalysisCoordinator.cancel()",
                "writeCoordinator.resetPresentationWrites()",
                "attemptCoordinator.setRecoverablePresentationScanId(nil)",
                "presentationCoordinator.reset()",
                "presentationState.finishCancellation("
            ]
        )

        let recoveredBackground = try section(
            lifecycle,
            from: "func commitRecoveredBackgroundResult(",
            until: "func commitRecoveredQueuedResult("
        )
        try expectOrder(
            in: recoveredBackground,
            tokens: [
                "attemptCoordinator.canCommitRecoveredBackgroundResult(",
                "attemptCoordinator.cancelAndClearActiveAttempt()",
                "localAnalysisCoordinator.cancel()",
                "publishSuccessfulResult(speciesData, persistedMediaItems: nil)"
            ]
        )

        let recoveredQueued = try section(
            lifecycle,
            from: "func commitRecoveredQueuedResult(",
            until: "func commitRecoveredQueuedRecord("
        )
        try expectOrder(
            in: recoveredQueued,
            tokens: [
                "attemptCoordinator.recoverablePresentationScanId == scanId",
                "speciesData.scanId?.caseInsensitiveCompare(scanId)",
                "attemptCoordinator.activeScanId == nil",
                "attemptCoordinator.cancelAndClearActiveAttempt()",
                "attemptCoordinator.setRecoverablePresentationScanId(nil)",
                "localAnalysisCoordinator.cancel()",
                "publishSuccessfulResult(speciesData, persistedMediaItems: nil)"
            ]
        )

        let recoveredRecord = try section(
            lifecycle,
            from: "func commitRecoveredQueuedRecord(",
            until: "func finishLivePipelinePresentation("
        )
        try expectOrder(
            in: recoveredRecord,
            tokens: [
                "attemptCoordinator.recoverablePresentationScanId == scanId",
                "recordScanId == scanId",
                "attemptCoordinator.activeScanId == nil",
                "attemptCoordinator.setRecoverablePresentationScanId(nil)",
                "loadRecord()"
            ]
        )

        let historical = try section(
            lifecycle,
            from: "func beginHistoricalLoad() -> Bool",
            until: "func handleApplicationActiveStateChange(isActive: Bool)"
        )
        try expectOrder(
            in: historical,
            tokens: [
                "attemptCoordinator.invalidateActiveAttempt(",
                "attemptCoordinator.setRecoverablePresentationScanId(nil)",
                "presentationCoordinator.reset()",
                "presentationState.beginHistoricalLoad()",
                "hydrationCoordinator.cancelAllTasks()",
                "localAnalysisCoordinator.cancel()",
                "writeCoordinator.resetPresentationWrites()"
            ]
        )

        let preparation = try section(
            lifecycle,
            from: "private func prepareForNewScanUnchecked(",
            until: "\n    }\n}"
        )
        try expectOrder(
            in: preparation,
            tokens: [
                "attemptCoordinator.invalidateActiveAttempt(",
                "hydrationCoordinator.cancelAllTasks()",
                "hydrationCoordinator.resetEnrichmentRateLimit()",
                "localAnalysisCoordinator.cancel()",
                "writeCoordinator.resetPresentationWrites()",
                "attemptCoordinator.setActiveScanId(nil)",
                "attemptCoordinator.setRecoverablePresentationScanId(nil)",
                "presentationCoordinator.prepare(",
                "presentationState.prepareForNewScan("
            ]
        )
    }

    private func section(
        _ source: String,
        from startToken: String,
        until endToken: String
    ) throws -> Substring {
        let start = try #require(source.range(of: startToken))
        let end = try #require(source.range(
            of: endToken,
            range: start.upperBound..<source.endIndex
        ))
        return source[start.lowerBound..<end.lowerBound]
    }

    private func expectOrder(
        in source: Substring,
        tokens: [String]
    ) throws {
        var lowerBound = source.startIndex
        for token in tokens {
            let match = try #require(source.range(
                of: token,
                range: lowerBound..<source.endIndex
            ))
            lowerBound = match.upperBound
        }
    }

    private func lineCount(_ source: String) -> Int {
        source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
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

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }
}
